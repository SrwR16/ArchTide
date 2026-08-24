#!/bin/bash
# flow engine — build, install, manage the Go engine

cmd_engine() {
    local action="${1:-build}"; shift || true
    local src="$BASE_DIR/engine"

    case "$action" in
        build)
            if ! command -v go &>/dev/null; then
                echo "✗ go not on PATH"; exit 1
            fi
            echo "▸ Building Flow engine"
            GOAMD64=v4 go build -ldflags="-s -w" -trimpath \
                -o "$src/.flow-build-iris" ./cmd/iris && {
                mkdir -p "$HOME/.local/bin"
                rm -f "$HOME/.local/bin/iris"
                mv "$src/.flow-build-iris" "$HOME/.local/bin/iris"
                chmod 0755 "$HOME/.local/bin/iris"
                echo "✓ installed → ~/.local/bin/iris"
            }
            ;;
        test)
            cd "$src" && go test ./... 2>&1 | grep -E "FAIL|^ok" | head -15
            ;;
        clean)
            rm -f "$src/iris" "$src/.flow-build-iris"
            echo "cleaned"
            ;;
        *)
            echo "Usage: flow engine [build|test|clean]"
            ;;
    esac
}
