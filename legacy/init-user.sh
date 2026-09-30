#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# init-user.sh
#
# One-time user environment initialization
# - Creates home directory structure
# - Initializes XDG dirs
# - Enables user services
# - Refreshes caches
#
# Safe to run multiple times, but guarded by a sentinel.
# ------------------------------------------------------------

SENTINEL="$HOME/.local/state/invictus-initialized"
# Machines set up before the rename (hyprdots) already ran this once.
LEGACY_SENTINEL="$HOME/.local/state/hyprdots-initialized"

# Ensure state directory exists
mkdir -p "$HOME/.local/state"

if [[ -f "$SENTINEL" || -f "$LEGACY_SENTINEL" ]]; then
  echo "==> User environment already initialized. Skipping."
  exit 0
fi

echo "==> Running first-time user initialization"

# ------------------------------------------------------------
# Home directory structure
# ------------------------------------------------------------

echo "==> Creating home directory structure"

mkdir -p \
  "$HOME/Repos" \
  "$HOME/Projects" \
  "$HOME/Documents" \
  "$HOME/Downloads" \
  "$HOME/Screenshots" \
  "$HOME/Pictures/Wallpapers" \
  "$HOME/.local/bin" \
  "$HOME/.cache"

# ------------------------------------------------------------
# XDG user directories
# ------------------------------------------------------------

if command -v xdg-user-dirs-update &>/dev/null; then
  echo "==> Initializing XDG user directories"
  xdg-user-dirs-update
fi

# ------------------------------------------------------------
# Enable user services
# ------------------------------------------------------------

echo "==> Enabling user services"

systemctl --user daemon-reexec

systemctl --user enable --now \
  pipewire.service \
  pipewire-pulse.service \
  wireplumber.service \
  xdg-desktop-portal.service || true

# ------------------------------------------------------------
# Cache refresh
# ------------------------------------------------------------

echo "==> Refreshing system caches"

fc-cache -f || true
gtk-update-icon-cache -f "$HOME/.icons" 2>/dev/null || true
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true

# ------------------------------------------------------------
# Mark initialization complete
# ------------------------------------------------------------

touch "$SENTINEL"

echo "==> User environment initialization complete"
