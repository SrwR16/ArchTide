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
  fi
done

# sort desc by score (default whitespace separator handles tabs)
mapfile -t results_sorted < <(printf '%s\n' "${results[@]}" | sort -k1,1nr)

count=${#results_sorted[@]}
if [ "$LIMIT" -gt 0 ] && [ "$count" -gt "$LIMIT" ]; then count=$LIMIT; fi

tab=$'\t'
if [ "$JSON" -eq 1 ]; then
  printf '{'
  printf '"schema":%d,' "$FLOW_PRED_SCHEMA_VERSION"
  printf '"prefix":%s,' "$(printf '%s' "$PREFIX" | jq -Rsa . 2>/dev/null || printf '"%s"' "$PREFIX")"
  printf '"count":%d,' "$count"
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
    set -- ${cmd_stats["$key"]}
    printf '{"score":%d,"command":%s,"count":%d,"success":%d,"fail":%d,"class":%s,"risk":%s}' \
      "$score" \
      "$(printf '%s' "$key" | jq -Rsa . 2>/dev/null || printf '"%s"' "$key")" \
      "$1" "$2" "$3" \
      "$(printf '%s' "${key_class[$key]:-other}" | jq -Rsa . 2>/dev/null || printf '"%s"' "${key_class[$key]:-other}")" \
      "$(flow_pred_risk_class "$key"; printf '"%s"' "$FLOW_PRED_RESULT" | jq -Rsa . 2>/dev/null || printf '"%s"' "$FLOW_PRED_RESULT")"
  done
  printf ']}\n'
  exit 0
fi

echo "flow-suggest: ${count} candidate(s) for '${PREFIX}'"
echo "context: dir=${DIR} profile=${PROFILE} workspace=${WORKSPACE} project=${PROJECT} runtime=${RUNTIME} host=${HOST}"
tab=$'\t'
for ((i=0; i<count; i++)); do
  rec="${results_sorted[$i]}"
  IFS=$tab read -r score key <<< "$rec"
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
  echo "  ${key}  score=${score}  ${1}x  ${pct}% success  ${ago}  class=${key_class[$key]:-other}  risk=$(flow_pred_risk_class "$key"; echo "$FLOW_PRED_RESULT")"
done