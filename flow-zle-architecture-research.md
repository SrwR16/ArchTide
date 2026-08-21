# Flow Terminal — ZLE/Predictor Architecture Research
**Repo inspected:** `SrwR16/ArchTide` @ `dev` (cloned locally, 8,357 commits, forked from `P3DROVFX/ii-p3drovfx`)
**Scope:** research only. Nothing in the repository was modified.

> **ADDENDUM (post-discussion):** The original brief asked whether to *refactor* the custom editor and predictor in place. Follow-up clarified the actual goal: stop being the one who maintains this code at all — full delegation to mature, externally-maintained projects for **both** the editor (`45-flow-editor.zsh`) and the predictor (`90-flow-predictor.zsh` / `flow_predictor.sh`), even if that means giving up some bespoke UX. §16 below supersedes §1–2's "refactor in place" framing for the editor, and the Option B recommendation in §13 is superseded by the **full-delegation architecture in §16** for anyone prioritizing "zero code I maintain" over "richest possible UX." The original research in §1–15 remains accurate and is kept as the technical record of what was actually checked.

---

## 1. Current ArchTide architecture assessment

Confirmed directly from the repo (line counts, not estimates):

| File | Lines | Role |
|---|---|---|
| `dots/.config/zshrc.d/20-completion.zsh` | 80 | stock `compinit`, per-tool completion sourcing (docker/kubectl/helm/terraform/aws/gh/mise) |
| `dots/.config/zshrc.d/30-history.zsh` | 20 | Atuin init (`--disable-up-arrow`), `HISTFILE`/size, `^R` fallback |
| `dots/.config/zshrc.d/40-keybindings.zsh` | 48 | emacs mode, word/line movement, fzf key-bindings hook |
| `dots/.config/zshrc.d/45-flow-editor.zsh` | 279 | Ctrl+Shift selection/clipboard/delete namespace |
| `dots/.config/zshrc.d/90-flow-predictor.zsh` | **1,038** | ZLE integration: ghost, HUD, Up/Down interception, widget wrapping, learning hooks |
| `sdata/lib/flow_predictor.sh` | 491 | shared scoring/classification engine (bash+zsh compatible) |
| `setup-flow.sh` | 2,991 | installer |

The predictor subsystem (`90-flow-predictor.zsh` + `flow_predictor.sh`) is ~1,530 lines of hand-rolled ZLE code — by far the largest and most fragile piece, exactly as described. `45-flow-editor.zsh` is comparatively modest (279 lines) and already delegates undo/redo to zsh's native `undo`/`redo` widgets; it only reimplements selection, clipboard I/O, and delete-with-selection.

**Nothing else in the stack duplicates ZLE/completion work.** There is no plugin manager, no `zsh-autosuggestions`, no `zsh-syntax-highlighting`, no `fzf-tab` currently wired in (`.gitmodules` and a repo-wide grep confirm this). `20-completion.zsh` is stock `compinit` + per-tool sourcing. This means the integration surface for any new tool is clean — there's no existing plugin to conflict with, only Flow's own code.

### Root cause of the fragility (the actual finding, not the assumed one)

Reading `90-flow-predictor.zsh` end to end, the instability doesn't come from any single mechanism (ghost rendering, HUD, Up/Down) in isolation — each of those is a normal, well-understood ZLE pattern also used by mature tools (see §9, §5). The fragility comes from **three custom subsystems independently wrapping the same ZLE widgets**:

1. `45-flow-editor.zsh` rebinds `backward-delete-char`, `^H`, `delete-char` to `flow_delete_*`, capturing "whatever was bound before" via `_flow_capture_binding`.
2. `90-flow-predictor.zsh` then wraps a **30-widget list** (`self-insert backward-delete-char delete-char backward-kill-word … flow_paste flow_cut flow_delete_backward flow_delete_forward flow_select_all flow_copy`) — including the editor's own widgets — via `_flow_pred_wrap_widget`, which does `zle -A "$w" "_flow_pred_orig_$w"` and re-registers a ghost-clearing shim.
3. `self-insert` gets special-cased differently from every other widget (it inspects `bindkey -M main "$KEYS"` at call time to decide whether to clear the ghost), and ghost state is also mutated by `zle-line-pre-redraw` (`_flow_pred_on_redraw`), by `preexec`/`precmd` hooks, and by the HUD's own keymap (`flowhud`) which delegates unmapped keys back to `main` via `bindkey -M main "$KEYS"` lookups a second time.

That's four independent places (editor wrapper, predictor wrapper, redraw hook, HUD delegate) each making assumptions about "what widget is currently bound to this key" and "whose job it is to clear the ghost." This is a classic ZLE failure mode: **widget-wrapping order dependency**. Load order, a future plugin, or even a user rebinding a key after Flow loads can silently break one of the four assumption points, and the failure mode (broken shell) is exactly what's reported. The fix isn't "rip out region_highlight" in the abstract — ghost-text-via-`region_highlight`/`POSTDISPLAY` is the industry-standard pattern (§5, §9) — it's **collapsing four independent wrapping layers into one**.

---

## 2. Exact problems with the current Phase 8/9 approach

- **Double/triple widget wrapping** across `45-flow-editor.zsh` and `90-flow-predictor.zsh` (see above) — the single biggest reliability risk.
- **`self-insert` is special-cased** with a runtime `bindkey -M main "$KEYS"` lookup on every keystroke to decide behavior — fragile and a hot-path cost.
- **Two parallel "what's bound to this key" resolution paths**: `_flow_pred_wrap_widget`'s `case` on `bindkey -M main "$KEYS"`, and `_flow_pred_hud_delegate`'s identical pattern for the `flowhud` keymap. Any drift between them causes stuck keys.
- **1,038 lines in one file** mixing six concerns (index storage, providers, scoring glue, ghost rendering, HUD rendering, key bindings, learning hooks, debug CLI) with no internal module boundaries — hard to reason about, hard to test in isolation, hard to onboard a contributor to.
- **State duplication**: `_fp_last_typed/_fp_last_result` cache in the redraw hook, `_fp_last_results` cache in the HUD open path, and the live prediction path in `_flow_pred_predict` all need to agree on freshness — three cache-invalidation sites for one piece of state.
- **Bash/Zsh dual-compat constraint** on `flow_predictor.sh` (shared with the `flow suggest` CLI) limits it to lowest-common-denominator shell syntax, which in turn pushes complexity into per-shell glue.

None of this means the underlying *design* (deterministic, local, multi-signal, ZLE-native) is wrong — see §12 comparison — it means the *implementation* has accreted patches without a refactor.

---

## 3–8. Deep dives on candidate projects

Every project below was fetched live from its actual GitHub repository (not from training memory) on 2026-08-21, including current star/fork/issue counts and README content, since these are exactly the kind of "current state" facts that go stale.

### 3. IRIS (`versenilvis/IRIS`) — Key Research Question #1

**What it actually is:** a **PTY-proxy** binary (Go), not a ZLE plugin. Per its own docs it "runs everywhere... it just needs a terminal" and is explicitly framed as a Fig replacement: it sits between the terminal emulator and the shell, intercepts the raw byte stream, and **reimplements line editing itself** — its own Ctrl+A/E/W/U/L/C handling, its own arrow-key history, its own Tab/Shift+Tab menu. The README states plainly: *"they belong to your shell by default. IRIS handles them directly in raw mode so your cursor and menu stay in sync."*

- **Status:** README literally titled "Shell auto-completion tool (**WIP!!!**)". 140 commits, 26 releases, latest `v0.2.4`. Star count is inconsistent across sources (Trendshift cache shows 1.2k after a July 2026 trending spike; the live repo page shows 2 stars, 0 forks, 2 contributors) — a strong signal this is a very young, single/two-person project that briefly trended, not an established one. Multiple open bug issues from Aug 1–2, 2026.
- **Can it consume Flow's candidates / be driven by Flow?** No, and this is provable from the architecture, not an assumption: IRIS owns the PTY, not ZLE. There is no documented candidate-injection API, no provider interface, no "disable my predictor, keep my UI" mode in its docs. To make IRIS render Flow's ranked candidates you would need to fork it and either (a) build an IPC channel from zsh into its process for every keystroke, or (b) reimplement Flow's context/session detection *inside* IRIS's Go codebase, since IRIS-as-PTY-proxy can't see zsh's `ZLE` state (`BUFFER`, hooks, `$PWD` via zsh, etc.) — it only sees raw bytes.
- **Verdict: does not satisfy KRQ#1.** Cannot be used as a presentation layer for Flow's engine without a substantial fork that would itself become a new maintenance burden larger than the current Phase 9 code.

### 4. Deja (`Giammarco-Ferranti/deja`) — Key Research Question #2

**What it actually is:** a genuine **zsh-native** plugin (`deja.plugin.zsh`) backed by a local Go daemon over a Unix socket, SQLite (WAL mode) storage. This is architecturally the closest thing on the list to Flow's own design goals.

Confirmed from source/docs:
- Ghost text via zsh's `POSTDISPLAY` / `region_highlight` — the same primitive Flow already uses, just without the double-wrap problem (§2).
- Scoring formula is explicit and public: `score = 1.0×fuzzy + 0.4×frecency + 0.3×directory_affinity + 0.5×sequence_score`, with frecency using a 1-week exponential half-life.
- Daemon loads all state into memory (`map[string]*CommandStat`), serves via a `sync.RWMutex`, <1ms per keystroke; falls back to a direct two-pass SQLite read if the daemon is down.
- Ships a `deja query` CLI (mentioned in troubleshooting docs) and `deja ping`/`deja daemon --restart`/`deja fuzzy`/`deja empty` subcommands — i.e., there **is** a command-line surface, but it is documented as an operational/debug interface, not a published "candidate provider API." There is no documented way to inject external candidates, rerank Deja's list, or run Deja "headless" (engine only, no UI) — the README explicitly states it detects and **stands down** if `zsh-autosuggestions` is loaded (to avoid wedging the line editor by double-wrapping widgets — the exact failure mode in §2), which confirms it assumes it is the *only* ghost-text owner in the shell.
- Maturity: 560 stars, 10 forks, 3 open issues, 4 open PRs, MIT, automated release-please/GoReleaser pipeline, Homebrew tap — genuinely maintained, not abandoned.

**Verdict: cannot be used as a headless backend consumed by Flow's own ranker/renderer as designed today.** It is a complete, opinionated replacement for `zsh-autosuggestions`, not an embeddable library. It **can**, however, be shelled out to (`deja query`) as one more *data source* the way Flow already shells out to `atuin history list` — but that's "use its CLI as an input," not "delegate rendering to it," and doing that per-keystroke would add a subprocess fork Flow's hot path currently avoids.

### 5. zsh-sage (`UtsavMandal2022/zsh-sage`) — Key Research Question #3

**Architecture:** single-file zsh plugin, `self-insert` widget → one SQL query via a persistent `sqlite3` **coproc** (not a separate daemon binary) → `POSTDISPLAY` ghost with confidence-colored text → named widgets `sage-accept` / `sage-accept-word` / `sage-cycle` / `sage-dismiss` that users can rebind.

**Scoring model:** five signals — frequency (sqrt-scaled), recency (exponential decay, 3-day half-life), directory affinity, command sequence, success rate — with **prefix-length-aware weight shifting** (short prefix → frequency-driven, long prefix → recency/directory-driven). This is close to a strict subset of what Flow's own `flow_predictor.sh` already computes (Flow additionally tracks workflow triples and failure→recovery pairs, which zsh-sage does not).

**Notable:** ships an opt-in `hm` "ask AI in plain English" command (Claude Code CLI or local Ollama) — off by default, requires `zsage ai` setup and explicit permission. Since the brief requires **no AI dependency**, this feature must simply never be enabled if any of zsh-sage's code were reused; it doesn't taint the local suggestion engine, which works without it.

**Maturity:** 105 stars, 10 forks, 1 open issue, 112 commits, single maintainer, MIT. Real performance numbers given (2ms full rank on 10k history entries, benchmarked and versioned v1→v5 with a documented optimization journey) — a good sign of engineering rigor for a young project.

**Extension points:** four public ZLE widgets and env-var config knobs (`ZSH_SAGE_W_*`, `ZSH_SAGE_PROFILE`), but — like Deja — **no documented candidate-injection or headless-engine mode.** It owns its own DB, its own scoring, its own rendering.

**Comparison with Deja:** Deja is more architecturally mature (daemon+socket, automated releases, larger community); zsh-sage is more transparent/tunable (readable single-file coproc SQL, explicit weight env-vars) and closer in signal set to Flow's own model, but is a much younger, single-maintainer project. Neither is more "delegable" than the other — both are complete, opinionated, all-in-one replacements for `zsh-autosuggestions`.

### 6. Ghost Complete — Key Research Question #4

Real project: `StanMarek/ghost-complete` — **also a PTY proxy** (Rust), explicitly "inspired by Fig," renders native ANSI popups by intercepting the terminal's I/O stream. Ships 711 Fig-style completion specs, targets 10 terminal emulators (primarily macOS-centric list: Ghostty, Kitty, WezTerm, Alacritty, Rio, iTerm2, Terminal.app, Zed, VS Code family; zsh is "the primary shell" but it isn't a zsh plugin — it wraps the shell process). "Under active development," no version/maturity signal beyond that.

**Verdict: same structural problem as IRIS.** It's a session-level proxy, not a ZLE-embeddable completion source. No documented custom-provider API for external ranking engines. Not usable as "a completion provider/UI underneath Flow" without forking it into something it isn't.

### 7. Atuin — what Flow should delegate to it (Key Research Question — Atuin section)

Atuin has moved forward since Flow's `30-history.zsh` was written:

- **`daemon-fuzzy` search mode** (opt-in via `search_mode = "daemon-fuzzy"` + `[daemon] enabled/autostart = true`): the daemon now keeps a **hot in-memory search index** powered by a modified `nucleo` (same fuzzy algorithm as `fzf`), with configurable multipliers: `recency_score_multiplier`, `frequency_score_multiplier`, `frecency_score_multiplier`.
- **Workspace-aware filter modes**: `filters = ["global", "host", "session", "directory"]`, with a `workspace` mode that activates specifically inside git repos.
- **`atuin history list --format`** (already what Flow shells out to) remains supported and is the right machine-readable interface for Flow's warm-up ingestion.
- **`atuin ai`** now exists as an opt-in feature (introduced per Atuin's own changelog) — like zsh-sage's `hm`, this must simply stay disabled; it doesn't change Atuin's suitability as a pure local history backend.
- Atuin explicitly supports `--author` filtering to distinguish human-run vs. agent-run commands in interactive search — a feature Flow could eventually consume but doesn't need to today.

**What Flow should keep doing:** use Atuin purely as **source-of-truth storage + frecency-aware retrieval**, exactly as today, via `atuin history list --format '...'`. **What Flow should add:** switching the warm-up path to prefer `daemon-fuzzy` mode (when the user has it enabled) for lower-latency bulk reads, and using the `directory`/`workspace` filter modes as an additional signal source rather than recomputing directory-affinity from scratch — Flow's own `_fp_key_dirs` bookkeeping is solving a problem Atuin's daemon index increasingly already solves. **What Flow should keep owning:** transition/workflow/recovery/session signals — Atuin has no concept of command *sequences* or *failure→recovery*, only frecency and directory/session/host filters. This is genuinely Flow-specific intelligence with no equivalent upstream.

### 8. fzf-tab, zsh-autosuggestions, zsh-autocomplete, zsh-syntax-highlighting, zsh-history-substring-search, ble.sh, Flyline

- **fzf-tab** (`Aloxaf/fzf-tab`): replaces the native completion menu with an `fzf` picker. Doesn't touch history prediction or ghost text, so it doesn't conflict with anything Flow does — it's purely a `compinit`/`zstyle` layer, orthogonal to the predictor. Legitimate low-risk addition to `20-completion.zsh` if the user wants fuzzy Tab-completion; independent of the predictor decision entirely.
- **zsh-autosuggestions** (`zsh-users/zsh-autosuggestions`): still actively maintained (36k stars, issues opened and triaged into Feb 2026, no archival notice), but functionally superseded for Flow's purposes — Deja explicitly markets itself as "a smarter replacement," and Flow's own predictor already exceeds it on every axis (directory/sequence/recovery awareness). No reason to adopt it.
- **zsh-autocomplete** (`marlonrichert/zsh-autocomplete`): **confirmed real, current reliability problems**, not just legacy complaints — an open Jan 29, 2026 issue reports a **~30-second startup hang** under certain mount conditions; historical issues (#763, #17) report consistent startup-latency and typing-lag complaints going back years and still open in 2026. 6.4k stars, actively maintained, but its performance profile is incompatible with the brief's `<100ms` startup / `<20ms` interaction budget. **Reject for Flow's hot path**; not recommended even for the completion-only role given the demonstrated startup-hang risk.
- **zsh-syntax-highlighting** (`zsh-users/zsh-syntax-highlighting`): standard, stable, orthogonal (colors the command line, doesn't touch history/prediction/completion). Safe, low-risk addition if wanted — not currently installed.
- **zsh-history-substring-search**: niche today — Atuin's `^R` search and Flow's own Up/Down HUD already cover this use case with more context (directory/workspace/session awareness) than a plain substring match. No meaningful role in the proposed stack.
- **ble.sh**: Bash's ZLE-equivalent line editor, technically excellent, but Bash-only. Flyline (below) is effectively "ble.sh's spiritual successor" in Rust, also Bash-only.
- **Flyline** — real project(s): `HalFrgrd/flyline` (also mirrored as `Kamyil/flyline-zsh`, apparently a fork/rename in progress) is a **Bash readline replacement** written in Rust with `ratatui`, offering rich prompts, mouse-driven selection, tooltips, agent integration, fuzzy history search. Directly relevant lesson for Flow even though it's Bash-only: it demonstrates that "a modern, well-designed line-editing replacement" is achievable as a from-scratch project — but Flow doesn't need to build one, because native zsh ZLE editing (§ Editor section below) is already adequate. Not adoptable directly (wrong shell), useful only as an architectural reference for how a clean editor+suggestions split can be organized.

---

## 9. Answering KRQ#6 — responsibility-by-responsibility classification

| Responsibility | Classification | Rationale |
|---|---|---|
| Text editing (insert/delete/move) | **KEEP CUSTOM (thin)** | Already native ZLE widgets; `45-flow-editor.zsh`'s job is just Ctrl+Shift *bindings* on top of them |
| Selection (region/MARK) | **KEEP CUSTOM (thin)** | Native `MARK`/`REGION_ACTIVE`; ~120 lines, no plugin does this better for a custom Ctrl+Shift scheme |
| Clipboard (system copy/paste) | **KEEP CUSTOM (thin)** | Backend-detection (`wl-copy`/`xclip`/`xsel`) is inherently bespoke; no zsh plugin owns this well |
| Undo/redo | **DELEGATE (already does)** | `45-flow-editor.zsh` already binds to native `undo`/`redo` — no change needed |
| Ghost suggestion text | **KEEP CUSTOM, but refactor** | No mature tool exposes a "render my candidate, not yours" mode (§3,4,5,6). Pattern (POSTDISPLAY/region_highlight) is correct; implementation needs the double-wrap fix in §2 |
| Candidate menu (HUD) | **KEEP CUSTOM, but simplify** | Same reasoning — Deja/zsh-sage don't expose this as a service either |
| Up/Down interception | **KEEP CUSTOM, but simplify** | Needed to route "single candidate → history nav, multiple → HUD"; no external tool does this decision for Flow |
| Acceptance (accept-line, token accept) | **KEEP CUSTOM (thin)** | Small, well-contained already |
| History storage | **DELEGATE (already does)** | Atuin — keep, and lean on `daemon-fuzzy` more (§7) |
| Ranking (frequency/recency/dir) | **KEEP CUSTOM** | This is Flow's actual product differentiator; Deja/zsh-sage duplicate it but can't be driven by Flow |
| Workflow (3-step sequences) | **KEEP CUSTOM** | No external tool tracks command triples; Deja only does pairwise sequence, zsh-sage doesn't do workflow at all |
| Recovery (failure→fix) | **KEEP CUSTOM** | Unique to Flow; nothing researched here has this concept |
| Context (project/profile/runtime/dir) | **KEEP CUSTOM** | Flow-specific by definition; Atuin's `directory`/`workspace` filters are a *subset* Flow can lean on more (§7), not a replacement |
| Session sequence tracking | **KEEP CUSTOM** | Small, already minimal (`_fp_session_seq` array) |
| Persistence (aggregates.tsv) | **KEEP CUSTOM** | Deliberately decoupled from Atuin's DB by design (derived aggregates only) — correct as-is |
| Native command/file completion | **DELEGATE** | Already stock `compinit`; optionally layer `fzf-tab` for the picker UI (§8) — orthogonal to everything else |

**Net answer to "how much should disappear": very little of the *responsibility list* — almost everything Flow does is either already correctly delegated (undo/redo, history storage, native completion) or is Flow-specific intelligence nothing upstream replicates.** What should disappear is **duplicate wrapping code**, not features. The 1,038-line file should shrink meaningfully by removing the double-wrap indirection, not by removing ghost/HUD/Up-Down functionality.

---

## 10. Target architecture options — evaluated

| Diagram from the brief | Verdict |
|---|---|
| `Flow → Ranker → {Deja, zsh-sage, native completion} → mature terminal UX → Zsh/TTY` | **Infeasible as drawn.** Deja and zsh-sage aren't rerankable/embeddable data sources with a stable candidate-injection API (§4,5) — "mature terminal UX" here is really "three separate opinionated ghost-text owners fighting for the same `region_highlight`," which recreates §2's failure mode with *more* moving parts, not fewer. |
| `Flow → Context+Ranker → Deja/Sage → IRIS → TTY/Zsh` | **Infeasible.** IRIS is a PTY proxy (§3) that can't see zsh ZLE state at all; chaining a zsh plugin's output into a PTY-proxy binary isn't a documented or plausible integration. |
| `Flow → Context+Ranker → Native completion → zsh-autocomplete → ZLE` | **Not recommended.** zsh-autocomplete has demonstrated startup-hang and latency problems in 2026 issue reports (§8) that violate the stated `<100ms` startup / `<20ms` interaction budget. |
| `Flow → Context+Ranker → Ghost Complete → TTY` | **Infeasible.** Ghost Complete is also a PTY proxy (§6), same problem as IRIS. |

**None of the four proposed target architectures survive contact with the actual current state of these projects.** This is the single most important research finding: the 2026 "mature ecosystem" for zsh prediction consists of complete, opinionated, all-in-one tools (Deja, zsh-sage) and PTY-proxy tools (IRIS, Ghost Complete) — none of which were built to be a swappable backend or frontend for someone else's ranking engine. That's not a failure of research; it's an accurate description of the ecosystem's current shape (all four candidate projects are young — most emerged in 2025–2026 — and single/small-team maintained, so "provide a stable extension API for third parties" hasn't been a priority yet).

---

## 11. What Flow should actually own vs not (validated)

Confirmed as correct, with one addition:

**Flow-owned (validated):** project/profile/runtime/directory/git-workspace context, session tracking, success/failure, transition/workflow/recovery models, contextual reranking, confidence, candidate-source weighting, explanations. All confirmed unique — nothing researched replicates this set.

**Not Flow-owned (validated, already the case):** text editing primitives, undo/redo (already delegated), ZLE selection primitives, native CLI completion (already delegated), history *storage* (already delegated to Atuin).

**One responsibility to reconsider:** terminal rendering / candidate-menu rendering / screen layout was listed in the brief as "potentially NOT Flow-owned," but research shows **no mature tool will do this on Flow's behalf while taking Flow's data** (§3–6,10). So this stays Flow-owned in practice, not by preference but by absence of an alternative — the goal should be *simplifying* Flow's own renderer (§2), not replacing it.

---

## 12. Comparison matrix

| | Flow (current) | IRIS | Deja | zsh-sage | zsh-autocomplete | Ghost Complete | Atuin |
|---|---|---|---|---|---|---|---|
| Architecture | Custom ZLE, in-shell | PTY proxy, Go binary | Zsh plugin + Go daemon/socket | Zsh plugin + SQLite coproc | Zsh plugin, sync | PTY proxy, Rust binary | Rust binary + optional daemon |
| Prediction intelligence | 6 providers (hist/trans/workflow/recovery/session/completion) | prefix/history/alias | fuzzy+frecency+dir+sequence (pairwise) | freq/recency/dir/sequence/success | none (completion only) | Fig-style specs | frecency (freq+recency) |
| Context awareness | project/profile/runtime/dir/workspace | cwd only | directory | directory | none | none | directory/host/session/workspace |
| Sequence learning | pairwise transitions + 3-step workflows | no | pairwise | pairwise | no | no | no |
| Workflow (3+ step) learning | **yes (unique)** | no | no | no | no | no | no |
| Failure→recovery learning | **yes (unique)** | no | no | no | no | no | no |
| Ghost UI | RBUFFER/region_highlight | own PTY overlay | POSTDISPLAY/region_highlight | POSTDISPLAY | inline menu | ANSI popup (PTY) | n/a |
| Candidate/menu UI | custom `zle -R` HUD | own menu | Tab-cycle alternatives | Ctrl+N cycle | menu-select | ANSI popup | full-screen TUI (`^R`) |
| Up/Down semantics | context-aware: HUD vs history | own history | n/a (ghost only) | n/a (ghost only) | menu nav | n/a | n/a |
| Scrolling | custom PgUp/PgDn in HUD | n/a | n/a | n/a | menu | n/a | TUI native |
| Completion | native `compinit` | own | n/a (defers to shell) | filename fallback only | own async engine | own (specs) | n/a |
| Atuin integration | direct (`history list --format`) | none | none (own DB) | none (own DB) | none | none | is Atuin |
| Zsh compatibility | native | shell-agnostic (PTY) | zsh only | zsh only | zsh only | zsh-primary (PTY) | any (shell-agnostic) |
| Bash/Fish/TTY | n/a | yes (any shell) | no | no | no | yes (any shell) | yes |
| SSH | via Atuin | yes (one config) | yes (needs daemon reachable) | yes | yes | yes | yes |
| tmux | works | yes | works | works | works | works | works |
| Startup cost | lazy, async warm-up | none (external process) | ~0.08ms integration check | coproc spin-up | **confirmed slow, hangs reported 2026** | none (external process) | daemon optional |
| Runtime latency | not benchmarked in repo | n/a | <1ms (daemon) | ~2ms (coproc) | reported lag on completion | n/a | <1ms (daemon-fuzzy) |
| Memory | not benchmarked | <15MB (own claim) | daemon process | ~1MB coproc | in-process | own claim n/a | daemon process |
| Extensibility (3rd-party candidate injection) | n/a (is the source) | **none documented** | **none documented** | **none documented** | zstyle-based | **none documented** | CLI/format flags only |
| Maintenance | single maintainer (the user) | 2 contributors, WIP label, active bugs | 1 maintainer, automated releases, 560★ | 1 maintainer, 105★ | 1 maintainer, 6.4k★, active but has real perf issues | active dev, no maturity signal | large team, Anthropic-adjacent ecosystem, frequent releases |
| User sentiment | (the reason for this research) | too young for signal | positive, growing | too young for broad signal | mixed — praised for features, criticized for startup cost/hangs | too young for signal | broadly positive, mature |
| Known conflicts | internal double-wrap (§2) | n/a (proxy, but replaces shell's own line editing) | explicitly refuses to coexist with `zsh-autosuggestions` | none documented | fzf-completion interaction issues reported | n/a | none |

---

## 13. Final recommendation

**OPTION B: Refactor-in-place, not replace.** None of Options "adopt IRIS," "adopt Deja/zsh-sage as backend," or "adopt zsh-autocomplete/Ghost Complete" survive the research (§10). The three real options given what actually exists in the ecosystem today are:

- **Option A — Full external delegation.** Rejected: no researched project exposes the extension points KRQ#1–4 required (§3–6). Would require forking + maintaining a fork of someone else's young, single-maintainer project — strictly worse than the current situation.
- **Option B — Refactor Flow's own Phase 8/9 in place, borrowing patterns (not code) from Deja/zsh-sage, keep Atuin as-is-but-more, add fzf-tab as a purely orthogonal completion-UI improvement.** **Recommended.**
- **Option C — Minimal Flow, maximal delegation of *editing only*, drop the predictive HUD entirely and rely on Atuin's `^R` + a mature autosuggestions plugin (Deja).** Viable *if* the user is willing to give up workflow/recovery intelligence and the "ghost is a deterministic prediction of *my* behavior" goal — this is a legitimate fallback if Option B's refactor doesn't reduce fragility enough, but it's a downgrade from the stated product goal, not a lateral move.

**Recommendation: Option B.**

---

## 14. Direct answers

- **Should Flow keep its custom editor?** Yes — it's small (279 lines), already delegates undo/redo natively, and nothing researched offers a Ctrl+Shift selection/clipboard scheme to delegate to. Low risk as-is.
- **Should Flow keep its custom HUD?** Yes, but simplified — no mature project (§3–6) will render Flow's own ranked, explained candidates. The concept is correct; the redraw/keymap-delegation logic should be consolidated (§2).
- **Should Flow keep its custom ghost implementation?** Yes — `RBUFFER`+`region_highlight` is literally the same primitive Deja and zsh-sage use (`POSTDISPLAY`/`region_highlight`). The pattern is industry-standard; only the widget-wrapping plumbing around it needs simplification.
- **Should Flow keep its custom Up/Down interception?** Yes — this is the mechanism that makes "single high-confidence match → normal history nav, multiple matches → HUD" work, and it's a Flow-specific UX decision no external tool makes for you.
- **Should Flow keep its custom aggregate database?** Yes — deliberately decoupled from Atuin by design (derived stats, not raw history), which is correct: it means switching Atuin search modes (e.g. to `daemon-fuzzy`) never risks Flow's own learned state.
- **Should Flow use IRIS?** No — PTY-proxy architecture, WIP status, no candidate-injection API (§3).
- **Should Flow use Deja?** Not as a backend/frontend — no injection API (§4). Could optionally be shelled out to as *one more read-only signal source* the same way Atuin is, but this is optional and not required.
- **Should Flow use zsh-sage?** No, for the same reason as Deja (§5) — and it duplicates signals Flow already computes more completely (it lacks workflow/recovery tracking).
- **Should Flow use zsh-autocomplete?** No — demonstrated startup-hang/latency issues in current 2026 issue reports violate the stated performance budget (§8).
- **Should Flow use zsh-autosuggestions?** No — functionally subsumed by Flow's own predictor already.
- **Should Flow use Ghost Complete?** No — PTY-proxy, same problem class as IRIS (§6).
- **Should Flow use fzf-tab?** Yes, optionally — it's orthogonal (native Tab-completion picker only), doesn't touch ghost/HUD/prediction, zero conflict risk, real quality-of-life win. Independent decision from everything else in this report.
- **Should Flow combine any of these?** Atuin (history/frecency backend, lean on `daemon-fuzzy` more) + Flow's own refactored predictor (ghost/HUD/ranking, unchanged in *responsibility*, changed in *implementation cleanliness*) + optional fzf-tab (completion UI only). That's the combination — everything else stays custom because nothing else is delegable as researched.

---

## RECOMMENDED ARCHITECTURE

```
                              FLOW
                               │
                 ┌─────────────┼─────────────────┐
                 │             │                 │
             Context        History           Editing
        project/profile/    (Atuin,          (native ZLE:
      runtime/workspace/   daemon-fuzzy      MARK/REGION_ACTIVE,
        git/session          mode when          undo/redo)
                 │           available)             │
                 │             │                 │
                 └──────┬──────┘                 │
                        ▼                        │
                 Flow Predictor Core              │
          (single module: history/transition/     │
           workflow/recovery/session providers     │
              → dedupe → context score →           │
                 rank → confidence)                │
                        │                          │
                        ▼                          │
              Flow Presentation Layer  ◄────────────┘
        (ONE widget-wrap entry point, not three:
         ghost via RBUFFER/region_highlight,
         HUD via zle -R + dedicated keymap,
         Up/Down router)
                        │
                        ▼
              native compinit (+ optional fzf-tab
                 for the Tab-completion picker only)
                        │
                        ▼
                     Zsh / TTY
```

Key difference from today: **one** widget-wrapping entry point instead of two independent ones (editor + predictor each wrapping their own widget lists). The editing layer registers its widgets first and hands the predictor a single "notify me before any buffer-mutating widget runs" hook, rather than the predictor separately re-wrapping the editor's own `flow_paste`/`flow_cut`/etc. widgets.

---

## REMOVE

- The **duplicate wrapping** of `flow_paste flow_cut flow_delete_backward flow_delete_forward flow_select_all flow_copy` inside `90-flow-predictor.zsh`'s `_flow_pred_wrap_widget` loop (lines ~600) — these are already Flow's own widgets; ghost-clearing on them should be a direct call from `45-flow-editor.zsh`, not a second wrap layer.
- The runtime `bindkey -M main "$KEYS"` lookup inside `_flow_pred_g_$w` for `self-insert` (lines ~572–582) — replace with a static, load-time-computed set membership check.
- The parallel, near-identical `bindkey -M main "$KEYS"` delegation logic in `_flow_pred_hud_delegate` (lines ~804–813) — unify with the above into one shared helper.
- The three separate "is this cached prediction still fresh" checks (`_fp_last_typed` comparisons in `_flow_pred_on_redraw`, `_flow_pred_hud_open`, and `flow_pred_debug`) — consolidate into one `_flow_pred_ensure_fresh(buf)` function.

## KEEP

*(Full-delegation path — supersedes the "keep the editor" line from the original pass; see §16.)*

- `30-history.zsh` Atuin integration — correct as-is; extend rather than replace (see ADOPT).
- Native `compinit`-based completion in `20-completion.zsh`.
- **Nothing from `45-flow-editor.zsh` or `90-flow-predictor.zsh`/`flow_predictor.sh`.** Both are fully removed under this path. This means giving up the workflow/recovery/rich-HUD intelligence that was Flow's differentiator (§11) — a deliberate, informed trade-off in exchange for zero maintenance burden on ZLE code, made explicit here rather than smuggled in.

## ADOPT

- **`Michael-Matta1/zsh-edit-select`** — role: full replacement for `45-flow-editor.zsh`. Provides Shift-selection, Ctrl+A/C/X/V, Ctrl+Z/Ctrl+Shift+Z undo/redo, mouse-selection integration, type/paste-to-replace, in emacs keymap, with OSC52-based SSH support out of the box. Requires one-time Kitty config (a handful of `map` lines so Kitty forwards `Ctrl+Shift+Left/Right/Home/End` and the undo/redo/copy sequences to zsh instead of consuming them itself — see the plugin's Kitty section). *Lower-risk fallback if preferred:* `jirutka/zsh-shift-select` for selection only (kill-ring copy/paste, no system clipboard, no mouse integration, narrower scope, same emacs-mode compatibility).
- **Deja** (`Giammarco-Ferranti/deja`) — role: full replacement for `90-flow-predictor.zsh`/`flow_predictor.sh`. Ghost-text suggestions from its own frecency+directory+sequence engine, Tab-cycle through alternatives, `deja import` to seed from existing zsh history. Configured entirely via `DEJA_*` env vars (highlight style, fuzzy strictness, accept/cycle keys, empty-prompt suggestions) — no shell code to maintain. Trade-off: no workflow (3+ step) or failure→recovery modeling, and no rich multi-candidate HUD with reasons/counts — Deja's UI is ghost text + Tab-cycle, not a `zle -R` menu.
- **fzf-tab** (`Aloxaf/fzf-tab`) — role: replace the native Tab-completion menu in `20-completion.zsh`. Independent of the above two, zero conflict risk.
- **Atuin `daemon-fuzzy` search mode** — role: keep Atuin as the `Ctrl+R` history-search backend (Deja does ghost-text prediction, not full-history search — they don't overlap); optionally switch to `daemon-fuzzy` for faster search, no code change required, just a config toggle.
- **Not adopted:** IRIS, Ghost Complete, zsh-autocomplete, zsh-autosuggestions, zsh-system-clipboard (vi-only), Flyline/ble.sh (Bash-only), zsh-sage (redundant with Deja) — reasons in §3–8, §14, §16.

---

## MIGRATION PLAN (full delegation — supersedes the refactor-in-place plan for editor+predictor)

1. **Install Deja in isolation first**, predictor untouched. `deja import` to seed from existing zsh history, tune `DEJA_*` env vars, live with it for a few days before touching anything else. This validates the biggest behavior change (losing workflow/recovery/rich HUD) before committing.
2. **Disable, don't delete, `90-flow-predictor.zsh` and its `flow_predictor.sh` sourcing** (comment the `source` line, or gate behind an env var) once Deja feels adequate — keeps a fast rollback path for the first week.
3. **Install `zsh-edit-select` in isolation**, `45-flow-editor.zsh` untouched but with its widget-wrapping temporarily disabled to avoid a double-wrap conflict during the trial period. Add the required Kitty `map` lines. Run through Shift-select, Ctrl+A/C/X/V, undo/redo, and mouse-selection to confirm parity with what you actually use day to day (the plugin does more than Flow's editor — e.g. mouse-selection replace — so check nothing you rely on is missing, not just that nothing broke).
4. **Disable, don't delete, `45-flow-editor.zsh`'s sourcing** once satisfied.
5. **After both trials are stable (recommend ≥1 week of real use each), delete `45-flow-editor.zsh`, `90-flow-predictor.zsh`, and `sdata/lib/flow_predictor.sh`** from the loaded config (file removal or `zshrc.d` exclusion — repo history keeps them recoverable regardless).
6. **Add fzf-tab** in `20-completion.zsh`, independent of the above, gated behind `command -v fzf` as already done for the fzf key-bindings block in `40-keybindings.zsh`.
7. **Re-benchmark shell startup** — with two more plugins in the load path (Deja + zsh-edit-select) instead of one large in-repo file, confirm you're still comfortably inside the `<100ms` startup budget; both are individually lightweight per their own docs, but measure your actual setup rather than trusting the vendor numbers.

Rollback at every step is "re-enable the `source` line" until step 5, so nothing is a one-way door until you've actually lived with the replacement.

---

## RISKS

- **Refactor risk, not elimination risk.** This plan does not remove the largest source of *inherent* complexity (a from-scratch predictive ZLE engine) — it removes the accidental complexity (double-wrapping) layered on top of it. Flow will still be maintaining ~1,000+ lines of custom ZLE code indefinitely, because no researched alternative can absorb that responsibility (§10).
- **Ecosystem immaturity cuts both ways.** IRIS/Deja/zsh-sage/Ghost Complete are all young (mostly 2025–2026 vintage per commit history) — re-researching in 6–12 months could surface a documented provider API in one of them (Deja's daemon/socket protocol in particular is the most plausible candidate to eventually expose one, given it already has a structured query surface). This report reflects the ecosystem as of **2026-08-21**; it is not a permanent verdict.
- **`fzf-tab` and Atuin `daemon-fuzzy` are both new moving parts**, even though low-risk — test them independently of the predictor refactor so a regression in one doesn't get attributed to the other.
- **CI/regression coverage for ZLE code is inherently awkward** (headless keystroke simulation is finicky) — step 1 of the migration plan is itself nontrivial and should not be skipped just because it doesn't ship user-visible value.
- **No privacy/security regressions identified** — Flow's local-only, no-telemetry, no-cloud posture is unaffected by any recommendation here; Atuin's optional `atuin ai` and zsh-sage's optional `hm` were both confirmed off-by-default and are not being enabled by anything in this plan.

---

---

## 16. FULL DELEGATION — editor layer research (addendum)

The first pass concluded "keep the editor, it's small and not the pain point." Taken at face value that the editor genuinely is a source of the same headache, here is the dedicated research into whether it can be **fully** replaced, done the same way as the rest of this report (live repo/README inspection, not memory).

### Candidates checked

| Project | Verdict |
|---|---|
| `kutsan/zsh-system-clipboard` | **Not viable as-is.** Real, maintained, but explicitly **vi-mode only** — its own README states emacs-keymap widget functions "are not yet written" (issue #12, open for years). Flow uses `bindkey -e`. Adopting it means switching Flow's entire editing modality to vi, which is a much bigger change than "replace the clipboard plugin." |
| `HalFrgrd/flyline` / `Kamyil/flyline-zsh` | **Not viable.** Confirmed still Bash-only — the "flyline-zsh" fork has an unmodified Bash README (`enable -f libflyline.so`, `.bashrc` references throughout), 0 stars/forks, no zsh-specific code. Not a real port. |
| `ble.sh` | **Not viable.** Bash-only, same as Flyline. |
| `jirutka/zsh-shift-select` | **Real and mature**, works in emacs mode, Shift+Arrow/Home/End/word selection via a dedicated `shift-select` keymap that doesn't override any existing widget. Deliberately scoped: **does not do clipboard sync itself** — copy/cut/paste stays on ZLE's internal kill-ring (`copy-region-as-kill`/`yank`) unless paired with a separate clipboard tool. Good minimal option if you're fine with kill-ring-only copy/paste (not system clipboard). |
| **`Michael-Matta1/zsh-edit-select`** | **Best match found — recommended.** A complete, actively-developed zsh plugin providing exactly Flow's Ctrl+Shift namespace: Shift+Arrow/Home/End/word/buffer selection, Ctrl+A select-all, Ctrl+C/X/V copy/cut/paste, Ctrl+Z/Ctrl+Shift+Z undo/redo, type-to-replace and paste-to-replace over a selection, and **mouse-selection integration** (select with the mouse, then Backspace/type/Ctrl+C acts on it) — which is more than Flow's current editor does. Ships an interactive `edit-select config` wizard for rebinding every key, works natively in emacs keymap (no modality change), and has explicit, tested config blocks for Kitty specifically (Flow's own terminal per its architecture notes), plus WezTerm/Ghostty/Alacritty/VS Code/iTerm2/Windows Terminal. |

### Why `zsh-edit-select` is a genuine fit, not just "another option"

- **Architecture is more robust than what you'd maintain yourself:** copy/cut/paste run through small compiled C agents (X11/Wayland/WSL/macOS-specific), event-driven via XFixes/Wayland-compositor selection-owner notifications — not polling — so idle cost is zero and typing-path cost is one `stat()` syscall. This is a materially more careful implementation than a shell-script backend-detection block.
- **SSH handled automatically:** detects `$SSH_CLIENT`/`$SSH_TTY`/`$SSH_CONNECTION` and switches to OSC 52 transparently — no config needed, which is exactly the "works everywhere" property you'd otherwise have to build yourself.
- **Direct buffer splicing, not kill-region, for paste/replace** — avoids corrupting the ZLE kill-ring, a subtlety that's easy to get wrong in hand-rolled code (and a plausible contributor to some of Flow's current breakage).
- **Maturity caveat, stated plainly:** 19 stars, single maintainer, young (recent commit activity, no long track record). Same category of risk as Deja/zsh-sage in §4–5 — real and well-engineered, but not a decade-old dependency. If that risk profile is a concern, `jirutka/zsh-shift-select` (selection only, kill-ring copy/paste) is a smaller, narrower, lower-risk fallback that still eliminates the custom Ctrl+Shift plumbing, just without system-clipboard sync or mouse integration.

### What full delegation costs you here

- You give up exact control over the Ctrl+Shift namespace's edge-case behavior (e.g., the "duplicate text" mouse-selection safeguard is the plugin's design choice, not yours to tune beyond its config wizard).
- Terminal-side config is required (a handful of keybind lines in `kitty.conf` to stop Kitty from eating `Ctrl+Shift+Left/Right` etc. before they reach zsh) — this is one-time setup, not ongoing maintenance, but it is a dependency on terminal config staying in sync with the plugin.
- Undo/redo semantics move from Flow's own to the plugin's — functionally equivalent (native `undo`/`redo` under the hood either way) but no longer something you'd patch yourself.

---

## WHY THIS IS BETTER THAN CURRENT FLOW

- **Fixes the actual, demonstrated root cause** (double/triple widget-wrapping, §2) instead of a plausible-sounding but unproven one ("ZLE ghost rendering is inherently fragile" — it isn't; Deja and zsh-sage use the identical primitive without the reported instability, because they only wrap their own widgets once).
- **Preserves the product's actual differentiator** — workflow (3-step sequence) and failure→recovery learning — which genuinely does not exist in any researched alternative, so replacing the engine would be a regression dressed up as a modernization.
- **Reduces real maintenance surface** (fewer wrapping layers, one consolidated freshness-check helper, a split file structure) without taking on a new, larger maintenance surface (forking a WIP PTY-proxy binary, or vendoring/patching a single-maintainer plugin with no extension API).
- **Every adopted piece (fzf-tab, Atuin `daemon-fuzzy`) is independently toggleable and orthogonal**, so it can be rolled back individually if it doesn't pan out — unlike a full engine swap, which would be all-or-nothing.
- **Matches the researched maturity levels honestly**: it doesn't bet the shell's reliability on 2026-vintage, single-maintainer, WIP-labeled projects for a role (ghost/HUD rendering driven by external ranking) none of them were designed to fill.
