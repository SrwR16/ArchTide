# Flow bootstrap — interactive conflict handler.
#
# Sourced by setup-flow.sh (which supplies ui_*, OPT_ASSUME_YES, OPT_DRY_RUN,
# BACKUP_BASE_DIR). Resolves "the file I want to write already exists and
# differs" with a short menu and a safe default, so a non-interactive or --yes
# run never hangs and never destroys anything by surprise.
#
# API:
#   conflict_resolve <dest> <newfile> <label> [default]
#     dest     — the file that exists and would be replaced
#     newfile  — a temp file holding the content that would be written
#     label    — short human name shown in the menu (e.g. "~/.zshrc")
#     default  — keep|overwrite|remove|skip (default: keep)
#
# On return the global CONFLICT_ACTION is one of:
#   keep      — leave dest untouched
#   overwrite — replace dest (a timestamped backup was kept first)
#   remove    — delete dest, then write the new file
#   skip      — do nothing, and don't ask about this file again
# CONFLICT_BACKUP holds the backup path after overwrite/remove, empty otherwise.
#
# Rules:
#   --yes        -> the default, silently, no backup prompt
#   --dry-run    -> prints what the choice would do, changes nothing
#   non-tty stdin -> the default, no hang (caller should prefer --yes)
#   broken symlink as dest -> default becomes overwrite (keeping it is useless)

declare -g CONFLICT_ACTION=""
declare -g CONFLICT_BACKUP=""

_conflict_backup() {
    local dest="$1"
    local stamp dir
    stamp="$(date +%Y%m%d_%H%M%S)"
    dir="$BACKUP_BASE_DIR/conflict_$stamp"
    mkdir -p "$dir" 2>/dev/null || {
        ui_warn "Could not create backup dir $(tilde "$dir") — overwriting without a backup"
        return 0
    }
    if [[ -L "$dest" ]]; then
        # Preserve the symlink itself plus whatever it pointed at (if anything).
        cp -aP "$dest" "$dir/$(basename "$dest")" 2>/dev/null
    else
        cp -a "$dest" "$dir/$(basename "$dest")" 2>/dev/null
    fi
    printf '%s/%s' "$dir" "$(basename "$dest")"
}

conflict_resolve() {
    local dest="$1" newfile="$2" label="$3" default="${4:-keep}"
    CONFLICT_ACTION=""
    CONFLICT_BACKUP=""

    # A broken symlink is not something a user wants to "keep".
    [[ -L "$dest" && ! -e "$dest" ]] && default="overwrite"

    if [[ "$OPT_DRY_RUN" == true ]]; then
        ui_note "Conflict at $label: would apply default \"$default\" (dry run — no change)"
        CONFLICT_ACTION="$default"
        return 0
    fi

    if [[ "$OPT_ASSUME_YES" == true ]]; then
        CONFLICT_ACTION="$default"
        [[ "$default" == "overwrite" || "$default" == "remove" ]] &&
            CONFLICT_BACKUP="$(_conflict_backup "$dest")"
        ui_verbose "conflict $label -> $default (--yes)"
        return 0
    fi

    if [[ ! -t 0 ]]; then
        ui_verbose "conflict $label -> $default (non-interactive stdin)"
        CONFLICT_ACTION="$default"
        return 0
    fi

    local hint
    case "$default" in
        overwrite) hint='[o]' ;;
        remove) hint='[r]' ;;
        skip) hint='[s]' ;;
        *) hint='[k]' ;;
    esac

    while true; do
        ui_clear_line
        printf '\n  %s%s%s %s\n' "$C_WARN" "$G_WARN" "$C_RST" \
            "$label already exists and differs from the Flow version."
        printf '    %s[k]%s Keep      leave the existing file untouched%s\n' "$C_B" "$C_RST" "$C_RST"
        printf '    %s[o]%s Overwrite replace it (a backup is kept)%s\n' "$C_B" "$C_RST" "$C_RST"
        printf '    %s[r]%s Remove    delete it and write the new one%s\n' "$C_B" "$C_RST" "$C_RST"
        printf '    %s[d]%s Diff      show what differs, then re-choose%s\n' "$C_B" "$C_RST" "$C_RST"
        printf '    %s[s]%s Skip      leave it and stop asking about this one%s\n' "$C_B" "$C_RST" "$C_RST"
        printf '  %s%-*s%s %s %s%s%s ' \
            "$C_WARN" "$G_W" "$G_WARN" "$C_RST" \
            "Choose (default $hint):" "$C_SUB" "(k/o/r/d/s)" "$C_RST"
        local reply
        read -r reply || reply=""
        printf '\n'
        [[ -z "$reply" ]] && reply="$default"
        case "${reply,,}" in
            k | keep)
                CONFLICT_ACTION="keep"
                return 0
                ;;
            o | overwrite)
                CONFLICT_BACKUP="$(_conflict_backup "$dest")"
                CONFLICT_ACTION="overwrite"
                return 0
                ;;
            r | remove)
                CONFLICT_BACKUP="$(_conflict_backup "$dest")"
                CONFLICT_ACTION="remove"
                return 0
                ;;
            d | diff)
                if have diff; then
                    diff -u "$dest" "$newfile" 2>/dev/null | sed 's/^/    /' || true
                else
                    ui_note "diff is not installed — assume they differ."
                fi
                ;;
            s | skip)
                CONFLICT_ACTION="skip"
                return 0
                ;;
            *) ui_note "Choose k, o, r, d or s." ;;
        esac
    done
}

# Apply the decision recorded in CONFLICT_ACTION.
# conflict_apply <dest> <newfile> — returns 0 if the new file ended up in place.
conflict_apply() {
    local dest="$1" newfile="$2"
    case "$CONFLICT_ACTION" in
        keep | skip)
            ui_verbose "kept $dest"
            return 0
            ;;
        remove)
            rm -f "$dest"
            mkdir -p "$(dirname "$dest")"
            cp -f "$newfile" "$dest"
            ui_note "Removed $dest and wrote the new file."
            return 0
            ;;
        overwrite)
            mkdir -p "$(dirname "$dest")"
            cp -f "$newfile" "$dest"
            ui_note "Overwrote $dest (backup: $(tilde "$CONFLICT_BACKUP"))."
            return 0
            ;;
    esac
    return 1
}