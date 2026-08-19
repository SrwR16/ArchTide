# 45-flow-editor.zsh — Flow native command-line editor
# A clean, modular ZLE editing layer on the Ctrl+Shift namespace.
# Built only from native ZLE primitives: BUFFER, CURSOR, MARK, REGION_ACTIVE
# and native widgets. No plugins, no external dependencies.
#
# Key delivery: kitty sends these in its DEFAULT (legacy) encoding; the
# keyboard protocol is intentionally NOT enabled (would re-encode every
# Ctrl/Alt key and require remapping all of them):
#   Shift+Left/Right            ->  ESC [ 1 ; 2 D / C
#   Ctrl+Shift+Left/Right       ->  ESC [ 1 ; 6 D / C
#   Ctrl+Shift+Home/End         ->  ESC [ 1 ; 6 H / F
#   Ctrl+Shift+<letter>         ->  ESC [ <code> ; 6 u   (code = lowercase ASCII)
# kitty.conf releases Ctrl+Shift+C / Ctrl+Shift+V (kitty's own copy/paste)
# by mapping them to no_op.

# Idempotency guard: skip if already loaded (the Flow bootstrap also guards this).
(( $+functions[flow_select_all] )) && return 0

# --- Clipboard backend -------------------------------------------------------
# Detected once at load; no work is performed on keypress. The backend can be
# forced with FLOW_CLIPBOARD_BACKEND=wl|xclip|xsel|none. Never logs clipboard
# contents; on failure the editor degrades to a transient message.
typeset -g FLOW_CLIPBOARD_BACKEND="${FLOW_CLIPBOARD_BACKEND:-auto}"

if (( ! $+functions[_flow_clipboard_write] )); then
  _flow_clipboard_backend=none
  case "$FLOW_CLIPBOARD_BACKEND" in
    wl)      _flow_clipboard_backend=wl ;;
    xclip)   _flow_clipboard_backend=xclip ;;
    xsel)    _flow_clipboard_backend=xsel ;;
    none)    _flow_clipboard_backend=none ;;
    auto)
      if [[ -z ${WAYLAND_DISPLAY:-} && -z ${DISPLAY:-} ]]; then
        _flow_clipboard_backend=none
      elif [[ -n ${WAYLAND_DISPLAY:-} ]] \
        && command -v wl-copy >/dev/null 2>&1 \
        && command -v wl-paste >/dev/null 2>&1; then
        _flow_clipboard_backend=wl
      elif command -v xclip >/dev/null 2>&1; then
        _flow_clipboard_backend=xclip
      elif command -v xsel >/dev/null 2>&1; then
        _flow_clipboard_backend=xsel
      fi
      ;;
  esac

  _flow_clipboard_write() {
    local text="$1"
    case "$_flow_clipboard_backend" in
      wl)    printf %s "$text" | command wl-copy 2>/dev/null ;;
      xclip) printf %s "$text" | command xclip -selection clipboard 2>/dev/null ;;
      xsel)  printf %s "$text" | command xsel -b -i 2>/dev/null ;;
      *)     return 1 ;;
    esac
  }

  _flow_clipboard_read() {
    case "$_flow_clipboard_backend" in
      wl)    command wl-paste 2>/dev/null ;;
      xclip) command xclip -o -selection clipboard 2>/dev/null ;;
      xsel)  command xsel -b -o 2>/dev/null ;;
      *)     return 1 ;;
    esac
  }
fi

# --- Region helpers ----------------------------------------------------------
_flow_region_bounds() {
  if (( CURSOR < MARK )); then
    _flow_lo=$CURSOR
    _flow_hi=$MARK
  else
    _flow_lo=$MARK
    _flow_hi=$CURSOR
  fi
}

_flow_pin_selection() {
  if (( ! REGION_ACTIVE )); then
    MARK=$CURSOR
    REGION_ACTIVE=1
  fi
}

_flow_delete_region() {
  _flow_region_bounds
  BUFFER="${BUFFER:0:$_flow_lo}${BUFFER:$_flow_hi}"
  CURSOR=$_flow_lo
  REGION_ACTIVE=0
}

# --- Selection widgets -------------------------------------------------------
# Movement is delegated to native widgets; the region is extended natively.
flow_select_all() {
  MARK=0
  CURSOR=${#BUFFER}
  REGION_ACTIVE=1
}

flow_select_buffer_start() {
  (( REGION_ACTIVE )) || MARK=$CURSOR
  CURSOR=0
  REGION_ACTIVE=1
}

flow_select_buffer_end() {
  (( REGION_ACTIVE )) || MARK=$CURSOR
  CURSOR=${#BUFFER}
  REGION_ACTIVE=1
}

flow_select_char_left() {
  _flow_pin_selection
  zle backward-char
}

flow_select_char_right() {
  _flow_pin_selection
  zle forward-char
}

flow_select_word_left() {
  _flow_pin_selection
  zle backward-word
}

flow_select_word_right() {
  _flow_pin_selection
  zle forward-word
}

# --- Clipboard widgets -------------------------------------------------------
flow_copy() {
  (( REGION_ACTIVE )) || return 0
  _flow_region_bounds
  local sel="${BUFFER:_flow_lo:$(( _flow_hi - _flow_lo ))}"
  _flow_clipboard_write "$sel" || zle -M "Flow: clipboard backend unavailable"
}

flow_cut() {
  (( REGION_ACTIVE )) || return 0
  _flow_region_bounds
  local sel="${BUFFER:_flow_lo:$(( _flow_hi - _flow_lo ))}"
  _flow_clipboard_write "$sel" || {
    zle -M "Flow: clipboard backend unavailable"
    return 1
  }
  _flow_delete_region
}

flow_paste() {
  local text st
  _flow_clipboard_read | IFS= read -r -d '' text
  st=$pipestatus[1]
  if (( st == 0 )) || [[ -n $text ]]; then
    if (( REGION_ACTIVE )); then
      _flow_delete_region
    fi
    BUFFER="${BUFFER:0:$CURSOR}${text}${BUFFER:$CURSOR}"
    CURSOR=$(( CURSOR + ${#text} ))
  else
    zle -M "Flow: clipboard backend unavailable"
    return 1
  fi
}

# --- Delete widgets ----------------------------------------------------------
# With a selection, Backspace/Delete remove the region. Without one they
# delegate to whatever widget was bound before this module loaded.
flow_delete_backward() {
  if (( REGION_ACTIVE )); then
    _flow_delete_region
  else
    zle "$_flow_orig_backspace"
  fi
}

flow_delete_ctrl_h() {
  if (( REGION_ACTIVE )); then
    _flow_delete_region
  else
    zle "$_flow_orig_ctrl_h"
  fi
}

flow_delete_forward() {
  if (( REGION_ACTIVE )); then
    _flow_delete_region
  else
    zle "$_flow_orig_delete"
  fi
}

# --- Public API (for the future Flow engine) ---------------------------------
# Call these from within a ZLE widget context.
flow_editor_buffer() {
  print -rn -- "$BUFFER"
}

flow_editor_cursor() {
  print -rn -- "$CURSOR"
}

flow_editor_selection() {
  (( REGION_ACTIVE )) || return 0
  _flow_region_bounds
  print -rn -- "${BUFFER:_flow_lo:$(( _flow_hi - _flow_lo ))}"
}

flow_editor_clear_selection() {
  REGION_ACTIVE=0
}

flow_editor_replace_selection() {
  local text="$1"
  _flow_region_bounds
  BUFFER="${BUFFER:0:$_flow_lo}${text}${BUFFER:$_flow_hi}"
  CURSOR=$(( _flow_lo + ${#text} ))
  REGION_ACTIVE=0
}

flow_editor_insert_at_cursor() {
  local text="$1"
  BUFFER="${BUFFER:0:$CURSOR}${text}${BUFFER:$CURSOR}"
  CURSOR=$(( CURSOR + ${#text} ))
}

# --- Register widgets --------------------------------------------------------
zle -N flow_select_all
zle -N flow_select_buffer_start
zle -N flow_select_buffer_end
zle -N flow_select_char_left
zle -N flow_select_char_right
zle -N flow_select_word_left
zle -N flow_select_word_right
zle -N flow_copy
zle -N flow_cut
zle -N flow_paste
zle -N flow_delete_backward
zle -N flow_delete_ctrl_h
zle -N flow_delete_forward

# --- Capture pre-existing delete bindings ------------------------------------
_flow_capture_binding() {
  local out key="$1" default="$2" w
  out="$(bindkey "$key")"
  if [[ -n "$out" ]]; then
    w="${out#* }"
    if [[ "$w" == flow_delete_* ]]; then
      print -r -- "$default"
    else
      print -r -- "$w"
    fi
  else
    print -r -- "$default"
  fi
}

_flow_orig_backspace="$(_flow_capture_binding '^?' backward-delete-char)"
_flow_orig_ctrl_h="$(_flow_capture_binding '^H' backward-delete-char)"
_flow_orig_delete="$(_flow_capture_binding '^[[3~' delete-char)"

# --- Bindings ----------------------------------------------------------------
bindkey '^?' flow_delete_backward
bindkey '^H' flow_delete_ctrl_h
bindkey '^[[3~' flow_delete_forward

bindkey '^[[1;2D' flow_select_char_left
bindkey '^[[1;2C' flow_select_char_right
bindkey '^[[1;6D' flow_select_word_left
bindkey '^[[1;6C' flow_select_word_right
bindkey '^[[1;6H' flow_select_buffer_start
bindkey '^[[1;6F' flow_select_buffer_end

bindkey '^[[97;6u' flow_select_all
bindkey '^[[99;6u' flow_copy
bindkey '^[[120;6u' flow_cut
bindkey '^[[118;6u' flow_paste
bindkey '^[[122;6u' undo
bindkey '^[[121;6u' redo