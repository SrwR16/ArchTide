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
FLOW_PRED_EXPLAIN=""

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

# -- confidence thresholds ----------------------------------------------------
# Presentation mode is determined by the final score:
#   >=80  very high → inline ghost
#   >=60  high      → ghost + alternatives accessible
#   >=40  medium    → no ghost, HUD available on demand
#   >=20  low       → HUD only when explicitly requested
#   <20   very low  → no suggestion
FLOW_PRED_CONF_VHIGH=80
FLOW_PRED_CONF_HIGH=60
FLOW_PRED_CONF_MEDIUM=40
FLOW_PRED_CONF_LOW=20

# flow_pred_confidence <score> -> confidence label in FLOW_PRED_RESULT
flow_pred_confidence() {
  local s="${1:-0}"
  if   [ "$s" -ge "$FLOW_PRED_CONF_VHIGH" ]; then FLOW_PRED_RESULT="very_high"
  elif [ "$s" -ge "$FLOW_PRED_CONF_HIGH" ];  then FLOW_PRED_RESULT="high"
  elif [ "$s" -ge "$FLOW_PRED_CONF_MEDIUM" ]; then FLOW_PRED_RESULT="medium"
  elif [ "$s" -ge "$FLOW_PRED_CONF_LOW" ];   then FLOW_PRED_RESULT="low"
  else FLOW_PRED_RESULT="very_low"
  fi
}

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
# Full scorer used by the HUD and the CLI. Sets FLOW_PRED_SCORE,
# FLOW_PRED_MATCH, and FLOW_PRED_EXPLAIN (space-separated explanation tokens).
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
  FLOW_PRED_EXPLAIN=""
  local score=0 keylen=${#key} prefixlen=${#prefix}

  if [ "$prefixlen" -gt 0 ]; then
    case "$key" in
      "$prefix"*)
        score=$(( score + FLOW_PRED_W_PREFIX ))
        score=$(( score + (prefixlen * 100 / keylen) / 4 ))
        FLOW_PRED_MATCH=1
        FLOW_PRED_EXPLAIN="prefix_match"
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
        FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN dir_match"
        local fb=$(( dcount * FLOW_PRED_W_FREQ ))
        if [ "$fb" -gt "$FLOW_PRED_W_FREQ_CAP" ]; then fb=$FLOW_PRED_W_FREQ_CAP; fi
        score=$(( score + fb ))
      elif [ "${dir#$dpath/}" != "$dir" ]; then
        score=$(( score + FLOW_PRED_W_DIR_PARENT ))
        FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN parent_dir_match"
      fi
    done
    IFS=$oldifs2
  fi

  if [ -n "$profile" ]; then
    case "$key" in "$profile"*)
      score=$(( score + FLOW_PRED_W_PROFILE ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN profile_match"
    ;; esac
  fi
  if [ -n "$workspace" ]; then
    case "$key" in "$workspace"*)
      score=$(( score + FLOW_PRED_W_WORKSPACE ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN workspace_match"
    ;; esac
  fi
  if [ -n "$project" ]; then
    case "$key" in "$project"*)
      score=$(( score + FLOW_PRED_W_PROJECT ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN project_match"
    ;; esac
  fi
  if [ -n "$runtime" ]; then
    case "$key" in "$runtime"*)
      score=$(( score + FLOW_PRED_W_RUNTIME ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN runtime_match"
    ;; esac
  fi
  if [ -n "$session" ] && [ "$session" = "$key" ]; then
    score=$(( score + FLOW_PRED_W_SESSION ))
    FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN session_match"
  fi
  [ -n "$host" ] && [ "$host" = "$key" ] && score=$(( score + FLOW_PRED_W_HOST ))

  local total=$(( success + fail ))
  if [ "$total" -gt 0 ]; then
    score=$(( score + (success * FLOW_PRED_W_SUCCESS / total) ))
    FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN ${success}ok_${fail}fail"
    if [ "$total" -ge 3 ] && [ "$fail" -gt 0 ] && [ $(( fail * 100 / total )) -ge 50 ]; then
      score=$(( score - FLOW_PRED_N_FAIL_PENALTY ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN high_failure_rate"
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

  [ "$count" -gt 0 ] && FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN ${count}x_used"

  FLOW_PRED_SCORE=$score
  return 0
}

# flow_pred_score_fast <key> <count> <success> <fail> <last> <first> <dirs>
#   <class> <prefix> <ctx> [<trans_cnt> <trans_suc> <wf_cnt> <wf_suc> <rec_cnt>]
# Fast heuristic scorer for the keystroke hot path. Sets FLOW_PRED_SCORE,
# FLOW_PRED_MATCH, and FLOW_PRED_EXPLAIN (space-separated explanation tokens).
# Optional trailing args add transition/workflow/recovery bonuses.
flow_pred_score_fast() {
  local key="$1" count="${2:-0}" success="${3:-0}" fail="${4:-0}" last="${5:-0}" first="${6:-0}" dirs="${7:-}" cls="${8:-}" prefix="$9" ctx="${10:-}"
  local tcnt="${11:-0}" tsuc="${12:-0}" wcnt="${13:-0}" wsuc="${14:-0}" rcnt="${15:-0}"
  local score=0 prefixlen=${#prefix} keylen=${#key}
  FLOW_PRED_MATCH=0
  FLOW_PRED_EXPLAIN=""

  if [ "$prefixlen" -gt 0 ]; then
    case "$key" in
      "$prefix"*)
        FLOW_PRED_MATCH=1
        FLOW_PRED_EXPLAIN="prefix_match"
        ;;
      *)
        FLOW_PRED_SCORE=0
        FLOW_PRED_EXPLAIN=""
        return 1
        ;;
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
      *",$dir:"*)
        score=$(( score + FLOW_PRED_W_DIR ))
        FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN dir_match"
        ;;
      *",${dir%/},"*)
        score=$(( score + FLOW_PRED_W_DIR ))
        FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN dir_match"
        ;;
      *)
        case ",$dirs," in
          *",${dir%%/*}:"*)
            score=$(( score + FLOW_PRED_W_DIR_PARENT ))
            FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN parent_dir_match"
            ;;
        esac
        ;;
    esac
  fi
  if [ -n "$profile" ]; then
    case "$key" in "$profile"*)
      score=$(( score + FLOW_PRED_W_PROFILE ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN profile_match"
    ;; esac
  fi
  if [ -n "$workspace" ]; then
    case "$key" in "$workspace"*)
      score=$(( score + FLOW_PRED_W_WORKSPACE ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN workspace_match"
    ;; esac
  fi
  if [ -n "$project" ]; then
    case "$key" in "$project"*)
      score=$(( score + FLOW_PRED_W_PROJECT ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN project_match"
    ;; esac
  fi
  if [ -n "$runtime" ]; then
    case "$key" in "$runtime"*)
      score=$(( score + FLOW_PRED_W_RUNTIME ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN runtime_match"
    ;; esac
  fi
  if [ -n "$session" ] && [ "$session" = "$key" ]; then
    score=$(( score + FLOW_PRED_W_SESSION ))
    FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN session_match"
  fi

  # transition boost: proportional to count, capped
  if [ "$tcnt" -gt 0 ]; then
    local tboost=0 tbase=0
    while [ "$tcnt" -gt 1 ]; do tbase=$((tbase+1)); tcnt=$((tcnt >> 1)); done
    tboost=$(( tbase * FLOW_PRED_W_TRANSITION ))
    [ "$tboost" -gt "$FLOW_PRED_W_TRANSITION_CAP" ] && tboost=$FLOW_PRED_W_TRANSITION_CAP
    score=$(( score + tboost ))
    FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN follows_prev"
  fi

  # workflow boost: proportional to count, capped
  if [ "$wcnt" -gt 0 ]; then
    local wboost=0 wbase=0
    while [ "$wcnt" -gt 1 ]; do wbase=$((wbase+1)); wcnt=$((wcnt >> 1)); done
    wboost=$(( wbase * FLOW_PRED_W_WORKFLOW ))
    [ "$wboost" -gt "$FLOW_PRED_W_WORKFLOW_CAP" ] && wboost=$FLOW_PRED_W_WORKFLOW_CAP
    score=$(( score + wboost ))
    FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN workflow_step"
  fi

  # recovery boost
  if [ "$rcnt" -gt 0 ]; then
    local rboost=$(( rcnt * FLOW_PRED_W_RECOVERY ))
    [ "$rboost" -gt 20 ] && rboost=20
    score=$(( score + rboost ))
    FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN recovery_candidate"
  fi

  local total=$(( success + fail ))
  if [ "$total" -gt 0 ]; then
    score=$(( score + (success * FLOW_PRED_W_SUCCESS / total) ))
    FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN ${success}ok_${fail}fail"
    if [ "$total" -ge 3 ] && [ "$fail" -gt 0 ] && [ $(( fail * 100 / total )) -ge 50 ]; then
      score=$(( score - FLOW_PRED_N_FAIL_PENALTY ))
      FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN high_failure_rate"
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

  # append count/recency explanation
  [ "$count" -gt 0 ] && FLOW_PRED_EXPLAIN="$FLOW_PRED_EXPLAIN ${count}x_used"

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