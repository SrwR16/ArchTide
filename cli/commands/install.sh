#!/bin/bash
# flow install — dependency installation by tier or "all"
# Usage: flow install [core|ux|devops|devops-gui|all|missing] [-y]

cmd_install() {
    local tier="${1:-all}"
    source "$BASE_DIR/lib/deps.sh"
    deps_init

    local -a tiers=()
    case "$tier" in
        all)    tiers=(core ux devops devops-gui) ;;
        core|ux|devops|devops-gui) tiers=("$tier") ;;
        *) echo "Unknown tier: $tier"; echo "Available: core ux devops devops-gui all"; exit 1 ;;
    esac

    echo "Flow install — ${tiers[*]}"

    local -a all_missing=()
    for t in "${tiers[@]}"; do
        while IFS= read -r key; do
            [[ -n "$key" ]] && all_missing+=("$key")
        done < <(deps_missing "$t")
    done

    if ((${#all_missing[@]} == 0)); then
        echo "✓ All dependencies already installed"
        return 0
    fi

    echo "Installing ${#all_missing[@]} package(s):"
    for key in "${all_missing[@]}"; do
        local meta="${FLOW_DEPS_META[$key]}"
        IFS='|' read -r k t pkg reason bin <<<"$meta"
        printf "  %-20s %s\n" "$key" "$reason"
    done
    echo

    if [[ "$OPT_ASSUME_YES" != true && "$OPT_DRY_RUN" != true ]]; then
        read -rp "Install now? [Y/n] " confirm
        [[ "$confirm" =~ ^[nN] ]] && { echo "Cancelled."; return 1; }
    fi

    # resolve packages (skip duplicates)
    local -a pkgs=()
    local -A seen_pkg=()
    for key in "${all_missing[@]}"; do
        local meta="${FLOW_DEPS_META[$key]}"
        IFS='|' read -r k t pkg reason bin <<<"$meta"
        [[ -n "$pkg" ]] || continue
        [[ -n "${seen_pkg[$pkg]:-}" ]] && continue
        seen_pkg[$pkg]=1
        pkgs+=("$pkg")
    done

    if ((${#pkgs[@]} == 0)); then
        echo "✓ Nothing to install"
        return 0
    fi

    # install via platform module
    source "$BASE_DIR/cli/lib/platform.sh"
    pkg_install "${pkgs[@]}"

    # verify
    local still=0
    for key in "${all_missing[@]}"; do
        local meta="${FLOW_DEPS_META[$key]}"
        IFS='|' read -r k t pkg reason bin <<<"$meta"
        command -v "$bin" &>/dev/null || { echo "⚠ $key still missing ($pkg)"; ((still++)); }
    done
    ((still == 0)) && echo "✓ All dependencies installed"
    return $still
}
