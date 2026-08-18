#!/usr/bin/env bash
#
# setup-flow.sh — installer, updater and manager for the Flow Quickshell configuration.
#
# Running it bare applies the Quickshell config only. Flow is self-contained
# and does not require a base dotfiles installation.
#
# The same file is symlinked to ~/.local/bin/flow and every command
# below is reachable through that name too, with one difference: bare
# `flow` prints help instead of applying.
#
# ── Commands ─────────────────────────────────────────────────────────────────
#
#   apply                   Apply the Quickshell config (the default)
#   install                 Install Flow dependencies and apply config
#   update                  Refresh the Flow config from GitHub
#   restart                 Restart Quickshell (alias: run)
#   doctor                  Report resolved paths, active state and tooling
#   hyprset <args>          Write a Hyprland key or animation
#   hyprmerge <args>        Merge a Hyprland config into the local one
#   project detect          Show detected languages/frameworks/tooling (read-only)
#   remove-cli              Remove the flow symlink
#   help                    Print the full surface (alias: -h, --help)
#   version                 Print the version (alias: -V, --version)
#   demo                    Render every UI primitive and exit
#
# ── Options ──────────────────────────────────────────────────────────────────
#
#   -l, --local <path>        Deploy from a local checkout instead of GitHub
#   -y, --yes                 Skip every confirmation
#   -v, --verbose             Echo command output as it runs
#   -q, --quiet               Only errors on stdout
#       --dry-run             Print what would be done without making changes
#       --backup              Keep the replaced config (default)
#       --no-backup           Discard the replaced config instead
#       --keep-config         Never reset ~/.config/flow/config.json
#       --reset-config        Always reset it (a backup is kept)
#       --no-restart          Leave Quickshell alone when finished
#       --hypr                Install the fork's ~/.config/hypr files
#       --no-hypr             Never install them, never ask
#       --sddm                Install the Flow SDDM greeter + its matugen template
#       --no-sddm             Never install them, never ask
#       --extras              Install the fork's extra configs (mpv + setup scripts)
#       --no-extras           Never install them, never ask
#       --rebuild-quickshell  Rebuild Quickshell from source first
#       --log-file <path>     Write the run log elsewhere
#       --no-log              Do not write a run log
#       --ascii               ASCII glyphs only
#       --no-color            Strip ANSI colour
#       --json                Emit JSON (currently used by: project detect)
#
# --local takes either a fork checkout (with dots/.config/quickshell/flow*) or a
# flow config dir directly. `update` will not guess a local path back: it refuses
# and prints the --local line to re-run, so a stale checkout is never silently
# redeployed.
#
# On Arch, `install` ends by putting the AUR quickshell-git back: the base
# installer builds its own pinned quickshell and this fork is written against
# master. That happens before any config lands, and asks first unless -y.
#
# Given neither --keep-config nor --reset-config, config.json is kept on
# updates and branch hops and reset on source switches, where the schema changes.
#
# apply, install, update and switch offer to overlay the fork's Hyprland config
# on ~/.config/hypr. Given neither --hypr nor --no-hypr it is a question, and
# -y answers it "no" rather than "yes": the Settings update button runs
# unattended and must not rewrite Hyprland underneath you. --hypr is the way to
# ask for it in a script.
#
# `install` alone also offers the Flow SDDM greeter — the Flow theme, its
# matugen template and the sddm service. The same -y/"no" rule applies, and
# --sddm is the explicit yes. SDDM writes to /usr/share and /etc, so the
# installer's own sudo prompts still appear.
#
# `install` also offers the Flow's extra dotfile folders (currently mpv) on top
# of the configs. Same -y/"no" rule; --extras is the explicit yes.
#
# Options take --flag=value as well as --flag value, and everything after a
# bare -- is passed through to hyprset/hyprmerge.
#
# Aliases kept for muscle memory: --no-confirm/--noconfirm (-y),
# --preserve-config (--keep-config), --force-install (--skip-base-check),
# --no-colour (--no-color), and the flag spellings --apply, --install,
# --update, --switch, --demo.

set -Eeuo pipefail

SETUP_VERSION="2.0.0"

# ── Resolve this script's real directory (follows symlinks) ──────────────────
_source="${BASH_SOURCE[0]}"
while [[ -L "$_source" ]]; do
    _dir="$(cd -P "$(dirname "$_source")" >/dev/null 2>&1 && pwd)"
    _source="$(readlink "$_source")"
    [[ "$_source" != /* ]] && _source="$_dir/$_source"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_source")" >/dev/null 2>&1 && pwd)"
SCRIPT_SELF="$(basename "$_source")"
INVOKED_AS="$(basename "${0}")"
unset _source _dir

# ── Paths ────────────────────────────────────────────────────────────────────
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

MIRROR_DIR="$XDG_DATA_HOME/flow"       # installed copy of this script + libs
SETUP_STATE_DIR="$XDG_STATE_HOME/flow" # logs and backups
BACKUP_BASE_DIR="$SETUP_STATE_DIR/backups"
DEFAULT_LOG_FILE="$SETUP_STATE_DIR/setup.log"
QS_DIR="$XDG_CONFIG_HOME/quickshell"
TARGET_DIR="$QS_DIR/flow"
FLOW_CONFIG_DIR="$TARGET_DIR"
FLOW_CONFIG_FILE="$XDG_CONFIG_HOME/flow/config.json"
BIN_DIR="$HOME/.local/bin"
CLI_NAME="flow"

BACKUPS_TO_KEEP=3

# ── Flow upstream ────────────────────────────────────────────────────────
# Single source of truth — no fork switching, no upstream cache required.
FLOW_URL="https://github.com/SrwR16/ArchTide"
FLOW_BRANCH="dev"

# Files carried across a replace, relative to the Quickshell config dir.
PROTECTED_PATTERNS=(
    ".env"
    "*.env"
    "user/generated/*.json"
    "scripts/hyprland/workspace_compactor"
    "scripts/hyprland/workspace_profile_manager"
    "scripts/osk/osk_autoshow"
    "scripts/appStats/app_stats"
)

# ── The fork's Hyprland config ───────────────────────────────────────────────
# Everything under dots/.config/hypr is overlaid on ~/.config/hypr except the
# paths below, matched against the path relative to that directory.

# The base installer owns custom/ and it is where your own edits are meant to
# live, so the fork never writes there.
HYPR_EXCLUDE_DIRS=("custom")

# Matugen rewrites both of these on every wallpaper change — see the
# [templates.hyprland] and [templates.hyprlock] blocks in matugen's config.toml.
# The repo's copies are a snapshot of whatever wallpaper was set at commit time,
# so they are seeded when missing and never overwritten afterwards.
HYPR_SEED_ONLY=("hyprland/colors.lua" "hyprlock/colors.conf")

# ── Options ──────────────────────────────────────────────────────────────────
COMMAND=""
OPT_LOCAL=""
OPT_VERBOSE=false
OPT_QUIET=false
OPT_ASSUME_YES=false
OPT_DRY_RUN=false
OPT_BACKUP=true
OPT_KEEP_CONFIG="" # "" = per-command default, true/false = explicit
OPT_REBUILD_QS=false
OPT_RESTART=true
OPT_HYPR="" # "" = ask (and -y declines), true/false = explicit
OPT_SDDM="" # "" = ask on install only (and -y declines), true/false = explicit
OPT_EXTRAS="" # "" = ask on install only (and -y declines), true/false = explicit
OPT_ASCII=false
OPT_NO_COLOR=false
OPT_JSON=false
OPT_LOG=true
LOG_FILE="$DEFAULT_LOG_FILE"
LOG_READY=false
PASSTHRU_ARGS=()
PROJECT_ARGS=()

# ── Run state (used by the exit trap) ────────────────────────────────────────
STAGE_DIR=""
CLONE_DIR=""
LOCAL_SRC=""  # resolved --local path; empty means "clone from GitHub"
LOCAL_KIND="" # repo | ii
DISPLACED_DIR=""
SWAP_STATE="none" # none | moved-away | done
START_EPOCH="$SECONDS"

#══════════════════════════════════════════════════════════════════════════════
# UI layer
#══════════════════════════════════════════════════════════════════════════════

UI_TTY=false
UI_COLOR=true
UI_TRUECOLOR=false
UI_GLYPHS="unicode" # nerd | unicode | ascii
UI_WIDTH=52
UI_LABELCOL=11 # shared label column, so every row type lines up
UI_SPIN_I=0
UI_LIVE=false # a step line is currently held open on the terminal
UI_STEP_LABEL=""
UI_STEP_US=0       # start of the open step, in microseconds
UI_PIPE_MARK=0     # last milestone emitted by the non-TTY progress backend
UI_ROW_FD=1        # stream ui_row writes to; ui_fail flips it to stderr
ERR_REPORTED=false # a failure has already been surfaced to the user

# ── Material palette ─────────────────────────────────────────────────────────
# Matugen regenerates this on every wallpaper change; the Settings panel watches
# the same file through MaterialThemeLoader.qml.
M3_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/colors.json"
M3_PRIMARY="" M3_SECONDARY="" M3_TERTIARY="" M3_ERROR="" M3_OUTLINE=""

# Pull the handful of roles we colour with straight out of the generated JSON.
# Deliberately sed and not jq: this has to work mid-`install` on a bare machine,
# before either jq or matugen exists.
ui_m3_load() {
    [[ -r "$M3_FILE" ]] || return 1
    local k v
    while IFS=$'\t' read -r k v; do
        case "$k" in
            primary) M3_PRIMARY="$v" ;;
            secondary) M3_SECONDARY="$v" ;;
            tertiary) M3_TERTIARY="$v" ;;
            error) M3_ERROR="$v" ;;
            outline) M3_OUTLINE="$v" ;;
        esac
    done < <(sed -n 's/^[[:space:]]*"\([a-z_]*\)"[[:space:]]*:[[:space:]]*"\(#[0-9a-fA-F]\{6\}\)".*/\1\t\2/p' "$M3_FILE" 2>/dev/null)
    [[ -n "$M3_PRIMARY" && -n "$M3_SECONDARY" && -n "$M3_TERTIARY" &&
        -n "$M3_ERROR" && -n "$M3_OUTLINE" ]]
}

ui_fg() {
    printf '\033[38;2;%d;%d;%dm' "$((16#${1:1:2}))" "$((16#${1:3:2}))" "$((16#${1:5:2}))"
}

# Colours. Kept on even when piped: the Settings panel parses these SGR codes.
ui_palette() {
    if [[ "$UI_COLOR" != true ]]; then
        C_RST="" C_B="" C_DIM="" C_IT="" C_UL=""
        C_ERR="" C_OK="" C_WARN="" C_STEP="" C_ACC="" C_HEAD="" C_SUB=""
        return 0
    fi
    C_RST=$'\033[0m'
    C_B=$'\033[1m'
    C_DIM=$'\033[2m'
    C_IT=$'\033[3m'
    C_UL=$'\033[4m'
    C_ERR=$'\033[0;31m'
    C_OK=$'\033[0;32m'
    C_WARN=$'\033[1;33m'
    C_STEP=$'\033[0;34m'
    C_ACC=$'\033[0;35m'
    C_HEAD=$'\033[1;36m'
    C_SUB=$'\033[0;90m'

    # On a real 24-bit terminal, repaint from the live matugen palette. Piped
    # output keeps the basic codes above on purpose: AboutConfig.qml maps them
    # onto theme roles, so the Settings log box re-themes with the wallpaper
    # instead of freezing to whatever it was when the line was written.
    if [[ "$UI_TTY" == true && "$UI_TRUECOLOR" == true ]] && ui_m3_load; then
        C_ERR="$(ui_fg "$M3_ERROR")"
        C_OK="$(ui_fg "$M3_PRIMARY")"
        C_WARN="$(ui_fg "$M3_TERTIARY")"
        C_STEP="$(ui_fg "$M3_SECONDARY")"
        C_ACC="$(ui_fg "$M3_TERTIARY")"
        C_HEAD="$(ui_fg "$M3_PRIMARY")"
        C_SUB="$(ui_fg "$M3_OUTLINE")"
    fi
}

ui_glyphset() {
    BAR_P=()
    case "$UI_GLYPHS" in
        nerd)
            G_OK=$'' G_ERR=$'' G_WARN=$'' G_STEP=$''
            G_DOT=$'' G_ARROW=$'' G_SEP="·" G_W=1
            RULE="─" ELLIPSIS="…"
            BAR_L="▕" BAR_R="▏" BAR_F="█" BAR_E="░"
            BAR_P=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉")
            SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
            ;;
        unicode)
            G_OK="✓" G_ERR="✗" G_WARN="⚠" G_STEP="▸"
            G_DOT="●" G_ARROW="→" G_SEP="·" G_W=1
            RULE="─" ELLIPSIS="…"
            BAR_L="▕" BAR_R="▏" BAR_F="█" BAR_E="░"
            BAR_P=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉")
            SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
            ;;
        *)
            G_OK="ok" G_ERR="X" G_WARN="!" G_STEP=">"
            G_DOT="*" G_ARROW="->" G_SEP="-" G_W=2
            RULE="-" ELLIPSIS="..."
            BAR_L="[" BAR_R="]" BAR_F="#" BAR_E="-"
            SPIN=(- \\ \| /)
            ;;
    esac
}

# Operation icons, nerd only. They replace the generic tick on a completed row:
# the row is already green and already in the success position, so the glyph is
# free to say *what* finished rather than *that* it finished.
ui_icon() {
    [[ "$UI_GLYPHS" == "nerd" ]] || {
        printf '%s' "$G_OK"
        return 0
    }
    case "$1" in
        Cloned | Fetched) printf '%s' $'' ;;          # cloud-download
        Copied | Staged | Sourced) printf '%s' $'' ;; # files
        Swapped) printf '%s' $'' ;;                   # exchange
        Mirrored) printf '%s' $'' ;;                  # clone
        Restarted) printf '%s' $'' ;;                 # refresh
        Removed) printf '%s' $'' ;;                   # trash
        Reset) printf '%s' $'' ;;                     # undo
        Queried) printf '%s' $'' ;;                   # git-branch
        Deps | Configured | Compiled | Installed)
            printf '%s' $'' # package
            ;;
        *) printf '%s' "$G_OK" ;;
    esac
}

ui_has_nerd_font() {
    command -v fc-list >/dev/null 2>&1 || return 1
    # In a subshell with pipefail off: grep -q exits on the first match and
    # SIGPIPEs fc-list, which pipefail reports as 141 — indistinguishable from
    # "no patched font installed", so the upgrade never fired.
    (
        set +o pipefail
        fc-list 2>/dev/null | grep -qiE 'nerd font|nerdfont'
    )
}

# Provisional defaults so anything that fails before ui_init still renders.
ui_palette
ui_glyphset

ui_init() {
    [[ -t 1 ]] && UI_TTY=true

    if [[ "$OPT_NO_COLOR" == true || -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
        UI_COLOR=false
    fi
    case "${COLORTERM:-}" in
        truecolor | 24bit) UI_TRUECOLOR=true ;;
    esac

    local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [[ "$OPT_ASCII" == true ]] || [[ -n "${NO_UNICODE:-}" ]] ||
        [[ "$loc" == "C" || "$loc" == "POSIX" || -z "$loc" ]] ||
        [[ ! "$loc" =~ [Uu][Tt][Ff]-?8 ]]; then
        UI_GLYPHS="ascii"
    elif [[ "$UI_TTY" == true ]] && ui_has_nerd_font; then
        # Only upgrade on a real terminal: the Settings panel renders with the
        # theme's monospace family, which is not necessarily patched.
        UI_GLYPHS="nerd"
    else
        UI_GLYPHS="unicode"
    fi

    if [[ "$UI_TTY" == true ]]; then
        local cols
        cols="$( (tput cols 2>/dev/null || echo 80))"
        [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
        UI_WIDTH=$((cols - 2))
        ((UI_WIDTH > 76)) && UI_WIDTH=76
        ((UI_WIDTH < 44)) && UI_WIDTH=44
    else
        # Fixed width so the layout survives the Settings log box at any panel size.
        UI_WIDTH=52
    fi

    ui_palette
    ui_glyphset
}

ui_repeat() {
    local ch="$1" n="${2:-0}" out=""
    ((n < 0)) && n=0
    while ((n-- > 0)); do out+="$ch"; done
    printf '%s' "$out"
}

ui_pad() { printf '%*s' "$(($1 > 0 ? $1 : 0))" ''; }

ui_trunc() {
    local s="$1" max="$2"
    ((max < 4)) && max=4
    if ((${#s} > max)); then
        printf '%s%s' "${s:0:max-${#ELLIPSIS}}" "$ELLIPSIS"
    else
        printf '%s' "$s"
    fi
}

# Microseconds since the epoch. EPOCHREALTIME is bash 5; the decimal separator
# is locale-dependent, so strip it rather than assuming a dot.
ui_now_us() {
    local t="${EPOCHREALTIME:-}"
    if [[ -n "$t" ]]; then
        printf '%s' "${t/[.,]/}"
    else
        printf '%s000000' "$SECONDS"
    fi
}

ui_fmt_dur() {
    local us="$1" ms s
    ((us < 0)) && us=0
    ms=$((us / 1000))
    if ((ms < 60000)); then
        printf '%d.%ds' $((ms / 1000)) $(((ms % 1000) / 100))
    else
        s=$((ms / 1000))
        printf '%dm%02ds' $((s / 60)) $((s % 60))
    fi
}

# Append a plain, timestamped line to the log file. Never touches stdout, and
# stays silent until open_log has proven the file is actually writable.
ui_logline() {
    [[ "$LOG_READY" == true ]] || return 0
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE" 2>/dev/null || true
}

ui_out() {
    [[ "$OPT_QUIET" == true ]] && return 0
    printf '%s\n' "$1"
}

# ── Rules and headers ────────────────────────────────────────────────────────

ui_rule() {
    local title="${1:-}" col="${2:-$C_SUB}"
    [[ "$OPT_QUIET" == true ]] && return 0
    if [[ -z "$title" ]]; then
        printf '%s%s%s\n' "$col" "$(ui_repeat "$RULE" "$UI_WIDTH")" "$C_RST"
        return 0
    fi
    title="$(ui_trunc "$title" $((UI_WIDTH - 8)))"
    printf '%s%s%s %s%s%s %s%s%s\n' \
        "$col" "$RULE$RULE" "$C_RST" "$C_B$col" "$title" "$C_RST" \
        "$col" "$(ui_repeat "$RULE" $((UI_WIDTH - 4 - ${#title})))" "$C_RST"
}

ui_banner() {
    local title="$1" sub="${2:-}"
    ui_logline "== $title ${sub:+- $sub}"
    [[ "$OPT_QUIET" == true ]] && return 0
    local right="" left="$title"
    [[ -n "$sub" ]] && left="$title  $sub"
    # `help` already puts the version in the subtitle; don't print it twice.
    [[ "$sub" =~ ^v[0-9] ]] || right="v$SETUP_VERSION"
    left="$(ui_trunc "$left" $((UI_WIDTH - ${#right} - 2)))"
    printf '\n%s%s%s%s%s%s%s%s%s\n' \
        "$C_B$C_HEAD" "$title" "$C_RST" \
        "$C_SUB" "${left#"$title"}" "$C_RST" \
        "$(ui_pad $((UI_WIDTH - ${#left} - ${#right})))" \
        "$C_SUB$right" "$C_RST"
    ui_rule
    printf '\n'
}

# ── Buffered key/value sections ──────────────────────────────────────────────
# Rows are collected instead of printed so the key column can be sized to the
# widest key actually present, rather than to a hardcoded guess.

UI_SECTION_TITLE=""
UI_SECTION_ROWS=()

ui_frame_open() {
    UI_SECTION_TITLE="${1:-}"
    UI_SECTION_ROWS=()
}

ui_kv() {
    local key="$1" val="$2"
    ui_logline "$key: $val"
    [[ "$OPT_QUIET" == true ]] && return 0
    UI_SECTION_ROWS+=("k"$'\t'"$key"$'\t'"$val")
}

ui_frame_row() {
    [[ "$OPT_QUIET" == true ]] && return 0
    UI_SECTION_ROWS+=("r"$'\t'"$1")
}

ui_frame_close() {
    [[ "$OPT_QUIET" == true ]] && return 0
    ((${#UI_SECTION_ROWS[@]} == 0)) && {
        UI_SECTION_TITLE=""
        return 0
    }
    local keycol=0 entry kind key val
    for entry in "${UI_SECTION_ROWS[@]}"; do
        IFS=$'\t' read -r kind key val <<<"$entry"
        [[ "$kind" == "k" ]] && ((${#key} > keycol)) && keycol=${#key}
    done
    ((keycol > 0)) && keycol=$((keycol + 2))

    ui_rule "$UI_SECTION_TITLE"
    for entry in "${UI_SECTION_ROWS[@]}"; do
        IFS=$'\t' read -r kind key val <<<"$entry"
        if [[ "$kind" == "k" ]]; then
            val="$(ui_trunc "$val" $((UI_WIDTH - 2 - keycol)))"
            printf '  %s%s%s%s%s\n' \
                "$C_SUB" "$key" "$(ui_pad $((keycol - ${#key})))" "$C_RST" "$val"
        else
            printf '  %s\n' "$(ui_trunc "$key" $((UI_WIDTH - 2)))"
        fi
    done
    printf '\n'
    UI_SECTION_TITLE=""
    UI_SECTION_ROWS=()
}

# ── Rows ─────────────────────────────────────────────────────────────────────

# One grammar for every message type, so glyph, label, detail and timing all
# land in the same columns no matter which of them printed the line.
# ui_row <colour> <glyph> <label> [detail] [timing]
ui_row() {
    local col="$1" glyph="$2" label="$3" detail="${4:-}" timing="${5:-}"
    local room used pad="" lblpad=""
    room=$((UI_WIDTH - 3 - G_W))
    [[ -n "$timing" ]] && room=$((room - ${#timing} - 2))
    ((room < 8)) && room=8
    if [[ -n "$detail" ]]; then
        ((${#label} < UI_LABELCOL)) && lblpad="$(ui_pad $((UI_LABELCOL - ${#label})))"
        detail="$(ui_trunc "$detail" $((room - ${#label} - ${#lblpad} - 1)))"
        used=$((${#label} + ${#lblpad} + 1 + ${#detail}))
    else
        label="$(ui_trunc "$label" "$room")"
        used=${#label}
    fi
    [[ -n "$timing" ]] && pad="$(ui_pad $((room + 2 - used)))"
    printf '  %s%-*s%s %s%s%s%s%s%s%s\n' \
        "$col" "$G_W" "$glyph" "$C_RST" \
        "$label" "$lblpad" "${detail:+ $C_SUB$detail$C_RST}" \
        "$pad" "$C_SUB" "$timing" "$C_RST" >&"$UI_ROW_FD"
}

# ── Steps and progress ───────────────────────────────────────────────────────

ui_spin_frame() {
    local f="${SPIN[UI_SPIN_I % ${#SPIN[@]}]}"
    UI_SPIN_I=$((UI_SPIN_I + 1))
    printf '%s' "$f"
}

ui_clear_line() {
    [[ "$UI_TTY" == true && "$UI_LIVE" == true ]] || return 0
    printf '\r\033[K'
    UI_LIVE=false
}

ui_step() {
    UI_STEP_LABEL="$1"
    UI_STEP_US="$(ui_now_us)"
    UI_PIPE_MARK=0
    ui_logline "step: $1"
    [[ "$OPT_QUIET" == true ]] && return 0
    if [[ "$UI_TTY" == true ]]; then
        printf '  %s%-*s%s %s' "$C_STEP" "$G_W" "$(ui_spin_frame)" "$C_RST" "$1"
        UI_LIVE=true
    else
        printf '  %s%-*s%s %s\n' "$C_STEP" "$G_W" "$G_STEP" "$C_RST" "$1"
    fi
}

# ui_progress <current> <total> [detail]
ui_progress() {
    local cur="$1" total="$2" detail="${3:-}"
    [[ "$OPT_QUIET" == true ]] && return 0
    ((total <= 0)) && return 0
    local pct=$((cur * 100 / total))
    ((pct > 100)) && pct=100

    if [[ "$UI_TTY" == true ]]; then
        local cells=12
        # Eighth-blocks so the bar advances smoothly instead of in 8% jumps.
        local eighths=$((pct * cells * 8 / 100))
        local whole=$((eighths / 8)) rem=$((eighths % 8)) bar
        bar="$(ui_repeat "$BAR_F" "$whole")"
        if ((rem > 0 && whole < cells && ${#BAR_P[@]} > 0)); then
            bar+="${BAR_P[rem]}"
            whole=$((whole + 1))
        fi
        bar="$BAR_L$bar$(ui_repeat "$BAR_E" $((cells - whole)))$BAR_R"
        local line
        line="$(printf '%-*s %s/%s  %s %3s%%' "$UI_LABELCOL" "$UI_STEP_LABEL" "$cur" "$total" "$bar" "$pct")"
        printf '\r\033[K  %s%-*s%s %s' "$C_STEP" "$G_W" "$(ui_spin_frame)" "$C_RST" "$(ui_trunc "$line" $((UI_WIDTH - 3 - G_W)))"
        UI_LIVE=true
    else
        # Same milestones, one discrete line each, so a piped consumer sees
        # progress without needing to interpret carriage returns.
        local mark=$((pct / 25 * 25))
        if ((mark > UI_PIPE_MARK && mark > 0 && mark < 100)); then
            UI_PIPE_MARK=$mark
            ui_row "$C_SUB" "$G_DOT" "$UI_STEP_LABEL" "$mark%${detail:+ $G_SEP $detail}"
        fi
    fi
}

ui_ok() {
    local label="$1" detail="${2:-}" timing=""
    ui_logline "ok: $label${detail:+ — $detail}"
    if ((UI_STEP_US > 0)); then
        timing="$(ui_fmt_dur $(($(ui_now_us) - UI_STEP_US)))"
        UI_STEP_US=0
    fi
    [[ "$OPT_QUIET" == true ]] && return 0
    ui_clear_line
    ui_row "$C_OK" "$(ui_icon "$label")" "$label" "$detail" "$timing"
}

ui_fail() {
    local label="$1" detail="${2:-}"
    ERR_REPORTED=true
    UI_STEP_US=0
    ui_logline "fail: $label${detail:+ — $detail}"
    ui_clear_line
    UI_ROW_FD=2
    ui_row "$C_ERR" "$G_ERR" "$label" "$detail"
    UI_ROW_FD=1
}

ui_warn() {
    ui_logline "warn: $1"
    [[ "$OPT_QUIET" == true ]] && return 0
    ui_clear_line
    ui_row "$C_WARN" "$G_WARN" "$1"
}

ui_info() {
    ui_logline "info: $1"
    [[ "$OPT_QUIET" == true ]] && return 0
    ui_clear_line
    ui_row "$C_STEP" "$G_STEP" "$1"
}

ui_note() {
    ui_logline "note: $1"
    [[ "$OPT_QUIET" == true ]] && return 0
    ui_clear_line
    printf '    %s%s%s\n' "$C_SUB" "$(ui_trunc "$1" $((UI_WIDTH - 4)))" "$C_RST"
}

ui_verbose() {
    [[ "$OPT_VERBOSE" == true ]] || {
        ui_logline "debug: $1"
        return 0
    }
    ui_clear_line
    printf '    %s%s%s\n' "$C_DIM" "$1" "$C_RST"
    ui_logline "debug: $1"
}

# ui_result <ok|fail> <headline> [extra lines...]
ui_result() {
    local kind="$1" headline="$2"
    shift 2
    local col="$C_OK" glyph="$G_OK"
    [[ "$kind" != "ok" ]] && {
        col="$C_ERR"
        glyph="$G_ERR"
    }
    ui_logline "result($kind): $headline"
    [[ "$OPT_QUIET" == true ]] && {
        for l in "$@"; do ui_logline "  $l"; done
        return 0
    }
    ui_clear_line
    printf '\n'
    ui_rule "" "$col"
    ui_row "$col$C_B" "$glyph" "$headline"
    local line
    for line in "$@"; do
        ui_logline "  $line"
        printf '    %s%s%s\n' "$C_SUB" "$(ui_trunc "$line" $((UI_WIDTH - 4)))" "$C_RST"
    done
    printf '\n'
}

ui_die() {
    ui_fail "${1:-Failed}" "${2:-}"
    exit "${3:-1}"
}

# ui_confirm <question> [default] — honours --yes, refuses to hang on a
# non-interactive stdin. Pass "yes" as the second argument to make a bare Enter
# accept; anything else keeps the cautious no-by-default behaviour.
ui_confirm() {
    [[ "$OPT_ASSUME_YES" == true ]] && return 0
    if [[ ! -t 0 ]]; then
        ui_die "Confirmation required" "stdin is not a terminal — re-run with --yes"
    fi
    local default_yes=false hint='(y/N)'
    [[ "${2:-}" == "yes" ]] && { default_yes=true; hint='(Y/n)'; }
    ui_clear_line
    printf '  %s%-*s%s %s %s%s%s ' \
        "$C_WARN" "$G_W" "$G_WARN" "$C_RST" "$1" "$C_SUB" "$hint" "$C_RST"
    local reply
    read -r reply || reply=""
    printf '\n'
    [[ -z "$reply" && "$default_yes" == true ]] && return 0
    [[ "$reply" =~ ^[Yy]$ ]]
}

ui_elapsed() {
    local secs=$((SECONDS - START_EPOCH))
    if ((secs < 60)); then
        printf '%ds' "$secs"
    else
        printf '%dm%02ds' $((secs / 60)) $((secs % 60))
    fi
}

# ── Demo ─────────────────────────────────────────────────────────────────────
ui_demo() {
    ui_banner "Flow" "ui demo"
    ui_frame_open "Resolve"
    ui_kv "source" "github.com/SrwR16/Flow"
    ui_kv "branch" "dev"
    ui_kv "target" "${TARGET_DIR/#$HOME/\~}"
    ui_frame_close
    ui_step "Cloning"
    local i
    for i in 3 25 50 75 99; do
        ui_progress "$((i * 1284 / 100))" 1284 "objects"
        [[ "$UI_TTY" == true ]] && sleep 0.12
    done
    ui_ok "Cloned" "1284 files $G_SEP 4.2 MB"
    ui_step "Staging"
    [[ "$UI_TTY" == true ]] && sleep 0.2
    ui_ok "Staged" "3 protected files carried"
    ui_step "Swapping"
    [[ "$UI_TTY" == true ]] && sleep 0.1
    ui_ok "Swapped" "backup $G_ARROW flow_flow_dev_20260727-1412"
    printf '\n'
    ui_info "an informational step"
    ui_note "a dimmed aside"
    ui_warn "a warning"
    ui_fail "a failure" "with detail"
    ui_verbose "a verbose line (only with -v)"
    ui_result ok "demo complete $G_SEP $(ui_elapsed)" \
        "glyphs: $UI_GLYPHS $G_SEP width: $UI_WIDTH $G_SEP tty: $UI_TTY" \
        "palette: $([[ -n "$M3_PRIMARY" ]] && printf 'matugen %s' "$M3_PRIMARY" || printf 'ansi 16')"
    printf '%s  text styles:%s %sbold%s %sdim%s %sitalic%s %sunderline%s %saccent%s\n\n' \
        "$C_SUB" "$C_RST" "$C_B" "$C_RST" "$C_DIM" "$C_RST" \
        "$C_IT" "$C_RST" "$C_UL" "$C_RST" "$C_ACC" "$C_RST"
}

#══════════════════════════════════════════════════════════════════════════════
# Traps
#══════════════════════════════════════════════════════════════════════════════

on_err() {
    local rc=$1 line=$2 cmd=$3
    # Whatever went wrong has already been explained in the user's own terms.
    [[ "$ERR_REPORTED" == true ]] && return 0
    ui_clear_line
    ui_fail "Aborted" "line $line exited $rc"
    [[ "$OPT_VERBOSE" == true ]] && printf '%s  %s%s\n' "$C_DIM" "$cmd" "$C_RST" >&2
    ui_logline "error: line $line rc=$rc cmd=$cmd"
}

on_exit() {
    local rc=$?
    # Nothing this trap does is worth an error report, and its own `return $rc`
    # is itself a failing command on any non-zero exit — which is where the
    # spurious second "Aborted, line 1" after a clean ui_fail came from.
    trap - ERR
    [[ "$UI_TTY" == true ]] && {
        printf '\033[?25h'
        ui_clear_line
    }

    # Died between the two renames: put the previous tree back.
    if [[ "$SWAP_STATE" == "moved-away" && -n "$DISPLACED_DIR" && -d "$DISPLACED_DIR" && ! -e "$TARGET_DIR" ]]; then
        if mv "$DISPLACED_DIR" "$TARGET_DIR" 2>/dev/null; then
            ui_warn "Restored the previous config after a failed swap."
        fi
    fi

    [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]] && rm -rf "$STAGE_DIR"
    [[ -n "$CLONE_DIR" && -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"
    return "$rc"
}

on_signal() {
    ui_clear_line
    ui_fail "Interrupted" "cleaning up"
    exit 130
}

trap 'on_err $? $LINENO "$BASH_COMMAND"' ERR
trap on_exit EXIT
trap on_signal INT TERM

#══════════════════════════════════════════════════════════════════════════════
# Helpers
#══════════════════════════════════════════════════════════════════════════════

have() { command -v "$1" >/dev/null 2>&1; }

tilde() { printf '%s' "${1/#$HOME/\~}"; }

# Make a string safe as a single path component. Branch names legitimately
# contain '/' (refactor/setup-p3drovfx), which would otherwise turn a backup
# name into a nested path whose parent does not exist.
path_slug() {
    local s="${1//[^A-Za-z0-9._-]/-}"
    s="${s##-}"
    printf '%s' "${s:-unknown}"
}

# Run a command, tee its output to the log, echo it only when verbose.
run_logged() {
    local rc=0
    if [[ "$OPT_VERBOSE" == true ]]; then
        "$@" 2>&1 | tee -a "$LOG_FILE" || rc=${PIPESTATUS[0]}
    else
        "$@" >>"$LOG_FILE" 2>&1 || rc=$?
    fi
    return "$rc"
}

normalize_url() {
    local raw="$1"
    raw="${raw%.git}"
    raw="${raw%/}"
    if [[ "$raw" == git@github.com:* ]]; then
        raw="https://github.com/${raw#git@github.com:}"
    elif [[ "$raw" == ssh://git@github.com/* ]]; then
        raw="https://github.com/${raw#ssh://git@github.com/}"
    elif [[ "$raw" == http://github.com/* ]]; then
        raw="https://${raw#http://}"
    fi
    printf '%s' "$raw"
}

# resolve_local <path> -- prints "abspath|kind", kind being repo or ii.
# A fork checkout and the ii config dir inside one are both valid sources; the
# difference is only whether detect_ii_subdir still has work to do.
resolve_local() {
    local raw="${1/#\~/$HOME}" abs
    abs="$(cd -P -- "$raw" 2>/dev/null && pwd)" || {
        ui_fail "No such directory" "$raw"
        return 1
    }
    if [[ "$abs" == "$TARGET_DIR" ]]; then
        ui_fail "Source is the target" "$(tilde "$abs") is what gets replaced"
        return 1
    fi
    if [[ -d "$abs/dots/.config/quickshell" ]]; then
        printf '%s|repo' "$abs"
        return 0
    fi
    if [[ -f "$abs/shell.qml" ]]; then
        printf '%s|ii' "$abs"
        return 0
    fi
    ui_fail "Not a source tree" "$(tilde "$abs")"
    # 2, not 1: this is the one failure worth explaining, and the explanation
    # has to come from the caller — ui_note writes to stdout, which the command
    # substitution around this function would swallow.
    return 2
}

# Sets LOCAL_SRC and LOCAL_KIND from OPT_LOCAL, or leaves both empty.
load_local_src() {
    [[ -n "$OPT_LOCAL" ]] || return 0
    local pair rc=0
    pair="$(resolve_local "$OPT_LOCAL")" || rc=$?
    if ((rc != 0)); then
        ((rc == 2)) && ui_note "Expected dots/.config/quickshell/ii* or a shell.qml at the top."
        exit 1
    fi
    LOCAL_SRC="${pair%|*}"
    LOCAL_KIND="${pair#*|}"
}

read_state() {
    local remote="" branch="" fork=""
    [[ -f "$TARGET_DIR/.active-remote" ]] && remote="$(<"$TARGET_DIR/.active-remote")"
    [[ -f "$TARGET_DIR/.active-branch" ]] && branch="$(<"$TARGET_DIR/.active-branch")"
    [[ -f "$TARGET_DIR/.active-fork" ]] && fork="$(<"$TARGET_DIR/.active-fork")"
    remote="${remote//[$'\r\n']/}"
    branch="${branch//[$'\r\n']/}"
    fork="${fork//[$'\r\n']/}"
    [[ -z "$branch" ]] && branch="$FLOW_BRANCH"
    printf '%s|%s|%s' "$remote" "$branch" "$fork"
}

# The local path the active config was deployed from, or empty.
read_local_state() {
    local p=""
    [[ -f "$TARGET_DIR/.active-local" ]] && p="$(<"$TARGET_DIR/.active-local")"
    printf '%s' "${p//[$'\r\n']/}"
}

require_base() {
    [[ -d "$FLOW_CONFIG_DIR" ]] && return 0
    ui_fail "Flow config missing" "$(tilde "$FLOW_CONFIG_DIR") does not exist"
    ui_note "Flow config is not installed. Install it explicitly:"
    ui_note "    $SCRIPT_SELF install"
    exit 1
}

open_log() {
    [[ "$OPT_LOG" == true ]] || return 0
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || return 0
    touch "$LOG_FILE" 2>/dev/null || return 0
    LOG_READY=true
    # Keep the log from growing without bound across many runs.
    if [[ -f "$LOG_FILE" ]]; then
        local lines
        lines="$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)"
        if ((lines > 5000)); then
            tail -n 2000 "$LOG_FILE" >"$LOG_FILE.trim" 2>/dev/null &&
                mv "$LOG_FILE.trim" "$LOG_FILE"
        fi
    fi
    ui_logline "--- $SCRIPT_SELF $SETUP_VERSION | ${COMMAND:-apply} | args: ${ORIGINAL_ARGS[*]:-} ---"
}

#══════════════════════════════════════════════════════════════════════════════
# Clone / copy with progress
#══════════════════════════════════════════════════════════════════════════════

# tree_stats <dir> — "1284 files ⋅ 4.2M", the tail of a Cloned/Sourced row
tree_stats() {
    local count size
    count="$({ find "$1" -type f -not -path '*/.git/*' 2>/dev/null || true; } | wc -l)"
    size="$(du -sh --exclude=.git "$1" 2>/dev/null | cut -f1)"
    printf '%s files%s' "$count" "${size:+ $G_SEP $size}"
}

# clone_repo <url> <branch> <dest> — <branch> may be "default"
clone_repo() {
    local url="$1" branch="$2" dest="$3"
    local args=(clone --depth=1 --recurse-submodules --progress)
    [[ "$branch" != "default" ]] && args+=(--branch "$branch")
    args+=("$url" "$dest")

    ui_step "Cloning"
    local rc=0
    set +o pipefail
    git "${args[@]}" 2>&1 | tr '\r' '\n' | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
        # "Receiving objects:  63% (812/1284), 4.20 MiB | 2.00 MiB/s"
        case "$line" in
            Receiving* | Resolving* | Updating*)
                local frag="${line#*\(}"
                frag="${frag%%\)*}"
                if [[ "$frag" == */* && "$frag" != *[!0-9/]* ]]; then
                    ui_progress "${frag%%/*}" "${frag##*/}" "${line%%:*}"
                fi
                ;;
        esac
    done
    rc=${PIPESTATUS[0]}
    set -o pipefail

    if ((rc != 0)); then
        ui_fail "Clone failed" "branch '$branch' on $url"
        ui_note "List what exists with: $SCRIPT_SELF list-branches"
        return 1
    fi

    # --depth=1 can silently skip a submodule pinned to an unreachable SHA.
    git -C "$dest" submodule update --init --recursive --depth=1 >>"$LOG_FILE" 2>&1 || true

    ui_ok "Cloned" "$(tree_stats "$dest")"
    return 0
}

# copy_tree <src>/ <dst>/
copy_tree() {
    local src="$1" dst="$2"
    ui_step "Copying"
    mkdir -p "$dst"
    if have rsync; then
        local rc=0
        set +o pipefail
        rsync -a --info=progress2 --exclude='.git' --exclude='.gitmodules' \
            "$src/" "$dst/" 2>&1 | tr '\r' '\n' | while IFS= read -r line; do
            [[ "$line" =~ ([0-9]+)% ]] && ui_progress "${BASH_REMATCH[1]}" 100 ""
        done
        rc=${PIPESTATUS[0]}
        set -o pipefail
        ((rc == 0)) || {
            ui_fail "Copy failed" "rsync exited $rc"
            return 1
        }
    else
        cp -a "$src/." "$dst/" || {
            ui_fail "Copy failed" "cp exited $?"
            return 1
        }
        find "$dst" -name '.git' -maxdepth 3 -exec rm -rf {} + 2>/dev/null || true
    fi
    ui_ok "Copied" "$(find "$dst" -type f 2>/dev/null | wc -l) files staged"
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# Protected files, backups, atomic swap
#══════════════════════════════════════════════════════════════════════════════

# carry_protected <live_dir> <stage_dir> — prints the number of files carried
carry_protected() {
    local live="$1" stage="$2" n=0
    [[ -d "$live" ]] || {
        printf '0'
        return 0
    }
    local pattern f rel
    for pattern in "${PROTECTED_PATTERNS[@]}"; do
        while IFS= read -r -d '' f; do
            rel="${f#"$live"/}"
            mkdir -p "$stage/$(dirname "$rel")"
            cp -a "$f" "$stage/$rel"
            ui_verbose "carried $rel"
            n=$((n + 1))
        done < <(find "$live" -path "$live/$pattern" -type f -print0 2>/dev/null)
    done
    printf '%s' "$n"
}

# prune_backups [prefix] — keeps the newest BACKUPS_TO_KEEP of one family.
# The families are pruned independently: a run of config replaces must not age
# out the hypr backup that the same run just took.
prune_backups() {
    [[ -d "$BACKUP_BASE_DIR" ]] || return 0
    local prefix="${1:-ii_}" old
    while IFS= read -r old; do
        [[ -n "$old" ]] || continue
        rm -rf "$old"
        ui_verbose "pruned backup $(basename "$old")"
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "$prefix*" -printf '%T@ %p\n' 2>/dev/null |
        sort -rn | tail -n "+$((BACKUPS_TO_KEEP + 1))" | cut -d' ' -f2-)
}

# next_backup_dir <prefix> — a free, timestamped path under BACKUP_BASE_DIR.
# Second resolution is not enough for two runs in the same second.
next_backup_dir() {
    local base dir n=2
    base="$BACKUP_BASE_DIR/$1$(date +%Y%m%d-%H%M%S)"
    dir="$base"
    while [[ -e "$dir" ]]; do
        dir="$base-$n"
        n=$((n + 1))
    done
    printf '%s' "$dir"
}

# swap_in <stage> <fork_id> <branch> — atomically replaces TARGET_DIR
swap_in() {
    local stage="$1" fork="$2" branch="$3"
    ui_step "Swapping"

    local label=""
    if [[ -d "$TARGET_DIR" ]]; then
        if [[ "$OPT_BACKUP" == true ]]; then
            mkdir -p "$BACKUP_BASE_DIR"
            # A unique name matters more here than elsewhere: mv onto an
            # existing directory nests the config inside it rather than
            # replacing it, and the run after that fails outright.
            DISPLACED_DIR="$(next_backup_dir "ii_$(path_slug "$fork")_$(path_slug "$branch")_")"
            label="backup $G_ARROW $(basename "$DISPLACED_DIR")"
        else
            DISPLACED_DIR="$QS_DIR/.ii-discard-$$"
            label="previous config discarded"
        fi
        if ! mv "$TARGET_DIR" "$DISPLACED_DIR"; then
            DISPLACED_DIR=""
            ui_fail "Swap failed" "could not move the current config aside"
            return 1
        fi
        SWAP_STATE="moved-away"
    fi

    if ! mv "$stage" "$TARGET_DIR"; then
        ui_fail "Swap failed" "could not move the staged config into place"
        return 1
    fi
    STAGE_DIR=""
    SWAP_STATE="done"

    if [[ "$OPT_BACKUP" == false && -n "$DISPLACED_DIR" ]]; then
        rm -rf "$DISPLACED_DIR"
        DISPLACED_DIR=""
    else
        prune_backups
    fi

    ui_ok "Swapped" "${label:-fresh install}"
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# Repo introspection
#══════════════════════════════════════════════════════════════════════════════

# Where a bare run should pull from: this checkout's origin and current branch.
local_origin() {
    local remote="" branch=""
    if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        remote="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)"
        [[ -n "$remote" ]] && remote="$(normalize_url "$remote")"
        branch="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        [[ "$branch" == "HEAD" ]] && branch=""
    fi
    [[ -z "$remote" ]] && {
        remote="$FLOW_URL"
        branch="$FLOW_BRANCH"
    }
    [[ -z "$branch" ]] && branch="$FLOW_BRANCH"
    printf '%s|%s|flow' "$remote" "$branch"
}

#══════════════════════════════════════════════════════════════════════════════
# Quickshell
#══════════════════════════════════════════════════════════════════════════════

# ensure_quickshell_git — ensure quickshell-git is installed on Arch.
#
# The base installer builds its own pinned quickshell and drops quickshell-git
# on the way. This fork is written against Quickshell master, so the pinned
# build is normally older than the QML expects and the shell fails to start.
# Undo that before any config lands, which is why install is the only command
# that calls this.
#
# Arch only: every other distro packages Quickshell its own way, and the
# pinned PKGBUILD is an Arch-specific problem.
ensure_quickshell_git() {
    have pacman || return 0
    if pacman -Qq quickshell-git >/dev/null 2>&1; then
        ui_verbose "quickshell-git already installed"
        return 0
    fi

    local current
    current="$(pacman -Qqo /usr/bin/quickshell 2>/dev/null || true)"

    ui_frame_open "Quickshell package"
    ui_kv "installed" "${current:-none}"
    ui_kv "wanted" "quickshell-git"
    ui_frame_close
    ui_note "This fork follows Quickshell master. The pinned build the base"
    ui_note "installer ships is older, and the shell will not start on it."

    # yay first because that is what the base installer bootstraps, but paru
    # takes the same flags and plenty of people have only that one.
    local helper="" h
    for h in yay paru; do
        have "$h" && {
            helper="$h"
            break
        }
    done
    [[ -n "$helper" ]] || {
        ui_warn "No AUR helper found — install quickshell-git with yay or paru yourself."
        return 0
    }

    if [[ "$OPT_ASSUME_YES" != true ]]; then
        local q="Install quickshell-git?"
        [[ -n "$current" ]] && q="Replace $current with quickshell-git?"
        ui_confirm "$q" || {
            ui_note "Left as is. The shell may not start."
            return 0
        }
    fi

    # Swapping the packages orphans every Qt module the meta-package pulled in
    # as a dependency, and a later `yay -Yc` would then sweep away half of what
    # the shell needs at runtime. Diff the orphan list around the swap so the
    # ones it strands can be marked wanted, without having to guess the list.
    local before after
    before="$(pacman -Qdtq 2>/dev/null | sort || true)"

    ui_info "Running $helper -S quickshell-git — its own output follows."
    printf '\n'
    local -a flags=(-S --needed)
    [[ "$OPT_ASSUME_YES" == true ]] && flags+=(--noconfirm)
    local rc=0
    "$helper" "${flags[@]}" quickshell-git || rc=$?
    printf '\n'
    if ((rc != 0)); then
        ui_warn "quickshell-git install failed (exit $rc) — fix it before starting the shell."
        return 0
    fi

    after="$(pacman -Qdtq 2>/dev/null | sort || true)"
    local -a stranded=()
    mapfile -t stranded < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -v '^$' || true)
    if ((${#stranded[@]} > 0)); then
        run_logged sudo pacman -D -q --asexplicit "${stranded[@]}" ||
            ui_warn "Could not mark ${#stranded[@]} stranded deps explicit."
        ui_verbose "kept: ${stranded[*]}"
        ui_ok "Kept" "${#stranded[@]} Qt deps marked explicit"
    fi

    ui_ok "Quickshell" "$(pacman -Qq quickshell-git 2>/dev/null || printf 'quickshell-git')"
}

qt_mismatch() {
    have quickshell || return 1
    local msg
    msg="$(quickshell --version 2>&1 | grep -iE 'warning|mismatch|abi|symbol' || true)"
    [[ -n "$msg" ]] || return 1
    ui_warn "Quickshell reports a Qt ABI/symbol mismatch:"
    ui_note "$msg"
    return 0
}

build_quickshell() {
    ui_step "Deps"
    if [[ -f /etc/arch-release ]]; then
        run_logged sudo pacman -Sy --needed --noconfirm cmake extra-cmake-modules \
            qt6-base qt6-declarative qt6-wayland wayland libxkbcommon gcc git ||
            ui_warn "Dependency install reported errors; continuing."
        ui_ok "Deps" "arch"
    elif [[ -f /etc/fedora-release ]]; then
        run_logged sudo dnf install -y cmake extra-cmake-modules qt6-qtbase-devel \
            qt6-qtdeclarative-devel qt6-qtwayland-devel wayland-devel \
            libxkbcommon-devel gcc-c++ git ||
            ui_warn "Dependency install reported errors; continuing."
        ui_ok "Deps" "fedora"
    elif [[ -f /etc/debian_version ]]; then
        run_logged sudo apt-get update || true
        run_logged sudo apt-get install -y cmake extra-cmake-modules qt6-base-dev \
            qt6-declarative-dev qt6-wayland-dev libwayland-dev libxkbcommon-dev g++ git ||
            ui_warn "Dependency install reported errors; continuing."
        ui_ok "Deps" "debian"
    else
        ui_warn "Unknown distribution — install cmake, Qt6 dev packages and a C++ compiler yourself."
    fi

    local build_dir
    build_dir="$(mktemp -d "${TMPDIR:-/tmp}/quickshell-build-XXXXXX")"

    ui_step "Fetching"
    if ! run_logged git clone --depth=1 --recursive \
        https://github.com/outfoxxed/quickshell.git "$build_dir"; then
        rm -rf "$build_dir"
        ui_fail "Quickshell source" "clone failed"
        return 1
    fi
    ui_ok "Fetched" "outfoxxed/quickshell"

    ui_step "Configuring"
    if ! run_logged cmake -B "$build_dir/build" -S "$build_dir" \
        -DCMAKE_INSTALL_PREFIX="$HOME/.local" -DCRASH_HANDLER=OFF; then
        rm -rf "$build_dir"
        ui_fail "Quickshell build" "cmake configure failed"
        return 1
    fi
    ui_ok "Configured" "prefix ~/.local"

    ui_step "Compiling"
    run_logged cmake --build "$build_dir/build" -t quickshell-dbus -j"$(nproc)" || true
    local rc=0
    set +o pipefail
    cmake --build "$build_dir/build" -j"$(nproc)" 2>&1 | while IFS= read -r line; do
        printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
        [[ "$line" =~ ^\[[[:space:]]*([0-9]+)%\] ]] && ui_progress "${BASH_REMATCH[1]}" 100 ""
    done
    rc=${PIPESTATUS[0]}
    set -o pipefail
    if ((rc != 0)); then
        rm -rf "$build_dir"
        ui_fail "Quickshell build" "compilation failed (see $(tilde "$LOG_FILE"))"
        return 1
    fi
    ui_ok "Compiled" "quickshell"

    ui_step "Installing"
    if ! run_logged cmake --install "$build_dir/build"; then
        rm -rf "$build_dir"
        ui_fail "Quickshell install" "cmake --install failed"
        return 1
    fi
    rm -rf "$build_dir"
    ui_ok "Installed" "$(tilde "$HOME/.local/bin/quickshell")"
    return 0
}

# Quickshell watches its config tree and hot-reloads the moment anything in it
# changes. Swapping the tree out from under a live instance therefore makes it
# reload onto half the new config with the old process' state still loaded —
# which is how config.json ends up rewritten with defaults. Every path that
# touches the tree stops the shell first and starts it again afterwards.
# `qs` is a symlink to `quickshell`, and the process name follows whichever one
# was used to launch it, so both have to be matched. Missing one leaves a second
# instance alive writing its own schema over config.json.
quickshell_running() {
    pgrep -x qs >/dev/null 2>&1 || pgrep -x quickshell >/dev/null 2>&1
}

stop_quickshell() {
    [[ "$OPT_RESTART" == true ]] || return 0
    quickshell_running || return 0

    # A signalled Quickshell exits without reaping the processes it spawned, so
    # each restart leaves its long-lived children — the nmcli monitor above all —
    # running and reparented to init, one more every time. Asking it to quit over
    # its own IPC socket is the only shutdown that cleans up after itself, and it
    # gives Component.onDestruction, which blocks the final config.json write,
    # a proper chance to run.
    local bin=""
    have qs && bin="qs"
    [[ -n "$bin" ]] || { have quickshell && bin="quickshell"; }

    local stopped=false
    if [[ -n "$bin" ]]; then
        if [[ "$TARGET_DIR" == "$QS_DIR/ii" ]]; then
            "$bin" kill -c ii >>"$LOG_FILE" 2>&1 && stopped=true
        else
            "$bin" kill --path "$TARGET_DIR" >>"$LOG_FILE" 2>&1 && stopped=true
        fi
    fi

    # `kill` returns once the request is sent, not once the shell is gone.
    local waited=0
    while [[ "$stopped" == true ]] && (( waited < 30 )) && quickshell_running; do
        sleep 0.1
        waited=$((waited + 1))
    done

    # Wedged, or too old to answer over IPC: the blunt path, which is the one
    # that strands children, so it is only taken when it has to be.
    local killed=false
    if quickshell_running; then
        for name in qs quickshell; do
            pkill -x "$name" 2>/dev/null && killed=true
        done
        [[ "$killed" == true ]] && sleep 0.5
    fi

    [[ "$stopped" == true || "$killed" == true ]] && ui_ok "Stopped" "running Quickshell instance"
    return 0
}

start_quickshell() {
    [[ "$OPT_RESTART" == true ]] || {
        ui_note "Restart skipped (--no-restart)."
        return 0
    }
    local bin=""
    if have qs; then
        bin="qs"
    elif have quickshell; then
        bin="quickshell"
    else
        ui_warn "Neither qs nor quickshell on PATH — start Quickshell yourself."
        return 0
    fi

    ui_step "Starting"
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && have hyprctl; then
        hyprctl reload >>"$LOG_FILE" 2>&1 || ui_warn "hyprctl reload failed."
        sleep 0.5
    fi
    if [[ "$TARGET_DIR" == "$QS_DIR/ii" ]]; then
        nohup "$bin" -c ii >/dev/null 2>&1 &
        ui_ok "Started" "$bin -c ii"
    else
        nohup "$bin" --path "$TARGET_DIR" >/dev/null 2>&1 &
        ui_ok "Started" "$bin --path $(tilde "$TARGET_DIR")"
    fi
    return 0
}

restart_quickshell() {
    [[ "$OPT_RESTART" == true ]] || {
        ui_note "Restart skipped (--no-restart)."
        return 0
    }
    if ! have qs && ! have quickshell; then
        ui_warn "Neither qs nor quickshell on PATH — start Quickshell yourself."
        return 0
    fi

    stop_quickshell
    start_quickshell
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# CLI install / removal
#══════════════════════════════════════════════════════════════════════════════

install_cli() {
    mkdir -p "$BIN_DIR"
    local script="$MIRROR_DIR/$SCRIPT_SELF"
    [[ -f "$script" ]] || script="$SCRIPT_DIR/$SCRIPT_SELF"
    [[ -f "$script" ]] || return 0
    chmod +x "$script" 2>/dev/null || true
    ln -sfn "$script" "$BIN_DIR/$CLI_NAME"
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        ui_warn "$(tilde "$BIN_DIR") is not on PATH."
        ui_note "Add to your shell rc:  set -gx PATH \$HOME/.local/bin \$PATH"
    fi
    return 0
}

mirror_scripts() {
    local from="$1"
    ui_step "Mirroring"
    mkdir -p "$MIRROR_DIR"
    local copied=0 f
    for f in "$SCRIPT_SELF" setup; do
        if [[ -e "$from/$f" ]]; then
            cp -a "$from/$f" "$MIRROR_DIR/$f"
            chmod +x "$MIRROR_DIR/$f" 2>/dev/null || true
            copied=$((copied + 1))
        fi
    done
    # A fork whose remote has not picked up the rename yet still gets a working
    # mirror: fall back to the copy that is running right now.
    if [[ ! -f "$MIRROR_DIR/$SCRIPT_SELF" && -f "$SCRIPT_DIR/$SCRIPT_SELF" ]]; then
        cp -a "$SCRIPT_DIR/$SCRIPT_SELF" "$MIRROR_DIR/$SCRIPT_SELF"
        chmod +x "$MIRROR_DIR/$SCRIPT_SELF"
        copied=$((copied + 1))
    fi
    if [[ -d "$from/sdata" ]]; then
        rm -rf "$MIRROR_DIR/sdata"
        cp -a "$from/sdata" "$MIRROR_DIR/sdata"
        find "$MIRROR_DIR/sdata" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
        copied=$((copied + 1))
    fi
    # Scripts that used to live here and no longer ship.
    local obsolete
    for obsolete in setup-ii-vynx.sh update-with-customs.sh setup-ii-p3drovfx.sh update-fork.sh; do
        rm -f "${MIRROR_DIR:?}/$obsolete"
    done
    install_cli
    ui_ok "Mirrored" "$copied items $G_ARROW $(tilde "$MIRROR_DIR")"
}

remove_cli() {
    local target="$BIN_DIR/$CLI_NAME"
    if [[ -L "$target" ]]; then
        ui_confirm "Remove the $CLI_NAME CLI from $(tilde "$target")?" || {
            ui_note "Cancelled."
            return 0
        }
        rm -f "$target"
        ui_ok "Removed" "$(tilde "$target")"
        ui_note "$(tilde "$MIRROR_DIR") is left intact."
    else
        ui_warn "No $CLI_NAME symlink at $(tilde "$target")."
        local alt
        alt="$(command -v "$CLI_NAME" 2>/dev/null || true)"
        [[ -n "$alt" ]] && ui_note "Found $CLI_NAME at $alt — remove that one by hand."
    fi
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# The pipeline
#══════════════════════════════════════════════════════════════════════════════

backup_hyprland_config() {
    local dest="$XDG_CONFIG_HOME/hypr"
    [[ -d "$dest" ]] || return 0

    local stamp backup_dir entry
    stamp="$(date +%Y%m%d_%H%M%S)"
    backup_dir="$dest/hyprland_backup_$stamp"
    mkdir -p "$backup_dir" || {
        ui_warn "Could not create Hyprland backup directory: $(tilde "$backup_dir")"
        return 1
    }

    # Keep the backup inside ~/.config/hypr without recursively copying older
    # backups into the new one.
    while IFS= read -r -d '' entry; do
        cp -a "$entry" "$backup_dir/" || {
            ui_warn "Could not back up Hyprland config entry: $(basename "$entry")"
            return 1
        }
    done < <(find "$dest" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | while IFS= read -r -d '' entry; do
        [[ "$(basename "$entry")" == hyprland_backup_* ]] || printf '%s\0' "$entry"
    done)

    ui_note "Hyprland backup: $(tilde "$backup_dir")"
}

# install_hypr_config <repo_root>
#
# Overlays the fork's dots/.config/hypr onto ~/.config/hypr. An overlay and not
# a replace: files the repo does not ship — monitors.conf, your own scripts —
# stay exactly where they are. Anything overwritten is copied to the backup dir
# first unless --no-backup, and identical files are left alone so a re-run
# neither writes nor backs anything up.
install_hypr_config() {
    local repo_root="${1:-}"
    local dest="$XDG_CONFIG_HOME/hypr"

    [[ "$OPT_HYPR" == false ]] && return 0

    local src="$repo_root/dots/.config/hypr"
    if [[ -z "$repo_root" || ! -d "$src" ]]; then
        # Worth a word only when it was actually asked for. Otherwise the
        # source simply has no hypr dots to offer — an ii config dir passed to
        # --local never does — and silence is the right answer.
        [[ "$OPT_HYPR" == true ]] &&
            ui_warn "No dots/.config/hypr in the source — nothing to install."
        return 0
    fi

    if [[ -z "$OPT_HYPR" ]]; then
        # -y declines this one instead of accepting it. The Settings update
        # button runs unattended, and unattended is no time to rewrite the
        # compositor's config underneath somebody. --hypr is the explicit yes.
        if [[ "$OPT_ASSUME_YES" == true ]]; then
            ui_note "Left $(tilde "$dest") alone. Pass --hypr to install it."
            return 0
        fi
        ui_confirm "Also install this fork's Hyprland config into $(tilde "$dest")?" yes || {
            ui_note "Left $(tilde "$dest") alone."
            return 0
        }
    fi
    backup_hyprland_config || return 1

    ui_step "Hyprland"
    local backup_dir="" added=0 replaced=0 seeded=0 kept=0 same=0
    local f rel excluded seed d

    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"

        excluded=false
        for d in "${HYPR_EXCLUDE_DIRS[@]}"; do
            [[ "$rel" == "$d/"* ]] && {
                excluded=true
                break
            }
        done
        [[ "$excluded" == true ]] && continue

        seed=false
        for d in "${HYPR_SEED_ONLY[@]}"; do
            [[ "$rel" == "$d" ]] && {
                seed=true
                break
            }
        done

        if [[ -e "$dest/$rel" ]]; then
            if [[ "$seed" == true ]]; then
                kept=$((kept + 1))
                ui_verbose "kept generated $rel"
                continue
            fi
            if cmp -s "$f" "$dest/$rel"; then
                same=$((same + 1))
                continue
            fi
            if [[ "$OPT_BACKUP" == true ]]; then
                [[ -n "$backup_dir" ]] || {
                    backup_dir="$(next_backup_dir "hypr_")"
                    mkdir -p "$backup_dir"
                }
                mkdir -p "$backup_dir/$(dirname "$rel")"
                cp -a "$dest/$rel" "$backup_dir/$rel"
            fi
            replaced=$((replaced + 1))
        elif [[ "$seed" == true ]]; then
            seeded=$((seeded + 1))
        else
            added=$((added + 1))
        fi

        mkdir -p "$dest/$(dirname "$rel")"
        cp -a "$f" "$dest/$rel"
        [[ "$rel" == *.sh ]] && chmod +x "$dest/$rel" 2>/dev/null
        ui_verbose "wrote $rel"
    done < <(find "$src" -mindepth 1 -type f -print0 2>/dev/null | sort -z)

    local touched=$((added + replaced + seeded))
    if ((touched == 0)); then
        ui_ok "Hyprland" "already current $G_DOT $((same + kept)) files unchanged"
        return 0
    fi

    [[ -n "$backup_dir" ]] && prune_backups "hypr_"
    local detail="$replaced replaced, $added new"
    ((seeded > 0)) && detail="$detail, $seeded seeded"
    ((kept > 0)) && detail="$detail, $kept generated kept"
    ui_ok "Hyprland" "$detail"
    [[ -n "$backup_dir" ]] && ui_note "Replaced files: $(tilde "$backup_dir")"

    # Sub-files of the config are not watched, so nothing would pick these up
    # until the next relog. No-op when Hyprland is not the session, which is
    # exactly the case mid-install on a bare machine.
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && have hyprctl; then
        hyprctl reload >/dev/null 2>&1 || ui_warn "hyprctl reload failed — relog to apply."
    fi
    return 0
}

# install_sddm_config <repo_root> <verb>
#
# Wires the vendored SDDM setup (dots/.config/sddm plus the matugen sddm
# template) into ~/.config/matugen, /usr/share/sddm/themes and /etc/sddm.conf.d.
# Offered on `install` only, like the Hyprland overlay; -y declines it and
# --sddm is the explicit yes. Runs the fork's dots/.config/sddm/install.sh in
# its non-interactive mode, which still needs interactive sudo for the system
# writes, and never disables a display manager that is already running.
install_sddm_config() {
    local repo_root="${1:-}" verb="${2:-}"

    [[ "$OPT_SDDM" == false ]] && return 0

    local src="$repo_root/dots/.config/sddm"
    if [[ ! -f "$src/install.sh" ]]; then
        # Worth a word only when it was actually asked for. A bare --local ii
        # config dir never carries the sddm dots, and silence is fine.
        [[ "$OPT_SDDM" == true ]] &&
            ui_warn "No dots/.config/sddm in the source — nothing to install."
        return 0
    fi

    if [[ -z "$OPT_SDDM" ]]; then
        # Only ever offered on a fresh install, never on update/switch/apply,
        # and -y answers it "no": enabling the greeter is not something an
        # unattended update should do underneath somebody. --sddm is the ask.
        [[ "$verb" == "install" ]] || return 0
        if [[ "$OPT_ASSUME_YES" == true ]]; then
            ui_note "Left SDDM alone. Pass --sddm to install it."
            return 0
        fi
        ui_confirm "Install the Tide SDDM greeter (theme, matugen colours, service)?" yes || {
            ui_note "Left SDDM alone."
            return 0
        }
    fi

    ui_step "SDDM"
    local matugen="${XDG_CONFIG_HOME:-$HOME/.config}/matugen"
    if [[ -d "$repo_root/dots/.config/matugen/templates/sddm" ]]; then
        mkdir -p "$matugen/templates/sddm"
        cp -a "$repo_root/dots/.config/matugen/templates/sddm/." "$matugen/templates/sddm/"
    fi

    # Merge [templates.sddm] into the live matugen config without clobbering
    # whatever the base install wrote there. Idempotent: re-runs find it present
    # and skip.
    local cfg="$matugen/config.toml"
    if [[ -f "$cfg" ]] && ! grep -q '^\[templates\.sddm\]' "$cfg"; then
        local block
        block="$(awk '/^\[templates\.sddm\]/{f=1; print; next} f && /^\[/{f=0} f' "$repo_root/dots/.config/matugen/config.toml" 2>/dev/null || true)"
        if [[ -n "$block" ]]; then
            printf '\n%s\n' "$block" >>"$cfg"
            ui_ok "SDDM matugen" "added [templates.sddm] to $(tilde "$cfg")"
        fi
    fi

    (cd "$src" && bash ./install.sh -y) || return 1
    return 0
}

# Extras: fork-shipped dotfile folders beyond the shell/hypr/sddm, each
# overlaid on ~/.config/<name> during install. A folder may carry a setup
# script — fetch-*.sh or install.sh — that deploys the folder itself and pulls
# in external, unversioned dependencies (mpv's Anime4K shaders, material-osc,
# thumbfast). To ship another folder, add its name here.
EXTRA_DOTFILES=(
    mpv
)

# install_extras_config <repo_root> <verb>
#
# Deploys the fork's extra dotfile folders (EXTRA_DOTFILES) onto ~/.config.
# Offered on `install` only, like the Hyprland overlay; -y declines it and
# --extras is the explicit yes. A folder with a fetch-*/install.sh runs that
# script (it self-locates and deploys itself); otherwise the folder is copied
# over. Safe to re-run — copies are idempotent overlays.
install_extras_config() {
    local repo_root="${1:-}" verb="${2:-}"

    [[ "$OPT_EXTRAS" == false ]] && return 0

    if [[ -z "$OPT_EXTRAS" ]]; then
        # Same rule as hypr/sddm: offered on a fresh install, -y says no, and
        # an unattended update never touches these underneath somebody.
        [[ "$verb" == "install" ]] || return 0
        if [[ "$OPT_ASSUME_YES" == true ]]; then
            ui_note "Left extras alone. Pass --extras to install them."
            return 0
        fi
        ui_confirm "Install the fork's extra configs (${EXTRA_DOTFILES[*]})?" yes || {
            ui_note "Left extras alone."
            return 0
        }
    fi

    ui_step "Extras"
    local name src script deployed=0
    for name in "${EXTRA_DOTFILES[@]}"; do
        src="$repo_root/dots/.config/$name"
        [[ -d "$src" ]] || continue
        script=""
        [[ -f "$src/fetch-extras.sh" ]] && script="fetch-extras.sh"
        [[ -f "$src/install.sh" && -z "$script" ]] && script="install.sh"
        if [[ -n "$script" ]]; then
            ui_verbose "running $name/$script"
            (cd "$src" && bash "./$script") || {
                ui_fail "$name setup failed" "$script exited $?"
                return 1
            }
        else
            copy_tree "$src/" "$HOME/.config/$name/" || return 1
        fi
        deployed=$((deployed + 1))
    done
    if ((deployed == 0)); then
        ui_note "No extras found in the source."
        return 0
    fi
    ui_ok "Extras" "$deployed folder(s) deployed"
    return 0
}

# apply_config <url> <branch> <fork_id> <verb>
apply_config() {
    local url="$1" branch="$2" fork="$3" verb="$4"
    local head="" source_dir="" dirty=""

    if [[ -n "$LOCAL_SRC" ]]; then
        # A local deploy has no remote to speak of, so everything the state
        # files normally carry comes off the checkout instead. .active-local
        # marks the result, which is what makes `update` refuse later rather
        # than silently redeploy a path it only guessed at.
        fork="local"
        url="$LOCAL_SRC"
        branch="$(git -C "$LOCAL_SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        [[ -z "$branch" || "$branch" == "HEAD" ]] && branch="nobranch"
        head="$(git -C "$LOCAL_SRC" rev-parse HEAD 2>/dev/null || true)"
        git -C "$LOCAL_SRC" diff --quiet HEAD 2>/dev/null || dirty="uncommitted changes"
    else
        url="$(normalize_url "$url")"
        [[ -z "$fork" ]] && fork="flow"
        [[ -z "$branch" ]] && branch="$FLOW_BRANCH"
    fi

    ui_frame_open "Resolve"
    if [[ -n "$LOCAL_SRC" ]]; then
        ui_kv "source" "local $LOCAL_KIND"
        ui_kv "path" "$(tilde "$LOCAL_SRC")"
        ui_kv "branch" "$branch"
        [[ -n "$dirty" ]] && ui_kv "state" "$dirty"
    else
        ui_kv "source" "Flow"
        ui_kv "remote" "${url#https://}"
        ui_kv "branch" "$branch"
    fi
    ui_kv "target" "$(tilde "$TARGET_DIR")"
    ui_kv "backup" "$([[ "$OPT_BACKUP" == true ]] && printf '%s' "$(tilde "$BACKUP_BASE_DIR")" || printf 'disabled')"
    ui_frame_close

    if [[ "$OPT_ASSUME_YES" != true ]]; then
        local with="$fork/$branch"
        [[ -n "$LOCAL_SRC" ]] && with="$(tilde "$LOCAL_SRC")"
        ui_confirm "Replace $(tilde "$TARGET_DIR") with $with?" yes || {
            ui_note "Cancelled."
            return 0
        }
    fi

    if [[ "$OPT_DRY_RUN" == true ]]; then
        ui_banner "Flow" "dry-run"
        if [[ -n "$LOCAL_SRC" ]]; then
            ui_kv "source" "local $LOCAL_KIND"
            ui_kv "path" "$(tilde "$LOCAL_SRC")"
            ui_kv "branch" "$branch"
        else
            ui_kv "source" "Flow"
            ui_kv "remote" "${url#https://}"
            ui_kv "branch" "$branch"
        fi
        ui_kv "target" "$(tilde "$TARGET_DIR")"
        ui_kv "backup" "$([[ "$OPT_BACKUP" == true ]] && printf '%s' "$(tilde "$BACKUP_BASE_DIR")" || printf 'disabled')"
        ui_kv "verb" "$verb"
        if [[ "$verb" == "install" ]]; then
            ui_note "Would install system dependencies (quickshell-git on Arch)"
            ui_note "Would offer SDDM greeter installation"
            ui_note "Would offer Hyprland config overlay"
            ui_note "Would offer extras (mpv config)"
        fi
        ui_note "Dry run complete — no changes made"
        return 0
    fi

    if [[ -n "$LOCAL_SRC" ]]; then
        if [[ "$LOCAL_KIND" == "repo" ]]; then
            source_dir="$LOCAL_SRC/dots/.config/quickshell/flow"
            [[ -d "$source_dir" ]] || {
                ui_fail "Not a Flow checkout" "dots/.config/quickshell/flow not found in $(tilde "$LOCAL_SRC")"
                return 1
            }
        else
            source_dir="$LOCAL_SRC"
        fi
        ui_ok "Sourced" "$(tree_stats "$source_dir")"
        ui_verbose "source: $source_dir"
    else
        CLONE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flow-clone-XXXXXX")"
        clone_repo "$url" "$branch" "$CLONE_DIR" || return 1

        # Clone with branch "default" resolves to whatever HEAD points at.
        if [[ "$branch" == "default" ]]; then
            branch="$(git -C "$CLONE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'main')"
        fi
        head="$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null || true)"

        source_dir="$CLONE_DIR/dots/.config/quickshell/flow"
        [[ -d "$source_dir" ]] || {
            ui_fail "Not a Flow checkout" "dots/.config/quickshell/flow not found in cloned repo"
            return 1
        }
        ui_verbose "source: ${source_dir#"$CLONE_DIR"/}"
    fi

    mkdir -p "$QS_DIR"
    STAGE_DIR="$(mktemp -d "$QS_DIR/.ii-stage-XXXXXX")"
    copy_tree "$source_dir" "$STAGE_DIR" || return 1

    ui_step "Staging"
    local carried
    carried="$(carry_protected "$TARGET_DIR" "$STAGE_DIR")"
    printf '%s\n' "$url" >"$STAGE_DIR/.active-remote"
    printf '%s\n' "$branch" >"$STAGE_DIR/.active-branch"
    printf '%s\n' "$fork" >"$STAGE_DIR/.active-fork"
    if [[ -n "$LOCAL_SRC" ]]; then
        printf '%s\n' "$LOCAL_SRC" >"$STAGE_DIR/.active-local"
    else
        # Copied from a source tree that may itself have been deployed locally.
        rm -f "$STAGE_DIR/.active-local"
    fi
    [[ -n "$head" ]] && printf '%s\n' "$head" >"$STAGE_DIR/.active-commit"
    if [[ -d "$STAGE_DIR/scripts" ]]; then
        find "$STAGE_DIR/scripts" -type f \
            \( -name '*.sh' -o -name '*.py' -o -name '*.js' \) \
            -exec chmod +x {} + 2>/dev/null || true
    fi
    chmod 0755 "$STAGE_DIR"
    ui_ok "Staged" "$carried protected file$([[ "$carried" == "1" ]] || printf 's') carried"

    # Mirror before the swap, never after. The settings panel runs the mirrored
    # copy, so a fault in swap_in used to be self-perpetuating: the swap failed,
    # the mirror was never refreshed, and the panel kept running the same broken
    # script with no way to heal itself. A clone that reached this point is
    # sound, so its manager is always safe to install.
    # The hypr dots sit beside the ii config dir rather than inside it, so the
    # source tree has to survive until they have been read out of it.
    local repo_root=""
    if [[ -n "$LOCAL_SRC" ]]; then
        [[ "$LOCAL_KIND" == "repo" ]] && repo_root="$LOCAL_SRC"
        mirror_scripts "$LOCAL_SRC"
    else
        repo_root="$CLONE_DIR"
        mirror_scripts "$CLONE_DIR"
    fi

    # Stop before the swap, not after. swap_in moves the live tree aside and
    # deletes it, and a running Quickshell reacts to that by hot-reloading onto
    # whatever is at the path by then. Its config singleton reloads mid-swap and
    # can persist QML defaults over the user's config.json — the reset people
    # end up fixing by deleting the file. Nothing touches the tree until the
    # shell is down.
    stop_quickshell

    swap_in "$STAGE_DIR" "$fork" "$branch" || return 1

    # After the swap: a swap that failed leaves ~/.config/hypr untouched too,
    # so a half-applied pair of configs is not a state you can end up in.
    install_hypr_config "$repo_root"
    install_sddm_config "$repo_root" "$verb"
    install_extras_config "$repo_root" "$verb"

    if [[ -z "$LOCAL_SRC" && -n "$CLONE_DIR" ]]; then
        rm -rf "$CLONE_DIR"
        CLONE_DIR=""
    fi

    handle_base_config "$verb"

    # Only launch the welcome window at the end of default installation.
    # Prevent it from opening during update, fork switch, branch hop, or apply.
    local first_run_file="${XDG_STATE_HOME:-$HOME/.local/state}/flow/user/first_run.txt"
    if [[ "$verb" == "install" ]]; then
        rm -f "$first_run_file"
    else
        mkdir -p "$(dirname "$first_run_file")"
        if [[ ! -f "$first_run_file" ]]; then
            echo "This file is just here to confirm you've been greeted :>" > "$first_run_file"
        fi
    fi

    start_quickshell

    if [[ "$verb" == "install" ]]; then
        local bin=""
        if have qs; then
            bin="qs"
        elif have quickshell; then
            bin="quickshell"
        fi
        if [[ -n "$bin" ]]; then
            nohup "$bin" -p "$TARGET_DIR/welcome.qml" >/dev/null 2>&1 &
        fi
    fi

    local summary="$fork/$branch${head:+ @ ${head:0:8}}"
    [[ -n "$LOCAL_SRC" ]] && summary="local $G_ARROW $(tilde "$LOCAL_SRC")"
    ui_result ok "$verb complete $G_DOT $(ui_elapsed)" \
        "$summary" \
        "$(tilde "$TARGET_DIR")"
    return 0
}

# The real user config lives outside the Quickshell dir, so replacing flow never
# touches it. Reset it only when the schema is likely to have changed.
handle_base_config() {
    local verb="$1"
    [[ -f "$FLOW_CONFIG_FILE" ]] || return 0

    local keep="$OPT_KEEP_CONFIG"
    if [[ -z "$keep" ]]; then
        # Source switches change the option schema; updates and branch hops do not.
        [[ "$verb" == "switch" ]] && keep=false || keep=true
    fi
    if [[ "$keep" == true ]]; then
        ui_note "Kept $(tilde "$FLOW_CONFIG_FILE")."
        return 0
    fi

    if [[ "$OPT_ASSUME_YES" != true ]]; then
        ui_confirm "Reset $(tilde "$FLOW_CONFIG_FILE")? A backup is kept." || {
            ui_note "Kept the existing config."
            return 0
        }
    fi
    local dest
    dest="${FLOW_CONFIG_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$FLOW_CONFIG_FILE" "$dest"
    ui_ok "Reset" "config.json $G_ARROW $(basename "$dest")"
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# Commands
#══════════════════════════════════════════════════════════════════════════════

cmd_apply() {
    require_base
    load_local_src
    local origin url branch fork
    origin="$(local_origin)"
    url="${origin%%|*}"
    local rest="${origin#*|}"
    branch="${rest%%|*}"
    fork="${rest##*|}"

    ui_banner "Flow" "apply"
    apply_config "$url" "$branch" "$fork" "apply"
}

cmd_install() {
    load_local_src
    if [[ -n "$LOCAL_SRC" && "$LOCAL_KIND" != "repo" ]]; then
        ui_fail "Not a fork checkout" "$(tilde "$LOCAL_SRC") is a flow config dir"
        ui_note "install runs ./setup from the repository root. Point --local at that."
        exit 1
    fi

    ui_banner "Flow" "install"
    ui_note "Installs Flow dependencies and applies Flow's Quickshell config."
    printf '\n'

    local origin url branch fork
    origin="$(local_origin)"
    url="${origin%%|*}"
    local rest="${origin#*|}"
    branch="${rest%%|*}"
    fork="${rest##*|}"

    ui_frame_open "Flow install"
    if [[ -n "$LOCAL_SRC" ]]; then
        ui_kv "source" "$(tilde "$LOCAL_SRC")"
    else
        ui_kv "source" "${url#https://}"
        ui_kv "branch" "$branch"
    fi
    ui_kv "runs" "flow install"
    ui_frame_close

    if [[ "$OPT_ASSUME_YES" != true ]]; then
        ui_confirm "Install Flow now? This installs system packages." || {
            ui_note "Cancelled."
            return 0
        }
    fi

    # Flow is self-contained; no base dotfiles installer to run.
    # Just ensure Quickshell is available (on Arch, ensure quickshell-git).
    ensure_quickshell_git

    apply_config "$url" "$branch" "$fork" "install"
}

cmd_update() {
    require_base
    load_local_src

    # The active config came off somebody's working tree. Re-cloning the fork it
    # happens to sit in would quietly undo their changes, and there is no honest
    # way to tell whether the path is still the one they meant, so say so.
    local prev
    prev="$(read_local_state)"
    if [[ -n "$prev" && -z "$LOCAL_SRC" ]]; then
        ui_fail "Deployed from a local path" "$(tilde "$prev")"
        ui_note "Re-run with the path:  $SCRIPT_SELF update --local $(tilde "$prev")"
        ui_note "Or run: $SCRIPT_SELF update  # pulls from Flow upstream"
        exit 1
    fi

    local state url branch fork
    state="$(read_state)"
    url="${state%%|*}"
    local rest="${state#*|}"
    branch="${rest%%|*}"
    fork="${rest##*|}"

    if [[ -z "$url" && -z "$LOCAL_SRC" ]]; then
        ui_fail "Nothing to update" "no .active-remote in $(tilde "$TARGET_DIR")"
        ui_note "Run: $SCRIPT_SELF update  # pulls from Flow upstream"
        exit 1
    fi

    ui_banner "Flow" "update"
    apply_config "$url" "$branch" "$fork" "update"
}

cmd_switch() {
    require_base
    load_local_src
    if [[ -z "$LOCAL_SRC" ]]; then
        ui_fail "Nothing to switch" "pass --local <path> or use 'flow update' to pull from upstream"
        exit 1
    fi

    local url="" branch="" fork=""
    if [[ -n "$LOCAL_SRC" ]]; then
        : # apply_config reads the checkout itself
    else
        local state rest
        state="$(read_state)"
        url="${state%%|*}"
        rest="${state#*|}"
        branch="${rest%%|*}"
        fork="${rest##*|}"
        if [[ -z "$url" ]] || [[ -n "$(read_local_state)" ]]; then
            ui_fail "No active source" "no remote recorded in $(tilde "$TARGET_DIR")"
            ui_note "Use 'flow update' to pull from upstream"
            exit 1
        fi
    fi

    ui_banner "Flow" "switch"
    apply_config "$url" "$branch" "$fork" "switch"
}

cmd_doctor() {
    ui_banner "Flow" "doctor"
    local state url branch fork
    state="$(read_state)"
    url="${state%%|*}"
    local rest="${state#*|}"
    branch="${rest%%|*}"
    fork="${rest##*|}"

    local active_local
    active_local="$(read_local_state)"

    ui_frame_open "Active config"
    ui_kv "source" "${fork:-unknown}"
    ui_kv "branch" "${branch:-unknown}"
    if [[ -n "$active_local" ]]; then
        ui_kv "local" "$(tilde "$active_local")"
    else
        ui_kv "remote" "${url#https://}"
    fi
    ui_kv "target" "$([[ -d "$TARGET_DIR" ]] && tilde "$TARGET_DIR" || printf 'missing')"
    ui_frame_close

    ui_frame_open "Paths"
    ui_kv "base" "$([[ -d "$FLOW_CONFIG_DIR" ]] && tilde "$FLOW_CONFIG_DIR" || printf 'missing')"
    ui_kv "mirror" "$([[ -d "$MIRROR_DIR" ]] && tilde "$MIRROR_DIR" || printf 'missing')"
    ui_kv "backups" "$({ find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name 'ii_*' 2>/dev/null || true; } | wc -l) kept"
    ui_kv "log" "$(tilde "$LOG_FILE")"
    ui_frame_close

    ui_frame_open "Tooling"
    local t
    for t in git rsync qs quickshell hyprctl fc-list; do
        ui_kv "$t" "$(command -v "$t" 2>/dev/null || printf 'not found')"
    done
    ui_kv "cli" "$([[ -L "$BIN_DIR/$CLI_NAME" ]] && readlink "$BIN_DIR/$CLI_NAME" || printf 'not linked')"
    ui_frame_close

    ui_frame_open "Renderer"
    ui_kv "glyphs" "$UI_GLYPHS"
    ui_kv "colour" "$UI_COLOR"
    ui_kv "tty" "$UI_TTY"
    ui_kv "width" "$UI_WIDTH"
    ui_frame_close
}

cmd_hypr() {
    local lib="$1"
    shift
    local path=""
    local d
    for d in "$SCRIPT_DIR" "$MIRROR_DIR"; do
        [[ -f "$d/sdata/cli/lib/$lib.sh" ]] && {
            path="$d/sdata/cli/lib/$lib.sh"
            break
        }
    done
    [[ -n "$path" ]] || ui_die "Missing helper" "sdata/cli/lib/$lib.sh not found"
    exec bash "$path" "$@"
}

# cmd_project <subcmd> [args...] — dispatches "flow project <subcmd>".
# Mirrors cmd_hypr's resolve-then-ui_die convention: check SCRIPT_DIR, fall
# back to MIRROR_DIR, die with the normal error UI (not a raw shell error)
# if neither has the helper.
cmd_project() {
    local subcmd="${1:-detect}"
    (($# > 0)) && shift

    case "$subcmd" in
        detect)
            local path="" d
            for d in "$SCRIPT_DIR" "$MIRROR_DIR"; do
                [[ -f "$d/sdata/subcmd-project/detect.sh" ]] && {
                    path="$d/sdata/subcmd-project/detect.sh"
                    break
                }
            done
            [[ -n "$path" ]] || ui_die "Missing helper" "sdata/subcmd-project/detect.sh not found"
            local detect_args=("$@")
            [[ "$OPT_JSON" == true ]] && detect_args+=("--json")
            exec bash "$path" "${detect_args[@]}"
            ;;
        profile)
            local path="" d
            for d in "$SCRIPT_DIR" "$MIRROR_DIR"; do
                [[ -f "$d/sdata/subcmd-project/profile.sh" ]] && {
                    path="$d/sdata/subcmd-project/profile.sh"
                    break
                }
            done
            [[ -n "$path" ]] || ui_die "Missing helper" "sdata/subcmd-project/profile.sh not found"
            local profile_args=("$@" "${PASSTHRU_ARGS[@]+"${PASSTHRU_ARGS[@]}"}")
            [[ "$OPT_JSON" == true ]] && profile_args+=("--json")
            [[ "$OPT_VERBOSE" == true ]] && profile_args+=("-v")
            exec bash "$path" "${profile_args[@]}"
            ;;
        env)
            local path="" d
            for d in "$SCRIPT_DIR" "$MIRROR_DIR"; do
                [[ -f "$d/sdata/subcmd-project/env.sh" ]] && {
                    path="$d/sdata/subcmd-project/env.sh"
                    break
                }
            done
            [[ -n "$path" ]] || ui_die "Missing helper" "sdata/subcmd-project/env.sh not found"
            local env_args=("$@" "${PASSTHRU_ARGS[@]+"${PASSTHRU_ARGS[@]}"}")
            [[ "$OPT_JSON" == true ]] && env_args+=("--json")
            [[ "$OPT_VERBOSE" == true ]] && env_args+=("-v")
            exec bash "$path" "${env_args[@]}"
            ;;
        *)
            arg_error "Unknown project subcommand \"$subcmd\" (expected: detect, profile, env)"
            ;;
    esac
}

#══════════════════════════════════════════════════════════════════════════════
# Help
#══════════════════════════════════════════════════════════════════════════════

show_help() {
    local me="$SCRIPT_SELF"
    [[ "$INVOKED_AS" == "$CLI_NAME" ]] && me="$CLI_NAME"

    ui_banner "Flow" "v$SETUP_VERSION"

    ui_rule "Usage"
    printf '  %s [command] [options]\n\n' "$me"

    ui_rule "Commands"
    printf '  %s%-16s%s %s\n' "$C_OK" "apply" "$C_RST" "Apply the Quickshell config (default)"
    printf '  %s%-16s%s %s\n' "$C_OK" "install" "$C_RST" "Install Flow dependencies and apply config"
    printf '  %s%-16s%s %s\n' "$C_OK" "update" "$C_RST" "Refresh Flow config from GitHub"
    printf '  %s%-16s%s %s\n' "$C_OK" "restart" "$C_RST" "Restart Quickshell (alias: run)"
    printf '  %s%-16s%s %s\n' "$C_OK" "doctor" "$C_RST" "Report resolved paths, state and tooling"
    printf '  %s%-16s%s %s\n' "$C_OK" "hyprset" "$C_RST" "Write a Hyprland key/animation"
    printf '  %s%-16s%s %s\n' "$C_OK" "hyprmerge" "$C_RST" "Merge a Hyprland config into the local one"
    printf '  %s%-16s%s %s\n' "$C_OK" "project detect" "$C_RST" "Show detected languages/frameworks/tooling (read-only)"
    printf '  %s%-16s%s %s\n' "$C_OK" "project profile" "$C_RST" "Manage project profiles (list, create, use, set-default, status, delete)"
    printf '  %s%-16s%s %s\n' "$C_OK" "project env" "$C_RST" "Environment resolution & selection (list, show, set, clear)"
    printf '  %s%-16s%s Remove the %s symlink\n' "$C_OK" "remove-cli" "$C_RST" "$CLI_NAME"
    printf '  %s%-16s%s %s\n' "$C_OK" "help, version" "$C_RST" "This message / the version"
    printf '  %s%-16s%s %s\n' "$C_OK" "demo" "$C_RST" "Render every UI primitive and exit"
    printf '\n'

    ui_rule "Options"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-l, --local <path>" "$C_RST" "Deploy from a local checkout, not GitHub"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-y, --yes" "$C_RST" "Skip every confirmation"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-v, --verbose" "$C_RST" "Echo command output as it runs"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-q, --quiet" "$C_RST" "Only errors on stdout"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --backup" "$C_RST" "Keep the replaced config (default)"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-backup" "$C_RST" "Discard the previous config instead of keeping it"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --keep-config" "$C_RST" "Never reset ~/.config/flow/config.json"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --reset-config" "$C_RST" "Always reset it (a backup is kept)"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-restart" "$C_RST" "Leave Quickshell alone when finished"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --hypr" "$C_RST" "Install the fork's ~/.config/hypr files"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-hypr" "$C_RST" "Never install them, never ask"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --sddm" "$C_RST" "Install the Flow SDDM greeter + its matugen template"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-sddm" "$C_RST" "Never install them, never ask"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --extras" "$C_RST" "Install the fork's extra configs (mpv + setup scripts)"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-extras" "$C_RST" "Never install them, never ask"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --rebuild-quickshell" "$C_RST" "Rebuild Quickshell from source first"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --log-file <path>" "$C_RST" "Write the run log elsewhere"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-log" "$C_RST" "Do not write a run log"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --ascii" "$C_RST" "ASCII glyphs only"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-color" "$C_RST" "Strip ANSI colour"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --json" "$C_RST" "Emit JSON (used by: project detect, project profile)"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --demo" "$C_RST" "Render every UI primitive and exit"
    printf '\n'

    ui_rule "Notes"
    printf '  %s--local takes a fork checkout or a flow config dir; either way nothing%s\n' "$C_SUB" "$C_RST"
    printf '  %sis cloned. update will not guess the path back: it refuses and prints%s\n' "$C_SUB" "$C_RST"
    printf '  %sthe --local line to re-run.%s\n' "$C_SUB" "$C_RST"
    printf '  %sOn Arch, install swaps the base installer'"'"'s pinned quickshell for the%s\n' "$C_SUB" "$C_RST"
    printf '  %sAUR quickshell-git this fork targets, before any config lands.%s\n' "$C_SUB" "$C_RST"
    printf '  %sGiven neither --keep-config nor --reset-config, config.json is kept on%s\n' "$C_SUB" "$C_RST"
    printf '  %supdates and branch hops and reset on source switches, where the schema%s\n' "$C_SUB" "$C_RST"
    printf '  %schanges.%s\n' "$C_SUB" "$C_RST"
    printf '  %sapply, install, update and switch offer to overlay the fork'"'"'s Hyprland%s\n' "$C_SUB" "$C_RST"
    printf '  %sconfig on ~/.config/hypr, leaving custom/ and anything the repo does%s\n' "$C_SUB" "$C_RST"
    printf '  %snot ship alone. -y answers that question no, not yes; --hypr is the%s\n' "$C_SUB" "$C_RST"
    printf '  %sexplicit yes and --no-hypr the permanent no.%s\n' "$C_SUB" "$C_RST"
    printf '  %sinstall also offers the fork'"'"'s SDDM greeter (Flow theme + its%s\n' "$C_SUB" "$C_RST"
    printf '  %smatugen template + the sddm service). Same -y/no rule; --sddm is%s\n' "$C_SUB" "$C_RST"
    printf '  %sthe explicit yes. SDDM needs root, so its sudo prompts still appear.%s\n' "$C_SUB" "$C_RST"
    printf '  %sinstall also offers the fork'"'"'s extra configs (currently mpv, with its%s\n' "$C_SUB" "$C_RST"
    printf '  %sfetch-extras.sh). Same -y/no rule; --extras is the explicit yes.%s\n' "$C_SUB" "$C_RST"
    printf '  %sOptions take --flag=value as well as --flag value, and everything after%s\n' "$C_SUB" "$C_RST"
    printf '  %sa bare -- is passed through to hyprset/hyprmerge.%s\n' "$C_SUB" "$C_RST"
    printf '  %sAliases: --no-confirm/--noconfirm (-y), --preserve-config (--keep-config),%s\n' "$C_SUB" "$C_RST"
    printf '  %s--force-install (--skip-base-check), --no-colour (--no-color),%s\n' "$C_SUB" "$C_RST"
    printf '  %s--hypr-config (--hypr), --no-hypr-config (--no-hypr).%s\n' "$C_SUB" "$C_RST"
    printf '\n'

    ui_rule "Examples"
    printf '  %s%s install%s                  %sfirst-time setup on a bare machine%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '  %s%s update%s                   %spull the latest from Flow upstream%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '  %s%s apply --local .%s          %sdeploy the checkout you stand in%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '\n'
    printf '%sLog: %s%s\n' "$C_SUB" "$(tilde "$DEFAULT_LOG_FILE")" "$C_RST"
    printf '%sDocs: %shttps://github.com/SrwR16/ArchTide/wiki%s\n\n' "$C_SUB" "$C_UL" "$C_RST"
}

#══════════════════════════════════════════════════════════════════════════════
# Argument parsing
#══════════════════════════════════════════════════════════════════════════════

ORIGINAL_ARGS=("$@")

arg_error() {
    ERR_REPORTED=true
    printf '%s%s %s%s\n' "$C_ERR" "$G_ERR" "$1" "$C_RST" >&2
    printf '%s  Run "%s help" for usage.%s\n' "$C_SUB" "$SCRIPT_SELF" "$C_RST" >&2
    exit 2
}

need_value() {
    [[ -n "${2:-}" ]] || arg_error "$1 requires a value"
}

parse_args() {
    local -a positional=()
    while (($# > 0)); do
        local arg="$1" val=""
        # --opt=value
        if [[ "$arg" == --*=* ]]; then
            val="${arg#*=}"
            arg="${arg%%=*}"
            set -- "$arg" "$val" "${@:2}"
        fi
        case "$1" in
            -l | --local)
                need_value "$1" "${2:-}"
                OPT_LOCAL="$2"
                shift 2
                ;;
            --log-file)
                need_value "$1" "${2:-}"
                LOG_FILE="$2"
                shift 2
                ;;
            -v | --verbose)
                OPT_VERBOSE=true
                shift
                ;;
            -q | --quiet)
                OPT_QUIET=true
                shift
                ;;
            -y | --yes | --no-confirm | --noconfirm)
                OPT_ASSUME_YES=true
                shift
                ;;
            --dry-run)
                OPT_DRY_RUN=true
                shift
                ;;
            --no-backup)
                OPT_BACKUP=false
                shift
                ;;
            --backup)
                OPT_BACKUP=true
                shift
                ;;
            --keep-config | --preserve-config)
                OPT_KEEP_CONFIG=true
                shift
                ;;
            --reset-config)
                OPT_KEEP_CONFIG=false
                shift
                ;;
            --rebuild-quickshell)
                OPT_REBUILD_QS=true
                shift
                ;;
            --no-restart)
                OPT_RESTART=false
                shift
                ;;
            --hypr | --hypr-config)
                OPT_HYPR=true
                shift
                ;;
            --no-hypr | --no-hypr-config)
                OPT_HYPR=false
                shift
                ;;
            --sddm | --sddm-config)
                OPT_SDDM=true
                shift
                ;;
            --no-sddm | --no-sddm-config)
                OPT_SDDM=false
                shift
                ;;
            --extras)
                OPT_EXTRAS=true
                shift
                ;;
            --no-extras)
                OPT_EXTRAS=false
                shift
                ;;
            --no-log)
                OPT_LOG=false
                shift
                ;;
            --ascii)
                OPT_ASCII=true
                shift
                ;;
            --no-color | --no-colour)
                OPT_NO_COLOR=true
                shift
                ;;
            --json)
                OPT_JSON=true
                shift
                ;;
            --demo)
                COMMAND="demo"
                shift
                ;;
            -h | --help)
                COMMAND="help"
                shift
                ;;
            -V | --version)
                COMMAND="version"
                shift
                ;;
            # Legacy flag spellings, kept so old callers and muscle memory still work.
            --update)
                COMMAND="${COMMAND:-update}"
                shift
                ;;
            --switch)
                COMMAND="${COMMAND:-switch}"
                shift
                ;;
            --install)
                COMMAND="${COMMAND:-install}"
                shift
                ;;
            --apply)
                COMMAND="${COMMAND:-apply}"
                shift
                ;;
            --)
                shift
                PASSTHRU_ARGS+=("$@")
                break
                ;;
            -*)
                arg_error "Unknown option \"$1\""
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    # First positional is the command unless a legacy flag already chose one.
    if ((${#positional[@]} > 0)); then
        local first="${positional[0]}"
        case "$first" in
            apply | install | update | switch | restart | run | doctor | remove-cli | hyprset | hyprmerge | help | version | demo | project)
                COMMAND="$first"
                positional=("${positional[@]:1}")
                ;;
        esac
    fi

    # Command-specific positionals.
    case "$COMMAND" in
        hyprset | hyprmerge)
            PASSTHRU_ARGS=("${positional[@]}" "${PASSTHRU_ARGS[@]+"${PASSTHRU_ARGS[@]}"}")
            ;;
        project)
            # positional is local to this function and goes out of scope the
            # moment parse_args returns, so the subcommand ("detect", etc.)
            # must be captured into a global here — same pattern as
            # PASSTHRU_ARGS above. Leaving this empty (as it previously was)
            # meant main() could never see what the user actually typed and
            # silently always ran "detect".
            PROJECT_ARGS=("${positional[@]}")
            ;;
        *)
            if ((${#positional[@]} > 0)); then
                arg_error "Unexpected argument \"${positional[0]}\""
            fi
            ;;
    esac
}

#══════════════════════════════════════════════════════════════════════════════
# Main
#══════════════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"

    # Bare `flow` is a CLI, not an installer: show the surface instead of acting.
    if [[ -z "$COMMAND" && "$INVOKED_AS" == "$CLI_NAME" ]]; then
        COMMAND="help"
    fi
    [[ -z "$COMMAND" ]] && COMMAND="apply"

    if [[ -n "$OPT_LOCAL" ]]; then
        case "$COMMAND" in
            apply | install | update | switch) ;;
            *) arg_error "--local applies to apply, install, update and switch" ;;
        esac
    fi

    ui_init
    [[ "$UI_TTY" == true && "$COMMAND" != "help" ]] && printf '\033[?25l'

    case "$COMMAND" in
        help)
            show_help
            exit 0
            ;;
        version)
            printf '%s %s\n' "$SCRIPT_SELF" "$SETUP_VERSION"
            exit 0
            ;;
        demo)
            ui_demo
            exit 0
            ;;
        hyprset) cmd_hypr hyprset "${PASSTHRU_ARGS[@]+"${PASSTHRU_ARGS[@]}"}" ;;
        hyprmerge) cmd_hypr hyprmerge "${PASSTHRU_ARGS[@]+"${PASSTHRU_ARGS[@]}"}" ;;
        project) cmd_project "${PROJECT_ARGS[@]+"${PROJECT_ARGS[@]}"}" ;;
    esac

    open_log

    # Only the mutating commands migrate legacy paths; listing and doctor must
    # never move anything just because you asked them a question.
    case "$COMMAND" in
        apply | install | update | switch | restart | run | remove-cli) ;;
    esac

    case "$COMMAND" in
        restart | run)
            ui_banner "Flow" "restart"
            OPT_RESTART=true
            restart_quickshell
            ;;
        remove-cli)
            ui_banner "Flow" "remove-cli"
            remove_cli
            ;;
        doctor) cmd_doctor ;;
        apply | install | update | switch)
            if [[ "$OPT_REBUILD_QS" == true ]]; then
                build_quickshell || exit 1
            elif [[ "$COMMAND" != "install" ]] && qt_mismatch; then
                if ui_confirm "Rebuild Quickshell from source to match your Qt?"; then
                    build_quickshell || exit 1
                else
                    ui_note "Skipped. Crashes may persist until the ABI matches."
                fi
            fi
            case "$COMMAND" in
                apply) cmd_apply ;;
                install) cmd_install ;;
                update) cmd_update ;;
                switch) cmd_switch ;;
            esac
            ;;
        *)
            arg_error "Unknown command \"$COMMAND\""
            ;;
    esac
}

main "$@"
