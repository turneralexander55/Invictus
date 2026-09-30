#!/usr/bin/env bash
# Kept only so existing installs keep working: the deployed waybar config
# runs $HOME/hyprdots/scripts/update.sh when the updates module is clicked.
# The real script now lives in legacy/. An adopted machine uses
# invictus-update; remove this file once no machine runs the old config
# (tests/pkgs/fixtures/main-references.txt).
exec "$(dirname -- "${BASH_SOURCE[0]}")/../legacy/update.sh" "$@"
