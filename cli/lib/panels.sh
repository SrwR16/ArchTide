#!/bin/bash

# Panel management for Flow Shell

cmd_toggle_panel() {
    local panel="$1"
    local bin=$(get_qs_bin)
    info "Toggling $panel panel..."
    if ! command -v $bin &> /dev/null; then
        error "$bin not found. Please install it first."
    fi
    $bin -c flow ipc call "$panel" toggle
    success "$panel toggled."
}

cmd_spotlight() {
    local action="$1"
    local bin=$(get_qs_bin)
    if ! command -v $bin &> /dev/null; then
        error "$bin not found."
    fi

    case "$action" in
        files|file)
            info "Opening Spotlight in File mode..."
            $bin -c flow ipc call spotlight open
            hyprctl dispatch "quickshell:spotlightFiles" ""
            ;;
        apps|app)
            info "Opening Spotlight in App mode..."
            $bin -c flow ipc call spotlight open
            ;;
        commands|command|cmd)
            info "Opening Spotlight in Command mode..."
            hyprctl dispatch "quickshell:spotlightCommand" ""
            ;;
        clipboard|clip)
            info "Opening Spotlight in Clipboard mode..."
            hyprctl dispatch "quickshell:spotlightClipboard" ""
            ;;
        emoji)
            info "Opening Spotlight in Emoji mode..."
            hyprctl dispatch "quickshell:spotlightEmoji" ""
            ;;
        *)
            cmd_toggle_panel "spotlight"
            ;;
    esac
}

cmd_region() {
    local action="$1"
    local bin=$(get_qs_bin)
    
    if [[ "$action" == "record-audio" ]]; then
        action="recordWithSound"
    fi
    
    case "$action" in
        screenshot|search|ocr|qrcode|record|recordWithSound)
            $bin -c flow ipc call region "$action"
            ;;
        *)
            echo "Usage: flow region {screenshot|search|ocr|qrcode|record|record-audio}"
            ;;
    esac
}
