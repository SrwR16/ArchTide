#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="flow"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  # Apply colors using Python for robust literal string replacement (no regex or sed shell escaping issues)
  python3 -c '
import sys
import os
scss_path, template_path, output_path = sys.argv[1:4]
vars_dict = {}
try:
    with open(scss_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("$") or ":" not in line:
                continue
            name, val = line.split(":", 1)
            name = name.strip()
            val = val.strip().rstrip(";").lstrip("#")
            vars_dict[name + " #"] = val
except Exception as e:
    print(f"Error reading colors scss: {e}", file=sys.stderr)
    sys.exit(1)

if len(vars_dict) < 10:
    print("Error: Too few colors generated. Aborting Kitty theme update.", file=sys.stderr)
    sys.exit(1)

with open(template_path, "r") as f:
    content = f.read()

for name, val in vars_dict.items():
    content = content.replace(name, val)

import re
if re.search(r"#\$[a-zA-Z0-9_]+", content):
    print("Error: Unreplaced placeholders found in Kitty theme. Aborting update.", file=sys.stderr)
    sys.exit(1)

tmp_path = output_path + ".tmp"
with open(tmp_path, "w") as f:
    f.write(content)
os.rename(tmp_path, output_path)
' "$STATE_DIR/user/generated/material_colors.scss" "$SCRIPT_DIR/terminal/kitty-theme.conf" "$STATE_DIR/user/generated/terminal/kitty-theme.conf"

  # Ensure current-theme.conf is a symlink to our generated kitty-theme.conf
  local kitty_theme_dir="$XDG_CONFIG_HOME/kitty"
  local kitty_theme_file="$kitty_theme_dir/current-theme.conf"
  local gen_kitty_theme="$STATE_DIR/user/generated/terminal/kitty-theme.conf"
  if [ -d "$kitty_theme_dir" ]; then
    if [ ! -L "$kitty_theme_file" ] || [ "$(readlink -f "$kitty_theme_file")" != "$gen_kitty_theme" ]; then
      echo "Restoring Kitty current-theme.conf symlink to dynamic theme..."
      rm -f "$kitty_theme_file"
      ln -sf "$gen_kitty_theme" "$kitty_theme_file"
    fi
  fi

  # Reload
  if ! pgrep -f kitty >/dev/null; then
    return
  fi
  kill -SIGUSR1 $(pidof kitty)
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  # Apply colors using Python for robust literal string replacement (no regex or sed shell escaping issues)
  python3 -c '
import sys
import os
scss_path, template_path, output_path, alpha = sys.argv[1:5]
vars_dict = {}
try:
    with open(scss_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("$") or ":" not in line:
                continue
            name, val = line.split(":", 1)
            name = name.strip()
            val = val.strip().rstrip(";").lstrip("#")
            vars_dict[name + " #"] = val
except Exception as e:
    print(f"Error reading colors scss: {e}", file=sys.stderr)
    sys.exit(1)

if len(vars_dict) < 10:
    print("Error: Too few colors generated. Aborting sequences update.", file=sys.stderr)
    sys.exit(1)

with open(template_path, "r") as f:
    content = f.read()

for name, val in vars_dict.items():
    content = content.replace(name, val)

content = content.replace("$alpha", alpha)

import re
if re.search(r"#\$[a-zA-Z0-9_]+", content):
    print("Error: Unreplaced placeholders found in Terminal sequences. Aborting update.", file=sys.stderr)
    sys.exit(1)

tmp_path = output_path + ".tmp"
with open(tmp_path, "w") as f:
    f.write(content)
os.rename(tmp_path, output_path)
' "$STATE_DIR/user/generated/material_colors.scss" "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR/user/generated/terminal/sequences.txt" "$term_alpha"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      # Only inject into ptys that actually have a shell attached, not daemons
      # that happen to hold a stray pty as their controlling terminal (e.g. kded6).
      if ! ps -t "${file#/dev/}" -o comm= 2>/dev/null | grep -qE '^(bash|zsh|fish|sh|dash|tcsh|csh|ksh|nu|xonsh|elvish)$'; then
        continue
      fi
      {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_starship() {
  # Static base config lives next to the quickshell dir (~/.config/starship.toml
  # installed, dots/.config/starship.toml in a checkout) — 4 levels up from here.
  local base_starship="$SCRIPT_DIR/../../../../starship.toml"
  if [ ! -f "$base_starship" ]; then
    echo "Static Starship config not found. Skipping Starship palette generation."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  # Splice the [palettes.flow] section from Material tokens. Same robustness
  # pattern as the Kitty/sequences generators: literal replacement, sanity
  # guards, atomic tmp+rename so a failed run keeps the last valid config.
  python3 -c '
import sys
import os
scss_path, base_path, output_path = sys.argv[1:4]
vars_dict = {}
try:
    with open(scss_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("$") or ":" not in line:
                continue
            name, val = line.split(":", 1)
            name = name.strip().lstrip("$")
            val = val.strip().rstrip(";").lstrip("#")
            vars_dict[name] = val
except Exception as e:
    print(f"Error reading colors scss: {e}", file=sys.stderr)
    sys.exit(1)

if len(vars_dict) < 10:
    print("Error: Too few colors generated. Aborting Starship palette update.", file=sys.stderr)
    sys.exit(1)

# Semantic mapping: Flow palette key -> Material 3 token (material_colors.scss)
mapping = [
    ("flow_identity",    "onSurface"),
    ("flow_host_bg",     "surfaceContainerHigh"),
    ("flow_host_fg",     "onSurface"),
    ("flow_git",         "primary"),
    ("flow_git_status",  "onSurfaceVariant"),
    ("flow_profile",     "primary"),
    ("flow_target",      "onSurfaceVariant"),
    ("flow_runtime",     "secondary"),
    ("flow_tool",        "secondary"),
    ("flow_infra",       "secondary"),
    ("flow_remote",      "tertiary"),
    ("flow_production",  "error"),
    ("flow_success",     "primary"),
    ("flow_error",       "error"),
    ("flow_metadata",    "onSurfaceVariant"),
]

with open(base_path, "r") as f:
    content = f.read()

marker = "FLOW_GENERATED_PALETTE_BEGIN"
if marker not in content:
    print("Error: Static Starship config has no FLOW_GENERATED_PALETTE_BEGIN marker. Skipping.", file=sys.stderr)
    sys.exit(1)

# Keep everything above the marker line (header + docs), then emit the palette.
head = content[:content.rfind("\n", 0, content.index(marker)) + 1]
lines = ["[palettes.flow]"]
missing = []
for key, token in mapping:
    if token not in vars_dict:
        missing.append(token)
        continue
    lines.append(f"{key} = \"#{vars_dict[token]}\"")
if missing:
    missing_str = ", ".join(missing)
    print(f"Error: Missing Material tokens: {missing_str}. Aborting Starship palette update.", file=sys.stderr)
    sys.exit(1)

output = head + "\n".join(lines) + "\n"
tmp_path = output_path + ".tmp"
with open(tmp_path, "w") as f:
    f.write(output)
os.rename(tmp_path, output_path)
' "$STATE_DIR/user/generated/material_colors.scss" "$base_starship" "$STATE_DIR/user/generated/terminal/starship.toml"
}

apply_term() {
  apply_anyterm &
  apply_starship &
  apply_kitty &
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/flow/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

# apply_qt & # Qt theming is already handled by kde-material-colors