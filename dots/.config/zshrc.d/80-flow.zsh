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
# Shell functions that wrap the activation command
# This ensures activation affects the parent shell via eval

# Resolve activate.sh location (once, at source time)
_flow_activate_script=""
if [[ -n "${FLOW_BASE_DIR:-}" && -f "${FLOW_BASE_DIR}/sdata/subcmd-project/activate.sh" ]]; then
  _flow_activate_script="${FLOW_BASE_DIR}/sdata/subcmd-project/activate.sh"
elif [[ -f "${HOME}/.local/share/flow/sdata/subcmd-project/activate.sh" ]]; then
  _flow_activate_script="${HOME}/.local/share/flow/sdata/subcmd-project/activate.sh"
fi

flow_activate() {
  if [[ -z "$_flow_activate_script" ]]; then
    echo "Flow: activate.sh not found (set FLOW_BASE_DIR or install Flow)" >&2
    return 1
  fi
  
  local commands
  commands=$(bash "$_flow_activate_script" activate "$@")
  if [[ $? -eq 0 ]]; then
    eval "$commands"
  else
    return $?
  fi
}

flow_deactivate() {
  if [[ -z "$_flow_activate_script" ]]; then
    echo "Flow: activate.sh not found (set FLOW_BASE_DIR or install Flow)" >&2
    return 1
  fi
  
  local commands
  commands=$(bash "$_flow_activate_script" deactivate "$@")
  if [[ $? -eq 0 ]]; then
    eval "$commands"
  else
    return $?
  fi
}

flow_status() {
  if [[ -z "$_flow_activate_script" ]]; then
    echo "Flow: activate.sh not found (set FLOW_BASE_DIR or install Flow)" >&2
    return 1
  fi
  
  bash "$_flow_activate_script" status "$@"
}

# Aliases
alias fa='flow_activate'
alias fd='flow_deactivate'
alias fs='flow_status'