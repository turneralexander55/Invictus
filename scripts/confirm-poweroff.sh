#!/usr/bin/env bash

# ------------------------------------------------------------
# confirm-poweroff.sh
# Asks "Power off?" in a small rofi menu and powers off only on
# "Yes". "No" is the default (first row, preselected). Escape,
# closing the menu or any other answer does nothing.
#
# Bound to SUPER + ALT + CTRL + Escape in lua/binds.lua.
#
# ROFI and POWEROFF_CMD can point at other commands (used by the
# tests).
# ------------------------------------------------------------

set -euo pipefail

ROFI="${ROFI:-rofi}"
POWEROFF_CMD="${POWEROFF_CMD:-systemctl poweroff}"

# rofi exits non-zero on Escape; treat that as an empty answer.
answer=$(printf 'No\nYes\n' | "$ROFI" -dmenu -i -no-custom -selected-row 0 -p "Power off?" -lines 2 2>/dev/null) || answer=""

if [[ "$answer" == "Yes" ]]; then
  # shellcheck disable=SC2086  # POWEROFF_CMD is a command plus arguments
  exec $POWEROFF_CMD
fi
