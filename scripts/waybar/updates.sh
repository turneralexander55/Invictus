#!/usr/bin/env bash

# ------------------------------------------------------------
# waybar-updates.sh
# Checks for available system updates (pacman + AUR)
# Returns JSON for waybar custom module
#
# Uses checkupdates which syncs to a temp database
# ------------------------------------------------------------

set -euo pipefail

# Shared cache file (same for all Waybar instances)
CACHE_FILE="$HOME/.cache/waybar-updates.cache"
CACHE_DIR="$(dirname "$CACHE_FILE")"
LOCK_FILE="$CACHE_DIR/waybar-updates.lock"

# Cache validity: 10 minutes (600 seconds)
CACHE_MAX_AGE=600

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# ------------------------------------------------------------
# Function: Get cached result if valid
# ------------------------------------------------------------
get_cached_result() {
    if [[ -f "$CACHE_FILE" ]]; then
        local cache_time
        cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        local current_time
        current_time=$(date +%s)
        local age=$((current_time - cache_time))
        # Packages changed since the count was cached (any pacman or paru
        # transaction touches the local database): the count is stale.
        local db_time
        db_time=$(stat -c %Y /var/lib/pacman/local 2>/dev/null || echo 0)

        if [[ $age -lt $CACHE_MAX_AGE && $db_time -le $cache_time ]]; then
            cat "$CACHE_FILE"
            return 0
        fi
    fi
    return 1
}

# ------------------------------------------------------------
# Try to get cached result first (fast path)
# ------------------------------------------------------------
if get_cached_result; then
    exit 0
fi

# ------------------------------------------------------------
# Acquire lock to prevent simultaneous updates
# ------------------------------------------------------------
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    # Another instance is updating, wait and use cache
    flock -w 10 200 || exit 0
    get_cached_result || echo '{"text":"?","tooltip":"Checking for updates..."}'
    exit 0
fi

# ------------------------------------------------------------
# Count official repo updates
# ------------------------------------------------------------
UPDATES=0

if command -v checkupdates &>/dev/null; then
    # checkupdates syncs to a temporary database automatically
    # Exit code 2 = no updates (normal)
    # Exit code 0 = updates found
    # Other codes = error

    if PACMAN_OUTPUT=$(checkupdates 2>&1); then
        # Count non-empty lines
        UPDATES=$(echo "$PACMAN_OUTPUT" | sed '/^\s*$/d' | wc -l)
    elif [[ $? -eq 2 ]]; then
        # Exit code 2 means no updates available (this is success)
        UPDATES=0
    else
        # Some other error - try fallback
        UPDATES=0
    fi
else
    # Fallback: pacman -Qu (works on systems without pacman-contrib)
    if PACMAN_OUTPUT=$(pacman -Qu 2>/dev/null); then
        UPDATES=$(echo "$PACMAN_OUTPUT" | sed '/^\s*$/d' | wc -l)
    fi
fi

# ------------------------------------------------------------
# Count AUR updates if paru is installed
# ------------------------------------------------------------
AUR_UPDATES=0

if command -v paru &>/dev/null; then
    if AUR_OUTPUT=$(paru -Qua 2>/dev/null); then
        AUR_UPDATES=$(echo "$AUR_OUTPUT" | sed '/^\s*$/d' | wc -l)
    fi
fi

TOTAL=$((UPDATES + AUR_UPDATES))

# ------------------------------------------------------------
# Build tooltip
# ------------------------------------------------------------
TIMESTAMP=$(date '+%b %d, %H:%M')

if [[ $TOTAL -eq 0 ]]; then
    TOOLTIP="System up to date\\nLast check: $TIMESTAMP"
else
    TOOLTIP="$TOTAL update(s) available\\n"
    [[ $UPDATES -gt 0 ]] && TOOLTIP+="  Pacman: $UPDATES\\n"
    [[ $AUR_UPDATES -gt 0 ]] && TOOLTIP+="  AUR: $AUR_UPDATES\\n"
    TOOLTIP+="Last check: $TIMESTAMP"
fi

# ------------------------------------------------------------
# Build JSON output
# ------------------------------------------------------------
if [[ $TOTAL -gt 0 ]]; then
    OUTPUT="{\"text\":\"$TOTAL\",\"tooltip\":\"$TOOLTIP\",\"class\":\"has-updates\"}"
else
    OUTPUT="{\"text\":\"0\",\"tooltip\":\"$TOOLTIP\",\"class\":\"up-to-date\"}"
fi

# ------------------------------------------------------------
# Write to cache and output
# ------------------------------------------------------------
echo "$OUTPUT" > "$CACHE_FILE"
echo "$OUTPUT"

# Release lock (automatic when script exits)
exit 0
