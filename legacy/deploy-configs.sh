#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# deploy-configs.sh
# Copies dotfiles from repo into ~/.config
# Requires --force and prompts per directory
# ------------------------------------------------------------

FORCE=false

# Parse arguments
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
elif [[ $# -gt 0 ]]; then
  echo "Unknown argument: $1"
  echo "Usage: $0 --force"
  exit 1
fi

# Require --force
if [[ "$FORCE" != true ]]; then
  echo "ERROR: This script will overwrite files in ~/.config."
  echo "You must run it with --force to proceed."
  echo
  echo "Example:"
  echo "  ./legacy/deploy-configs.sh --force"
  exit 1
fi

echo "==> deploy-configs.sh running in FORCE mode"
echo "==> You will be prompted before each directory is overwritten"

# ------------------------------------------------------------
# Setup paths
# ------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DOTFILES_DIR="$REPO_ROOT/config"
TARGET_DIR="$HOME/.config"

# Ensure ~/.config exists
mkdir -p "$TARGET_DIR"

# Explicit list of config directories we manage
CONFIGS=(
  hypr
  waybar
  rofi
  kitty
  fastfetch
  btop
  cava
  swaync
  zed
)

# ------------------------------------------------------------
# Pass 1: Check what exists and get approval
# ------------------------------------------------------------

APPROVED_CONFIGS=()

echo
echo "==> The following configuration directories may be overwritten:"
echo

for cfg in "${CONFIGS[@]}"; do
  SRC="$DOTFILES_DIR/$cfg"
  DEST="$TARGET_DIR/$cfg"

  # Skip if source does not exist in repo
  if [[ ! -d "$SRC" ]]; then
    echo "Skipping $cfg (not present in repo)"
    continue
  fi

  # If destination exists, ask before overwriting
  if [[ -e "$DEST" ]]; then
    echo "Config '$cfg' exists at $DEST"
    read -r -p "Overwrite this directory? [y/N] " reply
    echo

    case "$reply" in
      y|Y|yes|YES)
        APPROVED_CONFIGS+=("$cfg")
        ;;
      *)
        echo "Skipping $cfg"
        ;;
    esac
  else
    # Destination does not exist — safe to deploy automatically
    APPROVED_CONFIGS+=("$cfg")
  fi
done

# Nothing approved? Abort safely.
if [[ "${#APPROVED_CONFIGS[@]}" -eq 0 ]]; then
  echo "No configuration directories approved for deployment."
  echo "Nothing to do."
  exit 0
fi

echo "==> Approved configuration directories:"
for cfg in "${APPROVED_CONFIGS[@]}"; do
  echo "  - $cfg"
done
echo

# ------------------------------------------------------------
# Pass 2: Final confirmation
# ------------------------------------------------------------

echo "==> Final confirmation"
echo "The following configuration directories WILL be overwritten:"
echo

for cfg in "${APPROVED_CONFIGS[@]}"; do
  echo "  - $cfg"
done

echo
read -r -p "Proceed with deploying these configurations? [y/N] " final_reply
echo

case "$final_reply" in
  y|Y|yes|YES)
    echo "==> Proceeding with deployment..."
    ;;
  *)
    echo "Deployment aborted. No changes were made."
    exit 0
    ;;
esac

echo

# ------------------------------------------------------------
# Pass 3: Deploy configs (COPY ONLY)
# ------------------------------------------------------------

for cfg in "${APPROVED_CONFIGS[@]}"; do
  SRC="$DOTFILES_DIR/$cfg"
  DEST="$TARGET_DIR/$cfg"

  echo "==> Deploying $cfg"

  # Remove existing destination if it exists
  if [[ -e "$DEST" ]]; then
    rm -rf "$DEST"
  fi

  # Copy entire directory structure from repo into ~/.config
  # -a preserves permissions, timestamps, etc.
  # -L follows symlinks (copies actual files, not symlinks)
  cp -aL "$SRC" "$DEST"

  echo "    Copied $SRC -> $DEST"

  # The configs call scripts and assets as $HOME/invictus/... . If this
  # clone lives elsewhere (for example ~/hyprdots from before the rename),
  # point the deployed copy at where the repo really is.
  if [[ "$REPO_ROOT" != "$HOME/invictus" ]]; then
    # shellcheck disable=SC2016  # a literal $HOME, expanded later by the config's shell
    TOKEN='$HOME/invictus/'
    grep -rlF "$TOKEN" "$DEST" 2>/dev/null | while IFS= read -r f; do
      sed -i "s|$TOKEN|$REPO_ROOT/|g" "$f"
      echo "    Repo path set to $REPO_ROOT in $f"
    done
  fi
done

echo
echo "==> Configuration deployment complete."

# ------------------------------------------------------------
# Pass 4: GTK theme activation
# ------------------------------------------------------------

echo
echo "==> Applying GTK theme settings"

# Ensure gsettings is available
if ! command -v gsettings &>/dev/null; then
  echo "WARNING: gsettings not found. Skipping GTK theming."
else
  # GTK theme
  gsettings set org.gnome.desktop.interface gtk-theme "Nordic-Darker"

  # Icon theme
  gsettings set org.gnome.desktop.interface icon-theme "Snow"

  # Prefer dark color scheme
  gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"

  echo "==> GTK theme settings applied"
fi

echo
echo "==> Deployment complete!"
