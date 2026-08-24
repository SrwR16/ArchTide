#!/bin/bash

# System actions for Flow Shell

cmd_reboot() {
    info "Rebooting system..."
    systemctl reboot
}

cmd_lock() {
    info "Locking screen via Flow Shell..."
    local bin=$(get_qs_bin)
    if ! command -v $bin &> /dev/null; then
        error "$bin not found."
    fi
    # Use IPC call to the lock handler defined in Lock.qml
    $bin -c flow ipc call lock activate
    success "Lock command sent."
}

cmd_poweroff() {
    info "Shutting down system..."
    systemctl poweroff
}

cmd_brightness() {
    local action="$1"
    local bin=$(get_qs_bin)
    case "$action" in
        up|increment) $bin -c flow ipc call brightness increment ;;
        down|decrement) $bin -c flow ipc call brightness decrement ;;
        *) echo "Usage: flow brightness {up|down|increment|decrement}" ;;
    esac
}

cmd_pomodoro() {
    local action="$1"
    local bin=$(get_qs_bin)
    case "$action" in
        start|pause|stop|reset) $bin -c flow ipc call pomodoro "$action" ;;
        *) echo "Usage: flow pomodoro {start|pause|stop|reset}" ;;
    esac
}
