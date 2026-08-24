#!/bin/bash
# flow doctor — read-only health check

cmd_doctor() {
    echo "Flow Doctor — $(date)"
    echo "────────────────────────────────────────"
    echo

    # Shell
    echo "Shell: ${SHELL:-unknown}"

    # Core deps
    echo; echo "Core dependencies:"
    for t in git starship atuin mise fzf fd rg zoxide direnv; do
        printf "  %-12s %s\n" "$t" "$(command -v $t &>/dev/null && echo '✓' || echo '✗ MISSING')"
    done

    # DevOps
    echo; echo "DevOps tools:"
    for t in docker kubectl helm k9s kind gh terraform tofu ansible aws-cli; do
        printf "  %-12s %s\n" "$t" "$(command -v $t &>/dev/null && echo '✓' || echo '—')"
    done

    # Engine
    echo; echo "Flow engine:"
    if [[ -x "$HOME/.local/bin/iris" ]]; then
        echo "  binary: ~/.local/bin/iris ✓"
    else
        echo "  binary: ✗ not installed (run: flow engine build)"
    fi

    # Intelligence store
    local agg="$HOME/.local/state/flow/predictor/aggregates.tsv"
    if [[ -f "$agg" ]]; then
        echo "  aggregates: $(wc -l < "$agg") records ✓"
    else
        echo "  aggregates: no data yet"
    fi

    # Trust
    echo; echo "Trusted projects:"
    if [[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/flow/trust.json" ]]; then
        trust_list
    else
        echo "  (none yet)"
    fi
}
