#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-snapper ROOT: snapper for / and /home (design 2.2,
# design-simple-mode 2.5 and 12.2). Runs after the bootloader job, so
# limine-snapper-sync finds limine.conf.
#
#  1. Each config keeps its snapshots on its own subvolume: @snapshots at
#     /.snapshots, @home-snapshots at /home/.snapshots. `snapper
#     create-config` wants to make a nested .snapshots subvolume instead, so
#     for each: unmount ours, let snapper do that, delete the nested one,
#     mount ours back (the Arch wiki recipe). fstab already has both lines
#     from Calamares.
#  2. root: no timeline (snapshots on change: snap-pac, the pre-admin
#     snapshot; design 2.2 keeps the ESP under LIMIT_USAGE_PERCENT), 10
#     numbered, 10 important.
#     home: hourly timeline, 24 hourly and 7 daily (DS12), and
#     ALLOW_GROUPS=users with SYNC_ACL=yes so a person can open
#     /home/.snapshots/<n>/snapshot/<their folder> ("Look inside", 12.2).
#     Set through `snapper set-config`, which also applies the ACLs.
#  3. Enable snapper-cleanup.timer, snapper-timeline.timer and
#     limine-snapper-sync.service.
#  4. Snapshot 1 of / "Fresh install", then one limine-snapper-sync run so it
#     is in the boot menu from the first boot (not fatal if the sync cannot
#     run in the installer's chroot: the service syncs on first boot).
#  5. The Windows VM folder (@vm) gets No_COW: btrfs mount options such as
#     nodatacow apply to the whole file system, not one subvolume, so the
#     design's per-subvolume option would not work (build note).
# ------------------------------------------------------------
set -euo pipefail
JOB_NAME=invictus-snapper
# shellcheck source=installer/jobs/lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

need_root "${1:-}"
VM_DIR="$ROOT/var/lib/invictus/vm"

# snapper_config NAME PATH SUBVOLUME: create config NAME for PATH (inside the
# target) with its .snapshots on SUBVOLUME.
snapper_config() {
    local name="$1" path="$2" subvol="$3"
    local snap="$ROOT${path%/}/.snapshots" opts dev mount_opts
    opts="$(findmnt -n -o OPTIONS --mountpoint "$snap" || true)"
    [[ ",$opts," == *",subvol=$subvol,"* ]] \
        || die "${path%/}/.snapshots is not the ${subvol#/} subvolume (options: '${opts}')"
    dev="$(findmnt -n -o SOURCE --mountpoint "$snap")"
    dev="${dev%%\[*}"
    mount_opts="$(tr ',' '\n' <<<"$opts" | grep -Ev '^(subvol|subvolid)=' | paste -sd, -)"

    umount "$snap"
    rmdir "$snap"
    in_target snapper --no-dbus -c "$name" create-config "$path" || die "snapper create-config $name failed"
    [[ -f "$ROOT/etc/snapper/configs/$name" ]] || die "snapper wrote no config for $name"
    if [[ -d "$snap" ]]; then
        btrfs subvolume delete "$snap" >/dev/null || die "could not delete snapper's nested ${path%/}/.snapshots"
    fi
    install -d -m 750 "$snap"
    mount -o "subvol=$subvol,$mount_opts" "$dev" "$snap" || die "could not mount ${subvol#/} back"
    chmod 750 "$snap"
    say "$name: ${subvol#/} mounted at ${path%/}/.snapshots"
}

# ---- 1 and 2. configs ----------------------------------------------------------
snapper_config root / /@snapshots
in_target snapper --no-dbus -c root set-config \
    TIMELINE_CREATE=no NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=10 \
    || die "could not configure snapper for /"
say "root: no timeline, keep 10 + 10 important"

snapper_config home /home /@home-snapshots
in_target snapper --no-dbus -c home set-config \
    TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
    TIMELINE_LIMIT_HOURLY=24 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=0 \
    TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 \
    NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=10 \
    ALLOW_GROUPS=users SYNC_ACL=yes \
    || die "could not configure snapper for /home"
say "home: hourly for a day, daily for a week; readable by the users group"

# ---- 3. services ------------------------------------------------------------------
in_target systemctl enable snapper-cleanup.timer snapper-timeline.timer limine-snapper-sync.service \
    || die "could not enable the snapshot services"

# ---- 4. first snapshot ---------------------------------------------------------------
in_target snapper --no-dbus -c root create --type single --cleanup-algorithm number \
    --userdata important=yes --description "Fresh install" || die "could not create the first snapshot"
say "snapshot 1: Fresh install"
if in_target limine-snapper-sync; then
    say "snapshot entries added to the boot menu"
else
    say "limine-snapper-sync could not run here; the service adds the entries on first boot"
fi

# ---- 5. VM folder -------------------------------------------------------------------
if [[ -d "$VM_DIR" ]]; then
    chattr +C "$VM_DIR" || die "could not set No_COW on /var/lib/invictus/vm"
    say "No_COW on /var/lib/invictus/vm"
fi
