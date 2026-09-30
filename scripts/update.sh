#!/usr/bin/env bash
# Kept only so existing installs keep working: the deployed waybar config
# runs $HOME/invictus/scripts/update.sh when the updates module is clicked.
# The real script now lives in legacy/. Phase 1 replaces both with
# invictus-update and removes this file.
exec "$(dirname -- "${BASH_SOURCE[0]}")/../legacy/update.sh" "$@"
