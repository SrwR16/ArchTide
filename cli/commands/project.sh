#!/bin/bash
# flow project — detect, profile, trust, env
# Delegates to sdata/subcmd-project/ scripts

PROJECT_DIR="$BASE_DIR/sdata/subcmd-project"

cmd_project() {
    local sub="${1:-detect}"; shift || true
    local script=""
    case "$sub" in
        detect)  script="$PROJECT_DIR/detect.sh" ;;
        profile) script="$PROJECT_DIR/profile.sh" ;;
        env)     script="$PROJECT_DIR/env.sh" ;;
        activate) script="$PROJECT_DIR/activate.sh" ;;
        *) echo "Unknown: flow project $sub"; echo "Available: detect profile env activate"; exit 1 ;;
    esac
    if [[ -f "$script" ]]; then
        bash "$script" "$@"
    elif [[ -f "$BASE_DIR/sdata/subcmd-project/$sub.sh" ]]; then
        bash "$BASE_DIR/sdata/subcmd-project/$sub.sh" "$@"
    else
        echo "✗ $sub not found"
        exit 1
    fi
}

# flow trust — delegates to sdata/lib/trust.sh
cmd_trust() {
    local sub="${1:-status}"; shift || true
    if [[ -f "$BASE_DIR/sdata/lib/trust.sh" ]]; then
        bash "$BASE_DIR/sdata/lib/trust.sh" "$sub" "$@"
    fi
}
