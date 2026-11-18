#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# link-repo.sh
#
# Points ~/.local/share/invictus at this repo, wherever it is cloned.
# Deployed configs (waybar, hyprpaper, keybindings) reach repo
# scripts and assets through this one link, so the repo can live
# in any folder. Re-run after moving the repo.
# ------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LINK="$HOME/.local/share/invictus"

mkdir -p "$(dirname -- "$LINK")"

if [[ -e "$LINK" && ! -L "$LINK" ]]; then
  echo "ERROR: $LINK exists and is not a symlink. Move it aside and re-run."
  exit 1
fi

ln -sfn "$REPO_ROOT" "$LINK"
echo "==> Linked $LINK -> $REPO_ROOT"
