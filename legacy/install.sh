#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Invictus installer orchestrator
# ------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo " Invictus Installer"
echo "============================================================"
echo

# ------------------------------------------------------------
# Stage 1: Install packages (pacman + AUR)
# ------------------------------------------------------------

echo "==> Stage 1: Installing packages"
echo

"$SCRIPT_DIR/install-packages.sh"

echo
echo "==> Package installation complete"
echo

# ------------------------------------------------------------
# Stage 2: First-time user initialization
# ------------------------------------------------------------

echo "==> Stage 2: Initializing user environment"
echo

"$SCRIPT_DIR/init-user.sh"

echo
echo "==> Initialization complete"
echo

# ------------------------------------------------------------
# Stage 3: Deploy configuration files
# ------------------------------------------------------------

echo "==> Stage 3: Deploying configuration files"
echo

"$SCRIPT_DIR/deploy-configs.sh" --force

echo
echo "==> Configuration deployment complete"
echo

# ------------------------------------------------------------
# Stage 4: Deploy shell configuration
# ------------------------------------------------------------

echo "==> Stage 4: Deploying shell configuration"
echo

"$SCRIPT_DIR/deploy-shell.sh" --force

echo
echo "==> Shell configuration complete"
echo

# ============================================================
# Step 5: Session Manager (SDDM)
# ============================================================

echo
read -r -p "Do you want to deploy the SDDM session manager? [y/N] " deploy_sddm
echo

if [[ "$deploy_sddm" =~ ^([yY]|yes|YES)$ ]]; then
  echo "==> Deploying SDDM"

  SDDM_SCRIPT="$SCRIPT_DIR/install-sddm.sh"

  if [[ ! -f "$SDDM_SCRIPT" ]]; then
    echo "ERROR: SDDM install script not found:"
    echo "  $SDDM_SCRIPT"
    exit 1
  fi

  chmod +x "$SDDM_SCRIPT"

  "$SDDM_SCRIPT"
else
  echo "==> Skipping SDDM deployment"
fi

echo "======================================"
echo " Invictus installation complete"
echo
echo " System will reboot in 5 seconds"
echo " Press Ctrl+C to cancel"
echo "======================================"
echo

sleep 5

if [[ $EUID -ne 0 ]]; then
  sudo reboot
else
  reboot
fi
