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
  
  # Atuin handles Ctrl+R, but we keep native bindings as fallback
  # Bind Ctrl+R to Atuin search if not already bound
  if ! bindkey -M emacs '^R' | grep -q atuin; then
    bindkey '^R' atuin-search
  fi
fi