#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# deploy-shell.sh
#
# Deploy shell configuration files (e.g. .zshrc)
# Copies files into $HOME with guarded overwrites
# Sets zsh as the default shell
# Requires --force and per-file confirmation
# ------------------------------------------------------------

FORCE=false

# ------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
elif [[ $# -gt 0 ]]; then
  echo "ERROR: Unknown argument: $1"
  echo
  echo "Usage:"
  echo "  $0 --force"
  exit 1
fi

if [[ "$FORCE" != true ]]; then
  echo "ERROR: This script will overwrite shell config files."
  echo "You must run it with --force to proceed."
  echo
  echo "Example:"
  echo "  ./legacy/deploy-shell.sh --force"
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR/../config/shell"
HOME_DIR="$HOME"

echo "==> deploy-shell.sh running in FORCE mode"
echo

# ------------------------------------------------------------
# Ensure zsh is installed
# ------------------------------------------------------------

if ! command -v zsh &>/dev/null; then
  echo "ERROR: zsh is not installed."
  echo "Please install zsh first:"
  echo "  sudo pacman -S zsh"
  exit 1
fi

ZSH_PATH=$(which zsh)
echo "Found zsh at: $ZSH_PATH"
echo

# ------------------------------------------------------------
# Deploy .zshrc
# ------------------------------------------------------------

SRC="$DOTFILES_DIR/zshrc"
DEST="$HOME_DIR/.zshrc"

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: zshrc not found in repo at $SRC"
  exit 1
fi

if [[ -f "$DEST" ]]; then
  echo ".zshrc already exists at $DEST"
  read -r -p "Overwrite ~/.zshrc? A backup will be created. [y/N] " reply
  echo

  case "$reply" in
    y|Y|yes|YES)
      echo "Backing up existing .zshrc to ~/.zshrc.bak"
      cp "$DEST" "$DEST.bak"
      ;;
    *)
      echo "Skipping .zshrc"
      SKIP_ZSHRC=true
      ;;
  esac
fi

if [[ "${SKIP_ZSHRC:-false}" != true ]]; then
  echo "Installing .zshrc"
  cp "$SRC" "$DEST"
  echo "✓ .zshrc installed"
fi

echo

# ------------------------------------------------------------
# Set zsh as default shell
# ------------------------------------------------------------

CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)

if [[ "$CURRENT_SHELL" == "$ZSH_PATH" ]]; then
  echo "✓ zsh is already your default shell"
else
  echo "Current shell: $CURRENT_SHELL"
  echo "Target shell: $ZSH_PATH"
  echo
  read -r -p "Set zsh as your default shell? [Y/n] " shell_reply
  echo

  case "$shell_reply" in
    n|N|no|NO)
      echo "Skipping shell change"
      ;;
    *)
      echo "Changing default shell to zsh..."

      # Ensure zsh is in /etc/shells
      if ! grep -q "^${ZSH_PATH}$" /etc/shells; then
        echo "Adding $ZSH_PATH to /etc/shells (requires sudo)"
        echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
      fi

      # Change the user's shell
      chsh -s "$ZSH_PATH"

      echo "✓ Default shell changed to zsh"
      echo
      echo "IMPORTANT: You must log out and log back in for the change to take effect."
      echo "Or simply run: exec zsh"
      ;;
  esac
fi

echo
echo "==> Shell configuration deployment complete."
