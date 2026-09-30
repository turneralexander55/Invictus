#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# install-packages.sh
#
# Installs:
#  - Pacman packages
#  - Paru (AUR helper)
#  - AUR packages
#
# This script installs SOFTWARE ONLY.
# It does NOT deploy configs or touch ~/.config.
# ------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Starting Invictus package installation"

# ------------------------------------------------------------
# Ensure we are running on Arch Linux
# ------------------------------------------------------------

if [[ ! -f /etc/arch-release ]]; then
  echo "ERROR: This script is intended for Arch Linux only."
  exit 1
fi

# ------------------------------------------------------------
# Ensure pacman exists
# ------------------------------------------------------------

if ! command -v pacman &>/dev/null; then
  echo "ERROR: pacman not found. Is this an Arch-based system?"
  exit 1
fi

# ------------------------------------------------------------
# Pacman packages
# ------------------------------------------------------------

PACMAN_LIST="$SCRIPT_DIR/packages/pacman.txt"

if [[ ! -f "$PACMAN_LIST" ]]; then
  echo "ERROR: pacman package list not found at $PACMAN_LIST"
  exit 1
fi

echo "==> Installing pacman packages..."

mapfile -t PACMAN_PACKAGES < <(
  grep -Ev '^\s*#|^\s*$' "$PACMAN_LIST"
)

if [[ "${#PACMAN_PACKAGES[@]}" -eq 0 ]]; then
  echo "No pacman packages to install."
else
  sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"
fi

echo "==> Pacman packages installed successfully."
echo

# ------------------------------------------------------------
# AUR setup (paru)
# ------------------------------------------------------------

echo "==> Setting up AUR (paru)"

# Ensure git exists
if ! command -v git &>/dev/null; then
  echo "==> Installing git..."
  sudo pacman -S --needed --noconfirm git
fi

# Ensure base-devel exists
if ! pacman -Qi base-devel &>/dev/null; then
  echo "==> Installing base-devel..."
  sudo pacman -S --needed --noconfirm base-devel
fi

# Install paru if missing
if ! command -v paru &>/dev/null; then
  echo "==> Paru not found. Bootstrapping paru..."

  PARU_DIR="$(mktemp -d)"
  git clone https://aur.archlinux.org/paru.git "$PARU_DIR/paru"
  pushd "$PARU_DIR/paru" >/dev/null

  makepkg -si --noconfirm

  popd >/dev/null
  rm -rf "$PARU_DIR"

  echo "==> Paru installed successfully."
else
  echo "==> Paru already installed. Skipping bootstrap."
fi

echo

# ------------------------------------------------------------
# AUR packages
# ------------------------------------------------------------

AUR_LIST="$SCRIPT_DIR/packages/aur.txt"

if [[ ! -f "$AUR_LIST" ]]; then
  echo "ERROR: AUR package list not found at $AUR_LIST"
  exit 1
fi

echo "==> Installing AUR packages..."

mapfile -t AUR_PACKAGES < <(
  grep -Ev '^\s*#|^\s*$' "$AUR_LIST"
)

if [[ "${#AUR_PACKAGES[@]}" -eq 0 ]]; then
  echo "No AUR packages to install."
else
  paru -S --needed --noconfirm "${AUR_PACKAGES[@]}"
fi

echo "==> AUR packages installed successfully."
