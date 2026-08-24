#!/bin/bash
# Flow trust registry — per-project trust management.

TRUST_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/flow/trust.json"

_trust_hash() { printf '%s' "$1" | sha256sum | cut -c1-16; }
_trust_ensure() {
    mkdir -p "$(dirname "$TRUST_FILE")" 2>/dev/null
    [[ -s "$TRUST_FILE" ]] || printf '{"projects":{}}\n' > "$TRUST_FILE"
}

trust_status() { local root="${1:-$PWD}"; entry=$(jq -c --arg h "$(_trust_hash "$root")" '.projects[$h] // empty' "$TRUST_FILE" 2>/dev/null); if [[ -n "$entry" ]]; then echo "$entry"; else printf '{"root":"%s","trusted":false,"auto_env":false}\n' "$root"; fi; }
trust_on() { local root="${1:-$PWD}"; _trust_ensure; jq --arg h "$(_trust_hash "$root")" --arg r "$root" '.projects[$h] = ((.projects[$h] // {}) + {root:$r, trusted:true})' "$TRUST_FILE" > /tmp/tt && mv /tmp/tt "$TRUST_FILE"; }
trust_off() { local root="${1:-$PWD}"; _trust_ensure; jq --arg h "$(_trust_hash "$root")" '.projects[$h].trusted = false' "$TRUST_FILE" > /tmp/tt && mv /tmp/tt "$TRUST_FILE"; }
trust_list() { jq -r '.projects | to_entries[] | [.value.root, .value.trusted, .value.auto_env] | @tsv' "$TRUST_FILE" 2>/dev/null | column -t; }
