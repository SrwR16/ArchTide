# 45-zsh-edit-select.zsh — Selection, clipboard, undo/redo via zsh-edit-select
# Replaces the custom 45-flow-editor.zsh with an externally maintained plugin.
# https://github.com/Michael-Matta1/zsh-edit-select
#
# Provides: Shift-select, Ctrl+A/C/X/V, Ctrl+Z/Ctrl+Shift+Z undo/redo,
# mouse-selection integration, OSC52 SSH clipboard support.
#
# One-time setup: run `edit-select config` to generate keybindings,
# then add the Kitty map lines from the plugin's README so Kitty
# forwards Ctrl+Shift sequences to zsh.

# Idempotency guard
(( $+functions[edit-select-init] )) && return 0

# Plugin locations to search (XDG first, then common paths)
local -a _es_dirs=(
  "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-edit-select"
  "$HOME/.local/share/zsh-edit-select"
  "$HOME/.zsh-plugins/zsh-edit-select"
  "/usr/share/zsh-edit-select"
)

local _es_dir=""
for _es_dir in "${_es_dirs[@]}"; do
  if [[ -f "$_es_dir/zsh-edit-select.plugin.zsh" ]]; then
    source "$_es_dir/zsh-edit-select.plugin.zsh"
    return 0
  fi
done

# Fallback: try loading from any zsh plugin path
if [[ -d "$HOME/.zsh-plugins" ]]; then
  for _es_dir in "$HOME/.zsh-plugins"/*; do
    if [[ -f "$_es_dir/zsh-edit-select.plugin.zsh" ]]; then
      source "$_es_dir/zsh-edit-select.plugin.zsh"
      return 0
    fi
  done
fi

# Plugin not found — skip silently (user may not have installed it yet)
