#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-update: the one update path (design 1.4). Installed as
# /usr/bin/invictus-update by invictus-tools; replaces
# legacy/update.sh on machines that run the packages.
#
#   invictus-update              pacman -Syu, then invictus-doctor
#   invictus-update --noconfirm  no pacman questions
#   invictus-update --aur        also paru -Sua afterwards (builds AUR
#                                packages you installed yourself)
#
# What it never does: git pull, git stash, or a partial upgrade
# (pacman -Sy without -u). The desktop config arrives inside the
# packages; your own files in ~/.config are never touched.
#
# Snapshots: where snap-pac is installed, pacman's own hooks take a
# pre and post snapshot around the -Syu. This script does not.
#
# Exit: pacman's code if pacman fails; 3 if the doctor finds a
# problem after a good update; 0 otherwise.
# Env (tests): INVICTUS_PACMAN, INVICTUS_SUDO, INVICTUS_DOCTOR, INVICTUS_PARU
# ------------------------------------------------------------
set -euo pipefail

PACMAN="${INVICTUS_PACMAN:-pacman}"
DOCTOR="${INVICTUS_DOCTOR:-invictus-doctor}"
PARU="${INVICTUS_PARU:-paru}"
if [[ -n "${INVICTUS_SUDO+x}" ]]; then SUDO="$INVICTUS_SUDO"
elif [[ $EUID -eq 0 ]]; then SUDO=""
else SUDO="sudo"; fi

CONFIRM=()
AUR=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --noconfirm) CONFIRM=(--noconfirm); shift ;;
        --aur) AUR=true; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "invictus-update: unknown argument $1" >&2; exit 2 ;;
    esac
done

echo "==> Invictus update"

if pacman -Q snap-pac >/dev/null 2>&1; then
    echo "==> snap-pac will take a snapshot before and after"
elif [[ "$(findmnt -no FSTYPE / 2>/dev/null)" == btrfs ]]; then
    echo "==> Note: / is btrfs but snap-pac is not installed, so no snapshot is taken"
fi

# The whole system at once. Never -Sy on its own.
echo "==> ${SUDO:+$SUDO }$PACMAN -Syu ${CONFIRM[*]}"
set +e
${SUDO:+"$SUDO"} "$PACMAN" -Syu "${CONFIRM[@]}"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    echo "==> pacman stopped (exit $rc). Nothing else was run."
    exit "$rc"
fi

if $AUR; then
    if command -v "$PARU" >/dev/null; then
        echo "==> $PARU -Sua ${CONFIRM[*]}"
        "$PARU" -Sua "${CONFIRM[@]}"
    else
        echo "==> --aur: paru is not installed, skipped"
    fi
elif command -v "$PARU" >/dev/null && n="$("$PARU" -Qua 2>/dev/null | grep -c .)" && [[ "$n" -gt 0 ]]; then
    echo "==> $n AUR package(s) you installed yourself have updates: invictus-update --aur"
fi

# Waybar's update counter
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.cache"
pkill -RTMIN+8 waybar 2>/dev/null || true

echo
echo "==> Checking the system after the update"
if "$DOCTOR" --post-update; then
    echo "==> Update complete."
else
    echo "==> Updated, but invictus-doctor found a problem (above)."
    exit 3
fi
