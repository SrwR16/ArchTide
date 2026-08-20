#!/bin/bash
# flow suggest - Predictive Command Intelligence debug/query CLI.
# Usage: flow suggest [prefix] [--json] [--debug] [--limit N]
#
# Deterministic, local, offline. Reads only the persisted derived aggregates
# (${XDG_STATE_HOME}/flow/predictor/aggregates.tsv) plus the live environment
# context. Never reads raw command history, clipboard or secrets.

set -euo pipefail

# locate the shared engine (mirrors the ZLE module path resolution)
_engine=""
for _cand in \
  "${FLOW_BASE_DIR:-}/sdata/lib/flow_predictor.sh" \
  "${HOME}/.local/share/flow/sdata/lib/flow_predictor.sh" \
  "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)/sdata/lib/flow_predictor.sh" \
  "$(dirname "${BASH_SOURCE[0]}")/../../lib/flow_predictor.sh"; do
  if [ -f "$_cand" ]; then _engine="$_cand"; break; fi
done
if [ -z "$_engine" ]; then
  echo "flow-suggest: engine not found" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$_engine"

PREFIX=""
JSON=0
DEBUG=0
LIMIT=10
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --debug) DEBUG=1; shift ;;
    --limit) LIMIT="${2:-10}"; shift 2 ;;
    -h|--help)
      echo "usage: flow suggest [prefix] [--json] [--debug] [--limit N]"
      exit 0
      ;;
    -*) echo "flow-suggest: unknown option $1" >&2; exit 2 ;;
    *) PREFIX="$1"; shift ;;
  esac
done

# ---- load aggregates -------------------------------------------------------
# Override state dir from env if provided (for testing)
FLOW_PRED_STATE_DIR="${FLOW_PRED_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/flow/predictor}"
FLOW_PRED_AGGREGATES="${FLOW_PRED_AGGREGATES:-$FLOW_PRED_STATE_DIR/aggregates.tsv}"

declare -A cmd_stats key_dirs key_class trans workflow recovery
hist_order=()

load_cmd() { cmd_stats["$1"]="$2 $3 $4 $5 $6"; [ -n "$7" ] && key_dirs["$1"]="$7"; [ -n "$8" ] && key_class["$1"]="$8"; hist_order+=("$1"); }
load_trans() { trans["$1"]="$2 $3 $4"; }
load_workflow() { workflow["$1"]="$2 $3 $4"; }
load_recovery() { recovery["$1"]="$2 $3 $4"; }

# Source the engine AFTER setting state dir
_engine=""
for _cand in \
  "${FLOW_BASE_DIR:-}/sdata/lib/flow_predictor.sh" \
  "${HOME}/.local/share/flow/sdata/lib/flow_predictor.sh" \
  "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)/sdata/lib/flow_predictor.sh" \
  "$(dirname "${BASH_SOURCE[0]}")/../../lib/flow_predictor.sh"; do
  if [ -f "$_cand" ]; then _engine="$_cand"; break; fi
done
if [ -z "$_engine" ]; then
  echo "flow-suggest: engine not found" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$_engine"

flow_pred_load_aggregates load_cmd load_trans load_workflow load_recovery || {
  echo "flow-suggest: no aggregates yet (run a few commands first)" >&2
  exit 1
}

# ---- context ---------------------------------------------------------------
DIR="${PWD:-$PWD}"
PROFILE="${FLOW_ENV_PROFILE:-${FLOW_STARSHIP_PROFILE:-}}"
WORKSPACE="${FLOW_ENV_ROOT:-${FLOW_STARSHIP_ROOT:-}}"
PROJECT=""
[ -n "$WORKSPACE" ] && PROJECT="${WORKSPACE##*/}"
RUNTIME=""
[ -n "${VIRTUAL_ENV:-}" ] && RUNTIME="${VIRTUAL_ENV##*/}"
HOST="${HOSTNAME:-$(hostname 2>/dev/null || echo "")}"
CTX="dir=$DIR|profile=$PROFILE|workspace=$WORKSPACE|project=$PROJECT|runtime=$RUNTIME|host=$HOST|session="

# ---- rank ------------------------------------------------------------------
results=()
explanations=()
start_ts=$(date +%s%N 2>/dev/null || echo 0)
for key in "${!cmd_stats[@]}"; do
  # Build full record: key\tcount\tsuccess\tfail\tlast\tfirst\tdirs\tclass
  set -- ${cmd_stats[$key]}
  count=$1 success=$2 fail=$3 last=$4 first=$5
  dirs="${key_dirs[$key]:-}"
  cls="${key_class[$key]:-other}"
  rec="${key}\t${count}\t${success}\t${fail}\t${last}\t${first}\t${dirs}\t${cls}"
  flow_pred_score_record "$rec" "$PREFIX" "$CTX"
  if [ "$FLOW_PRED_MATCH" -eq 1 ]; then
    results+=("$FLOW_PRED_SCORE"$'\t'"$key")
    explanations+=("${FLOW_PRED_EXPLAIN:-}")
  fi
done
end_ts=$(date +%s%N 2>/dev/null || echo 0)
elapsed_ms=0
if [ "$start_ts" != "0" ] && [ "$end_ts" != "0" ]; then
  elapsed_ms=$(( (end_ts - start_ts) / 1000000 ))
fi

# sort desc by score (default whitespace separator handles tabs)
# also reorder explanations to match sorted results
sorted_indices=()
for ((i=0; i<${#results[@]}; i++)); do
  sorted_indices+=("$i")
done
# simple insertion sort by score
for ((i=1; i<${#sorted_indices[@]}; i++)); do
  j=$i
  while [ $j -gt 0 ]; do
    prev_pos=$((j-1))
    prev_idx=${sorted_indices[$prev_pos]}
    curr_idx=${sorted_indices[$j]}
    prev_score="${results[$prev_idx]%%$'\t'*}"
    curr_score="${results[$curr_idx]%%$'\t'*}"
    if [ "$curr_score" -gt "$prev_score" ]; then
      sorted_indices[$j]="$prev_idx"
      sorted_indices[$prev_pos]="$curr_idx"
      j=$prev_pos
    else
      break
    fi
  done
done

results_sorted=()
explanations_sorted=()
for ((i=0; i<${#sorted_indices[@]}; i++)); do
  idx=${sorted_indices[$i]}
  results_sorted+=("${results[$idx]}")
  explanations_sorted+=("${explanations[$idx]:-}")
done

count=${#results_sorted[@]}
if [ "$LIMIT" -gt 0 ] && [ "$count" -gt "$LIMIT" ]; then count=$LIMIT; fi

# confidence for best result
best_score=0
[ "$count" -gt 0 ] && best_score="${results_sorted[0]%%$'\t'*}"
flow_pred_confidence "$best_score"
best_conf="$FLOW_PRED_RESULT"

tab=$'\t'
if [ "$JSON" -eq 1 ]; then
  printf '{'
  printf '"schema":%d,' "$FLOW_PRED_SCHEMA_VERSION"
  printf '"prefix":%s,' "$(printf '%s' "$PREFIX" | jq -Rsa . 2>/dev/null || printf '"%s"' "$PREFIX")"
  printf '"count":%d,' "$count"
  printf '"latency_ms":%d,' "$elapsed_ms"
  printf '"confidence":%s,' "$(printf '%s' "$best_conf" | jq -Rsa . 2>/dev/null || printf '"%s"' "$best_conf")"
  printf '"context":{"dir":%s,"profile":%s,"workspace":%s,"project":%s,"runtime":%s,"host":%s},' \
    "$(printf '%s' "$DIR" | jq -Rsa . 2>/dev/null || printf '"%s"' "$DIR")" \
    "$(printf '%s' "$PROFILE" | jq -Rsa . 2>/dev/null || printf '"%s"' "$PROFILE")" \
    "$(printf '%s' "$WORKSPACE" | jq -Rsa . 2>/dev/null || printf '"%s"' "$WORKSPACE")" \
    "$(printf '%s' "$PROJECT" | jq -Rsa . 2>/dev/null || printf '"%s"' "$PROJECT")" \
    "$(printf '%s' "$RUNTIME" | jq -Rsa . 2>/dev/null || printf '"%s"' "$RUNTIME")" \
    "$(printf '%s' "$HOST" | jq -Rsa . 2>/dev/null || printf '"%s"' "$HOST")"
  printf '"candidates":['
  for ((i=0; i<count; i++)); do
    [ $i -gt 0 ] && printf ','
    rec="${results_sorted[$i]}"
    IFS=$tab read -r score key <<< "$rec"
    expl="${explanations_sorted[$i]:-}"
    set -- ${cmd_stats["$key"]}
    flow_pred_confidence "$score"
    cand_conf="$FLOW_PRED_RESULT"
    # build reasons array from explanation tokens
    reasons="["
    first_reason=1
    for token in $expl; do
      case "$token" in
        prefix_match)      r="prefix_match" ;;
        dir_match)         r="exact_directory" ;;
        parent_dir_match)  r="parent_directory" ;;
        profile_match)     r="profile_match" ;;
        workspace_match)   r="workspace_match" ;;
        project_match)     r="project_match" ;;
        runtime_match)     r="runtime_match" ;;
        session_match)     r="session_match" ;;
        follows_prev)      r="follows_previous_command" ;;
        workflow_step)     r="workflow_continuation" ;;
        recovery_candidate) r="recovery_after_failure" ;;
        high_failure_rate) r="high_failure_rate" ;;
        *) r="$token" ;;
      esac
      [ $first_reason -eq 0 ] && reasons+=","
      reasons+="$(printf '%s' "$r" | jq -Rsa . 2>/dev/null || printf '"%s"' "$r")"
      first_reason=0
    done
    reasons+="]"
    printf '{"score":%d,"confidence":%s,"command":%s,"count":%d,"success":%d,"fail":%d,"class":%s,"risk":%s,"reasons":%s}' \
      "$score" \
      "$(printf '%s' "$cand_conf" | jq -Rsa . 2>/dev/null || printf '"%s"' "$cand_conf")" \
      "$(printf '%s' "$key" | jq -Rsa . 2>/dev/null || printf '"%s"' "$key")" \
      "$1" "$2" "$3" \
      "$(printf '%s' "${key_class[$key]:-other}" | jq -Rsa . 2>/dev/null || printf '"%s"' "${key_class[$key]:-other}")" \
      "$(flow_pred_risk_class "$key"; printf '"%s"' "$FLOW_PRED_RESULT" | jq -Rsa . 2>/dev/null || printf '"%s"' "$FLOW_PRED_RESULT")" \
      "$reasons"
  done
  printf ']}\n'
  exit 0
fi

# ---- human-readable output --------------------------------------------------
echo "flow-suggest: ${count} candidate(s) for '${PREFIX}'"
echo "context: dir=${DIR} profile=${PROFILE} workspace=${WORKSPACE} project=${PROJECT} runtime=${RUNTIME} host=${HOST}"
echo "confidence: ${best_conf}  latency: ${elapsed_ms}ms"
if [ "$DEBUG" -eq 1 ]; then
  echo "--- debug ---"
  echo "weights: prefix=$FLOW_PRED_W_PREFIX dir=$FLOW_PRED_W_DIR profile=$FLOW_PRED_W_PROFILE workspace=$FLOW_PRED_W_WORKSPACE project=$FLOW_PRED_W_PROJECT runtime=$FLOW_PRED_W_RUNTIME session=$FLOW_PRED_W_SESSION success=$FLOW_PRED_W_SUCCESS freq=$FLOW_PRED_W_FREQ"
  echo "confidence thresholds: very_high>=$FLOW_PRED_CONF_VHIGH high>=$FLOW_PRED_CONF_HIGH medium>=$FLOW_PRED_CONF_MEDIUM low>=$FLOW_PRED_CONF_LOW"
fi
for ((i=0; i<count; i++)); do
  rec="${results_sorted[$i]}"
  IFS=$tab read -r score key <<< "$rec"
  expl="${explanations_sorted[$i]:-}"
  set -- ${cmd_stats["$key"]}   # count success fail last first
  total=$(( $2 + $3 ))
  pct=0
  [ "$total" -gt 0 ] && pct=$(( $2 * 100 / total ))
  ago=""
  if [ "$5" -gt 0 ]; then
    now=$(date +%s)
    diff=$(( now - $5 ))
    if [ "$diff" -lt 60 ]; then ago="just now"
    elif [ "$diff" -lt 3600 ]; then ago="$(( diff / 60 ))m ago"
    elif [ "$diff" -lt 86400 ]; then ago="$(( diff / 3600 ))h ago"
    else ago="$(( diff / 86400 ))d ago"
    fi
  fi
  flow_pred_confidence "$score"
  cand_conf="$FLOW_PRED_RESULT"
  line="  ${key}  score=${score} (${cand_conf})  ${1}x  ${pct}% success  ${ago}  class=${key_class[$key]:-other}  risk=$(flow_pred_risk_class "$key"; echo "$FLOW_PRED_RESULT")"
  if [ "$DEBUG" -eq 1 ] && [ -n "$expl" ]; then
    line+="  reasons=(${expl})"
  fi
  echo "$line"
done