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
#   invictus-update --system     the system half only: the doctor's system
#                                checks, nothing in any home folder (no
#                                waybar cache, no paru). invictus-sys update
#                                runs this as root, then the per-user checks
#                                as you. Always on when run as root.
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
# Env (tests): INVICTUS_PACMAN, INVICTUS_SUDO, INVICTUS_DOCTOR, INVICTUS_PARU,
#   INVICTUS_LIB (where lib/pacman.sh is), INVICTUS_SYS_ROOT (prefix for the
#   ssh generator mask check)
# ------------------------------------------------------------
set -euo pipefail

PACMAN="${INVICTUS_PACMAN:-pacman}"
DOCTOR="${INVICTUS_DOCTOR:-invictus-doctor}"
PARU="${INVICTUS_PARU:-paru}"
# ssh_mask_overwrite (Janus P-L2): a dev install's unowned generator mask
# shellcheck source=scripts/lib/pacman.sh
. "${INVICTUS_LIB:-/usr/lib/invictus}/lib/pacman.sh"
if [[ -n "${INVICTUS_SUDO+x}" ]]; then SUDO="$INVICTUS_SUDO"
elif [[ $EUID -eq 0 ]]; then SUDO=""
else SUDO="sudo"; fi

CONFIRM=()
AUR=false
# Root never reads a person's home (Janus H1): as root, system half only.
SYSTEM=false
[[ $EUID -eq 0 ]] && SYSTEM=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --noconfirm) CONFIRM=(--noconfirm); shift ;;
        --aur) AUR=true; shift ;;
        --system) SYSTEM=true; shift ;;
        -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
        *) echo "invictus-update: unknown argument $1" >&2; exit 2 ;;
    esac
done
if $SYSTEM && $AUR; then
    echo "invictus-update: --aur builds your own AUR packages; run it as yourself, without --system" >&2
    exit 2
fi

echo "==> Invictus update"

if pacman -Q snap-pac >/dev/null 2>&1; then
    echo "==> snap-pac will take a snapshot before and after"
elif [[ "$(findmnt -no FSTYPE / 2>/dev/null)" == btrfs ]]; then
    echo "==> Note: / is btrfs but snap-pac is not installed, so no snapshot is taken"
fi

# The whole system at once. Never -Sy on its own. On a dev install from
# before invictus-sys 0.2.0-5, pacman may replace the installer's unowned
# ssh generator mask with the package's identical one (that path only).
ssh_mask_overwrite
echo "==> ${SUDO:+$SUDO }$PACMAN -Syu ${CONFIRM[*]} ${PACMAN_OVERWRITE[*]}"
set +e
${SUDO:+"$SUDO"} "$PACMAN" -Syu "${CONFIRM[@]}" "${PACMAN_OVERWRITE[@]}"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    echo "==> pacman stopped (exit $rc). Nothing else was run."
    exit "$rc"
fi

if $SYSTEM; then
    :
elif $AUR; then
    if command -v "$PARU" >/dev/null; then
        echo "==> $PARU -Sua ${CONFIRM[*]}"
        "$PARU" -Sua "${CONFIRM[@]}"
    else
        echo "==> --aur: paru is not installed, skipped"
    fi
elif command -v "$PARU" >/dev/null && n="$("$PARU" -Qua 2>/dev/null | grep -c .)" && [[ "$n" -gt 0 ]]; then
    echo "==> $n AUR package(s) you installed yourself have updates: invictus-update --aur"
fi

# Waybar's update counter (the person's own cache and bar; invictus-sys
# does this in its user half)
if ! $SYSTEM; then
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.cache"
    pkill -RTMIN+8 waybar 2>/dev/null || true
fi

echo
echo "==> Checking the system after the update"
doctor_args=(--post-update)
$SYSTEM && doctor_args+=(--system)
if "$DOCTOR" "${doctor_args[@]}"; then
    echo "==> Update complete."
else
    echo "==> Updated, but invictus-doctor found a problem (above)."
    exit 3
fi
