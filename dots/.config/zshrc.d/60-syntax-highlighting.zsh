# 60-syntax-highlighting.zsh — Fish-like syntax highlighting (load LAST, 23k★)
# https://github.com/zsh-users/zsh-syntax-highlighting

# Idempotency guard
(( $+functions[_zsh_highlight] )) && return 0

# Preferred install location
_sh_install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-syntax-highlighting"

# 1. Try loading from known paths
local -a _sh_dirs=(
  "$_sh_install_dir"
  "$HOME/.zsh-plugins/zsh-syntax-highlighting"
  "/usr/share/zsh/plugins/zsh-syntax-highlighting"
)

local _sh_dir=""
for _sh_dir in "${_sh_dirs[@]}"; do
  if [[ -f "$_sh_dir/zsh-syntax-highlighting.zsh" ]]; then
    source "$_sh_dir/zsh-syntax-highlighting.zsh"
    # Custom styles for Flow
    ZSH_HIGHLIGHT_STYLES[flow-command]='fg=green,bold'
    ZSH_HIGHLIGHT_STYLES[flow-alias]='fg=cyan,bold'
    return 0
  fi
done

# 2. Not found — auto-install
if command -v git >/dev/null 2>&1; then
  print -P "%F{yellow}zsh-syntax-highlighting: not found, cloning...%f" 2>/dev/null
  if git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$_sh_install_dir" 2>/dev/null; then
    source "$_sh_install_dir/zsh-syntax-highlighting.zsh"
    ZSH_HIGHLIGHT_STYLES[flow-command]='fg=green,bold'
    ZSH_HIGHLIGHT_STYLES[flow-alias]='fg=cyan,bold'
    print -P "%F{green}zsh-syntax-highlighting: installed to $_sh_install_dir%f" 2>/dev/null
    return 0
  fi
  print -P "%F{red}zsh-syntax-highlighting: clone failed%f" 2>/dev/null
fi