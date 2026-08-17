# Flow Zsh Keybindings
# Line editing and history navigation

# Use emacs keybindings (standard)
bindkey -e

# History search
bindkey '^R' history-incremental-search-backward
bindkey '^S' history-incremental-search-forward
bindkey '^P' up-line-or-history
bindkey '^N' down-line-or-history

# Beginning/end of line
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line

# Word movement
bindkey '^[[1;5C' forward-word      # Ctrl+Right
bindkey '^[[1;5D' backward-word     # Ctrl+Left
bindkey '^[[H' beginning-of-line    # Home
bindkey '^[[F' end-of-line          # End
bindkey '^[b' backward-word         # Alt+Left / Esc+b
bindkey '^[f' forward-word          # Alt+Right / Esc+f

# Delete word
bindkey '^W' backward-kill-word     # Ctrl+W
bindkey '^[[3;5~' kill-word         # Ctrl+Delete
bindkey '^H' backward-kill-word     # Ctrl+Backspace (from existing shortcuts.zsh)
bindkey '^[[3~' delete-char         # Delete

# Undo
bindkey '^Z' undo                   # Ctrl+Z (from existing shortcuts.zsh)
bindkey '^[_' redo                  # Alt+_

# Clear screen
bindkey '^L' clear-screen

# Edit command line in $EDITOR
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line    # Ctrl+X Ctrl+E

# FZF integration (if available)
if command -v fzf >/dev/null 2>&1; then
  # Load fzf keybindings
  local fzf_shell="${XDG_DATA_HOME:-$HOME/.local/share}/fzf"
  [[ -f "$fzf_shell/key-bindings.zsh" ]] && source "$fzf_shell/key-bindings.zsh"
  [[ -f "$fzf_shell/completion.zsh" ]] && source "$fzf_shell/completion.zsh"
fi