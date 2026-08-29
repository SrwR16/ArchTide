# 57-zsh-abbr.zsh — Fish-style abbreviations (800★)
# https://github.com/olets/zsh-abbr
# Type abbreviation + Space/Enter to expand. Ctrl+Space to skip expansion.
# Abbreviations sync to ~/.config/zsh/abbr.zsh for dotfile management.

# Load via plugin-load (defined in 05-plugin-manager.zsh)
# Plugin repo: olets/zsh-abbr

# Configuration (before plugin loads)
export ABBR_USER_ABBREVIATIONS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/abbr.zsh"

# Apply user abbreviations after plugin loads
if (( $+functions[abbr] )); then
  # Example abbreviations (add your own via `abbr add` or edit the file)
  # abbr add gco 'git checkout'
  # abbr add gcm 'git checkout main'
  # abbr add gp 'git push'
  # abbr add gl 'git pull'
  # abbr add lg 'lazygit'
  # abbr add k 'kubectl'
  # abbr add kctx 'kubectx'
  # abbr add kns 'kubens'
  # abbr add h 'helm'
  # abbr add d 'docker'
  # abbr add dc 'docker-compose'
  # abbr add tf 'terraform'
  # abbr add v 'nvim'
  # abbr add vz 'nvim ~/.zshrc'
  # abbr add sz 'source ~/.zshrc'
  true
fi