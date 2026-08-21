# 50-zsh-autosuggestions.zsh — Fish-like autosuggestions (async, proven 36k★)
# https://github.com/zsh-users/zsh-autosuggestions

# Idempotency guard
(( $+functions[_zsh_autosuggest_bind_widgets] )) && return 0

# Preferred install location
_as_install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-autosuggestions"

# 1. Try loading from known paths
local -a _as_dirs=(
  "$_as_install_dir"
  "$HOME/.zsh-plugins/zsh-autosuggestions"
  "/usr/share/zsh/plugins/zsh-autosuggestions"
)

local _as_dir=""
for _as_dir in "${_as_dirs[@]}"; do
  if [[ -f "$_as_dir/zsh-autosuggestions.zsh" ]]; then
    source "$_as_dir/zsh-autosuggestions.zsh"
    # Custom config for Flow
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=245,bold,standout'
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    return 0
  fi
done

# 2. Not found — auto-install
if command -v git >/dev/null 2>&1; then
  print -P "%F{yellow}zsh-autosuggestions: not found, cloning...%f" 2>/dev/null
  if git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$_as_install_dir" 2>/dev/null; then
    source "$_as_install_dir/zsh-autosuggestions.zsh"
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=245,bold,standout'
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    print -P "%F{green}zsh-autosuggestions: installed to $_as_install_dir%f" 2>/dev/null
    return 0
  fi
  print -P "%F{red}zsh-autosuggestions: clone failed%f" 2>/dev/null
fi