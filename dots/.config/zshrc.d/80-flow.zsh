# Flow Terminal Integration
# Load generated terminal sequences from Flow/Matugen pipeline

# Generated color sequences (from Matugen via QuickShell)
local sequences_file="${FLOW_STATE_DIR:-$HOME/.local/state/quickshell/user/generated/terminal}/sequences.txt"
if [[ -f "$sequences_file" && -r "$sequences_file" ]]; then
  command cat "$sequences_file"
fi

# Kitty theme (if using Kitty)
if [[ "$TERM" == "xterm-kitty" ]] || [[ -n "$KITTY_WINDOW_ID" ]]; then
  local kitty_theme="${FLOW_STATE_DIR:-$HOME/.local/state/quickshell/user/generated/terminal}/kitty-theme.conf"
  if [[ -f "$kitty_theme" && -r "$kitty_theme" ]]; then
    # Kitty loads this via include in kitty.conf, but we can also source for immediate effect
    # Note: kitty.conf includes this file, so terminal colors are applied on startup
    # This fragment ensures sequences are output for non-Kitty terminals too
    :
  fi
fi

# Flow Project Activation (Phase 3C)
# Shell function that wraps the activation command
# This ensures activation affects the parent shell via eval

flow_activate() {
  local flow_cmd="${FLOW_CMD:-flow}"
  local activate_script="${0:A:h}/../../sdata/subcmd-project/activate.sh"
  
  # Find the activate.sh script
  if [[ ! -f "$activate_script" ]]; then
    # Try the installed location
    activate_script="${HOME}/.local/share/flow/sdata/subcmd-project/activate.sh"
  fi
  
  if [[ ! -f "$activate_script" ]]; then
    echo "Flow: activate.sh not found" >&2
    return 1
  fi
  
  # Generate activation commands and eval them
  local commands
  commands=$(bash "$activate_script" activate "$@")
  if [[ $? -eq 0 ]]; then
    eval "$commands"
  else
    return $?
  fi
}

# Flow Deactivation
flow_deactivate() {
  local flow_cmd="${FLOW_CMD:-flow}"
  local activate_script="${0:A:h}/../../sdata/subcmd-project/activate.sh"
  
  # Find the activate.sh script
  if [[ ! -f "$activate_script" ]]; then
    # Try the installed location
    activate_script="${HOME}/.local/share/flow/sdata/subcmd-project/activate.sh"
  fi
  
  if [[ ! -f "$activate_script" ]]; then
    echo "Flow: activate.sh not found" >&2
    return 1
  fi
  
  # Generate deactivation commands and eval them
  local commands
  commands=$(bash "$activate_script" deactivate "$@")
  if [[ $? -eq 0 ]]; then
    eval "$commands"
  else
    return $?
  fi
}

# Flow Status
flow_status() {
  local flow_cmd="${FLOW_CMD:-flow}"
  local activate_script="${0:A:h}/../../sdata/subcmd-project/activate.sh"
  
  # Find the activate.sh script
  if [[ ! -f "$activate_script" ]]; then
    # Try the installed location
    activate_script="${HOME}/.local/share/flow/sdata/subcmd-project/activate.sh"
  fi
  
  if [[ ! -f "$activate_script" ]]; then
    echo "Flow: activate.sh not found" >&2
    return 1
  fi
  
  bash "$activate_script" status "$@"
}

# Aliases
alias fa='flow_activate'
alias fd='flow_deactivate'
alias fs='flow_status'