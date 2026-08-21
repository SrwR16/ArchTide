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

# Kubectl completion
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion zsh) 2>/dev/null || true
fi

# Helm completion
if command -v helm >/dev/null 2>&1; then
  source <(helm completion zsh) 2>/dev/null || true
fi

# Terraform completion
if command -v terraform >/dev/null 2>&1; then
  complete -o nospace -C terraform terraform
fi

# AWS CLI completion
if command -v aws >/dev/null 2>&1; then
  complete -C aws_completer aws
fi

# GH completion
if command -v gh >/dev/null 2>&1; then
  source <(gh completion -s zsh) 2>/dev/null || true
fi

# Mise completion
if command -v mise >/dev/null 2>&1; then
  source <(mise completion zsh) 2>/dev/null || true
fi

# Rebuild completion cache once per day
if [[ ! -f "$zcompdump" ]] || [[ "$zcompdump" -ot "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  compinit -d "$zcompdump"
else
  compinit -C -d "$zcompdump"
fi

# ── fzf-tab: fuzzy completion picker (load AFTER compinit) ──────────────────
# https://github.com/Aloxaf/fzf-tab
if command -v fzf >/dev/null 2>&1 && [[ -f ~/.local/share/fzf-tab/fzf-tab.plugin.zsh ]]; then
  source ~/.local/share/fzf-tab/fzf-tab.plugin.zsh
  # Disable native menu, let fzf-tab handle it
  zstyle ':completion:*' menu no
  # fzf-tab config
  zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
  zstyle ':fzf-tab:*' switch-group '<' '>'
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
  zstyle ':fzf-tab:complete:ssh:*' fzf-preview 'echo {}'
  zstyle ':fzf-tab:complete:git-checkout:*' sort false
fi