#!/bin/bash
# flow status — quick system overview

cmd_status() {
    echo "Flow Terminal Status"
    echo "────────────────────────────────────────"
    echo
    echo "  Engine:     $([ -x "$HOME/.local/bin/iris" ] && echo "~/.local/bin/iris ✓" || echo "not installed")"
    echo "  Shell:      ${SHELL}"
    echo "  Distro:     $(cat /etc/os-release 2>/dev/null | grep -m1 '^ID=' | cut -d= -f2 || echo unknown)"
    echo

    if [[ -f "$HOME/.local/state/flow/predictor/aggregates.tsv" ]]; then
        local count; count=$(grep -c "^C" "$HOME/.local/state/flow/predictor/aggregates.tsv")
        echo "  Brain:      $count commands learned"
    fi

    if [[ -f "${XDG_STATE_HOME:-$HOME/.local/state}/flow/trust.json" ]]; then
        echo "  Trust:      $(jq -r '.projects | length' "${XDG_STATE_HOME:-$HOME/.local/state}/flow/trust.json" 2>/dev/null || 0) projects"
    fi

    # QuickShell status
    pgrep -x quickshell &>/dev/null && echo "  QuickShell: running ✓" || echo "  QuickShell: not running"

    echo
}
