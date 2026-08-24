#!/bin/bash
# Flow conflict handler — interactive resolution when deploying over existing files.

flow_conflict_resolve() {
    local src="$1" dest="$2" verb="${3:-install}"
    if [[ ! -e "$dest" && ! -L "$dest" ]]; then return 0; fi
    cmp -s "$src" "$dest" && return 0

    echo "  Conflict: $(tilde "$dest")"
    local choice
    if [[ "$OPT_ASSUME_YES" == true ]]; then choice="overwrite"
    else
        read -rp "  [o]verwrite / [b]ackup+overwrite / [k]eep existing / [s]kip: " choice
    fi
    case "$choice" in
        o|overwrite)
            mkdir -p "$(dirname "$dest")"
            cp -a "$src" "$dest" ;;
        b|backup)
            mkdir -p "$(dirname "$dest")"
            local bak="${dest}.$(date +%Y%m%d%H%M%S).bak"
            mv "$dest" "$bak" && cp -a "$src" "$dest"
            echo "    backed up → $bak" ;;
        k|keep) ;;
        s|skip) ;;
        *) ;;
    esac
}
