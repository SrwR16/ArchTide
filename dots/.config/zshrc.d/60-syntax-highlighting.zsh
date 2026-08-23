# 60-syntax-highlighting.zsh — Fish-like syntax highlighting (load LAST, 23k★)
# https://github.com/zsh-users/zsh-syntax-highlighting

# Idempotency guard
(( $+functions[_zsh_highlight] )) && return 0

# ── Flow Material token styles ──────────────────────────────────────────────
# Semantic mapping; ANSI color names resolve through the terminal palette
# remap (sequences.txt), so hues follow the wallpaper like Starship/Kitty.
_flow_apply_hl_styles() {
  typeset -gA ZSH_HIGHLIGHT_STYLES
  # primary (runnable things)
  ZSH_HIGHLIGHT_STYLES[command]='fg=cyan,bold'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=cyan'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=cyan'
  ZSH_HIGHLIGHT_STYLES[function]='fg=cyan'
  ZSH_HIGHLIGHT_STYLES[arg0]='fg=cyan,bold'
  # error / risk
  ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red,bold'
  # secondary (structure)
  ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=magenta,bold'
  ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=magenta,bold'
  # strings
  ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=green'
  ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=green'
  ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=green'
  ZSH_HIGHLIGHT_STYLES[backslash-escape]='fg=magenta'
  # paths & patterns
  ZSH_HIGHLIGHT_STYLES[path]='underline'
  ZSH_HIGHLIGHT_STYLES[globbing]='fg=yellow,bold'
  # options stay quiet
  ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='none'
  ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='none'
  ZSH_HIGHLIGHT_STYLES[comment]='fg=8'
}

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
  # Check both .zsh and .plugin.zsh (system packages use .zsh)
  if [[ -f "$_sh_dir/zsh-syntax-highlighting.zsh" ]]; then
    source "$_sh_dir/zsh-syntax-highlighting.zsh"
    _flow_apply_hl_styles
    return 0
  elif [[ -f "$_sh_dir/zsh-syntax-highlighting.plugin.zsh" ]]; then
    source "$_sh_dir/zsh-syntax-highlighting.plugin.zsh"
    _flow_apply_hl_styles
    return 0
  fi
done

# 2. Not found — auto-install
if command -v git >/dev/null 2>&1; then
  print -P "%F{yellow}zsh-syntax-highlighting: not found, cloning...%f" 2>/dev/null
  if git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$_sh_install_dir" 2>/dev/null; then
    source "$_sh_install_dir/zsh-syntax-highlighting.zsh"
    _flow_apply_hl_styles
    print -P "%F{green}zsh-syntax-highlighting: installed to $_sh_install_dir%f" 2>/dev/null
    return 0
  fi
  print -P "%F{red}zsh-syntax-highlighting: clone failed%f" 2>/dev/null
fi