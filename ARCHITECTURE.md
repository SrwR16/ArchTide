# Flow Terminal — Architecture & Decision Record

> Living document. Every architectural decision gets a dated entry here so
> past-us never relitigates settled questions. Last updated: 2026-08-23.

---

## 1. What Flow Is

Flow Terminal is a **production-grade DevOps workstation**: a Material-themed,
context-aware terminal environment where the shell understands which project
you are in, which profile you are working under, and how risky the command you
are about to run is — without demanding that any repository adopt
Flow-specific files.

**Design principle (locked):**

> Flow owns presentation. Zsh owns interaction. The project engine owns
> context. mise/uv own environments. DevOps CLIs own operations.
> Nothing does another layer's job.

---

## 2. Target Architecture

```text
                              FLOW
                               │
                    Material Expressive
                    (matugen → colors.json)
                    ├── QuickShell (desktop)
                    ├── Kitty (terminal)
                    ├── Starship (prompt)
                    └── zsh highlighting        [pending]
                               │
                             Kitty
                               │
                              Zsh
              ┌────────────────┼────────────────┐
            Shell         Project Engine      Prompt
              │                │                │
      completion/history  detect·profiles   Starship
      keybinds/engine     activation        ← consumes FLOW_* state
      syntax/zoxide       trust store
              │
      ┌───────┼──────────────────────────┐
    Python   Node/Go/Rust             DevOps
     uv       mise                  k8s/docker/tf/aws/ansible
```

---

## 3. Layer Contracts

| Contract | Rule |
|---|---|
| Repos are never modified to remember preferences | All Flow state lives in `~/.local/state/flow/` |
| Detection is read-only and cached | Runs on project-root change (git toplevel), 6h TTL cache, `timeout 3` bound |
| Activation is explicit | Only safe actions auto (runtime versions, existing venv, PATH). AWS/K8s/TF context, prod profiles: named confirmation required. Unknown contexts are never switched |
| Prompt renders state, never discovers it | Starship reads `FLOW_*` env vars; zero subprocess forks per render (file-marker "noise" modules are legacy debt, being retired) |
| One intelligence store | `aggregates.tsv` is the single source for commands, success rates, directory evidence, transitions. Writers: engine recorder only |
| Startup ≤ 100ms | Currently ~87ms. Tool-init forks are cached (`_flow_cached_eval`, weekly TTL). No network at startup |
| Engines fail silent | A broken suggestion layer must never break the prompt or a running command |

---

## 4. System Map (what lives where)

| Component | Path | Notes |
|---|---|---|
| **Flow Engine** (suggestions) | `engine/` — Go, module `github.com/SrwR16/flow-engine` | Vendored from IRIS v0.6.4 (0BSD), upstream intentionally severed. PTY wrapper: ghost text, candidate menu, key interception, word-wise accept (`Ctrl+→`/`Alt+F`) |
| ↳ Flow provider | `engine/internal/flow/` | Reads the aggregate store; dir-context ranking, success-rate weighting, `./` script discovery, recovery pairs |
| ↳ Scoring adapter | `engine/internal/scoring/frecency.go` | Same public API as upstream, backed by the Flow store instead of SQLite |
| Intelligence store | `~/.local/state/flow/predictor/aggregates.tsv` | Canonical schema=1: `C`ommands / `T`ransitions / `W`orkflows / `R`ecoveries. Written by `iris record` (zsh hook, async, atomic) |
| Project detector | `sdata/subcmd-project/detect.sh` | Read-only; languages/frameworks/containers/infra/ci_cd with confidence+evidence; JSON mode |
| Profiles & activation | `sdata/subcmd-project/{profile,activate,env}.sh` | State: `~/.local/state/flow/projects/<sha256-16>.json`. Eval-based, idempotent, rollback-on-failure |
| Shell fragments | `dots/.config/zshrc.d/*.zsh` | Numbered load order via `~/.config/zsh/.zshrc` bootstrap (`FLOW_ZSH_LOADED` guard). Starship initializes last |
| Theme pipeline | `dots/.config/matugen/` + QuickShell scripts | wallpaper → matugen → tokens → QuickShell/Kitty/starship palette/**engine theme.toml** |
| Installer / CLI | `setup-flow.sh` (symlinked as `flow`) | Deploys configs, builds+installs engine, mirrors `sdata/`; `--extras` covers mpv/kitty/zshrc.d/starship/matugen |

---

## 5. Decision Record

### D-001 · 2026-08-22 — Own the presentation engine: vendored IRIS fork
Custom ZLE predictor (1,124 lines, triple widget-wrapping) was unstable and deleted. From-scratch Go/Rust engine rejected: PTY proxying + VT parsing + rendering is years of edge cases. IRIS is **0BSD** ("no strings attached") — cloned into `engine/`, module renamed, upstream merges not planned. Thin-patch discipline: providers/features yes, rendering core never.
*Corollary:* `github.com/versenilvis/fuzzy` stays as an ordinary library dependency.

### D-002 · 2026-08-23 — One intelligence store
Two brains (IRIS SQLite frecency vs frozen `aggregates.tsv`) caused stale ranking and divergent learning. Everything consolidated into the TSV (C/T/W/R records); `FrecencyStore` became an in-memory adapter over it; SQLite dropped from ranking. *Accepted cost:* permanent divergence from upstream's persistence layer. *Note:* the sqlite driver remains solely to read Atuin's DB (`atuin-history=1`).

### D-003 · 2026-08-23 — Updater deleted
A fork must never fetch upstream releases that would overwrite it. `autoupdate.go`/`update.go`/changelog command removed; `updater.check-on-startup=false` enforced by default.

### D-004 · 2026-08-23 — Navigation split: literal `cd`, deliberate `z`
zoxide aliased `cd→z`, so `cd Programming/` fuzzy-jumped to the hottest match (ArchTide) from directories where the path didn't exist — surprising and wrong-feeling. Now: `cd` is stock builtin; `z <fragment>` fuzzy-jumps; `z <exact-name>` resolves exact dirs first (common roots); `zi` interactive.

### D-005 · 2026-08-23 — Projects are git repositories
Detection keys off `git rev-parse --show-toplevel`. Non-git directories can never become phantom projects — this also immunizes against init scripts transiently cd-ing through plumbing dirs. Hints fire once per root, ever (persisted `.hinted` markers); silenced permanently once a profile state file exists.

### D-006 · 2026-08-23 — Suggestion UX direction (parked, not dead)
Menu chrome reduced (flow candidates present as native history rows). Research converged on IDE-grade patterns worth building later, in priority order: G1 Pure-Ghost cycling (Zed/Copilot paradigm), G2 hint-key selection (zero navigation), G3 explain-on-hold cards, recovery-ghost after failures (unique to Flow's data). Deferred until the platform work stabilizes.

### D-007 · 2026-08-22 — Record contract is canonical and versioned
History of corruption (space-joined stats blobs, sticky padding, `$'\x1f'` quoting leaks, literal `\t` strings) ended by contract: producers call `flow_pred_encode_cmd_record` / `iris record`; readers use one tolerant parser (canonical ≥5-tab rows, legacy padded blobs normalized, key-only rows preserved as degraded). Loader semantics: last-wins.

### D-008 · 2026-08-22 — Material theme is generated, four surfaces
Wallpaper → matugen → tokens → QuickShell, Kitty, Starship palette, and now `~/.config/iris/theme.toml`. Registered in matugen config as `[templates.flow_engine]`.

### D-009 · 2026-08-23 — Startup performance is a product requirement
Target ≤100ms interactive. Current ≈87ms. Techniques locked in: single compinit, `_flow_cached_eval` (weekly-TTL caches for atuin/mise/starship/direnv/zoxide inits — five forks replaced by file sources), project detection deferred to first precmd. Remaining costs are behavioral (mise env hook, compinit audit, syntax highlighting) — cutting them means feature trade-offs.

### D-010 · 2026-08-23 — Danger gate removed (built, then retired)
Phase 8 shipped twice: engine-side (typed confirmation at Enter) and shell-side (accept-line wrapper). Both worked in isolation but conflicted with the engine's Enter ownership, the inline strip fought overlay redraws, and mid-session context switching needed /proc-environ tricks to arm correctly. Net: more friction than protection at current maturity. Removed fully (engine package, wrapper hooks, config field, shell fragment). The **production prompt segment (⚠ + context name) remains** as the standing safety signal. Revisit only if a real incident demands hard gating.

### Historical (pre-this-document, honored)
- Custom ZLE predictor/HUD deleted in favor of engine-native presentation — root cause of instability was triple widget-wrapping plus the broken record pipeline (now fixed), not ZLE itself.
- Atuin remains the history search surface (`^R`); Flow's aggregates are derived analytics, deliberately decoupled.
- Fish stays installed as optional secondary, unmaintained by Flow.

---

## 6. Data Contracts

### aggregates.tsv (schema=1)
```
# flow-predictor schema=1
C  KEY  COUNT SUCCESS FAIL LAST_TS FIRST_TS DIRS CLASS     DIRS="dir:count:ts,…"
T  PREV<US>NEXT  COUNT SUCCESS LAST_TS                        US = \x1f
W  C1<US>C2<US>C3 COUNT SUCCESS LAST_TS
R  FAILED<US>FIX  COUNT SUCCESS LAST_TS
```
- TAB-separated; keys may contain spaces, never TAB/newline.
- Readers: last-wins per key; tolerant of legacy padded rows.
- Writers: `iris record` / `RecordTransition` only (atomic tmp+rename).

### Project state
`~/.local/state/flow/projects/<sha256(root)[0:16]>.json`
```json
{ "profiles": { "<name>": { "name","type","scope","environment":{…} } },
  "default_profile": "<name>" }
```

### Environment/state variables (consumed by Starship)
`FLOW_ENV_PROFILE TARGET ROOT LANGUAGE STRATEGY VENV ACTIVATED NODE_VERSION …`
mirrored to `FLOW_STARSHIP_*` equivalents by the state loader.
Planned: `~/.local/state/flow/trust.json` gating any future auto-environment.

### Engine ⇄ shell protocol (inherited from IRIS)
`IRIS_PID / IRIS_FD / IRIS_CWD:<pwd> / IRIS_CMD_START / IRIS_CMD_STOP:<code>`
— stable wire format; renaming deferred until feature set stabilizes (tracked as "deep rebrand").

---

## 7. Roadmap Status

| Phase | Scope | Status |
|---|---|---|
| 0 | Cleanup (legacy predictor, HUD) | ✅ done |
| 1 | Lean modular Zsh foundation | ✅ done (startup ≈87ms) |
| 2 | Project detector | ✅ done (exceeds spec) |
| 3 | Profiles + external state | ✅ wired end-to-end |
| 4 | Runtime activation (mise/uv/direnv) | ✅ safe-only path live |
| 5 | Starship state-driven prompt | ✅ core done; file-noise modules retirement pending |
| 6 | Material theming | ✅ four surfaces (highlighting pending) |
| — | Flow Intelligence engine | ✅ single-store, live-learning |
| — | Flow Engine (fork) ownership + provider | ✅ this document's era |
| 7 | DevOps context providers (AWS/K8s/TF/SSH) | ⬜ needs Tier-1 tools |
| 8 | Production safety gate | 🚫 removed (D-010) |
| 9 | Tier-1 toolchain installs | 🔶 partial (git, docker) |
| 10 | Kitty polish | ⬜ |
| 11 | Benchmarks + docs | 🔶 benchmarks inline; this doc started |
| — | Trust store v0 | ⬜ small; before any auto-env |
| — | bats tests (detect/activate/env/parser) | ⬜ rides with phase 7 |
| — | Deep rebrand (binary name, config paths, protocol vars) | ⬜ deliberate, after features stabilize |

---

## 8. Operations

```bash
# Deploy everything current (configs + engine build):
bash setup-flow.sh apply -y [--extras]

# Fresh machine:
bash setup-flow.sh install -y

# Rebuild engine only:
cd engine && go build -o iris ./cmd/iris && rm -f ~/.local/bin/iris && cp iris ~/.local/bin/iris

# Regenerate theme after wallpaper change:
matugen image <wallpaper> --prefer darkness

# Inspect the intelligence store:
cat ~/.local/state/flow/predictor/aggregates.tsv

# Query suggestions (CLI, always available):
flow suggest "" | flow suggest "git " | flow suggest "./" [--json]
```

Rollback paths: engine binary backup at `~/.local/bin/iris.bak` (if present);
Quickshell config swaps keep timestamped backups automatically.
