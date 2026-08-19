#!/bin/bash
# Flow Terminal — Starship State Generator
# Generates environment variables for Starship to consume
# Called from 80-flow.zsh after activation

# Source icon abstraction
FLOW_ICONS_FILE="${BASH_SOURCE[0]%/*}/starship-icons.sh"
[[ -f "$FLOW_ICONS_FILE" ]] && source "$FLOW_ICONS_FILE"

# Export current state for Starship
export FLOW_STARSHIP_PROFILE="${FLOW_ENV_PROFILE:-}"
export FLOW_STARSHIP_LANGUAGE="${FLOW_ENV_LANGUAGE:-}"
export FLOW_STARSHIP_STRATEGY="${FLOW_ENV_STRATEGY:-}"
export FLOW_STARSHIP_TARGET="${FLOW_ENV_TARGET:-}"
export FLOW_STARSHIP_ROOT="${FLOW_ENV_ROOT:-}"
export FLOW_STARSHIP_ACTIVATED="${FLOW_ENV_ACTIVATED:-}"

# Export runtime information
export FLOW_STARSHIP_VENV="${FLOW_ENV_VENV:-}"
export FLOW_STARSHIP_NODE_VERSION="${FLOW_ENV_NODE_VERSION:-}"
export FLOW_STARSHIP_MISE_NODE="${FLOW_ENV_MISE_NODE:-}"
export FLOW_STARSHIP_MISE_PYTHON="${FLOW_ENV_MISE_PYTHON:-}"

# Export icons for Starship
export FLOW_ICON_PYTHON="${FLOW_ICON_PYTHON:-󰌠}"
export FLOW_ICON_NODEJS="${FLOW_ICON_NODEJS:-󰜙}"
export FLOW_ICON_GO="${FLOW_ICON_GO:-󰟓}"
export FLOW_ICON_RUST="${FLOW_ICON_RUST:-󱘗}"
export FLOW_ICON_DOCKER="${FLOW_ICON_DOCKER:-󰡨}"
export FLOW_ICON_KUBERNETES="${FLOW_ICON_KUBERNETES:-󱃾}"
export FLOW_ICON_HELM="${FLOW_ICON_HELM:-󱃾}"
export FLOW_ICON_TERRAFORM="${FLOW_ICON_TERRAFORM:-󱁢}"
export FLOW_ICON_AWS="${FLOW_ICON_AWS:-󰸏}"
export FLOW_ICON_GCP="${FLOW_ICON_GCP:-󰦧}"
export FLOW_ICON_AZURE="${FLOW_ICON_AZURE:-󰦾}"
export FLOW_ICON_GIT="${FLOW_ICON_GIT:-󰘬}"
export FLOW_ICON_GITHUB="${FLOW_ICON_GITHUB:-󰊤}"
export FLOW_ICON_GITLAB="${FLOW_ICON_GITLAB:-󰊕}"
export FLOW_ICON_WARNING="${FLOW_ICON_WARNING:-⚠}"
export FLOW_ICON_SEPARATOR="${FLOW_ICON_SEPARATOR:-·}"

# Detect remote shell
export FLOW_STARSHIP_REMOTE=""
if [[ -n "${SSH_CLIENT:-}" ]] || [[ -n "${SSH_TTY:-}" ]] || [[ -n "${DISPLAY:-}" && "$(whoami)" != "$(logname 2>/dev/null || echo root)" ]]; then
  export FLOW_STARSHIP_REMOTE="1"
fi

# Detect production context
export FLOW_STARSHIP_PROD=""
if [[ "${FLOW_ENV_TARGET:-}" == "production" ]] || [[ "${FLOW_ENV_PROFILE:-}" =~ prod ]]; then
  export FLOW_STARSHIP_PROD="1"
fi
