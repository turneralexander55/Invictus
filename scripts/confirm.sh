#!/usr/bin/env bash

# ------------------------------------------------------------
# confirm.sh
# Usage: confirm.sh "Prompt?" -- command [args...]
#
# Asks the prompt in a small rofi menu and runs the command only on
# "Yes". "No" is the default (first row, preselected). Escape, closing
# the menu or any other answer does nothing.
#
# Used by the power-off and log-out binds in
# config/hypr/invictus/binds.lua.
#
# ROFI can point at another command (used by the tests).
# ------------------------------------------------------------

set -euo pipefail

if [[ $# -lt 3 || "$2" != "--" ]]; then
  echo "usage: confirm.sh \"Prompt?\" -- command [args...]" >&2
  exit 2
fi

ROFI="${ROFI:-rofi}"
prompt="$1"
shift 2

# rofi exits non-zero on Escape; treat that as an empty answer.
answer=$(printf 'No\nYes\n' | "$ROFI" -dmenu -i -no-custom -selected-row 0 -p "$prompt" -l 2 2>/dev/null) || answer=""

if [[ "$answer" == "Yes" ]]; then
  exec "$@"
fi
