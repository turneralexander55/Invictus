#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# update.sh
#
# Updates:
#  - Repo (git pull)
#  - Pacman packages
#  - Paru (AUR) packages
#  - Invalidates Waybar update cache
#
# Developer mode: Aborts if local changes exist
# ------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# ------------------------------------------------------------
# Developer mode detection
# ------------------------------------------------------------

# Set this to your username or check for a sentinel file
DEVELOPER_MODE=false

# Option 1: Check for a sentinel file
if [[ -f "$REPO_ROOT/.developer" ]]; then
  DEVELOPER_MODE=true
fi

# Option 2: Check username (uncomment and modify)
# if [[ "$USER" == "yourusername" ]]; then
#   DEVELOPER_MODE=true
# fi

echo "==> Starting Invictus update"

if [[ "$DEVELOPER_MODE" == true ]]; then
  echo "==> DEVELOPER MODE ENABLED"
  echo "==> Will abort on any uncommitted changes"
fi

# ------------------------------------------------------------
# Ensure we are running on Arch Linux
# ------------------------------------------------------------

if [[ ! -f /etc/arch-release ]]; then
  echo "ERROR: This script is intended for Arch Linux only."
  exit 1
fi

# ------------------------------------------------------------
# Ensure git exists
# ------------------------------------------------------------

if ! command -v git &>/dev/null; then
  echo "ERROR: git not found. Please install git first."
  exit 1
fi

# ------------------------------------------------------------
# Check remote URL and provide guidance
# ------------------------------------------------------------

echo "==> Checking repository remote configuration..."

REMOTE_URL=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")

if [[ -z "$REMOTE_URL" ]]; then
  echo "WARNING: No remote origin configured."
  echo "Skipping repository update."
  SKIP_REPO_UPDATE=true
else
  SKIP_REPO_UPDATE=false
  echo "Remote URL: $REMOTE_URL"

  # Check if using HTTPS
  if [[ "$REMOTE_URL" =~ ^https:// ]]; then
    echo ""
    echo "NOTE: You're using HTTPS authentication."
    echo "If prompted for credentials, consider switching to SSH:"
    echo "  cd $REPO_ROOT"
    echo "  git remote set-url origin git@github.com:USERNAME/REPO.git"
    echo ""
  fi
fi

# ------------------------------------------------------------
# Pull latest repo changes
# ------------------------------------------------------------

if [[ "$SKIP_REPO_UPDATE" == false ]]; then
  echo "==> Checking repository status..."

  # Check for uncommitted changes (tracked files)
  if ! git -C "$REPO_ROOT" diff-index --quiet HEAD -- 2>/dev/null; then
    if [[ "$DEVELOPER_MODE" == true ]]; then
      echo ""
      echo "ERROR: You have uncommitted changes in tracked files."
      echo ""
      echo "Changed files:"
      git -C "$REPO_ROOT" diff --name-only HEAD
      echo ""
      echo "DEVELOPER MODE: Aborting to protect your work."
      echo "Please commit or stash your changes first."
      exit 1
    else
      echo "WARNING: You have uncommitted changes in the repository."
      echo "Stashing changes before pull..."
      git -C "$REPO_ROOT" stash push -m "Auto-stash by update.sh at $(date)"
      STASHED=true
    fi
  else
    STASHED=false
  fi

  # Check for untracked files
  UNTRACKED=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard)
  if [[ -n "$UNTRACKED" ]]; then
    if [[ "$DEVELOPER_MODE" == true ]]; then
      echo ""
      echo "ERROR: You have untracked files in the repository."
      echo ""
      echo "Untracked files:"
      echo "$UNTRACKED"
      echo ""
      echo "DEVELOPER MODE: Aborting to protect your work."
      echo "Please commit or remove these files first."
      exit 1
    else
      echo "WARNING: You have untracked files (they will not be affected by pull)"
    fi
  fi

  # Check for unpushed commits
  git -C "$REPO_ROOT" fetch origin

  LOCAL=$(git -C "$REPO_ROOT" rev-parse @)
  REMOTE=$(git -C "$REPO_ROOT" rev-parse "@{u}" 2>/dev/null || echo "$LOCAL")
  BASE=$(git -C "$REPO_ROOT" merge-base @ "@{u}" 2>/dev/null || echo "$LOCAL")

  if [[ "$LOCAL" != "$REMOTE" && "$LOCAL" != "$BASE" ]]; then
    # We have unpushed commits
    AHEAD=$(git -C "$REPO_ROOT" rev-list --count "@{u}"..@ 2>/dev/null || echo "0")

    if [[ "$DEVELOPER_MODE" == true ]]; then
      echo ""
      echo "ERROR: You have $AHEAD unpushed commit(s)."
      echo ""
      echo "Recent unpushed commits:"
      git -C "$REPO_ROOT" log --oneline "@{u}"..@ 2>/dev/null || true
      echo ""
      echo "DEVELOPER MODE: Aborting to protect your work."
      echo "Please push your commits first."
      exit 1
    else
      echo "WARNING: You have $AHEAD unpushed commit(s)."
      echo "These will not be affected, but consider pushing them."
    fi
  fi

  # Check if we're behind
  if [[ "$LOCAL" == "$REMOTE" ]]; then
    echo "==> Repository is already up to date."
  else
    # Pull with fast-forward only
    echo "==> Pulling latest changes..."
    if git -C "$REPO_ROOT" pull --ff-only; then
      echo "==> Repo updated successfully."
    else
      echo "ERROR: Failed to pull. You may need to resolve conflicts manually."
      if [[ "$STASHED" == true ]]; then
        echo "Restoring stashed changes..."
        git -C "$REPO_ROOT" stash pop
      fi
      exit 1
    fi
  fi

  # Restore stashed changes if any
  if [[ "$STASHED" == true ]]; then
    echo "==> Restoring stashed changes..."
    if ! git -C "$REPO_ROOT" stash pop; then
      echo "WARNING: Stash pop had conflicts. Please resolve manually."
      echo "Your stashed changes are still saved in git stash."
    fi
  fi

  echo
fi

# ------------------------------------------------------------
# Ensure pacman exists
# ------------------------------------------------------------

if ! command -v pacman &>/dev/null; then
  echo "ERROR: pacman not found. Is this an Arch-based system?"
  exit 1
fi

# ------------------------------------------------------------
# Update pacman packages
# ------------------------------------------------------------

echo "==> Updating pacman packages..."

sudo pacman -Syu --noconfirm

echo "==> Pacman packages updated successfully."

echo

# ------------------------------------------------------------
# Update AUR packages with paru
# ------------------------------------------------------------

if ! command -v paru &>/dev/null; then
  echo "WARNING: paru not found. Skipping AUR package updates."
  echo "Install paru first to enable AUR updates."
else
  echo "==> Updating AUR packages with paru..."

  paru -Sua --noconfirm

  echo "==> AUR packages updated successfully."
fi

# ------------------------------------------------------------
# Invalidate Waybar update cache
# ------------------------------------------------------------

echo
echo "==> Refreshing Waybar update counter..."

CACHE_FILE="$HOME/.cache/waybar-updates.cache"
if [[ -f "$CACHE_FILE" ]]; then
  rm -f "$CACHE_FILE"
  echo "Update cache cleared."
fi

# Signal Waybar to refresh (if running)
if command -v pkill &>/dev/null; then
  pkill -RTMIN+8 waybar 2>/dev/null || true
fi

echo
echo "==> Update complete!"
echo "The update counter will refresh within 5 minutes."
