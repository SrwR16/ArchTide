#!/bin/bash
# Flow UI — colored output helpers used by every module.

# Colors (Material palette, falls back gracefully without color support)
if [[ -t 2 ]]; then
    C_MAIN=$'\e[38;2;202;169;224m'
    C_ACCENT=$'\e[38;2;145;177;240m'
    C_DIM=$'\e[38;2;129;122;150m'
    C_GREEN=$'\e[38;2;166;209;137m'
    C_YELLOW=$'\e[38;2;229;200;144m'
    C_RED=$'\e[38;2;231;130;132m'
    C_WHITE=$'\e[38;2;205;214;244m'
    C_BOLD=$'\e[1m'
    C_RST=$'\e[0m'
else
    C_MAIN='' C_ACCENT='' C_DIM='' C_GREEN='' C_YELLOW='' C_RED='' C_WHITE='' C_BOLD='' C_RST=''
fi

ui_step()   { echo -e "\n${C_MAIN}${C_BOLD}▸ $1${C_RST}"; }
ui_ok()     { local msg="${2:-}"; [[ -n "$msg" ]] && echo -e "${C_GREEN}✓${C_RST} ${C_BOLD}$1${C_RST} ${C_DIM}$msg${C_RST}" || echo -e "${C_GREEN}✓ $1${C_RST}"; }
ui_fail()   { local msg="${2:-}"; echo -e "${C_RED}✗ $1${C_RST}"; [[ -n "$msg" ]] && echo -e "  ${C_DIM}$msg${C_RST}"; }
ui_warn()   { echo -e "${C_YELLOW}⚠ $1${C_RST}"; }
ui_note()   { echo -e "${C_DIM}  $1${C_RST}"; }
ui_kv()     { printf "  ${C_BOLD}%-${PAD:-16}s${C_RST} %s\n" "$1" "$2"; }
ui_banner() { local a="${1:-Flow}" b="${2:-}"; echo -e "\n${C_MAIN}${C_BOLD}  Flow  ${C_RST}${b:+$C_DIM$b$C_RST}\n"; }
ui_frame_open() { echo -e "${C_DIM}── ${1} ──${C_RST}"; }
ui_frame_close(){ echo -e "${C_DIM}───────────────────────────────────────${C_RST}"; }

# Confirmation
ui_confirm() {
    local prompt="${1:-Continue?}" dflt="${2:-yes}"
    if [[ "$OPT_ASSUME_YES" == true ]]; then return 0; fi
    if [[ "$OPT_DRY_RUN" == true ]]; then ui_note "Dry run — skipping confirm"; return 0; fi
    local hint=" [y/N]"; [[ "$dflt" == yes ]] && hint=" [Y/n]"
    read -rp "$(echo -e "${C_BOLD}$prompt$hint ${C_RST}")" response
    case "$response" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# Tilde-abbreviate paths for display
tilde() { echo "${1/#$HOME/\~}"; }
