#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-cleanup ROOT: turn the unpacked live image into an installed
# system. Runs right after unpackfs and machineid, before users, fstab and
# the initramfs (design 2.2, jobs/invictus-cleanup).
#
#  1. Delete every live-only file listed in live-only.txt (the live user's
#     autologin, its sudo rule, the archiso mkinitcpio drop-in, volatile
#     journald, ...). tests/iso/profile.sh checks that every file the ISO
#     profile adds is either on that list or on keep.txt.
#  2. Remove the live user `liber` and its home, so the person's account
#     gets uid 1000.
#  3. Remove the live-only packages (installer, Calamares, cage).
#  4. Lock root: the live image has an empty root password; an installed
#     machine never does (design-simple-mode 1.3; Calamares
#     setRootPassword: false only hides the field).
#  5. Set up pacman's keyring (the live one is a tmpfs and is not copied).
# ------------------------------------------------------------
set -euo pipefail
JOB_NAME=invictus-cleanup
# shellcheck source=installer/jobs/lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

need_root "${1:-}"

LIVE_USER="liber"
LIVE_PACKAGES="invictus-installer calamares cage"

# ---- 1. live-only files -----------------------------------------------------
list="$INVICTUS_INSTALLER_DATA/live-only.txt"
[[ -f "$list" ]] || die "missing $list"
while IFS= read -r path || [[ -n "$path" ]]; do
    path="${path%%#*}"
    path="${path//[[:space:]]/}"
    [[ -n "$path" ]] || continue
    # Absolute, no '..', no '//', not a top-level folder.
    [[ "$path" == /* && "$path" != *..* && "$path" != *//* ]] || die "bad path in live-only.txt: $path"
    [[ "$path" == /*/* ]] || die "refusing to delete a top-level folder: $path"
    if [[ -e "$ROOT$path" || -L "$ROOT$path" ]]; then
        rm -rf -- "${ROOT:?}$path"
        say "removed $path"
    fi
done <"$list"

# ---- 2. live user -----------------------------------------------------------
if grep -q "^$LIVE_USER:" "$ROOT/etc/passwd"; then
    in_target userdel --remove "$LIVE_USER" || die "could not remove the live user $LIVE_USER"
    say "removed user $LIVE_USER"
fi
rm -rf -- "${ROOT:?}/home/$LIVE_USER"
# userdel leaves a group of the same name when other users are in it.
if grep -q "^$LIVE_USER:" "$ROOT/etc/group"; then
    in_target groupdel "$LIVE_USER" || true
fi

# ---- 3. live-only packages --------------------------------------------------
remove=()
for p in $LIVE_PACKAGES; do
    if in_target pacman -Q "$p" >/dev/null 2>&1; then remove+=("$p"); fi
done
if ((${#remove[@]})); then
    in_target pacman -Rns --noconfirm "${remove[@]}" || die "could not remove ${remove[*]}"
    say "removed packages ${remove[*]}"
fi

# ---- 4. lock root -----------------------------------------------------------
# Edit the target's shadow directly: '!*' is a locked account with no
# password. Checked afterwards, because an unlocked root is a hole.
shadow="$ROOT/etc/shadow"
[[ -f "$shadow" ]] || die "no /etc/shadow in the target"
tmp="$(mktemp "$shadow.XXXXXX")"
awk -F: -v OFS=: '$1 == "root" { $2 = "!*" } { print }' "$shadow" >"$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$shadow"
root_pw="$(awk -F: '$1 == "root" { print $2 }' "$shadow")"
[[ "$root_pw" == '!'* ]] || die "root is not locked (shadow field '$root_pw')"
say "root locked"

# ---- 5. pacman keyring -------------------------------------------------------
in_target pacman-key --init || die "pacman-key --init failed"
in_target pacman-key --populate || die "pacman-key --populate failed"
say "pacman keyring ready"
