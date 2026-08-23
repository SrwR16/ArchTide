# 76-flow-context.zsh — Infrastructure context provider (Phase 7)
#
# Computes infrastructure state from CHEAP sources only (env vars + config
# file reads — never cloud CLI calls) and exports FLOW_STARSHIP_* variables
# for Starship's Layer-6/7 modules.
#
# Sources:
#   Kubernetes : current-context from $KUBECONFIG / ~/.kube/config
#   AWS        : $AWS_PROFILE (+ region from ~/.aws/config when present)
#   Remote     : $SSH_CONNECTION
#   Production : name matches $FLOW_PROD_REGEX (default *prod*)
#
# Recomputed only when an input changes (mtime/hash guard) — effectively
# free on every prompt.

typeset -g _FLOW_CTX_SIG=""
typeset -g _FLOW_CTX_LAST_ROOT=""

_flow_context_compute() {
  local sig="$KUBECONFIG|$AWS_PROFILE|$SSH_CONNECTION"
  local kube_cfg="${KUBECONFIG:-$HOME/.kube/config}"
  [[ -f "$kube_cfg" ]] && sig+="|$(stat -Lc %Y "$kube_cfg" 2>/dev/null)"

  # recompute only when something could have changed
  if [[ "$sig" == "$_FLOW_CTX_SIG" && "$PWD" == "$_FLOW_CTX_LAST_ROOT" ]]; then
    return 0
  fi
  _FLOW_CTX_SIG="$sig"
  _FLOW_CTX_LAST_ROOT="$PWD"

  unset FLOW_STARSHIP_K8S FLOW_STARSHIP_AWS FLOW_STARSHIP_REMOTE \
        FLOW_STARSHIP_PROD FLOW_ENV_TARGET

  # --- Kubernetes -----------------------------------------------------------
  local ctx=""
  if [[ -f "$kube_cfg" ]]; then
    ctx="$(awk '
      /^[[:space:]]*current-context:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/"/,""); print; exit }
    ' "$kube_cfg" 2>/dev/null)"
    # push to the Flow Engine over its FD protocol — env exports made in zsh
    # never reach the parent engine process. Empty value clears its state.
    if (( $+IRIS_FD )) && [[ -n "$IRIS_FD" ]]; then
      print -u $IRIS_FD -N -r -- "IRIS_KUBECTX:${ctx}" 2>/dev/null
    fi
    if [[ -n "$ctx" ]]; then
      export FLOW_STARSHIP_K8S="$ctx"
    fi
  fi

  # --- AWS ------------------------------------------------------------------
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    export FLOW_STARSHIP_AWS="$AWS_PROFILE"
  elif [[ -n "${AWS_DEFAULT_PROFILE:-}" ]]; then
    export FLOW_STARSHIP_AWS="$AWS_DEFAULT_PROFILE"
  fi

  # --- Remote shell ---------------------------------------------------------
  [[ -n "${SSH_CONNECTION:-}" ]] && export FLOW_STARSHIP_REMOTE=1

  # --- Production gate ------------------------------------------------------
  local rx="${FLOW_PROD_REGEX:-prod}"
  local hay="${FLOW_STARSHIP_K8S:-} ${FLOW_STARSHIP_AWS:-}"
  if [[ "${(L)hay}" == *"${(L)rx}"* ]]; then
    export FLOW_STARSHIP_PROD=1
    export FLOW_ENV_TARGET="production"
  fi
}
