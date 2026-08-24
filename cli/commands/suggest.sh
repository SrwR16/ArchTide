#!/bin/bash
# flow suggest — query the suggestion engine (CLI debug/introspection)

SUGGEST_SCRIPT="$BASE_DIR/sdata/cli/lib/suggest.sh"

cmd_suggest() {
    if [[ -f "$BASE_DIR/sdata/cli/lib/suggest.sh" ]]; then
        bash "$BASE_DIR/sdata/cli/lib/suggest.sh" "$@"
    elif [[ -f "$HOME/.local/share/flow/sdata/cli/lib/suggest.sh" ]]; then
        bash "$HOME/.local/share/flow/sdata/cli/lib/suggest.sh" "$@"
    else
        echo "✗ suggest.sh not found"
        exit 1
    fi
}
