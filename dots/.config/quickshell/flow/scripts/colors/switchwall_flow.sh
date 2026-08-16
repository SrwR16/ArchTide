#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="flow"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/flow/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

handle_kde_material_you_colors() {
    # Check if Qt app theming is enabled in config
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")
        if [ "$enable_qt_apps" == "false" ]; then
            return
        fi
    fi

    # Map $type_flag to allowed scheme variants for kde-material-you-colors-wrapper.sh
    local kde_scheme_variant=""
    case "$type_flag" in
        scheme-content|scheme-expressive|scheme-fidelity|scheme-fruit-salad|scheme-monochrome|scheme-neutral|scheme-rainbow|scheme-tonal-spot|scheme-vibrant)
            kde_scheme_variant="$type_flag"
            ;;
        scheme-intense)
            kde_scheme_variant="scheme-fidelity"
            ;;
        *)
            kde_scheme_variant="scheme-tonal-spot" # default
            ;;
    esac
    "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$kde_scheme_variant"
}

request_shell_theme_reload() {
    # FileView normally notices colors.json, but an atomic inode replacement can
    # be missed on some Quickshell/filesystem combinations. Ask the running shell
    # to recreate its watcher after the generated file is complete.
    if ! command -v qs >/dev/null 2>&1; then
        echo "[switchwall_flow.sh] Warning: qs not found; relying on the colors.json watcher" >&2
        return 0
    fi
    if ! qs -c flow ipc call theme reapplyTheme 2>/dev/null; then
        echo "[switchwall_flow.sh] Warning: could not request Quickshell theme reload" >&2
    fi
}

pre_process() {
    local mode_flag="$1"
    # Set GNOME color-scheme if mode_flag is dark or light
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

post_process() {
    local screen_width="$1"
    local screen_height="$2"
    local wallpaper_path="$3"

    handle_kde_material_you_colors &
    "$SCRIPT_DIR/code/material-code-set-color.sh" &
    
    # Generate YouTube Music theme
    "$SCRIPT_DIR/../ytmusic/generate-ytmusic-theme.sh" > /dev/null 2>&1 &
}

check_and_prompt_upscale() {
    local img="$1"
    min_width_desired="$(hyprctl monitors -j | jq '([.[].width] | max)' | xargs)" # max monitor width
    min_height_desired="$(hyprctl monitors -j | jq '([.[].height] | max)' | xargs)" # max monitor height

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then # Not check resolution for videos, just let em pass
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            img_width=$(identify -format "%w" "$img" 2>/dev/null)
            img_height=$(identify -format "%h" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            action=$(notify-send "Upscale?" \
                "Image resolution (${img_width}x${img_height}) is lower than screen resolution (${min_width_desired}x${min_height_desired})" \
                -A "open_upscayl=Open Upscayl"\
                -a "Wallpaper switcher")
            if [[ "$action" == "open_upscayl" ]]; then
                upscayl-bin -i "$img" -o "$img" -s 2 > /dev/null 2>&1
            fi
        fi
    fi
}

is_video() {
    local file="$1"
    local ext="${file##*.}"
    case "${ext,,}" in
        mp4|mkv|webm|mov|avi|gif) return 0 ;;
        *) return 1 ;;
    esac
}

main() {
    imgpath=""
    mode_flag=""
    type_flag=""
    color_flag=""
    color=""
    noswitch_flag=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image) imgpath="$2"; shift 2 ;;
            --mode)  mode_flag="$2"; shift 2 ;;
            --type)  type_flag="$2"; shift 2 ;;
            --color) color_flag="$2"; shift 2 ;;
            --noswitch) noswitch_flag="1"; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$type_flag" ]]; then
        type_flag=$(get_type_from_config)
    fi
    if [[ -z "$mode_flag" ]]; then
        mode_flag=$(get_mode_from_config)
    fi
    if [[ -z "$color_flag" ]]; then
        color=$(get_accent_color_from_config)
    fi

    pre_process "$mode_flag"

    local generate_colors_material_args=(
        --scheme "$type_flag"
        --mode "$mode_flag"
        --color "$color"
    )

    local matugen_args=(
        image
        "--config" "$MATUGEN_DIR/config.toml"
    )

    if [[ -n "$imgpath" ]]; then
        matugen_args+=("$imgpath")
        matugen image "$imgpath" --config "$MATUGEN_DIR/config.toml" 2>&1 | grep -v "^$" | while IFS= read -r line; do
            echo "[switchwall_flow.sh] matugen: $line"
        done
    else
        # Use config wallpaper or default
        local wall_path=$(jq -r '.background.wallpaperPath // empty' "$SHELL_CONFIG_FILE")
        if [[ -n "$wall_path" && -f "$wall_path" ]]; then
            matugen_args+=(image "$wall_path")
            generate_colors_material_args+=(--path "$wall_path")
        else
            local default_wall="$HOME/.config/quickshell/flow/assets/images/default_wallpaper.png"
            matugen_args+=(image "$default_wall")
            generate_colors_material_args=(--path "$default_wall")
        fi
    fi

    # Build matugen
    local colors_output="$STATE_DIR/user/generated/colors.json"
    mkdir -p "$(dirname "$colors_output")"
    matugen "${matugen_args[@]}" --json "$colors_output" 2>&1 | grep -v "^$" | while IFS= read -r line; do
        echo "[switchwall_flow.sh] matugen: $line"
    done

    # Generate material colors for terminal
    python3 "$SCRIPT_DIR/generate_colors_material_flow.py" "${generate_colors_material_args[@]}" \
        --all-previews "$STATE_DIR/user/generated/wallpaper_preview_colors.json" \
        --request-token "$request_token_file" --request-value "$my_request_token" \
        > "$STATE_DIR/user/generated/material_colors.scss.tmp" 2>&1

    if [[ -f "$STATE_DIR/user/generated/material_colors.scss.tmp" ]]; then
        mv "$STATE_DIR/user/generated/material_colors.scss.tmp" "$STATE_DIR/user/generated/material_colors.scss"
    else
        echo "[switchwall_flow.sh] Color generation skipped; preserving the previous terminal palette." >&2
    fi

    request_shell_theme_reload

    # Handle lockscreen
    local lock_wall=$(jq -r '.background.lockscreenWallpaperPath // empty' "$SHELL_CONFIG_FILE")
    if [[ -n "$lock_wall" && -f "$lock_wall" ]]; then
        matugen image "$lock_wall" --config "$MATUGEN_DIR/config.toml" --json "$STATE_DIR/user/generated/lockscreen_colors.json" 2>&1 | grep -v "^$" | while IFS= read -r line; do
            echo "[switchwall_flow.sh] matugen (lockscreen): $line"
        done
    fi

    # Apply terminal colors
    python3 "$SCRIPT_DIR/applycolor_flow.sh" 2>&1 | while IFS= read -r line; do
        echo "[switchwall_flow.sh] applycolor: $line"
    done

    post_process 1920 1080 "$imgpath"
}

# Helper functions
get_type_from_config() {
    jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
}

get_mode_from_config() {
    jq -r '.appearance.palette.mode' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
}

get_accent_color_from_config() {
    jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
}

get_color_from_config() {
    jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
}

# Main entry
case "$1" in
    --image) imgpath="$2"; shift 2 ;;
    --mode)  mode_flag="$2"; shift 2 ;;
    --type)  type_flag="$2"; shift 2 ;;
    --color) color_flag="$2"; shift 2 ;;
    --noswitch) noswitch_flag="1"; shift ;;
    *) shift ;;
esac

# If no type_flag provided, get from config
if [[ -z "$type_flag" ]]; then
    type_flag=$(get_type_from_config)
fi
if [[ -z "$mode_flag" ]]; then
    mode_flag=$(get_mode_from_config)
fi
if [[ -z "$color_flag" ]]; then
    color=$(get_accent_color_from_config)
fi

main "$@"