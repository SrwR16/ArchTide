#!/bin/bash

# Config management for Flow Shell

CONFIG_FILE="$HOME/.config/flow/config.json"

cmd_config() {
    local action="$1"
    
    if [[ "$action" == "edit" ]]; then
        info "Opening config file in your editor..."
        local editor="${EDITOR:-nano}"
        $editor "$CONFIG_FILE"
        success "Config updated."
    else
        info "Config path: $CONFIG_FILE"
        echo "Usage: flow config edit"
    fi
}
