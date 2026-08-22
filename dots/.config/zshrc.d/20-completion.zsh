# Flow Zsh Completion
# Native Zsh completion with caching

# Completion directory
local zcompdir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d "$zcompdir" ]] || mkdir -p "$zcompdir"
local zcompdump="$zcompdir/zcompdump-${ZSH_VERSION}"

# Load completion system
autoload -Uz compinit
compinit -d "$zcompdump" -C

# Completion styles
zstyle ':completion:*' cache-path "$zcompdir"
zstyle ':completion:*' use-cache on
zstyle ':completion:*' rehash true
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:messages' format '%F{blue}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches --%f'
zstyle ':completion:*:corrections' format '%F{green}-- %d (errors: %e) --%f'

# Kill completion
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:kill:*' force-list always
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:*:kill:*:processes' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# SSH/SCP/RSYNC completion
zstyle ':completion:*:(ssh|scp|rsync):*' tag-order 'hosts:-host:host hosts:-domain:domain hosts:-ipaddr:ip\ address *'
zstyle ':completion:*:(ssh|scp|rsync):*' group-order users hosts-host hosts-domain hosts-ipaddr

# Git completion (uses git's own completion if available)
if command -v git >/dev/null 2>&1; then
  zstyle ':completion:*:*:git:*' script ~/.local/share/zsh/git-completion.bash 2>/dev/null || true
fi

# Docker completion
if command -v docker >/dev/null 2>&1; then
  fpath=("${XDG_DATA_HOME:-$HOME/.local/share}/zsh/completions" $fpath)
fi

# Cache generated completion scripts to avoid subshell execution on every startup
_flow_source_cached_completion() {
  local cmd="$1" cache_file="$2"
  shift 2
  if command -v "$cmd" >/dev/null 2>&1; then
    local bin_path
    bin_path="$(command -v "$cmd")"
    if [[ ! -f "$cache_file" || "$cache_file" -ot "$bin_path" ]]; then
      "$@" > "$cache_file" 2>/dev/null || rm -f "$cache_file"
    fi
    [[ -f "$cache_file" ]] && source "$cache_file" 2>/dev/null || true
  fi
}

_flow_comp_cache_dir="${zcompdir}/completions"
[[ -d "$_flow_comp_cache_dir" ]] || mkdir -p "$_flow_comp_cache_dir"

_flow_source_cached_completion kubectl "$_flow_comp_cache_dir/kubectl.zsh" kubectl completion zsh
_flow_source_cached_completion helm "$_flow_comp_cache_dir/helm.zsh" helm completion zsh
_flow_source_cached_completion gh "$_flow_comp_cache_dir/gh.zsh" gh completion -s zsh
_flow_source_cached_completion mise "$_flow_comp_cache_dir/mise.zsh" mise completion zsh

# Rebuild completion cache once per day
if [[ ! -f "$zcompdump" ]] || [[ "$zcompdump" -ot "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  compinit -d "$zcompdump"
else
  compinit -C -d "$zcompdump"
fi

# ── fzf-tab: fuzzy completion picker (load AFTER compinit) ──────────────────
# https://github.com/Aloxaf/fzf-tab

# Idempotency guard
(( $+functions[-ftb-complete] )) && return 0

# Preferred install location
_ft_install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fzf-tab"

# 1. Try loading from known paths
local -a _ft_dirs=(
  "$_ft_install_dir"
  "$HOME/.zsh-plugins/fzf-tab"
  "/usr/share/zsh/plugins/fzf-tab"
  "/usr/share/zsh/plugins/fzf-tab-git"
)

local _ft_dir=""
for _ft_dir in "${_ft_dirs[@]}"; do
  if [[ -f "$_ft_dir/fzf-tab.plugin.zsh" ]]; then
    source "$_ft_dir/fzf-tab.plugin.zsh"
    zstyle ':completion:*' menu no
    zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
    zstyle ':fzf-tab:*' switch-group '<' '>'
    zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
    zstyle ':fzf-tab:complete:ssh:*' fzf-preview 'echo {}'
    zstyle ':fzf-tab:complete:git-checkout:*' sort false
    return 0
  fi
done

# 2. Not found — auto-install
if command -v git >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
  print -P "%F{yellow}fzf-tab: not found, cloning...%f" 2>/dev/null
  if git clone --depth=1 https://github.com/Aloxaf/fzf-tab "$_ft_install_dir" 2>/dev/null; then
    source "$_ft_install_dir/fzf-tab.plugin.zsh"
    zstyle ':completion:*' menu no
    zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
    zstyle ':fzf-tab:*' switch-group '<' '>'
    zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
    zstyle ':fzf-tab:complete:ssh:*' fzf-preview 'echo {}'
    zstyle ':fzf-tab:complete:git-checkout:*' sort false
    print -P "%F{green}fzf-tab: installed to $_ft_install_dir%f" 2>/dev/null
    return 0
  fi
  print -P "%F{red}fzf-tab: clone failed%f" 2>/dev/null
fi