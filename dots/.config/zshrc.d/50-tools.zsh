# Flow Zsh Tools
# Initialize installed CLI tools

# zoxide - smarter cd
# Plain `cd` stays literal (stock builtin); fuzzy frecency jumps are
# deliberate via z / zi — initialized in 70-zoxide.zsh with --cmd z.'
fi

# fzf - fuzzy finder (keybindings loaded in 40-keybindings.zsh)
if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --color=fg:#d0d0d0,bg:#1e1e2e,hl:#f38ba8,fg+:#d0d0d0,bg+:#313244,hl+:#f38ba8,info:#cba6f7,prompt:#f38ba8,pointer:#f5e0dc,marker:#f5e0dc,spinner:#f5e0dc,header:#cba6f7'
fi

# eza - modern ls
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -l --icons --group-directories-first --git'
  alias la='eza -la --icons --group-directories-first --git'
  alias lt='eza --tree --icons --group-directories-first --git-ignore'
  alias lta='eza --tree --icons --group-directories-first -a --git-ignore'
fi

# bat - syntax highlighting cat
if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never'
  alias catp='bat'
  export BAT_THEME="${BAT_THEME:-Catppuccin Mocha}"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# ripgrep - fast grep
if command -v rg >/dev/null 2>&1; then
  alias grep='rg'
  export RIPGREP_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/ripgreprc"
fi

# fd - fast find
if command -v fd >/dev/null 2>&1; then
  alias find='fd'
fi

# lazygit
if command -v lazygit >/dev/null 2>&1; then
  alias lg='lazygit'
fi

# Common aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# Typos (from Fish config)
alias celar='clear'
alias claer='clear'
alias pamcan='pacman'

# Clear screen (kitty-compatible)
alias clear="printf '\033[2J\033[3J\033[1;1H'"

# Flow CLI shortcut
alias q='qs -c flow'