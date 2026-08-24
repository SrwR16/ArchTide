#!/bin/bash

# Lifecycle management for Flow Shell

SHELL_DIR="$HOME/.config/quickshell/flow"


is_shell_running() {
    pgrep -f "quickshell" > /dev/null || pgrep -f "\bqs\b" > /dev/null
}

stop_existing_shell() {
    if is_shell_running; then
        substep "Killing all existing Quickshell/qs processes..."
        pkill -9 -f "quickshell" || true
        pkill -9 -f "\bqs\b" || true
        sleep 1
    fi
}

cmd_run() {
    info "Starting Flow Shell..."
    if [[ ! -d "$SHELL_DIR" ]]; then
        error "Flow Shell not found. Run 'flow install' first."
    fi
    
    stop_existing_shell
    
    local bin=$(get_qs_bin)
    substep "Launching $bin in background..."
    # We use -d here because run is intended to be backgrounded/daemonized
    $bin -d -p "$SHELL_DIR" > /dev/null 2>&1
    
    sleep 1
    if is_shell_running; then
        success "Shell started successfully."
    else
        error "Shell failed to start. Try 'flow debug' to see why."
    fi
}

cmd_reload() {
    info "Reloading Flow Shell..."
    if is_shell_running; then
        local bin=$(get_qs_bin)
        $bin --reload
        success "Reload signal sent."
    else
        error "No running Quickshell instance found to reload."
    fi
}

cmd_debug() {
    info "Starting Flow Shell in DEBUG mode..."
    if [[ ! -d "$SHELL_DIR" ]]; then
        error "Flow Shell not found."
    fi
    
    stop_existing_shell
    
    local bin=$(get_qs_bin)
    substep "Logs will appear below using $bin. Press Ctrl+C to stop."
    echo "------------------------------------------------------------"
    # Simple foreground execution for natural debug logs
    exec $bin -p "$SHELL_DIR"
}

cmd_exit() {
    info "Exiting Flow Shell..."
    if is_shell_running; then
        pkill -f "quickshell" || true
        pkill -f "\bqs\b" || true
        success "Quickshell stopped."
    else
        info "Quickshell is not currently running."
    fi
}
