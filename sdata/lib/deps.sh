# Flow bootstrap — dependency registry.
#
# Sourced by setup-flow.sh. A single structured registry drives install and
# doctor, so package knowledge lives in one place instead of being repeated in
# checks all over the installer.
#
# Tiers:
#   core     — the minimal Flow terminal (required)
#   ux       — recommended ergonomics (optional)
#   devops   — DevOps profile, installed only on request (optional)
#   terminal — font/terminal verification (never force-installed)
#
# API:
#   flow_dep <key> <tier> <package> <reason> [bin]
#   deps_entries                        -> all registry lines "key tier pkg reason bin"
#   deps_by_tier <tier>                 -> keys in that tier
#   deps_missing <tier...>              -> keys whose binary is absent
#   deps_packages <keys...>             -> package names for keys
#   deps_installed <key>                -> 0 when the binary exists
#   deps_version <key>                  -> prints the installed version (best effort)
#   deps_tier_label <tier>              -> human label
#
# Bins are preferred over package queries: presence of the executable is the
# capability we care about, and it correctly recognizes tools installed via
# cargo, mise shims, or the AUR without forcing package ownership.

declare -g -a FLOW_DEPS=()

flow_dep() {
    local key="$1" tier="$2" pkg="$3" reason="$4" bin="${5:-$key}"
    FLOW_DEPS+=("$key|$tier|$pkg|$reason|$bin")
}

deps_entries() {
    local e
    for e in "${FLOW_DEPS[@]:-}"; do
        printf '%s\n' "$e"
    done
}

deps_by_tier() {
    local tier="$1" e key t
    for e in "${FLOW_DEPS[@]:-}"; do
        key="${e%%|*}"
        rest="${e#*|}"
        t="${rest%%|*}"
        if [[ "$t" == "$tier" ]]; then
            printf '%s\n' "$key"
        fi
    done
}

deps_installed() {
    local key="$1" e bin
    for e in "${FLOW_DEPS[@]:-}"; do
        [[ "${e%%|*}" == "$key" ]] || continue
        bin="${e##*|}"
        have "$bin"
        return $?
    done
    return 1
}

deps_missing() {
    local tier k
    for tier in "$@"; do
        while IFS= read -r k; do
            [[ -z "$k" ]] && continue
            deps_installed "$k" || printf '%s\n' "$k"
        done < <(deps_by_tier "$tier")
    done
}

deps_packages() {
    local key e key_ tier pkg reason bin
    for key in "$@"; do
        for e in "${FLOW_DEPS[@]:-}"; do
            IFS='|' read -r key_ tier pkg reason bin <<<"$e"
            [[ "$key_" == "$key" ]] || continue
            printf '%s\n' "$pkg"
            break
        done
    done
}

deps_reason() {
    local key="$1" e key_ tier pkg reason bin
    for e in "${FLOW_DEPS[@]:-}"; do
        IFS='|' read -r key_ tier pkg reason bin <<<"$e"
        [[ "$key_" == "$key" ]] || continue
        printf '%s\n' "$reason"
        return 0
    done
    return 1
}

deps_bin() {
    local key="$1" e key_ tier pkg reason bin
    for e in "${FLOW_DEPS[@]:-}"; do
        IFS='|' read -r key_ tier pkg reason bin <<<"$e"
        [[ "$key_" == "$key" ]] || continue
        printf '%s\n' "$bin"
        return 0
    done
    return 1
}

# Best-effort first-line version of a tool. Kept in deps.sh because doctor and
# install both want it, and nothing else in the shell startup path should.
# Never fails: an unparseable tool just yields an empty version, which callers
# treat as "version unknown" (a failing command substitution would otherwise
# trip the installer's ERR trap).
tool_version() {
    local bin="$1" out v
    out="$("$bin" --version 2>/dev/null | head -n3)"
    [[ -z "$out" ]] && out="$("$bin" version 2>/dev/null | head -n3)"
    v="$(printf '%s' "$out" | head -n1)"
    # Drop trailing ")..." parentheticals and anything from the first " (" on.
    while [[ "$v" == *\) ]]; do
        v="${v%)}"
        v="${v%%(*}"
    done
    v="${v##* }"
    # Not version-shaped (e.g. eza's tagline)? Pull a semver-ish token.
    if [[ ! "$v" =~ ^[vV]?[0-9] ]]; then
        v="$(printf '%s' "$out" | grep -oE '[vV]?[0-9]+(\.[0-9]+){1,4}(-[0-9A-Za-z.]+)?' | head -n1)"
    fi
    printf '%s' "$v"
    return 0
}

deps_tier_label() {
    case "$1" in
        core) printf 'Core' ;;
        ux) printf 'UX' ;;
        devops) printf 'DevOps' ;;
        terminal) printf 'Terminal' ;;
        *) printf '%s' "$1" ;;
    esac
}

# ── Registry ──────────────────────────────────────────────────────────────────
# Validated against the repo: every entry below is actually referenced by a
# zshrc.d module, the Starship config, or the Flow project engine. Nothing is
# installed just because it sounds useful.

flow_dep zsh core zsh "Zsh shell (Flow shell runtime)" zsh
flow_dep git core git "Git (project detection, Flow updates)" git
flow_dep starship core starship "Starship prompt" starship
flow_dep mise core mise "Runtime version manager (project profiles)" mise
flow_dep direnv core direnv "Per-project environment switching" direnv
flow_dep atuin core atuin "Shell history (local only, no sync)" atuin
flow_dep fzf core fzf "Fuzzy finder" fzf
flow_dep fd core fd "Fast find (FZF default command)" fd
flow_dep ripgrep core rg "Fast grep (zshrc.d, FZF)" rg
flow_dep zoxide core zoxide "Smarter cd (zshrc.d)" zoxide

flow_dep bat ux bat "Syntax-highlighting cat (zshrc.d aliases)" bat
flow_dep eza ux eza "Modern ls (zshrc.d aliases)" eza
flow_dep lazygit ux lazygit "Terminal git UI (zshrc.d alias lg)" lazygit

flow_dep docker devops docker "Containers" docker
flow_dep kubectl devops kubectl "Kubernetes CLI" kubectl
flow_dep helm devops helm "Kubernetes package manager" helm
flow_dep terraform devops terraform "Infrastructure as code (Terraform)" terraform
flow_dep opentofu devops tofu "OpenTofu (Terraform drop-in)" tofu
flow_dep ansible devops ansible "Configuration management" ansible
flow_dep gh devops github-cli "GitHub CLI" gh
flow_dep aws-cli devops aws-cli "AWS CLI" aws
flow_dep k9s devops k9s "Kubernetes TUI" k9s
flow_dep stern devops stern "Multi-pod log tailing" stern
flow_dep kubectx devops kubectx "Kube context switcher" kubectx
flow_dep kubens devops kubectx "Kube namespace switcher (part of kubectx)" kubens
flow_dep lazydocker devops lazydocker "Docker TUI" lazydocker
flow_dep delta devops git-delta "Diff pager" delta

# Fonts are verified, never force-installed: the terminal font preference is the
# user's own. `package` is the pacman extra package that satisfies it.
flow_dep jetbrains-mono-nerd terminal ttf-jetbrains-mono-nerd "Nerd Font glyphs (Starship/terminal)" "fc-list"