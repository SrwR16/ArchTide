# 60-syntax-highlighting.zsh — Fish-like syntax highlighting (load LAST)
# https://github.com/zsh-users/zsh-syntax-highlighting

# Load from system package or local install
if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [[ -f ~/.local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source ~/.local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Custom highlight styles for Flow commands
if (( ${+ZSH_HIGHLIGHT_STYLES} )); then
  ZSH_HIGHLIGHT_STYLES[flow-command]='fg=green,bold'
  ZSH_HIGHLIGHT_STYLES[flow-alias]='fg=cyan,bold'
fi