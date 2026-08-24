#!/bin/bash

# System actions for Nandoroid Shell

cmd_reboot() {
    info "Rebooting system..."
    systemctl reboot
}

cmd_lock() {
    info "Locking screen via Nandoroid Shell..."
    local bin=$(get_qs_bin)
    if ! command -v $bin &> /dev/null; then
        error "$bin not found."
    fi
    # Use IPC call to the lock handler defined in Lock.qml
    $bin -c nandoroid ipc call lock activate
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
        up|increment) $bin -c nandoroid ipc call brightness increment ;;
        down|decrement) $bin -c nandoroid ipc call brightness decrement ;;
        *) echo "Usage: nandoroid brightness {up|down|increment|decrement}" ;;
    esac
}

cmd_pomodoro() {
    local action="$1"
    local bin=$(get_qs_bin)
    case "$action" in
        start|pause|stop|reset) $bin -c nandoroid ipc call pomodoro "$action" ;;
        *) echo "Usage: nandoroid pomodoro {start|pause|stop|reset}" ;;
    esac
}
