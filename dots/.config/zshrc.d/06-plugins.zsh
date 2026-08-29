# 06-plugins.zsh — Load all plugins via zsh_unplugged (plugin-load)
# Must run AFTER 05-plugin-manager.zsh defines plugin-load

# Plugin load order matters:
# 1. zsh-completions (fpath) — loaded in 20-completion.zsh BEFORE compinit
# 2. fzf-tab — loaded in 20-completion.zsh AFTER compinit (checks for function)
# 3. zsh-autosuggestions
# 4. zsh-history-substring-search
# 5. zsh-abbr
# 6. zsh-autopair
# 7. zsh-you-should-use
# 8. fast-syntax-highlighting (MUST BE LAST)

# Load all plugins
plugin-load \
  zsh-users/zsh-autosuggestions \
  zsh-users/zsh-history-substring-search \
  olets/zsh-abbr \
  hlissner/zsh-autopair \
  MichaelAquilina/zsh-you-should-use \
  zdharma-continuum/fast-syntax-highlighting

# fzf-tab is loaded in 20-completion.zsh after compinit (checks for -ftb-complete function)
# zsh-completions fpath is added in 20-completion.zsh before compinit