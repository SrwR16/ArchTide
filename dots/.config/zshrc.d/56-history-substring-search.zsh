# 56-history-substring-search.zsh — Fish-like history search with Up/Down (load AFTER autosuggestions)
# https://github.com/zsh-users/zsh-history-substring-search

# Idempotency guard
(( $+functions[history-substring-search-up] )) && return 0

# Config
export HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND="fg=white,bold,bg=magenta"
export HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND="fg=white,bold,bg=red"
export HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
export HISTORY_SUBSTRING_SEARCH_FUZZY=1

# Preferred install location
_hss_install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-history-substring-search"

# 1. Try loading from known paths
local -a _hss_dirs=(
  "$_hss_install_dir"
  "$HOME/.zsh-plugins/zsh-history-substring-search"
  "/usr/share/zsh/plugins/zsh-history-substring-search"
)

local _hss_dir=""
for _hss_dir in "${_hss_dirs[@]}"; do
  if [[ -f "$_hss_dir/zsh-history-substring-search.zsh" ]]; then
    source "$_hss_dir/zsh-history-substring-search.zsh"
    break
  elif [[ -f "$_hss_dir/zsh-history-substring-search.plugin.zsh" ]]; then
    source "$_hss_dir/zsh-history-substring-search.plugin.zsh"
    break
  fi
done

# 2. Not found — auto-install
if ! (( $+functions[history-substring-search-up] )) && command -v git >/dev/null 2>&1; then
  print -P "%F{yellow}zsh-history-substring-search: not found, cloning...%f" 2>/dev/null
  if git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search "$_hss_install_dir" 2>/dev/null; then
    source "$_hss_install_dir/zsh-history-substring-search.zsh"
    print -P "%F{green}zsh-history-substring-search: installed to $_hss_install_dir%f" 2>/dev/null
  else
    print -P "%F{red}zsh-history-substring-search: clone failed%f" 2>/dev/null
  fi
fi

# Keybindings (after plugin loads)
bindkey "$terminfo[kcuu1]" history-substring-search-up   # Up
bindkey "$terminfo[kcud1]" history-substring-search-down # Down
bindkey -M emacs '^P' history-substring-search-up
bindkey -M emacs '^N' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down