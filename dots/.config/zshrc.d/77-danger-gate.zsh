# 77-danger-gate.zsh — Production Danger Gate (§8, shell-side)
#
# Wraps accept-line: destructive commands targeting production contexts are
# NOT executed on the first Enter. A red banner demands a deliberate second
# Enter to confirm; ANY edit to the line cancels the arm.
#
# Detection inputs are already in the shell (no forks):
#   FLOW_STARSHIP_K8S  (from 76-flow-context.zsh)  ·  AWS_PROFILE  ·  $PWD
# Host-killers (mkfs/dd/fork-bomb/rm -rf) gate everywhere, prod or not.

typeset -g FLOW_DANGER_REGEX="${FLOW_DANGER_REGEX:-prod}"
typeset -g _FLOW_ARMED_CMD=""
typeset -gi _FLOW_ARMED_UNTIL=0

_flow_danger_reason() { # <cmd> <is_prod:0|1> -> reason text, empty = pass
  local cmd="$1" prod="$2"
  local first="${cmd%% *}"

  # ── always-gate class (any context) ──────────────────────────────
  if [[ "$first" == "rm" || "$first" == "sudo" && "${cmd#*rm }" != "$cmd" ]]; then
    if [[ "$cmd" == *-[a-zA-Z]r* || "$cmd" == *-[a-zA-Z]*f[a-zA-Z]*r* || "$cmd" == *-[a-zA-Z]f[a-zA-Z]*r* || "$cmd" == *" -rf"* || "$cmd" == *" -fr"* ]]; then
      print "recursive/forced delete (rm)"
      return 0
    fi
  fi
  case "$cmd" in
    *mkfs*)          print "filesystem format"; return 0 ;;
    *" dd "*|*"dd if="*) print "raw disk write"; return 0 ;;
    *":(){ :|:& };"*|*":(){:"*) print "fork bomb"; return 0 ;;
  esac

  # ── production-gated class ───────────────────────────────────────
  (( prod )) || return 1
  case "$cmd" in
    kubectl*" delete"*|*" kubectl delete"*) print "kubernetes delete"; return 0 ;;
    terraform*" destroy"*|tofu*" destroy"*) print "infra destroy"; return 0 ;;
    helm*" uninstall"*|"helm del "*)        print "helm removal"; return 0 ;;
    *" aws "*delete*|*" aws "*terminate*)   print "aws destructive api"; return 0 ;;
    git\ push*" --force"*|"git push -f"*)   print "force push"; return 0 ;;
  esac
  return 1
}

_flow_danger_prod_name() {
  local ctx="${FLOW_STARSHIP_K8S:-}" aws="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"
  local rx="${(L)FLOW_DANGER_REGEX}"
  if [[ -n "$ctx" && "${(L)ctx}" == *"${rx}"* ]]; then print -r -- "$ctx"; return; fi
  if [[ -n "$aws" && "${(L)aws}" == *"${rx}"* ]]; then print -r -- "$aws"; return; fi
  # kubeconfig fallback (fork-free awk)
  local cfg="${KUBECONFIG:-$HOME/.kube/config}"
  [[ -f "$cfg" ]] || return 0
  local c
  c=$(awk '/^[[:space:]]*current-context:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/"/,""); print; exit }' "$cfg" 2>/dev/null)
  [[ -n "$c" && "${(L)c}" == *"${rx}"* ]] && print -r -- "$c"
}

# ── accept-line wrapper ──────────────────────────────────────────────────────
_flow_danger_accept() {
  local now=$EPOCHSECONDS

  # armed + identical buffer + within window => deliberate confirmation
  if (( $+_FLOW_ARMED_CMD )) && [[ "$BUFFER" == "$_FLOW_ARMED_CMD" ]] && (( now <= _FLOW_ARMED_UNTIL )); then
    zle -M ""
    local cmd="$_FLOW_ARMED_CMD"
    unset _FLOW_ARMED_CMD _FLOW_ARMED_UNTIL
    BUFFER="$cmd"
    CURSOR=${#BUFFER}
    zle .accept-line
    return
  fi
  unset _FLOW_ARMED_CMD _FLOW_ARMED_UNTIL

  # prod context?
  local prodname="" reason=""
  prodname="$(_flow_danger_prod_name 2>/dev/null)"
  if [[ -n "$prodname" ]]; then
    reason="$(_flow_danger_reason "$BUFFER" 1)"
  else
    reason="$(_flow_danger_reason "$BUFFER" 0)"
  fi

  if [[ -n "$reason" ]]; then
    _FLOW_ARMED_CMD="$BUFFER"
    _FLOW_ARMED_UNTIL=$(( now + 15 ))
    local who="this machine"
    [[ -n "$prodname" ]] && who="$prodname"
    zle -M "%F{red}%B⛔ PROD GATE%f %B(${who})%b · ${reason}%F{red} — press ENTER to EXECUTE, any edit cancels%f"
    return            # stay in the editor: nothing executes
  fi

  zle .accept-line
}

# idempotent wrap
if ! (( $+widgets[flow-danger-accept] )); then
  zle -N flow-danger-accept _flow_danger_accept
  zle -A flow-danger-accept accept-line   # inherit original behavior base
  bindkey '^M' flow-danger-accept
  bindkey '^J' flow-danger-accept
fi
