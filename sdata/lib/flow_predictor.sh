# flow_predictor.sh - shared engine for the Flow Predictive Command Intelligence.
# Pure, deterministic logic shared by the ZLE module (zsh) and the `flow suggest`
# CLI (bash). No side effects unless a function explicitly says so.
#
# Bash and zsh compatible. Do not use zsh-only syntax in this file.
#
# PERFORMANCE: every function in this file runs in-process (no command
# substitution / subprocess forks). Results are written to well-known globals
# so the hot keystroke path stays under budget:
#   FLOW_PRED_RESULT   - string result
#   FLOW_PRED_SCORE    - integer result
#   FLOW_PRED_MATCH    - 1 if a predicate matched, 0 otherwise
#
# Conventions
# -----------
# * A "command key" is the normalized command string (leading/trailing
#   whitespace trimmed, exactly one space between tokens, trailing ';' removed).
# * A "candidate record" is a single line with TAB-separated fields:
#       KEY  COUNT  SUCCESS  FAIL  LAST_TS  FIRST_TS  DIRS  CLASS
#   where DIRS is comma-separated "dir:count:last_ts" pairs and CLASS is the
#   command class name. Fields may not contain TAB; DIRS and CLASS may be empty.
# * Sub-field separator inside records is the unit separator "\x1f".
#
# Versioning
# ----------
FLOW_PRED_SCHEMA_VERSION=1
FLOW_PRED_STATE_DIR="${FLOW_PRED_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/flow/predictor}"
FLOW_PRED_AGGREGATES="${FLOW_PRED_AGGREGATES:-$FLOW_PRED_STATE_DIR/aggregates.tsv}"

FLOW_PRED_RESULT=""
FLOW_PRED_SCORE=0
FLOW_PRED_MATCH=0

# -- normalization ------------------------------------------------------------
# Normalize a raw command line into a command key. Result in FLOW_PRED_RESULT.
flow_pred_normalize() {
  local s
  s="${1:-}"
  s="${s%;}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  s="$(printf '%s' "$s" | tr -s '[:space:]' ' ')"
  FLOW_PRED_RESULT="$s"
}

# -- classification -----------------------------------------------------------
# Deterministic, lightweight command classification for risk classes and
# presentation. Result in FLOW_PRED_RESULT.
flow_pred_classify() {
  local cmd="${1:-}"
  local first
  first="${cmd%% *}"
  case "$first" in
    git|git-*)                 FLOW_PRED_RESULT='version_control' ;;
    uv|python|python3|pip|pip3|poetry|pipenv|pdm|pyenv|python3.11|python3.12) FLOW_PRED_RESULT='python' ;;
    cargo|rustup|rustc)        FLOW_PRED_RESULT='rust' ;;
    node|npm|npx|yarn|pnpm|bun) FLOW_PRED_RESULT='javascript' ;;
    docker|podman|docker-compose) FLOW_PRED_RESULT='container' ;;
    kubectl|helm|k3s|minikube|kind) FLOW_PRED_RESULT='kubernetes' ;;
    terraform|tofu|terragrunt) FLOW_PRED_RESULT='infrastructure' ;;
    ssh|scp|rsync|curl|wget|ping|nc|nmap) FLOW_PRED_RESULT='network' ;;
    systemctl|journalctl|service|systemd-*) FLOW_PRED_RESULT='system' ;;
    ls|cd|cat|less|vim|nvim|nano|rm|cp|mv|mkdir|rmdir|touch|chmod|chown|find|grep|rg|sed|awk|bat) FLOW_PRED_RESULT='filesystem' ;;
    make|cmake|ninja|meson|bazel|just|task|mise) FLOW_PRED_RESULT='build' ;;
    sudo) FLOW_PRED_RESULT='privileged' ;;
    pacman|yay|paru|dnf|apt|apt-get|flatpak|snap) FLOW_PRED_RESULT='package' ;;
    *) FLOW_PRED_RESULT='other' ;;
  esac
}

# Risk class for presentation/ranking only (never blocks anything).
# Result in FLOW_PRED_RESULT.
flow_pred_risk_class() {
  local cmd="${1:-}"
  local first
  first="${cmd%% *}"
  case "$first" in
    rm|rmdir|dd|mkfs|format|shutdown|reboot|poweroff|kill|pkill|killall|systemctl|sudo) FLOW_PRED_RESULT='destructive' ;;
    git|mv|cp|chmod|chown) FLOW_PRED_RESULT='caution' ;;
    *) FLOW_PRED_RESULT='normal' ;;
  esac
}

# -- scoring ------------------------------------------------------------------
# Weights are documented constants; tuning them changes ranking deterministically.
FLOW_PRED_W_PREFIX=40
FLOW_PRED_W_DIR=25
FLOW_PRED_W_DIR_PARENT=10
FLOW_PRED_W_PROFILE=15
FLOW_PRED_W_WORKSPACE=12
FLOW_PRED_W_PROJECT=10
FLOW_PRED_W_RUNTIME=8
FLOW_PRED_W_SESSION=12
FLOW_PRED_W_HOST=3
FLOW_PRED_W_TRANSITION=8
FLOW_PRED_W_TRANSITION_CAP=20
FLOW_PRED_W_WORKFLOW=10
FLOW_PRED_W_WORKFLOW_CAP=25
FLOW_PRED_W_RECOVERY=12
FLOW_PRED_W_SUCCESS=15
FLOW_PRED_W_FREQ=6
FLOW_PRED_W_FREQ_CAP=24
FLOW_PRED_W_RECENCY_H1=10
FLOW_PRED_W_RECENCY_D1=8
FLOW_PRED_W_RECENCY_D7=5
FLOW_PRED_W_RECENCY_D30=2
FLOW_PRED_N_FAIL_PENALTY=10

# _flow_pred_now - current unix timestamp. Result in FLOW_PRED_SCORE.
if [ -n "${ZSH_VERSION:-}" ]; then
  flow_pred_now() { FLOW_PRED_SCORE=$EPOCHSECONDS; }
else
  flow_pred_now() { FLOW_PRED_SCORE="$(date +%s)"; }
fi

# flow_pred_recency_bonus <last_ts> <now> -> integer in FLOW_PRED_SCORE
flow_pred_recency_bonus() {
  local age=$(( ${2:-0} - ${1:-0} ))
  if   [ "$age" -lt 3600 ]; then    FLOW_PRED_SCORE=$FLOW_PRED_W_RECENCY_H1
  elif [ "$age" -lt 86400 ]; then   FLOW_PRED_SCORE=$FLOW_PRED_W_RECENCY_D1
  elif [ "$age" -lt 604800 ]; then  FLOW_PRED_SCORE=$FLOW_PRED_W_RECENCY_D7
  elif [ "$age" -lt 2592000 ]; then FLOW_PRED_SCORE=$FLOW_PRED_W_RECENCY_D30
  else FLOW_PRED_SCORE=0
  fi
}

# flow_pred_ctx_get <ctx> <name> -> value in FLOW_PRED_RESULT
# ctx is a '|'-separated list of key=value pairs.
flow_pred_ctx_get() {
  local ctx="$1" name="$2" kv k v
  local oldifs=$IFS
  IFS='|'
  for kv in $ctx; do
    k="${kv%%=*}" v="${kv#*=}"
    if [ "$k" = "$name" ]; then
      FLOW_PRED_RESULT="$v"
      IFS=$oldifs
      return 0
    fi
  done
  IFS=$oldifs
  FLOW_PRED_RESULT=""
  return 1
}

# flow_pred_score_record <rec> <prefix> <ctx>
# Full scorer used by the HUD and the CLI. Sets FLOW_PRED_SCORE and
# FLOW_PRED_MATCH (1 if the record matched the prefix, 0 otherwise).
# rec: TAB-separated candidate record; ctx: see flow_pred_ctx_get.
flow_pred_score_record() {
  local rec="$1" prefix="$2" ctx="$3"
  local oldifs=$IFS
  local key count success fail last first dirs cls
  IFS=$'\t'
  set -- $rec
  IFS=$oldifs
  key="${1:-}" count="${2:-0}" success="${3:-0}" fail="${4:-0}" last="${5:-0}" first="${6:-0}" dirs="${7:-}" cls="${8:-}"

  FLOW_PRED_SCORE=0
  FLOW_PRED_MATCH=0
  local score=0 keylen=${#key} prefixlen=${#prefix}

  if [ "$prefixlen" -gt 0 ]; then
    case "$key" in
      "$prefix"*)
        score=$(( score + FLOW_PRED_W_PREFIX ))
        score=$(( score + (prefixlen * 100 / keylen) / 4 ))
        FLOW_PRED_MATCH=1
        ;;
      *)
        FLOW_PRED_MATCH=0
        ;;
    esac
  fi

  local dir profile workspace project runtime host session prev
  flow_pred_ctx_get "$ctx" dir;       dir="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" profile;   profile="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" workspace; workspace="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" project;   project="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" runtime;   runtime="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" host;      host="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" session;   session="$FLOW_PRED_RESULT"

  # directory context
  if [ -n "$dir" ] && [ -n "$dirs" ]; then
    local d dpath dcount
    local oldifs2=$IFS
    IFS=','
    for d in $dirs; do
      dpath="${d%%:*}"
      dcount="${d#*:}"; dcount="${dcount%%:*}"
      if [ "$dpath" = "$dir" ]; then
        score=$(( score + FLOW_PRED_W_DIR ))
        local fb=$(( dcount * FLOW_PRED_W_FREQ ))
        if [ "$fb" -gt "$FLOW_PRED_W_FREQ_CAP" ]; then fb=$FLOW_PRED_W_FREQ_CAP; fi
        score=$(( score + fb ))
      elif [ "${dir#$dpath/}" != "$dir" ]; then
        score=$(( score + FLOW_PRED_W_DIR_PARENT ))
      fi
    done
    IFS=$oldifs2
  fi

  [ -n "$profile" ]   && case "$key" in "$profile"*)   score=$(( score + FLOW_PRED_W_PROFILE )) ;; esac
  [ -n "$workspace" ] && case "$key" in "$workspace"*) score=$(( score + FLOW_PRED_W_WORKSPACE )) ;; esac
  [ -n "$project" ]   && case "$key" in "$project"*)   score=$(( score + FLOW_PRED_W_PROJECT )) ;; esac
  [ -n "$runtime" ]   && case "$key" in "$runtime"*)   score=$(( score + FLOW_PRED_W_RUNTIME )) ;; esac
  [ -n "$session" ]   && [ "$session" = "$key" ] && score=$(( score + FLOW_PRED_W_SESSION ))
  [ -n "$host" ]      && [ "$host" = "$key" ] && score=$(( score + FLOW_PRED_W_HOST ))

  local total=$(( success + fail ))
  if [ "$total" -gt 0 ]; then
    score=$(( score + (success * FLOW_PRED_W_SUCCESS / total) ))
    if [ "$total" -ge 3 ] && [ "$fail" -gt 0 ] && [ $(( fail * 100 / total )) -ge 50 ]; then
      score=$(( score - FLOW_PRED_N_FAIL_PENALTY ))
    fi
  fi

  local freq=0
  if [ "$count" -gt 0 ]; then
    local c=$count
    while [ "$c" -gt 1 ]; do c=$(( c >> 1 )); freq=$((freq+1)); done
  fi
  local fb=$(( freq * FLOW_PRED_W_FREQ ))
  if [ "$fb" -gt "$FLOW_PRED_W_FREQ_CAP" ]; then fb=$FLOW_PRED_W_FREQ_CAP; fi
  score=$(( score + fb ))

  flow_pred_now
  local now=$FLOW_PRED_SCORE
  flow_pred_recency_bonus "$last" "$now"
  score=$(( score + FLOW_PRED_SCORE ))

  FLOW_PRED_SCORE=$score
  return 0
}

# flow_pred_score_fast <key> <count> <success> <fail> <last> <first> <dirs> <class> <prefix> <ctx>
# Fast heuristic scorer for the keystroke hot path. Sets FLOW_PRED_SCORE and
# FLOW_PRED_MATCH. Uses only cheap operations; exact ranking is done by the
# full scorer in the HUD.
flow_pred_score_fast() {
  local key="$1" count="${2:-0}" success="${3:-0}" fail="${4:-0}" last="${5:-0}" first="${6:-0}" dirs="${7:-}" cls="${8:-}" prefix="$9" ctx="${10:-}"
  local score=0 prefixlen=${#prefix} keylen=${#key}
  FLOW_PRED_MATCH=0

  if [ "$prefixlen" -gt 0 ]; then
    case "$key" in
      "$prefix"*) FLOW_PRED_MATCH=1 ;;
      *) FLOW_PRED_SCORE=0; return 1 ;;
    esac
    score=$(( score + FLOW_PRED_W_PREFIX + (prefixlen * 100 / keylen) / 4 ))
  fi

  local dir profile workspace project runtime session
  flow_pred_ctx_get "$ctx" dir;       dir="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" profile;   profile="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" workspace; workspace="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" project;   project="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" runtime;   runtime="$FLOW_PRED_RESULT"
  flow_pred_ctx_get "$ctx" session;   session="$FLOW_PRED_RESULT"

  if [ -n "$dir" ] && [ -n "$dirs" ]; then
    case ",$dirs," in
      *",$dir:"*) score=$(( score + FLOW_PRED_W_DIR )) ;;
      *",${dir%/},"*) score=$(( score + FLOW_PRED_W_DIR )) ;;
      *) case ",$dirs," in *",${dir%%/*}:"*) score=$(( score + FLOW_PRED_W_DIR_PARENT )) ;; esac
    esac
  fi
  [ -n "$profile" ]   && case "$key" in "$profile"*)   score=$(( score + FLOW_PRED_W_PROFILE )) ;; esac
  [ -n "$workspace" ] && case "$key" in "$workspace"*) score=$(( score + FLOW_PRED_W_WORKSPACE )) ;; esac
  [ -n "$project" ]   && case "$key" in "$project"*)   score=$(( score + FLOW_PRED_W_PROJECT )) ;; esac
  [ -n "$runtime" ]   && case "$key" in "$runtime"*)   score=$(( score + FLOW_PRED_W_RUNTIME )) ;; esac
  [ -n "$session" ]   && [ "$session" = "$key" ] && score=$(( score + FLOW_PRED_W_SESSION ))

  local total=$(( success + fail ))
  if [ "$total" -gt 0 ]; then
    score=$(( score + (success * FLOW_PRED_W_SUCCESS / total) ))
    if [ "$total" -ge 3 ] && [ "$fail" -gt 0 ] && [ $(( fail * 100 / total )) -ge 50 ]; then
      score=$(( score - FLOW_PRED_N_FAIL_PENALTY ))
    fi
  fi

  local freq=0 c=$count
  while [ "$c" -gt 1 ]; do c=$(( c >> 1 )); freq=$((freq+1)); done
  local fb=$(( freq * FLOW_PRED_W_FREQ ))
  [ "$fb" -gt "$FLOW_PRED_W_FREQ_CAP" ] && fb=$FLOW_PRED_W_FREQ_CAP
  score=$(( score + fb ))

  flow_pred_now
  local now=$FLOW_PRED_SCORE
  flow_pred_recency_bonus "$last" "$now"
  score=$(( score + FLOW_PRED_SCORE ))

  FLOW_PRED_SCORE=$score
  return 0
}

# -- persistence --------------------------------------------------------------
# Aggregate file at $FLOW_PRED_AGGREGATES (versioned). Derived statistics only -
# never full command history, clipboard or secrets.
# Format (tab-separated):
#   # flow-predictor schema=1
#   C\t<key>\t<count>\t<success>\t<fail>\t<last_ts>\t<first_ts>\t<dirs>\t<class>
#   T\t<prev\x1fnext>\t<count>\t<success>\t<last_ts>
#   W\t<c1\x1fc2\x1fc3>\t<count>\t<success>\t<last_ts>
#   R\t<failed\x1frecovery>\t<count>\t<success>\t<last_ts>

flow_pred_hex() { printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'; }
flow_pred_unhex() { printf '%s' "$1" | sed 's/\(..\)/\\x\1/g' | while IFS= read -r line; do printf '%b' "$line"; done; }

flow_pred_agg_header() { printf '# flow-predictor schema=%s\n' "$FLOW_PRED_SCHEMA_VERSION"; }

# flow_pred_save_aggregates < cmds:TSV ... >  writes the file.
flow_pred_save_aggregates() {
  mkdir -p "$FLOW_PRED_STATE_DIR" 2>/dev/null || return 1
  local tmp="$FLOW_PRED_STATE_DIR/.aggregates.$$.tmp"
  {
    flow_pred_agg_header
    cat
  } > "$tmp" || return 1
  mv -f "$tmp" "$FLOW_PRED_AGGREGATES" || { rm -f "$tmp"; return 1; }
}

# flow_pred_load_aggregates <cb_cmd> <cb_trans> <cb_workflow> <cb_recovery> [<file>]
# Calls the given bash/zsh functions per record; each gets the record fields
# as $1..$n (key, count, success, ...).
flow_pred_load_aggregates() {
  local cb_cmd="$1" cb_trans="$2" cb_workflow="$3" cb_recovery="$4"
  local file="${5-}"
  if [ -z "$file" ]; then file="$FLOW_PRED_AGGREGATES"; fi
  [ -f "$file" ] || return 1
  local IFS=$'\t' line kind rest
  while IFS= read -r line; do
    case "$line" in
      \#*|'') continue ;;
    esac
    kind="${line%%$'\t'*}"
    rest="${line#*$'\t'}"
    # In zsh, unquoted $rest doesn't word-split; use ${=rest} for zsh,
    # plain $rest for bash. Both work when IFS=$'\t'.
    if [ -n "${ZSH_VERSION:-}" ]; then
      case "$kind" in
        C) set -- ${(s:	:)rest}; "$cb_cmd" "$@" ;;
        T) set -- ${(s:	:)rest}; "$cb_trans" "$@" ;;
        W) set -- ${(s:	:)rest}; "$cb_workflow" "$@" ;;
        R) set -- ${(s:	:)rest}; "$cb_recovery" "$@" ;;
      esac
    else
      case "$kind" in
        C) set -- $rest; "$cb_cmd" "$@" ;;
        T) set -- $rest; "$cb_trans" "$@" ;;
        W) set -- $rest; "$cb_workflow" "$@" ;;
        R) set -- $rest; "$cb_recovery" "$@" ;;
      esac
    fi
  done < "$file"
}