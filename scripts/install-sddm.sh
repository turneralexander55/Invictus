#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Self-escalate via sudo (prompt only when needed)
# ------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "==> Elevation required for SDDM theme installation"
  exec sudo "$0" "$@"
fi

echo "======================================"
echo " Installing SDDM Blackglass Theme"
echo "======================================"

# ------------------------------------------------------------
# Determine real user and paths
# ------------------------------------------------------------
REAL_USER="${SUDO_USER:-$(whoami)}"

echo "==> Configuring for user: $REAL_USER"

# ------------------------------------------------------------
# Verify SDDM is installed
# ------------------------------------------------------------
if ! command -v sddm >/dev/null; then
  echo "ERROR: SDDM is not installed"
  echo "Please install SDDM first (e.g., via archinstall or pacman -S sddm)"
  exit 1
fi

echo "==> SDDM found"

# ------------------------------------------------------------
# Install custom SDDM theme: blackglass
# ------------------------------------------------------------
echo "==> Installing blackglass theme"

# The repo may be cloned anywhere (~/invictus, or ~/hyprdots on older machines).
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THEME_SRC="$SCRIPT_DIR/../assets/SDDM/blackglass"
THEME_DST="/usr/share/sddm/themes/blackglass"

if [[ ! -d "$THEME_SRC" ]]; then
  echo "ERROR: Theme source not found at $THEME_SRC"
  exit 1
fi

# Verify theme has required files
if [[ ! -f "$THEME_SRC/Main.qml" ]]; then
  echo "ERROR: Theme missing Main.qml"
  exit 1
fi

if [[ ! -f "$THEME_SRC/metadata.desktop" ]]; then
  echo "ERROR: Theme missing metadata.desktop"
  exit 1
fi

echo "==> Theme source validated"

# Remove existing theme if present
if [[ -d "$THEME_DST" ]]; then
  echo "==> Removing existing blackglass theme"
  rm -rf "$THEME_DST"
fi

# Copy theme files
echo "==> Copying theme files to $THEME_DST"
cp -r "$THEME_SRC" "$THEME_DST"

# Set correct permissions
chmod 755 "$THEME_DST"
find "$THEME_DST" -type f -exec chmod 644 {} \;
find "$THEME_DST" -type d -exec chmod 755 {} \;

echo "==> Theme files installed"

# ------------------------------------------------------------
# Configure SDDM to use blackglass theme
# ------------------------------------------------------------
echo "==> Configuring SDDM to use blackglass theme"

mkdir -p /etc/sddm.conf.d

cat >/etc/sddm.conf.d/theme.conf <<EOF
[Theme]
Current=blackglass
EOF

echo "==> SDDM configuration updated"

# ------------------------------------------------------------
# Verify installation
# ------------------------------------------------------------
echo
echo "==> Verifying installation..."

if [[ -d "$THEME_DST" ]]; then
  echo "✓ Theme directory created"
else
  echo "✗ ERROR: Theme directory not found"
  exit 1
fi

if [[ -f "$THEME_DST/Main.qml" ]]; then
  echo "✓ Main.qml present"
else
  echo "✗ ERROR: Main.qml missing"
  exit 1
fi

if [[ -f "$THEME_DST/metadata.desktop" ]]; then
  echo "✓ metadata.desktop present"
else
  echo "✗ ERROR: metadata.desktop missing"
  exit 1
fi

if [[ -f /etc/sddm.conf.d/theme.conf ]]; then
  echo "✓ SDDM theme configuration created"
else
  echo "✗ ERROR: Configuration file missing"
  exit 1
fi

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
echo
echo "======================================"
echo " Blackglass theme installation complete"
echo "======================================"
echo
echo "Theme installed at: $THEME_DST"
echo "Configuration: /etc/sddm.conf.d/theme.conf"
echo
echo "The theme will be applied on next SDDM restart."
echo "To test immediately:"
echo "  sudo systemctl restart sddm"
echo
