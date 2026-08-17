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