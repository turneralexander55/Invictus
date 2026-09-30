#!/usr/bin/env bash

# ------------------------------------------------------------
# show-keybindings.sh
# Displays all Hyprland keybindings.
#
# Reads the live binds from `hyprctl binds`, so it always matches
# what Hyprland has loaded. The Lua config (lua/binds.lua) gives
# every bind a description "Section: action"; binds are grouped by
# that section.
#
#   --stdout   print the list instead of opening rofi/yad
#
# HYPRCTL can point at another hyprctl (used by the tests).
# ------------------------------------------------------------

set -euo pipefail

HYPRCTL="${HYPRCTL:-hyprctl}"

if ! BINDS=$("$HYPRCTL" binds 2>/dev/null); then
    notify-send "Keybindings" "Could not read binds from hyprctl" || true
    exit 1
fi

# ------------------------------------------------------------
# Parse `hyprctl binds` into "Section<TAB>Keys<TAB>Action"
# modmask bits: SHIFT 1, CAPS 2, CTRL 4, ALT 8, MOD2 16,
# MOD3 32, SUPER 64, MOD5 128
# ------------------------------------------------------------
parse_binds() {
    awk '
        function has(mask, bit) { return int(mask / bit) % 2 == 1 }
        function mods(mask,    out) {
            out = ""
            if (has(mask, 64))  out = out "Super + "
            if (has(mask, 4))   out = out "Ctrl + "
            if (has(mask, 8))   out = out "Alt + "
            if (has(mask, 1))   out = out "Shift + "
            if (has(mask, 2))   out = out "Caps + "
            if (has(mask, 16))  out = out "Mod2 + "
            if (has(mask, 32))  out = out "Mod3 + "
            if (has(mask, 128)) out = out "Mod5 + "
            return out
        }
        function emit(    section, action, i) {
            if (key == "") return
            section = "Other"
            action = desc
            i = index(desc, ": ")
            if (i > 0) {
                section = substr(desc, 1, i - 1)
                action = substr(desc, i + 2)
            }
            if (action == "") action = "(no description)"
            printf "%s\t%s%s\t%s\n", section, mods(mask), key, action
            key = ""; desc = ""; mask = 0
        }
        /^bind/                { emit(); next }
        /^\tmodmask: /         { mask = substr($0, 11) + 0; next }
        /^\tkey: /             { key = substr($0, 7); next }
        /^\tdescription: /     { desc = substr($0, 15); next }
        END                    { emit() }
    ' <<< "$BINDS"
}

# ------------------------------------------------------------
# Format: one header per section, in first-seen order
# ------------------------------------------------------------
format_binds() {
    echo "=== HYPRLAND KEYBINDINGS ==="
    parse_binds | awk -F '\t' '
        {
            if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 }
            rows[$1] = rows[$1] sprintf("  %-35s  →  %s\n", $2, $3)
        }
        END {
            for (i = 1; i <= n; i++) {
                printf "\n─── %s ───\n%s", order[i], rows[order[i]]
            }
            print ""
        }
    '
}

if [[ "${1:-}" == "--stdout" ]]; then
    format_binds
    exit 0
fi

OUTPUT_FILE=$(mktemp)
trap 'rm -f "$OUTPUT_FILE"' EXIT
format_binds > "$OUTPUT_FILE"

# ------------------------------------------------------------
# Display the keybindings
# ------------------------------------------------------------

if command -v rofi &>/dev/null; then
    rofi -dmenu \
        -i \
        -p "Keybindings" \
        -theme-str 'window {width: 60%;} listview {lines: 25;}' \
        -no-custom < "$OUTPUT_FILE" || true

elif command -v yad &>/dev/null; then
    yad --text-info \
        --title="Hyprland Keybindings" \
        --filename="$OUTPUT_FILE" \
        --width=900 \
        --height=700 \
        --button=gtk-close

else
    if command -v kitty &>/dev/null; then
        kitty --title "Keybindings" -e less "$OUTPUT_FILE"
    else
        xterm -title "Keybindings" -e less "$OUTPUT_FILE"
    fi
fi
