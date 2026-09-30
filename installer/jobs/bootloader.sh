#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-bootloader ROOT: install limine with bootable snapshots.
# Upstream Calamares has no limine module (design 2.2), so this job does it
# with limine-entry-tool (limine-mkinitcpio-hook) the way its README says:
#
#  1. UEFI only (D5): the live system must have booted in UEFI mode and the
#     ESP must be a FAT file system mounted at ROOT/boot.
#  2. Kernel command line from the mounted target: root by file-system UUID
#     (or rd.luks.name=... when / is LUKS), rootflags=subvol=/@, quiet splash.
#     Written to /etc/default/limine, the one file limine-entry-tool and
#     limine-snapper-sync both read; without it the tool would copy the live
#     ISO's /proc/cmdline.
#  3. limine.conf header in Venus's Dusk colours (look.md, Boot splash and
#     ISO), written before the tool runs so it keeps ours instead of its
#     default header.
#  4. mkinitcpio HOOKS: systemd hooks with sd-btrfs-overlayfs after
#     filesystems (boots read-only snapshots; the busybox btrfs-overlayfs
#     does not work with systemd hooks). initcpiocfg normally writes this;
#     the job checks it and fixes it if not.
#  5. limine-install --no-efi-register (EFI binary, fallback copy), then
#     limine-mkinitcpio (initramfs and one entry per kernel: linux,
#     linux-lts), then an NVRAM entry labelled "Invictus" (limine-install
#     would label it "Limine"; it finds ours by path next time and does not
#     add a second). If the firmware refuses the entry, limine goes in the
#     removable-media fallback path instead.
#  6. Check the result: an Invictus entry with a kernel in limine.conf, the
#     limine EFI binary on the ESP.
# ------------------------------------------------------------
set -euo pipefail
JOB_NAME=invictus-bootloader
# shellcheck source=installer/jobs/lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

need_root "${1:-}"
EFI_SYSFS="${INVICTUS_EFI_SYSFS:-/sys/firmware/efi}"
OS_NAME="Invictus"
ROOT_SUBVOL="/@"

# ---- 1. UEFI and the ESP ------------------------------------------------------
[[ -d "$EFI_SYSFS" ]] || die "this computer did not start in UEFI mode; Invictus needs UEFI (design D5)"
esp_fs="$(findmnt -n -o FSTYPE --mountpoint "$ROOT/boot" || true)"
[[ "$esp_fs" == vfat ]] || die "no FAT EFI system partition mounted at /boot (found '${esp_fs:-nothing}')"

# ---- 2. kernel command line ---------------------------------------------------
root_src="$(findmnt -n -o SOURCE --mountpoint "$ROOT")" || die "target root is not mounted"
root_src="${root_src%%\[*}"
root_fs="$(findmnt -n -o FSTYPE --mountpoint "$ROOT")"
root_uuid="$(findmnt -n -o UUID --mountpoint "$ROOT")"
root_opts="$(findmnt -n -o OPTIONS --mountpoint "$ROOT")"
[[ "$root_fs" == btrfs ]] || die "the root file system is $root_fs; Invictus needs btrfs"
[[ -n "$root_uuid" ]] || die "no UUID for the root file system"
[[ ",$root_opts," == *",subvol=$ROOT_SUBVOL,"* ]] \
    || die "root is not the $ROOT_SUBVOL subvolume (options: $root_opts)"

if [[ "$root_src" == /dev/mapper/* ]]; then
    mapper="${root_src#/dev/mapper/}"
    backing="$(cryptsetup status "$mapper" | awk '$1 == "device:" { print $2 }')"
    [[ -n "$backing" ]] || die "/ is on $root_src but it is not a LUKS mapping"
    luks_uuid="$(blkid -s UUID -o value "$backing")"
    [[ -n "$luks_uuid" ]] || die "no LUKS UUID for $backing"
    cmdline="rd.luks.name=$luks_uuid=$mapper root=/dev/mapper/$mapper"
else
    cmdline="root=UUID=$root_uuid"
fi
cmdline="$cmdline rootflags=subvol=$ROOT_SUBVOL rw quiet splash"
say "kernel command line: $cmdline"

write_file /etc/default/limine 644 <<EOF
# Written by the Invictus installer. Read by limine-entry-tool
# (limine-update, the kernel pacman hooks) and limine-snapper-sync.
# Change the command line here, then run limine-update.
ESP_PATH="/boot"
TARGET_OS_NAME="$OS_NAME"
KERNEL_CMDLINE[default]=$cmdline
ENABLE_VERIFICATION=yes
BOOT_ORDER="*, *lts*, *fallback, Snapshots"
FIND_BOOTLOADERS=yes

# limine-snapper-sync (design 2.2): the @snapshots subvolume is mounted at
# /.snapshots; keep the ESP under 85% full.
SNAPPER_CONFIG_NAME="root"
ROOT_SUBVOLUME_PATH="$ROOT_SUBVOL"
ROOT_SNAPSHOTS_PATH="/@snapshots"
LIMIT_USAGE_PERCENT=85
RESTORE_METHOD=replace
EOF

# ---- 3. limine.conf header ----------------------------------------------------
conf="$ROOT/boot/limine.conf"
header="$INVICTUS_INSTALLER_DATA/limine-header.conf"
[[ -f "$header" ]] || die "missing $header"
if [[ -f "$conf" ]]; then
    cp -f "$conf" "$conf.before-invictus"
    say "kept the existing limine.conf as limine.conf.before-invictus"
fi
cp -f "$header" "$conf"

# ---- 4. mkinitcpio hooks --------------------------------------------------------
mk="$ROOT/etc/mkinitcpio.conf"
[[ -f "$mk" ]] || die "no /etc/mkinitcpio.conf in the target"
[[ ! -e "$ROOT/etc/mkinitcpio.conf.d/archiso.conf" ]] \
    || die "the live ISO's mkinitcpio drop-in is still in the target (cleanup did not run)"
hooks_line="$(grep -E '^[[:space:]]*HOOKS=' "$mk" | tail -n 1)"
[[ -n "$hooks_line" ]] || die "no HOOKS= line in /etc/mkinitcpio.conf"
read -ra hooks <<<"$(sed -E 's/^[[:space:]]*HOOKS=\(([^)]*)\).*/\1/' <<<"$hooks_line")"
has_hook() { local h; for h in "${hooks[@]}"; do [[ "$h" == "$1" ]] && return 0; done; return 1; }
has_hook systemd || die "mkinitcpio HOOKS do not use the systemd hook: ${hooks[*]}"
has_hook filesystems || die "mkinitcpio HOOKS have no filesystems hook: ${hooks[*]}"
if ! has_hook sd-btrfs-overlayfs; then
    new=()
    for h in "${hooks[@]}"; do
        new+=("$h")
        [[ "$h" == filesystems ]] && new+=(sd-btrfs-overlayfs)
    done
    hooks=("${new[@]}")
    tmp="$(mktemp "$mk.XXXXXX")"
    awk -v line="HOOKS=(${hooks[*]})" '/^[[:space:]]*HOOKS=/ && !done { print line; done = 1; next } { print }' "$mk" >"$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$mk"
    say "added sd-btrfs-overlayfs to HOOKS"
fi
# sd-btrfs-overlayfs must come after filesystems.
pos_fs=-1 pos_ov=-1
for i in "${!hooks[@]}"; do
    [[ "${hooks[$i]}" == filesystems ]] && pos_fs=$i
    [[ "${hooks[$i]}" == sd-btrfs-overlayfs ]] && pos_ov=$i
done
((pos_ov > pos_fs)) || die "sd-btrfs-overlayfs is before filesystems in HOOKS: ${hooks[*]}"
say "HOOKS=(${hooks[*]})"

# ---- 5. install -------------------------------------------------------------------
in_target limine-install --no-efi-register || die "limine-install failed"
in_target limine-mkinitcpio || die "limine-mkinitcpio failed"

esp_src="$(findmnt -n -o SOURCE --mountpoint "$ROOT/boot")"
esp_disk="/dev/$(lsblk -n -d -o PKNAME "$esp_src" 2>/dev/null | head -n 1)"
esp_part="$(lsblk -n -d -o PARTN "$esp_src" 2>/dev/null | head -n 1 | tr -d ' ')"
loader='\EFI\limine\limine_x64.efi'
registered=false
if in_target efibootmgr 2>/dev/null | grep -Fqi 'limine_x64.efi'; then
    say "an NVRAM entry for limine already exists"
    registered=true
elif [[ "$esp_disk" != /dev/ && "$esp_part" =~ ^[0-9]+$ ]] \
    && in_target efibootmgr --create --disk "$esp_disk" --part "$esp_part" \
        --label "$OS_NAME" --loader "$loader" --unicode >/dev/null; then
    say "firmware boot entry '$OS_NAME' added ($esp_disk partition $esp_part)"
    registered=true
fi
if ! $registered; then
    # Some firmware refuses new entries (full NVRAM, some MSI boards: the
    # case limine-entry-tool's SKIP_UEFI is for), and some ESPs are not a
    # plain disk partition. Then the machine starts limine from the
    # removable-media path instead.
    in_target limine-install --no-efi-register --fallback || die "could not install limine as the fallback loader either"
    [[ -f "$ROOT/boot/EFI/BOOT/BOOTX64.EFI" ]] || die "no fallback loader on the ESP"
    say "WARNING: no firmware boot entry ($esp_src); limine is the fallback loader (EFI/BOOT/BOOTX64.EFI)"
fi

# ---- 6. check -------------------------------------------------------------------------
[[ -f "$ROOT/boot/EFI/limine/limine_x64.efi" ]] || die "limine EFI binary missing from the ESP"
grep -Eq "^/\+?$OS_NAME\b" "$conf" || die "no $OS_NAME entry in limine.conf"
# limine-entry-tool writes "//linux" entries with "path: boot():/<machine-id>/linux/vmlinuz#<hash>"
# and our command line (format seen in the first VM install).
grep -Eq '^[[:space:]]+path: boot\(\):/[^ ]+/vmlinuz' "$conf" || die "no kernel entry in limine.conf"
grep -Fq "cmdline: $cmdline" "$conf" || die "the kernel entries in limine.conf do not carry the command line"
say "limine installed"
