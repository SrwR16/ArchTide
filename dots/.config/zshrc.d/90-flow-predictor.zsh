# Flow Predictive Command Intelligence - ZLE integration.
# Phase 9: deterministic, local, offline, personalized command prediction.
#
# Loaded from zshrc.d AFTER 80-flow.zsh so Flow state is available.
#
# Design
# ------
# * Warm in-memory index built lazily after the first prompt (never blocks
#   shell startup). Source of truth for history is Atuin; we persist derived
#   aggregates only (${XDG_STATE_HOME}/flow/predictor/aggregates.tsv).
# * Pluggable candidate providers: history, transition, workflow, recovery,
#   session, native command completion. Providers feed a pipeline:
#     providers -> normalize -> deduplicate -> context score -> rank
#     -> confidence -> presentation (ghost / HUD)
# * Continuous learning: preexec/precmd hooks observe outcomes and update
#   transition/workflow/recovery statistics in memory, then persist them
#   (debounced) so the next prediction improves.
# * Ghost: ephemeral RBUFFER + region_highlight, never part of BUFFER until
#   accepted (Right / End / Ctrl+F for one token).
# * HUD: zle -R rendered list with native Up/Down/PageUp/PageDown/Enter/Tab/
#   Escape navigation through a dedicated keymap.

if (( flow_pred_loaded )); then
  return 0
fi
flow_pred_loaded=1

# ── config ──────────────────────────────────────────────────────────────────
FLOW_PRED_GHOST_ENABLED=${FLOW_PRED_GHOST_ENABLED:-1}
FLOW_PRED_HUD_MAX=${FLOW_PRED_HUD_MAX:-50}
FLOW_PRED_WARM_MIN_ENTRIES=${FLOW_PRED_WARM_MIN_ENTRIES:-50}
FLOW_PRED_SAVE_DEBOUNCE=${FLOW_PRED_SAVE_DEBOUNCE:-10}  # seconds between aggregate saves
FLOW_PRED_SKIP_ATUIN=${FLOW_PRED_SKIP_ATUIN:-0}         # 1 = offline mode (persisted aggregates only)
FLOW_PRED_DEBUG=${FLOW_PRED_DEBUG:-0}

# ── state dirs ──────────────────────────────────────────────────────────────
typeset -g FLOW_PRED_STATE_DIR="${FLOW_PRED_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/flow/predictor}"
typeset -g FLOW_PRED_AGGREGATES="${FLOW_PRED_AGGREGATES:-$FLOW_PRED_STATE_DIR/aggregates.tsv}"
mkdir -p "$FLOW_PRED_STATE_DIR" 2>/dev/null

# ── source shared engine ────────────────────────────────────────────────────
_flow_pred_lib=""
for _flow_pred_candidate in \
  "${FLOW_BASE_DIR:-}/sdata/lib/flow_predictor.sh" \
  "${HOME}/.local/share/flow/sdata/lib/flow_predictor.sh" \
  "${0:A:h}/../../../sdata/lib/flow_predictor.sh" \
  "${0:A:h}/../../sdata/lib/flow_predictor.sh"; do
  if [[ -f "$_flow_pred_candidate" ]]; then
    _flow_pred_lib="$_flow_pred_candidate"
    break
  fi
done
if [[ -z "$_flow_pred_lib" ]]; then
  return 0
fi
(( FLOW_PRED_DEBUG )) && print -u2 "flow-predictor: sourcing lib from $_flow_pred_lib" >>"${FLOW_PRED_DEBUG_LOG:-/dev/null}" 2>&1
source "$_flow_pred_lib"
(( FLOW_PRED_DEBUG )) && print -u2 "flow-predictor: lib sourced, functions: ${+functions[flow_pred_load_aggregates]}" >>"${FLOW_PRED_DEBUG_LOG:-/dev/null}" 2>&1
unset _flow_pred_candidate _flow_pred_lib

# zsh/datetime for EPOCHSECONDS (no fork in the hot path)
zmodload zsh/datetime 2>/dev/null

autoload -Uz add-zsh-hook add-zle-hook-widget

# ── index structures ────────────────────────────────────────────────────────
# Use typeset -gA/-ga at top level of sourced file (NOT inside a function)
# to ensure true globals. typeset -g INSIDE a function called from a sourced
# file can be scope-bound in zsh script mode.
typeset -gA _fp_cmd_stats=()
typeset -gA _fp_key_dirs=()
typeset -gA _fp_key_class=()
typeset -gA _fp_trans=()
typeset -gA _fp_workflow=()
typeset -gA _fp_recovery=()
typeset -gA _fp_letter=()
typeset -gA _fp_letter2=()
typeset -ga _fp_hist_order=()
typeset -ga _fp_session_seq=()
typeset -g _fp_warm=0
typeset -g _fp_atuin_warmed=0
typeset -g _fp_prev_cmd=""
typeset -g _fp_prev_prev_cmd=""
typeset -g _fp_prev_status=0
typeset -g _fp_last_save_ts=${EPOCHSECONDS:-0}
typeset -g _fp_ghost_active=0
typeset -g _fp_ghost_cmd=""
typeset -g _fp_ghost_typed=""
typeset -g _fp_ghost=""
typeset -g _fp_last_typed=""
typeset -g _fp_last_result=""
typeset -g _fp_last_score=0
typeset -g _fp_last_status=0
typeset -g _fp_last_result_count=0
typeset -ga _fp_last_results=()
typeset -ga _fp_last_result_src=()
typeset -ga _fp_last_result_meta=()
typeset -ga _fp_last_result_explain=()
typeset -ga _fp_hud_cands=()
typeset -ga _fp_hud_desc=()
typeset -ga _fp_hud_src=()
typeset -g _fp_hud_active=0
typeset -g _fp_hud_rendering=0
typeset -g _fp_hud_sel=0
typeset -g _fp_hud_offset=0
typeset -g _fp_hud_is_recovery=0
typeset -ga _fp_providers=()
typeset -ga _fp_result_explain=()

# ── load persisted aggregates immediately (fast, non-blocking) ───────────────
(( FLOW_PRED_DEBUG )) && print -u2 "flow-predictor: FLOW_PRED_STATE_DIR=$FLOW_PRED_STATE_DIR FLOW_PRED_AGGREGATES=$FLOW_PRED_AGGREGATES" >>"${FLOW_PRED_DEBUG_LOG:-/dev/null}" 2>&1

# ── _flow_pred_build_letter_index (must be defined before inline load) ───────
_flow_pred_build_letter_index() {
  _fp_letter=()
  _fp_letter2=()
  local k c c2
  for k in "${(k)_fp_cmd_stats[@]}"; do
    c="${k[1]}"
    c2="${k[1,2]}"
    _fp_letter[$c]="${_fp_letter[$c]:+${_fp_letter[$c]}}"$'\n'"$k"
    _fp_letter2[$c2]="${_fp_letter2[$c2]:+${_fp_letter2[$c2]}}"$'\n'"$k"
  done
  # trim leading newline
  for k in "${(k)_fp_letter[@]}"; do _fp_letter[$k]="${_fp_letter[$k]#$'\n'}"; done
  for k in "${(k)_fp_letter2[@]}"; do _fp_letter2[$k]="${_fp_letter2[$k]#$'\n'}"; done
}

# inline the load to avoid forward-reference issues
_flow_pred_cb_cmd() {
  local -a parts=("$@")
  _fp_cmd_stats[$parts[1]]="${parts[2]} ${parts[3]} ${parts[4]} ${parts[5]} ${parts[6]}"
  if [[ -n "${parts[7]}" ]]; then _fp_key_dirs[$parts[1]]="${parts[7]}"; fi
  if [[ -n "${parts[8]}" ]]; then _fp_key_class[$parts[1]]="${parts[8]}"; fi
  _fp_hist_order+=("$parts[1]")
}
_flow_pred_cb_trans() {
  local -a parts=("$@")
  _fp_trans["${parts[1]}$'\x1f'${parts[2]}"]="${parts[3]} ${parts[4]} ${parts[5]}"
}
_flow_pred_cb_workflow() {
  local -a parts=("$@")
  _fp_workflow["${parts[1]}$'\x1f'${parts[2]}$'\x1f'${parts[3]}"]="${parts[4]} ${parts[5]} ${parts[6]}"
}
_flow_pred_cb_recovery() {
  local -a parts=("$@")
  _fp_recovery["${parts[1]}$'\x1f'${parts[2]}"]="${parts[3]} ${parts[4]} ${parts[5]}"
}
flow_pred_load_aggregates _flow_pred_cb_cmd _flow_pred_cb_trans _flow_pred_cb_workflow _flow_pred_cb_recovery
unset -f _flow_pred_cb_cmd _flow_pred_cb_trans _flow_pred_cb_workflow _flow_pred_cb_recovery
local _load_ret=$?
(( FLOW_PRED_DEBUG )) && print -u2 "flow-predictor: load_aggregates returned $_load_ret" >>"${FLOW_PRED_DEBUG_LOG:-/dev/null}" 2>&1
_flow_pred_build_letter_index
_fp_warm=1
(( FLOW_PRED_DEBUG )) && print -u2 "flow-predictor: aggregates loaded (${#_fp_cmd_stats} commands)" >>"${FLOW_PRED_DEBUG_LOG:-/dev/null}" 2>&1

# ── context snapshot (reuses Flow state, no re-detection) ──────────────────
_flow_pred_context() {
  local dir="${PWD:-}"
  local profile="${FLOW_ENV_PROFILE:-${FLOW_STARSHIP_PROFILE:-}}"
  local workspace="${FLOW_ENV_ROOT:-${FLOW_STARSHIP_ROOT:-}}"
  local project=""
  if [[ -n "$workspace" && "$workspace" != "$dir" ]]; then
    project="${workspace:t}"
  fi
  local runtime=""
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    runtime="${VIRTUAL_ENV:t}"
  fi
  local host="$HOST"
  local session="${_fp_prev_cmd:-}"
  FLOW_PRED_CONTEXT="dir=$dir|profile=$profile|workspace=$workspace|project=$project|runtime=$runtime|host=$host|session=$session"
}

# Warm from Atuin. Runs once, lazily, after the first prompt. Uses
_flow_pred_warm_from_atuin() {
  (( _fp_atuin_warmed )) && return 0
  (( FLOW_PRED_SKIP_ATUIN )) && { _fp_atuin_warmed=1; _fp_warm=1; return 0 }
  command -v atuin >/dev/null 2>&1 || return 1
  local tmp="$FLOW_PRED_STATE_DIR/.warm.$$.tsv"
  if atuin history list --format '{command}\t{directory}\t{exit}\t{time}\t{session}' > "$tmp" 2>/dev/null; then
    local line cmd dir exit ts
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local oldifs=$IFS
      IFS=$'\t'; set -- ${=line}; IFS=$oldifs
      cmd="${1:-}" dir="${2:-}" exit="${3:-}" ts="${4:-}"
      if [[ -n "$ts" ]]; then
        ts=$(date -d "$ts" +%s 2>/dev/null) || ts=0
      else
        ts=0
      fi
      flow_pred_normalize "$cmd"
      cmd="$FLOW_PRED_RESULT"
      [[ -n "$cmd" ]] || continue
      _flow_pred_ingest_history_entry "$cmd" "$dir" "$exit" "$ts"
    done < "$tmp"
    rm -f "$tmp"
    _flow_pred_build_letter_index
  else
    rm -f "$tmp"
    return 1
  fi
  _fp_warm=1
  _fp_atuin_warmed=1
  (( FLOW_PRED_DEBUG )) && print -u2 "flow-predictor: warm index ready (${#_fp_cmd_stats} commands)" >>"${FLOW_PRED_DEBUG_LOG:-/dev/null}" 2>&1
  return 0
}

# Ingest one Atuin history entry into the in-memory index.
_flow_pred_ingest_history_entry() {
  local cmd="$1" dir="$2" exit_code="$3" ts="$4"
  local old
  old="${_fp_cmd_stats[$cmd]:-}"
  if [[ -z "$old" ]]; then
    _fp_cmd_stats[$cmd]="1 $([ "$exit_code" = 0 ] && echo 1 || echo 0) $([ "$exit_code" = 0 ] && echo 0 || echo 1) ${ts:-0} ${ts:-0}"
    _fp_hist_order+=("$cmd")
    flow_pred_classify "$cmd"; _fp_key_class[$cmd]="$FLOW_PRED_RESULT"
  else
    local count success fail last first
    set -- ${=old}
    count=$1 success=$2 fail=$3 last=$4 first=$5
    count=$((count + 1))
    if [ "$exit_code" = 0 ]; then success=$((success + 1)); else fail=$((fail + 1)); fi
    (( ts > last )) && last=$ts
    _fp_cmd_stats[$cmd]="$count $success $fail $last $first"
  fi
  if [[ -n "$dir" ]]; then
    local dkey="$dir:1:${ts:-0}"
    local existing="${_fp_key_dirs[$cmd]:-}"
    if [[ -n "$existing" ]]; then
      if [[ "$existing" == *",$dir:"* ]]; then
        # bump count for this dir
        local ndirs=""
        local d
        IFS=',' read -rA dlist <<< "$existing"
        for d in $dlist; do
          if [[ "${d%%:*}" == "$dir" ]]; then
            local dc="${d#*:}"; dc="${dc%%:*}"; dc=$((dc+1))
            local dl="${d#*:*}"; dl="${dl#*:}"
            ndirs+=",$dir:$dc:${ts:-0}"
          else
            ndirs+=",$d"
          fi
        done
        ndirs="${ndirs#,}"
        _fp_key_dirs[$cmd]="$ndirs"
      else
        _fp_key_dirs[$cmd]="$existing,$dkey"
      fi
    else
      _fp_key_dirs[$cmd]="$dkey"
    fi
  fi
}

# ── provider pipeline ───────────────────────────────────────────────────────
_flow_pred_register_provider() { _fp_providers+=("$1"); }

# history provider: prefix lookup through the letter index.
_flow_pred_provider_history() {
  local prefix="$1"
  local -a bucket keys
  if (( ${#prefix} >= 2 )); then
    bucket=(${(f)_fp_letter2[$prefix[1,2]]})
  else
    bucket=(${(f)_fp_letter[$prefix[1]]})
  fi
  keys=(${(M)${bucket}:#${prefix}*})
  local k
  for k in $keys; do
    _fp_pipeline_keys+=("$k")
    _fp_pipeline_src[$k]=history
  done
}

# transition provider: commands that follow the previous command.
_flow_pred_provider_transition() {
  local prefix="$1" k t
  [[ -n "$_fp_prev_cmd" ]] || return 0
  for k in "${(k)_fp_trans[@]}"; do
    if [[ "$k" == "${_fp_prev_cmd}"$'\x1f'* ]]; then
      local nxt="${k#*$'\x1f'}"
      [[ "$nxt" == "$prefix"* ]] || continue
      _fp_pipeline_keys+=("$nxt")
      _fp_pipeline_src[$nxt]=transition
    fi
  done
}

# workflow provider: c3 completing the last two commands (A -> B -> C).
_flow_pred_provider_workflow() {
  local prefix="$1" k c3
  local n=${#_fp_session_seq}
  (( n >= 2 )) || return 0
  local c1="${_fp_session_seq[$((n-1))]}"
  local c2="${_fp_session_seq[$n]}"
  [[ -n "$c1" && -n "$c2" ]] || return 0
  for k in "${(k)_fp_workflow[@]}"; do
    if [[ "$k" == "$c1"$'\x1f'"$c2"$'\x1f'* ]]; then
      c3="${k#*$'\x1f'$'\x1f'}"
      [[ "$c3" == "$prefix"* ]] || continue
      _fp_pipeline_keys+=("$c3")
      _fp_pipeline_src[$c3]=workflow
    fi
  done
}

# recovery provider: commands run after a failed command.
_flow_pred_provider_recovery() {
  local prefix="$1" k r
  [[ -n "$_fp_prev_cmd" ]] || return 0
  for k in "${(k)_fp_recovery}"; do
    if [[ "$k" == "${_fp_prev_cmd}"$'\x1f'* ]]; then
      r="${k#*$'\x1f'}"
      [[ "$r" == "$prefix"* ]] || continue
      _fp_pipeline_keys+=("$r")
      _fp_pipeline_src[$r]=recovery
    fi
  done
}

# session provider: this session's recent commands.
_flow_pred_provider_session() {
  local prefix="$1" k
  local n=${#_fp_session_seq}
  local i
  for (( i = n; i >= 1 && i > n - 10; i-- )); do
    k="${_fp_session_seq[$i]}"
    [[ "$k" == "$prefix"* ]] || continue
    _fp_pipeline_keys+=("$k")
    _fp_pipeline_src[$k]=session
  done
}

# completion provider: native command-name completion (no spaces in prefix).
_flow_pred_provider_completion() {
  local prefix="$1"
  [[ "$prefix" == *" "* ]] && return 0
  local c
  for c in ${(o)commands[(I)${prefix}*]}; do
    _fp_pipeline_keys+=("$c")
    _fp_pipeline_src[$c]=completion
  done
}

# register providers in ranking-priority order
_flow_pred_register_provider _flow_pred_provider_history
_flow_pred_register_provider _flow_pred_provider_transition
_flow_pred_register_provider _flow_pred_provider_workflow
_flow_pred_register_provider _flow_pred_provider_recovery
_flow_pred_register_provider _flow_pred_provider_session
_flow_pred_register_provider _flow_pred_provider_completion

# ── prediction ──────────────────────────────────────────────────────────────
# Generates ranked candidates for a typed prefix. Sets:
#   _fp_result         = best command (empty if none)
#   _fp_result_score   = score of best
#   _fp_results        = array of "score\tkey" sorted desc
#   _fp_result_src     = array parallel to _fp_results with source tags
#   _fp_result_meta    = array parallel with metadata strings
_flow_pred_predict() {
  local prefix="$1"
  _fp_result="" _fp_result_score=0
  _fp_results=() _fp_result_src=() _fp_result_meta=() _fp_result_explain=()
  [[ -n "$prefix" ]] || return 0

  if (( ! _fp_warm )); then
    # lightweight fallback: recent history from fc
    local line
    for line in ${(f)"$(fc -l -n -1 40 2>/dev/null)"}; do
      flow_pred_normalize "$line"; line="$FLOW_PRED_RESULT"
      [[ "$line" == "$prefix"* ]] || continue
      _fp_results+=("0	$line")
      _fp_result_src+=(history)
      _fp_result_meta+=("recent")
      _fp_result_explain+=("recent_history")
    done
    (( ${#_fp_results} )) || return 0
    _fp_result="${_fp_results[1]#*$'\t'}"
    return 0
  fi

  _fp_pipeline_keys=()
  typeset -gA _fp_pipeline_src=()
  local f
  for f in "${_fp_providers[@]}"; do
    $f "$prefix"
  done

  # deduplicate
  typeset -gA _fp_seen=()
  local k
  for k in "${_fp_pipeline_keys[@]}"; do
    (( ${_fp_seen[$k]:-0} )) && continue
    _fp_seen[$k]=1
    local stats="${_fp_cmd_stats[$k]:-}"
    [[ -n "$stats" ]] || { _fp_cmd_stats[$k]="1 1 0 0 0"; stats="1 1 0 0 0"; }
    local -a stat_parts=(${(z)stats})
    local count=$stat_parts[1] success=$stat_parts[2] fail=$stat_parts[3] last=$stat_parts[4] first=$stat_parts[5]
    local dirs="${_fp_key_dirs[$k]:-}"
    local cls="${_fp_key_class[$k]:-other}"

    # look up transition/workflow/recovery counts for this candidate
    local tcnt=0 tsuc=0 wcnt=0 wsuc=0 rcnt=0
    if [[ -n "$_fp_prev_cmd" ]]; then
      local tval="${_fp_trans[${_fp_prev_cmd}$'\x1f'$k]:-}"
      if [[ -n "$tval" ]]; then
        set -- ${=tval}; tcnt=$1; tsuc=$2
      fi
      local rval="${_fp_recovery[${_fp_prev_cmd}$'\x1f'$k]:-}"
      [[ -n "$rval" ]] && { set -- ${=rval}; rcnt=$1; }
    fi
    if (( ${#_fp_session_seq} >= 2 )); then
      local c1="${_fp_session_seq[$((${#_fp_session_seq}-1))]}"
      local c2="${_fp_session_seq[${#_fp_session_seq}]}"
      local wval="${_fp_workflow[$c1$'\x1f'$c2$'\x1f'$k]:-}"
      [[ -n "$wval" ]] && { set -- ${=wval}; wcnt=$1; wsuc=$2; }
    fi

    _flow_pred_context
    flow_pred_score_fast "$k" "$count" "$success" "$fail" "$last" "$first" "$dirs" "$cls" "$prefix" "$FLOW_PRED_CONTEXT" "$tcnt" "$tsuc" "$wcnt" "$wsuc" "$rcnt"
    (( FLOW_PRED_MATCH )) || continue
    _fp_results+=("$FLOW_PRED_SCORE	$k")
    _fp_result_src+=("${_fp_pipeline_src[$k]}")
    _fp_result_meta+=("$count $success $fail $last $first")
    _fp_result_explain+=("${FLOW_PRED_EXPLAIN:-}")
  done
  unset _fp_pipeline_src _fp_seen

  (( ${#_fp_results} )) || return 0
  # sort desc by score
  _fp_results=(${(nO)_fp_results})
  _fp_result="${_fp_results[1]#*$'\t'}"
  _fp_result_score="${_fp_results[1]%%$'\t'*}"
  # cap for HUD
  if (( ${#_fp_results} > FLOW_PRED_HUD_MAX )); then
    _fp_results=("${(@)_fp_results[1,FLOW_PRED_HUD_MAX]}")
    _fp_result_src=("${(@)_fp_result_src[1,FLOW_PRED_HUD_MAX]}")
    _fp_result_meta=("${(@)_fp_result_meta[1,FLOW_PRED_HUD_MAX]}")
    _fp_result_explain=("${(@)_fp_result_explain[1,FLOW_PRED_HUD_MAX]}")
  fi
  return 0
}

# ── ghost rendering (POSTDISPLAY pattern, like zsh-autosuggestions) ──────────
# Ghost state
typeset -g _fp_ghost_suggestion=""   # The full suggested command
typeset -g _fp_ghost_postdisplay=""  # The suffix to show (POSTDISPLAY)
typeset -g _fp_ghost_active=0
typeset -g _fp_ghost_score=0

# Clear ghost: reset POSTDISPLAY and highlight
_flow_pred_ghost_clear() {
  if (( _fp_ghost_active )); then
    _fp_ghost_active=0
    _fp_ghost_suggestion=""
    _fp_ghost_postdisplay=""
    _fp_ghost_score=0
    POSTDISPLAY=""
    _flow_pred_highlight_reset
  fi
}

# Reset highlight (like zsh-autosuggestions)
_flow_pred_highlight_reset() {
  typeset -g _fp_ghost_highlight
  if [[ -n "$_fp_ghost_highlight" ]]; then
    region_highlight=("${(@)region_highlight:#$_fp_ghost_highlight}")
    unset _fp_ghost_highlight
  fi
}

# Apply ghost highlight — dim text, same style as active command but muted
_flow_pred_highlight_apply() {
  typeset -g _fp_ghost_highlight
  if (( _fp_ghost_active )) && [[ -n "$_fp_ghost_postdisplay" ]]; then
    # fg=245 (muted gray) — dim like autosuggestions, no bold/standout
    _fp_ghost_highlight="$#BUFFER $(($#BUFFER + $#_fp_ghost_postdisplay)) fg=245"
    region_highlight+=("$_fp_ghost_highlight")
  else
    unset _fp_ghost_highlight
  fi
}

# Fetch suggestion for current buffer (async-safe, called from widget wrappers)
_flow_pred_fetch_suggestion() {
  local buf="$1"
  (( FLOW_PRED_GHOST_ENABLED )) || return 0
  (( ${#buf} )) || { _flow_pred_ghost_clear; return 0 }

  # Use cache if buffer unchanged and high confidence
  if [[ "$buf" == "$_fp_last_typed" && -n "$_fp_last_result" ]]; then
    if (( _fp_last_score >= FLOW_PRED_CONF_HIGH )); then
      _fp_result="$_fp_last_result"
      _fp_result_score="$_fp_last_score"
      _fp_results=("${(@)_fp_last_results[@]}")
      _fp_result_src=("${(@)_fp_last_result_src[@]}")
      _fp_result_meta=("${(@)_fp_last_result_meta[@]}")
      _fp_result_explain=("${(@)_fp_last_result_explain[@]}")
    else
      _flow_pred_ghost_clear
      return 0
    fi
  else
    _flow_pred_predict "$buf"
    _fp_last_typed="$buf"
    _fp_last_result="$_fp_result"
    _fp_last_score="$_fp_result_score"
    _fp_last_result_count=${#_fp_results}
    _fp_last_results=("${(@)_fp_results[@]}")
    _fp_last_result_src=("${(@)_fp_result_src[@]}")
    _fp_last_result_meta=("${(@)_fp_result_meta[@]}")
    _fp_last_result_explain=("${(@)_fp_result_explain[@]}")
  fi

  # Confidence gate
  if (( _fp_result_score < FLOW_PRED_CONF_HIGH )); then
    _flow_pred_ghost_clear
    return 0
  fi

  if [[ -n "$_fp_result" && "$_fp_result" != "$buf" ]]; then
    _fp_ghost_suggestion="$_fp_result"
    _fp_ghost_postdisplay="${_fp_result#${buf}}"
    _fp_ghost_score="$_fp_result_score"
    _fp_ghost_active=1
    POSTDISPLAY="$_fp_ghost_postdisplay"
    _flow_pred_highlight_apply
  else
    _flow_pred_ghost_clear
  fi
}

# on_redraw: safety net only (re-apply POSTDISPLAY if cleared externally)
_flow_pred_on_redraw() {
  (( FLOW_PRED_GHOST_ENABLED )) || return 0
  # Never show ghost on empty buffer
  if (( ${#BUFFER} == 0 )); then
    (( _fp_ghost_active )) && _flow_pred_ghost_clear
    return 0
  fi
  # If ghost was active but POSTDISPLAY got cleared (e.g., by another plugin),
  # re-apply it. This is a safety net, not the primary path.
  if (( _fp_ghost_active )) && [[ -z "$POSTDISPLAY" && -n "$_fp_ghost_postdisplay" ]]; then
    POSTDISPLAY="$_fp_ghost_postdisplay"
    _flow_pred_highlight_apply
  fi
}

# ── ghost acceptance ────────────────────────────────────────────────────────
_flow_pred_accept_ghost() {
  if (( _fp_ghost_active )); then
    BUFFER="$_fp_ghost_suggestion"
    CURSOR=${#BUFFER}
    _flow_pred_ghost_clear
    _fp_last_typed="$BUFFER"
    _fp_last_result=""
    return 0
  fi
  return 1
}

_flow_pred_accept_token() {
  if (( _fp_ghost_active )); then
    local ghost="$_fp_ghost_postdisplay"
    local token="${ghost%% *}"
    local rest="${ghost#* }"
    _flow_pred_ghost_clear
    BUFFER+="$token"
    if [[ -n "$rest" ]]; then
      _fp_ghost_suggestion="${_fp_ghost_suggestion}"
      _fp_ghost_postdisplay="$rest"
      _fp_ghost_active=1
      POSTDISPLAY=" $_fp_ghost_postdisplay"
      _flow_pred_highlight_apply
    fi
    CURSOR=${#BUFFER}
    _fp_last_typed="$BUFFER"
    _fp_last_result=""
    return 0
  fi
  return 1
}

# ── widget wrappers (clear ghost BEFORE mutation, fetch AFTER) ──────────────
_flow_pred_wrap_widget() {
  local w=$1
  local orig="_flow_pred_orig_$w"
  if (( ! ${+functions[$orig]} )); then
    zle -A "$w" "$orig" 2>/dev/null
    eval "_flow_pred_g_$w() {
      _flow_pred_ghost_clear
      zle $orig
      _flow_pred_fetch_suggestion \"\$BUFFER\"
    }"
    zle -N "$w" "_flow_pred_g_$w" 2>/dev/null
  fi
}

# accept-line wrapper: clear ghost only when called directly (not from
# within another widget like gst/dbg).
_flow_pred_g_accept-line() {
  if (( $WIDGET == accept-line )); then
    _flow_pred_ghost_clear
  fi
  zle .accept-line
}
zle -N accept-line _flow_pred_g_accept-line

for w in self-insert backward-delete-char delete-char backward-kill-word kill-word backward-word forward-word beginning-of-line end-of-line forward-char backward-char undo redo yank yank-pop clear-screen delete-char-or-list quoted-insert; do
  (( ${+widgets[$w]} )) && _flow_pred_wrap_widget "$w"
done

# ── HUD (IRIS-inspired design) ─────────────────────────────────────────────
#
# Key design decisions (learned from IRIS, zsh-autocomplete, fzf-tab):
#
# 1. RAW ANSI escape codes for rendering — NO ${(%):-} prompt expansion in the
#    render loop. That was the root cause of hangs: prompt expansion is slow
#    and can recurse into ZLE callbacks.
#
# 2. Simple keymap delegation: flowhud keymap handles ONLY arrow/scroll/accept
#    keys. Everything else closes HUD and re-dispatches via main keymap.
#    No complex widget-forwarding — that was the crash source.
#
# 3. _fp_hud_rendering flag prevents re-entrant renders from rapid keypresses.
#
# 4. IRIS color palette for a modern editor-like look:
#    border: #a277ff (purple), accent: #61ffca (green), muted: #6d6a7f,
#    text: #edecee, sel_bg: #3d375e, ghost: #4b4a4c

_flow_pred_hud_open() {
  if (( _fp_hud_active )); then
    _flow_pred_hud_close
  fi
  local prefix="$BUFFER"
  if [[ "$prefix" == "$_fp_last_typed" && ${#_fp_last_results} -gt 0 ]]; then
    _fp_results=("${(@)_fp_last_results[@]}")
    _fp_result_src=("${(@)_fp_last_result_src[@]}")
    _fp_result_meta=("${(@)_fp_last_result_meta[@]}")
    _fp_result_explain=("${(@)_fp_last_result_explain[@]}")
    _fp_result="$_fp_last_result"
    _fp_result_score="$_fp_last_score"
  else
    _flow_pred_predict "$prefix"
    _fp_last_typed="$prefix"
    _fp_last_result="$_fp_result"
    _fp_last_score="$_fp_result_score"
    _fp_last_result_count=${#_fp_results}
    _fp_last_results=("${(@)_fp_results[@]}")
    _fp_last_result_src=("${(@)_fp_result_src[@]}")
    _fp_last_result_meta=("${(@)_fp_result_meta[@]}")
    _fp_last_result_explain=("${(@)_fp_result_explain[@]}")
  fi
  (( ${#_fp_results} )) || { zle -M "Flow: no suggestions for '$prefix'"; return 1 }
  _flow_pred_ghost_clear
  _fp_hud_cands=() _fp_hud_desc=() _fp_hud_src=()

  local is_recovery=0
  if (( _fp_prev_status != 0 && ${#_fp_prev_cmd} > 0 )); then
    is_recovery=1
  fi

  local r score key src meta count success fail last expl
  local i
  for (( i = 1; i <= ${#_fp_results}; i++ )); do
    r="${_fp_results[$i]}"
    score="${r%%$'\t'*}"
    key="${r#*$'\t'}"
    src="${_fp_result_src[$i]}"
    meta="${_fp_result_meta[$i]}"
    expl="${_fp_result_explain[$i]}"

    set -- ${=${(s. .)meta}}
    count="${1:-0}" success="${2:-0}" fail="${3:-0}" last="${4:-0}"

    local reasons=""
    if [[ -n "$expl" ]]; then
      [[ "$expl" == *"dir_match"* ]] && reasons+="here"
      [[ "$expl" == *"parent_dir_match"* ]] && reasons+="subtree"
      [[ "$expl" == *"profile_match"* ]] && reasons+="profile"
      [[ "$expl" == *"workspace_match"* ]] && reasons+="workspace"
      [[ "$expl" == *"project_match"* ]] && reasons+="project"
      [[ "$expl" == *"runtime_match"* ]] && reasons+="runtime"
      [[ "$expl" == *"session_match"* ]] && reasons+="session"
      [[ "$expl" == *"follows_prev"* ]] && reasons+="follows ${_fp_prev_cmd:0:15}"
      [[ "$expl" == *"workflow_step"* ]] && reasons+="workflow"
      [[ "$expl" == *"recovery_candidate"* ]] && reasons+="recovery"
      [[ "$expl" == *"high_failure_rate"* ]] && reasons+="high fail"
    fi

    local desc=""
    if (( count > 0 )); then
      desc+="${count}×"
      if (( (success + fail) > 0 )); then
        local pct=$(( success * 100 / (success + fail) ))
        (( pct < 100 )) && desc+=" ${pct}%"
      fi
      if (( last > 0 )); then
        local ago=$(( EPOCHSECONDS - last ))
        if (( ago < 60 )); then desc+=" · now"
        elif (( ago < 3600 )); then desc+=" · $(( ago / 60 ))m"
        elif (( ago < 86400 )); then desc+=" · $(( ago / 3600 ))h"
        else desc+=" · $(( ago / 86400 ))d"
        fi
      fi
      [[ -n "$reasons" ]] && desc+=" · ${reasons}"
    fi
    _fp_hud_cands+=("$key")
    _fp_hud_desc+=("$desc")
    _fp_hud_src+=("$src")
  done
  _fp_hud_active=1
  _fp_hud_sel=0
  _fp_hud_offset=0
  _fp_hud_is_recovery=$is_recovery
  _flow_pred_hud_render
  zle -K flowhud
  return 0
}

_flow_pred_hud_render() {
  (( _fp_hud_active )) || return 0
  (( _fp_hud_rendering )) && return 0
  _fp_hud_rendering=1

  local n=${#_fp_hud_cands}
  if (( n == 0 )); then
    _fp_hud_rendering=0
    _flow_pred_hud_close
    return 0
  fi

  local max_visible=$(( LINES - 3 ))
  (( max_visible > 12 )) && max_visible=12
  (( max_visible < 3 )) && max_visible=3

  # Clamp offset
  local bottom=$(( _fp_hud_offset + max_visible ))
  (( _fp_hud_sel >= bottom )) && _fp_hud_offset=$(( _fp_hud_sel - max_visible + 1 ))
  (( _fp_hud_sel < _fp_hud_offset )) && _fp_hud_offset=$_fp_hud_sel
  (( _fp_hud_offset < 0 )) && _fp_hud_offset=0

  # ── IRIS-inspired color palette (ANSI 256) ──
  local RST=$'\e[0m'
  local ACC=$'\e[38;5;114m'    # accent green  #61ffca
  local DIM=$'\e[38;5;242m'    # dim gray      #6d6a7f
  local TXT=$'\e[38;5;255m'    # bright text   #edecee
  local SEL=$'\e[38;5;231m'    # sel text      #ffffff
  local SBG=$'\e[48;5;61m'     # sel bg        #3d375e
  local BRD=$'\e[38;5;141m'    # border purple #a277ff
  local DSC=$'\e[38;5;246m'    # desc gray     #9692a8
  local GRH=$'\e[38;5;75m'     # ghost teal    #4B4A4C

  # ── Header ──
  local label="Flow"
  [[ "$_fp_hud_is_recovery" == "1" ]] && label=" Flow recovery"
  local header=" ${BRD}──${RST} ${ACC}${label}${RST} ${DIM}${n} results${RST}"
  if (( n > max_visible )); then
    local page_top=$(( _fp_hud_offset + 1 ))
    local page_bot=$(( _fp_hud_offset + max_visible ))
    (( page_bot > n )) && page_bot=$n
    header+=" ${DIM}${page_top}-${page_bot}/${n}${RST}"
  fi
  header+=" ${BRD}─${RST}"

  # ── Candidate lines ──
  local -a lines=()
  local i idx
  for (( i = 0; i < max_visible && _fp_hud_offset + i < n; i++ )); do
    idx=$(( _fp_hud_offset + i + 1 ))
    local cand="${_fp_hud_cands[$idx]}"
    local desc="${_fp_hud_desc[$idx]}"
    local line=""
    if (( idx - 1 == _fp_hud_sel )); then
      # Selected: highlight bar like IRIS sel_bg
      line="${SBG}${SEL} ${cand} ${RST}${DSC} ${desc}${RST}"
    else
      line=" ${TXT}${cand} ${RST}${DSC} ${desc}${RST}"
    fi
    lines+=("$line")
  done

  # ── Footer hint ──
  lines+=(" ${DIM}↑↓ navigate  Tab/Enter accept  Esc close${RST}")

  zle -R "$header" "${lines[@]}"
  _fp_hud_rendering=0
}

_flow_pred_hud_close() {
  _fp_hud_active=0
  _fp_hud_cands=() _fp_hud_desc=() _fp_hud_src=()
  _fp_hud_sel=0 _fp_hud_offset=0
  _fp_hud_rendering=0
  zle -K main 2>/dev/null
  zle -R 2>/dev/null
}

_flow_pred_hud_up() {
  (( _fp_hud_active )) || return 0
  (( _fp_hud_sel > 0 )) && _fp_hud_sel=$(( _fp_hud_sel - 1 ))
  (( _fp_hud_sel < _fp_hud_offset )) && _fp_hud_offset=$_fp_hud_sel
  _flow_pred_hud_render
}

_flow_pred_hud_down() {
  (( _fp_hud_active )) || return 0
  local n=${#_fp_hud_cands}
  (( _fp_hud_sel + 1 < n )) && _fp_hud_sel=$(( _fp_hud_sel + 1 ))
  local max_visible=$(( LINES - 3 ))
  (( max_visible > 12 )) && max_visible=12
  (( max_visible < 3 )) && max_visible=3
  (( _fp_hud_sel >= _fp_hud_offset + max_visible )) && _fp_hud_offset=$(( _fp_hud_sel - max_visible + 1 ))
  _flow_pred_hud_render
}

_flow_pred_hud_pgup() {
  (( _fp_hud_active )) || return 0
  local step=$(( LINES - 3 ))
  (( step > 12 )) && step=12
  (( step < 1 )) && step=1
  _fp_hud_sel=$(( _fp_hud_sel - step ))
  (( _fp_hud_sel < 0 )) && _fp_hud_sel=0
  _fp_hud_offset=$_fp_hud_sel
  _flow_pred_hud_render
}

_flow_pred_hud_pgdn() {
  (( _fp_hud_active )) || return 0
  local n=${#_fp_hud_cands}
  local step=$(( LINES - 3 ))
  (( step > 12 )) && step=12
  (( step < 1 )) && step=1
  _fp_hud_sel=$(( _fp_hud_sel + step ))
  (( _fp_hud_sel >= n )) && _fp_hud_sel=$(( n - 1 ))
  local max_visible=$(( LINES - 3 ))
  (( max_visible > 12 )) && max_visible=12
  (( _fp_hud_sel >= _fp_hud_offset + max_visible )) && _fp_hud_offset=$(( _fp_hud_sel - max_visible + 1 ))
  (( _fp_hud_offset < 0 )) && _fp_hud_offset=0
  _flow_pred_hud_render
}

_flow_pred_hud_accept() {
  (( _fp_hud_active )) || return 0
  if (( ${#_fp_hud_cands} > 0 )); then
    BUFFER="${_fp_hud_cands[$((_fp_hud_sel + 1))]}"
    CURSOR=${#BUFFER}
    _fp_last_typed="$BUFFER" _fp_last_result=""
  fi
  _flow_pred_hud_close
}

_flow_pred_hud_delegate() {
  # SAFEST approach: close HUD, then look up the widget and call it.
  # We do NOT try to handle the key ourselves — just pass it through.
  _fp_hud_active=0
  _fp_hud_rendering=0
  zle -K main 2>/dev/null
  zle -R 2>/dev/null
  _fp_hud_cands=() _fp_hud_desc=() _fp_hud_src=()
  # Try to dispatch the key to its normal main-keymap widget
  local w
  w="${$(bindkey -M main "$KEYS" 2>/dev/null)//\"/}"
  if [[ -n "$w" && "$w" != "undefined-key" && "$w" != "-"* ]] && (( ${+widgets[$w]} )); then
    zle "$w" 2>/dev/null
  fi
}

# ── flowhud keymap ──
bindkey -N flowhud 2>/dev/null
zle -N _flow_pred_hud_delegate
bindkey -M flowhud '^['       _flow_pred_hud_close
bindkey -M flowhud '^M'       _flow_pred_hud_accept
bindkey -M flowhud '^J'       _flow_pred_hud_accept
bindkey -M flowhud '^I'       _flow_pred_hud_accept
bindkey -M flowhud '^G'       _flow_pred_hud_close
bindkey -M flowhud '\e[A'     _flow_pred_hud_up
bindkey -M flowhud '\e[B'     _flow_pred_hud_down
bindkey -M flowhud '\e[5~'    _flow_pred_hud_pgup
bindkey -M flowhud '\e[6~'    _flow_pred_hud_pgdn
bindkey -M flowhud -R " -~"   _flow_pred_hud_delegate
bindkey -M flowhud -R "\x00-\x1f" _flow_pred_hud_delegate

# ── main keymap widgets ─────────────────────────────────────────────────────
_flow_pred_up() {
  (( _fp_hud_active )) && { _flow_pred_hud_up; return }
  if (( ${#BUFFER} > 0 )); then
    zle history-search-backward
  else
    zle up-line-or-history
  fi
}

_flow_pred_down() {
  (( _fp_hud_active )) && { _flow_pred_hud_down; return }
  if (( _fp_warm )); then
    _flow_pred_hud_open
  else
    zle down-line-or-history
  fi
}

# ── key bindings ────────────────────────────────────────────────────────────
zle -N _flow_pred_accept_ghost
zle -N _flow_pred_accept_token
zle -N _flow_pred_hud_open
zle -N _flow_pred_up
zle -N _flow_pred_down
zle -N _flow_pred_hud_up
zle -N _flow_pred_hud_down
zle -N _flow_pred_hud_pgup
zle -N _flow_pred_hud_pgdn
zle -N _flow_pred_hud_accept
zle -N _flow_pred_hud_close

# ghost acceptance: Right, End, Ctrl+F (token), Ctrl+Right (word), Meta+P opens the HUD
zle -N _flow_pred_accept_ghost
zle -N _flow_pred_accept_token
zle -N _flow_pred_accept_word
bindkey "\e[C" _flow_pred_accept_ghost
bindkey "\e[F" _flow_pred_accept_ghost
bindkey "\C-f" _flow_pred_accept_token
bindkey "\e[1;5C" _flow_pred_accept_word   # Ctrl+Right: accept word
bindkey "\M-p" _flow_pred_hud_open       # Meta+P
bindkey "\M-P" _flow_pred_hud_open       # Meta+Shift+P

# Up/Down: Flow HUD navigation (Alt+Up/Alt+Down in HUD, regular Up/Down elsewhere)
# Regular Up: prefix history search (or recent history if empty)
# Regular Down: always open HUD
bindkey "\e[A" _flow_pred_up              # Up arrow
bindkey "\e[B" _flow_pred_down            # Down arrow
bindkey "\e[1;3A" _flow_pred_up          # Alt+Up (same as Up)
bindkey "\e[1;3B" _flow_pred_down        # Alt+Down (same as Down)

# ── continuous learning ─────────────────────────────────────────────────────
_flow_pred_preexec() {
  _flow_pred_ghost_clear
  flow_pred_normalize "$1"
  _fp_prev_prev_cmd="$_fp_prev_cmd"
  _fp_prev_cmd="$FLOW_PRED_RESULT"
  _fp_prev_status="$_fp_last_status"
}

_flow_pred_precmd() {
  local last_status=$?
  local cur="$_fp_prev_cmd" prev="$_fp_prev_prev_cmd"
  if [[ -n "$cur" ]]; then
    _fp_session_seq+=("$cur")
    # cmd stats
    local old="${_fp_cmd_stats[$cur]:-}"
    local count success fail last first
    if [[ -z "$old" ]]; then
      _fp_cmd_stats[$cur]="1 $([ $last_status -eq 0 ] && echo 1 || echo 0) $([ $last_status -eq 0 ] && echo 0 || echo 1) $EPOCHSECONDS $EPOCHSECONDS"
      _fp_hist_order+=("$cur")
      flow_pred_classify "$cur"; _fp_key_class[$cur]="$FLOW_PRED_RESULT"
    else
      set -- ${=old}
      count=$1 success=$2 fail=$3 last=$4 first=$5
      count=$((count + 1))
      if [ $last_status -eq 0 ]; then success=$((success + 1)); else fail=$((fail + 1)); fi
      _fp_cmd_stats[$cur]="$count $success $fail $EPOCHSECONDS $first"
    fi
    # dir entry
    local dkey="$PWD:1:$EPOCHSECONDS"
    local existing="${_fp_key_dirs[$cur]:-}"
    if [[ -n "$existing" ]]; then
      _fp_key_dirs[$cur]="$existing,$dkey"
    else
      _fp_key_dirs[$cur]="$dkey"
    fi
    # transition prev -> cur
    if [[ -n "$prev" ]]; then
      local tkey="$prev"$'\x1f'"$cur"
      local to="${_fp_trans[$tkey]:-}"
      if [[ -z "$to" ]]; then
        _fp_trans[$tkey]="1 $([ $last_status -eq 0 ] && echo 1 || echo 0) $EPOCHSECONDS"
      else
        set -- ${=to}
        local tc=$1 ts=$2 tl=$3
        tc=$((tc + 1))
        if [ $last_status -eq 0 ]; then ts=$((ts + 1)); fi
        _fp_trans[$tkey]="$tc $ts $EPOCHSECONDS"
      fi
      # recovery: previous command failed -> current is a recovery
      if (( _fp_prev_status != 0 )); then
        local rkey="$prev"$'\x1f'"$cur"
        local ro="${_fp_recovery[$rkey]:-}"
        if [[ -z "$ro" ]]; then
          _fp_recovery[$rkey]="1 0 $EPOCHSECONDS"
        else
          set -- ${=ro}
          local rc=$1 rs=$2 rl=$3
          rc=$((rc + 1))
          if [ $last_status -eq 0 ]; then rs=$((rs + 1)); fi
          _fp_recovery[$rkey]="$rc $rs $EPOCHSECONDS"
        fi
      fi
      # workflow: last three commands
      local n=${#_fp_session_seq}
      if (( n >= 3 )); then
        local c1="${_fp_session_seq[$((n-2))]}"
        local c2="${_fp_session_seq[$((n-1))]}"
        local c3="$cur"
        local wkey="$c1"$'\x1f'"$c2"$'\x1f'"$c3"
        local wo="${_fp_workflow[$wkey]:-}"
        if [[ -z "$wo" ]]; then
          _fp_workflow[$wkey]="1 $([ $last_status -eq 0 ] && echo 1 || echo 0) $EPOCHSECONDS"
        else
          set -- ${=wo}
          local wc=$1 ws=$2 wl=$3
          wc=$((wc + 1))
          if [ $last_status -eq 0 ]; then ws=$((ws + 1)); fi
          _fp_workflow[$wkey]="$wc $ws $EPOCHSECONDS"
        fi
      fi
    fi
    _fp_last_status=$last_status
    _flow_pred_save_if_due
  fi
}

_flow_pred_save_if_due() {
  local now=$EPOCHSECONDS
  (( now - _fp_last_save_ts < FLOW_PRED_SAVE_DEBOUNCE )) && return 0
  _fp_last_save_ts=$now
  local tmp="$FLOW_PRED_STATE_DIR/.save.$$.tsv"
  {
    flow_pred_agg_header
    local k
      for k in "${(k)_fp_cmd_stats[@]}"; do
      printf 'C\t%s\t%s\t%s\t%s\n' "$k" "${_fp_cmd_stats[$k]}" "${_fp_key_dirs[$k]}" "${_fp_key_class[$k]}"
    done
    for k in "${(k)_fp_trans[@]}"; do
      printf 'T\t%s\t%s\n' "$k" "${_fp_trans[$k]}"
    done
    for k in "${(k)_fp_workflow[@]}"; do
      printf 'W\t%s\t%s\n' "$k" "${_fp_workflow[$k]}"
    done
      for k in "${(k)_fp_recovery[@]}"; do
      printf 'R\t%s\t%s\n' "$k" "${_fp_recovery[$k]}"
    done
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$FLOW_PRED_AGGREGATES" || rm -f "$tmp"
}

add-zsh-hook preexec _flow_pred_preexec
add-zsh-hook precmd _flow_pred_precmd
add-zle-hook-widget zle-line-pre-redraw _flow_pred_on_redraw

# lazy atuin enrichment after the first prompt
_flow_pred_warmup() {
  add-zsh-hook -d precmd _flow_pred_warmup
  # Run atuin warm-up in background so prompt appears instantly.
  # Suppress job monitoring notice [1] <PID> and completion notice [1] done.
  {
    setopt LOCAL_OPTIONS NO_MONITOR NO_NOTIFY
    {
      local log="${FLOW_PRED_DEBUG_LOG:-/dev/null}"
      (( FLOW_PRED_DEBUG )) && print -u2 "flow-predictor: atuin warmup starting" >>"$log" 2>&1
      _flow_pred_warm_from_atuin
      (( FLOW_PRED_DEBUG )) && print -u2 "flow-predictor: warm index ready (${#_fp_cmd_stats} commands)" >>"$log" 2>&1
    } &
    disown
  } 2>/dev/null
}
add-zsh-hook precmd _flow_pred_warmup

# ── CLI helpers for `flow suggest` ─────────────────────────────────────────
# `flow suggest [prefix] [--json]` is implemented by sdata/cli/lib/suggest.sh
# which sources this engine for its pure logic. The live ZLE state (in-memory
# index) is not visible to the CLI; the CLI rebuilds from the persisted
# aggregates, which is sufficient for offline debugging.

# _flow_pred_query: compute a fresh prediction for the current BUFFER.
# Sets _fp_ghost, _fp_ghost_cmd, _fp_ghost_active. Safe to call from any
# widget context; does NOT modify RBUFFER or region_highlight.
# Also updates _fp_last_typed/_fp_last_result so the redraw hook's cache
# path does not overwrite the fresh result with stale data.
_flow_pred_query() {
  local buf="${1:-$LBUFFER}"
  [[ -n "$buf" ]] || { _fp_ghost=""; _fp_ghost_cmd=""; _fp_ghost_active=0; return 0; }
  _flow_pred_predict "$buf"
  _fp_last_typed="$buf"
  _fp_last_result="$_fp_result"
  _fp_last_score="$_fp_result_score"
  # Confidence gate: only activate ghost for high-confidence predictions
  if (( _fp_result_score >= FLOW_PRED_CONF_HIGH )); then
    if [[ -n "$_fp_result" && "$_fp_result" != "$buf" ]]; then
      _fp_ghost_cmd="$_fp_result"
      _fp_ghost_typed="$buf"
      _fp_ghost="${_fp_result#${buf}}"
      _fp_ghost_active=1
    else
      _fp_ghost=""
      _fp_ghost_cmd=""
      _fp_ghost_active=0
    fi
  else
    _fp_ghost=""
    _fp_ghost_cmd=""
    _fp_ghost_active=0
  fi
}

# debug snapshot command for the shell user
flow_pred_debug() {
  _flow_pred_predict "${1:-}"
  flow_pred_confidence "$_fp_result_score"
  local conf="$FLOW_PRED_RESULT"
  print -r -- "warm=$_fp_warm commands=${#_fp_cmd_stats} transitions=${#_fp_trans} workflows=${#_fp_workflow} recoveries=${#_fp_recovery}"
  print -r -- "context: $FLOW_PRED_CONTEXT"
  print -r -- "best: [$_fp_result] score=$_fp_result_score confidence=$conf"
  if (( ${#_fp_results} )); then
    local i r
    for (( i = 1; i <= ${#_fp_results}; i++ )); do
      r="${_fp_results[$i]}"
      local sc="${r%%$'\t'*}" ky="${r#*$'\t'}" expl="${_fp_result_explain[$i]:-}"
      print -r -- "  $i: $ky  score=$sc  [${_fp_result_src[$i]}]  ($expl)"
    done
  else
    print -r -- "  (no suggestions)"
  fi
}
