#!/bin/bash

# Log management for Flow Shell

SHELL_DIR="$HOME/.config/quickshell/flow"


cmd_logs() {
    local bin=$(get_qs_bin)
    info "Fetching $bin logs for flow..."
    
    # Check if shell is even running
    if ! pgrep -f "quickshell" > /dev/null && ! pgrep -f "\bqs\b" > /dev/null; then
        error "Flow Shell is not currently running."
    fi

    substep "Streaming logs from active instance (Ctrl+C to stop)..."
    echo "------------------------------------------------------------"
    
    # Use -f (follow) to keep the log stream active
    # Use -p to target the correct config path
    $bin log -f -p "$SHELL_DIR"
}
