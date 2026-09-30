#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-motion: the motion level (docs/look.md, Motion).
# Installed as /usr/bin/invictus-motion by invictus-tools.
#
#   invictus-motion get            print the level (showcase, calm or off)
#   invictus-motion set LEVEL      change it
#   invictus-motion pick           choose in a small rofi menu
#
# The level is one word in ~/.config/invictus/motion (missing means
# showcase). Setting it also:
#   kitty    links ~/.config/invictus/motion.d/kitty.conf to the level's
#            file in ~/.config/kitty/motion/ (kitty.conf includes it last)
#   waybar   copies motion/calm.css or motion/off.css over
#   swaync   ~/.config/<app>/motion.css; Showcase puts the shipped
#            motion.css back. swaync's transition-time: 220, 150 or 0 ms
#   GTK      gsettings enable-animations: true for Showcase only
# then reloads Hyprland (not while game mode is on; game mode forces Off
# by itself), waybar, swaync and kitty. A reload that fails is reported;
# the level stays set.
#
# Env (tests): INVICTUS_HYPRCTL, INVICTUS_PKILL, INVICTUS_SWAYNC_CLIENT,
# INVICTUS_GSETTINGS, INVICTUS_ROFI, INVICTUS_SHARE, INVICTUS_GAMEMODE_FILE
# ------------------------------------------------------------
set -uo pipefail

SHARE="${INVICTUS_SHARE:-/usr/share/invictus}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_FILE="$CFG/invictus/motion"
GAMEMODE="${INVICTUS_GAMEMODE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/invictus/game-mode}"
HYPRCTL="${INVICTUS_HYPRCTL:-hyprctl}"
PKILL="${INVICTUS_PKILL:-pkill}"
SWAYNC_CLIENT="${INVICTUS_SWAYNC_CLIENT:-swaync-client}"
GSETTINGS="${INVICTUS_GSETTINGS:-gsettings}"
ROFI="${INVICTUS_ROFI:-rofi}"

current() {
    local l=""
    [[ -r "$STATE_FILE" ]] && read -r l < "$STATE_FILE"
    case "$l" in showcase|calm|off) echo "$l" ;; *) echo showcase ;; esac
}

# The user's copy of an app's motion file, else the shipped one.
motion_src() {
    local app="$1" file="$2"
    if [[ -f "$CFG/$app/$file" ]]; then echo "$CFG/$app/$file"
    elif [[ -f "$SHARE/config/$app/$file" ]]; then echo "$SHARE/config/$app/$file"
    fi
}

problems=()
try() { "$@" >/dev/null 2>&1 || problems+=("$(basename "$1") $2"); }

set_level() {
    local level="$1" src app ms
    case "$level" in showcase|calm|off) ;; *) echo "invictus-motion: level must be showcase, calm or off" >&2; exit 2 ;; esac

    mkdir -p "$CFG/invictus/motion.d"
    printf '%s\n' "$level" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    if src="$(motion_src kitty "motion/$level.conf")" && [[ -n "$src" ]]; then
        ln -sfn "$src" "$CFG/invictus/motion.d/kitty.conf"
    fi
    for app in waybar swaync; do
        [[ -d "$CFG/$app" ]] || continue
        if [[ "$level" == showcase ]]; then src="$SHARE/config/$app/motion.css"
        else src="$(motion_src "$app" "motion/$level.css")"; fi
        [[ -n "$src" && -f "$src" ]] && cp "$src" "$CFG/$app/motion.css"
    done
    if [[ -f "$CFG/swaync/config.json" ]]; then
        case "$level" in showcase) ms=220 ;; calm) ms=150 ;; off) ms=0 ;; esac
        sed -i -E "s/(\"transition-time\"[[:space:]]*:[[:space:]]*)[0-9]+/\\1$ms/" "$CFG/swaync/config.json"
    fi

    local anim=false
    [[ "$level" == showcase ]] && anim=true
    command -v "$GSETTINGS" >/dev/null && try "$GSETTINGS" set org.gnome.desktop.interface enable-animations "$anim"

    if [[ -e "$GAMEMODE" ]]; then
        echo "invictus-motion: game mode is on; Hyprland keeps Off until it ends" >&2
    else
        command -v "$HYPRCTL" >/dev/null && try "$HYPRCTL" reload
    fi
    # pkill exits 1 when the app is not running: not a problem
    "$PKILL" -SIGUSR2 -x waybar >/dev/null 2>&1
    "$PKILL" -SIGUSR1 -x kitty >/dev/null 2>&1
    if command -v "$SWAYNC_CLIENT" >/dev/null && "$PKILL" -0 -x swaync >/dev/null 2>&1; then
        try "$SWAYNC_CLIENT" --reload-config
        try "$SWAYNC_CLIENT" --reload-css
    fi
    if [[ ${#problems[@]} -gt 0 ]]; then
        echo "invictus-motion: set to $level; did not reload: ${problems[*]}" >&2
    fi
    return 0
}

pick() {
    local cur rows="" choice l
    cur="$(current)"
    for l in showcase calm off; do
        rows+="${l^}$([[ "$l" == "$cur" ]] && echo '   ✓')"$'\n'
    done
    choice="$(printf '%s' "$rows" | "$ROFI" -dmenu -i -no-custom -p "Motion" -l 3 \
        -selected-row "$(case "$cur" in showcase) echo 0 ;; calm) echo 1 ;; off) echo 2 ;; esac)" 2>/dev/null)" || return 0
    choice="$(awk '{ print tolower($1) }' <<< "$choice")"
    [[ -n "$choice" && "$choice" != "$cur" ]] && set_level "$choice"
    return 0
}

case "${1:-}" in
    get) current ;;
    set) set_level "${2:-}" ;;
    pick) pick ;;
    -h|--help) sed -n '2,24p' "$0" ;;
    *) sed -n '2,24p' "$0" >&2; exit 2 ;;
esac
