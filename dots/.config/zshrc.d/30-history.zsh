# Flow Zsh History
# Persistent history with Atuin integration when available

# History file
local histdir="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
[[ -d "$histdir" ]] || mkdir -p "$histdir"
export HISTFILE="$histdir/history"
export HISTSIZE=50000
export SAVEHIST=50000

# Atuin integration (if installed)
if command -v atuin >/dev/null 2>&1; then
  # Initialize Atuin for Zsh
  eval "$(atuin init zsh --disable-up-arrow)"
  bindkey '^R' atuin-search
fi