#!/bin/bash
# Flow Engine build + install

ENGINE_BUILD() {
    local src=""
    for d in "$SCRIPT_DIR" "$BASE_DIR"; do
        [[ -n "$d" && -f "$d/engine/go.mod" ]] && { src="$d/engine"; break; }
    done
    if [[ -z "$src" ]]; then
        echo "✗ engine/ sources not found"
        return 1
    fi
    if ! command -v go &>/dev/null; then
        echo "✗ go not on PATH — install go, then rerun"
        return 1
    fi
    echo "▸ Building Flow engine (Go)"
    local tmp="$src/.flow-build-iris"
    if ! (cd "$src" && GOAMD64=v4 go build -ldflags="-s -w" -trimpath -o "$tmp" ./cmd/iris); then
        echo "✗ Flow engine build failed"
        return 1
    fi
    mkdir -p "$HOME/.local/bin"
    rm -f "$HOME/.local/bin/iris"
    mv -f "$tmp" "$HOME/.local/bin/iris"
    chmod 0755 "$HOME/.local/bin/iris"
    echo "✓ Flow engine → ~/.local/bin/iris"
}

ENGINE_DEPS() {
    local missing=()
    for t in go git; do
        command -v "$t" &>/dev/null || missing+=("$t")
    done
    if ((${#missing[@]} > 0)); then
        echo "missing: ${missing[*]}"
        return 1
    fi
}
