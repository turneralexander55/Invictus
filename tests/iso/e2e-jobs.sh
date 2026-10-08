#!/usr/bin/env bash
# ------------------------------------------------------------
# End-to-end test of the bootloader and snapper jobs with the real tools
# (limine-entry-tool, limine-snapper-sync, snapper, btrfs) on a real btrfs
# disk image. Run as root in a throwaway PRIVILEGED Arch container (loop
# devices, mounts):
#
#   docker run --rm --privileged -v "$PWD:/src:ro" -v "$PWD/out/iso-repo:/repo:ro" \
#       archlinux:base-devel bash /src/tests/iso/e2e-jobs.sh
#
# /repo must hold a repo made by scripts/build-iso.sh or build-repo.sh with
# limine-mkinitcpio-hook and limine-snapper-sync (they are AUR-only).
#
# It lays the disk out the way Calamares does (GPT, 1 GiB FAT ESP at /boot,
# btrfs with the mount.conf subvolumes), pacstraps a small system, writes
# the HOOKS line initcpiocfg writes, bind-mounts /proc, /sys, /dev and /run,
# then runs installer/jobs/bootloader.sh and snapper.sh against it and
# checks what they left. The container has no EFI variables and the ESP is
# a loop device, not a disk partition, so the job takes its fallback path
# (limine at EFI/BOOT/BOOTX64.EFI) and INVICTUS_EFI_SYSFS points at a
# stand-in folder; the NVRAM entry itself is only tested on hardware.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC="${1:-/src}"
REPO="${2:-/repo}"
[[ -f "$REPO/invictus-testing.db" ]] || { echo "No invictus-testing repo in $REPO." >&2; exit 2; }
grep -qw btrfs /proc/filesystems || { echo "The host kernel has no btrfs; this test cannot run here." >&2; exit 2; }

pass=0 fail=0
ok()  { echo "ok    $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

pacman -Syu --noconfirm --needed arch-install-scripts btrfs-progs dosfstools gptfdisk acl >/dev/null

W="$(mktemp -d)"
T="$W/target"
img="$W/disk.img"
truncate -s 16G "$img"
# GPT like Calamares makes it; each partition gets its own loop device at
# its offset (containers have no udev to create loopNpM nodes).
# No -q: in quiet mode sgdisk 1.0.x writes nothing to a blank image, so
# both "partitions" became offset 0 (CI run 36866977803). -o starts a GPT.
sgdisk -o -n1:0:+1G -t1:ef00 -n2:0:0 -t2:8300 "$img" >/dev/null
[[ "$(sgdisk -i 2 "$img" | awk '/^First sector/ { print $3 }')" =~ ^[0-9]+$ ]] || { echo "e2e-jobs: sgdisk wrote no partition table" >&2; exit 1; }
part_loop() {
    local start size
    read -r start size < <(sgdisk -i "$1" "$img" | awk '/^First sector/ { s = $3 } /^Last sector/ { e = $3 } END { print s, e - s + 1 }')
    losetup -f --show -o $((start * 512)) --sizelimit $((size * 512)) "$img"
}
# A privileged container sees only the loop nodes that existed when it
# started; make the next few so `losetup -f` hands out a usable node.
for i in $(seq 0 63); do [[ -e /dev/loop$i ]] || mknod -m 0660 "/dev/loop$i" b 7 "$i" 2>/dev/null || true; done
esp="$(part_loop 1)"
rootdev="$(part_loop 2)"
echo "e2e-jobs: ESP on $esp, root on $rootdev"
[[ -n "$esp" && -n "$rootdev" && "$esp" != "$rootdev" ]] || { echo "e2e-jobs: the two partitions did not get two loop devices" >&2; exit 1; }
cleanup() {
    # The rbind mounts of /dev, /proc, /sys and /run can stay busy for a
    # moment; detach them lazily so cleanup never decides the result.
    umount -R "$T" 2>/dev/null || umount -R -l "$T" 2>/dev/null || true
    losetup -d "$esp" "$rootdev" 2>/dev/null || true
    rm -rf "$W" 2>/dev/null || true
}
trap cleanup EXIT
mkfs.fat -F 32 -n EFI "$esp" >/dev/null
[[ "$(blkid -o value -s TYPE "$esp")" == vfat ]] || { echo "e2e-jobs: the ESP is not FAT after mkfs.fat" >&2; exit 1; }
mkfs.btrfs -q -f "$rootdev"
[[ "$(blkid -o value -s TYPE "$esp")" == vfat ]] || { echo "e2e-jobs: mkfs.btrfs on root overwrote the ESP" >&2; exit 1; }

# mount.conf's subvolumes and options.
mkdir -p "$T"
mount "$rootdev" "$T"
for s in @ @home @home-snapshots @log @cache @pkg @snapshots @vm; do btrfs -q subvolume create "$T/$s"; done
umount "$T"
opts="noatime,compress=zstd:1"
mount -o "subvol=/@,$opts" "$rootdev" "$T"
while read -r mp sv; do
    mkdir -p "$T$mp"
    mount -o "subvol=$sv,$opts" "$rootdev" "$T$mp"
done <<'EOF'
/home /@home
/home/.snapshots /@home-snapshots
/var/log /@log
/var/cache /@cache
/var/cache/pacman/pkg /@pkg
/.snapshots /@snapshots
/var/lib/invictus/vm /@vm
EOF
mkdir -p "$T/boot"
blkid "$esp" "$rootdev" || true
mount -t vfat -o umask=0077 "$esp" "$T/boot"

# A small system from Arch plus our repo (unsigned local repo, like a dev ISO).
cat >"$W/pacman.conf" <<EOF
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
[invictus-testing]
SigLevel = Never
Server = file://$REPO
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
EOF
pacstrap -C "$W/pacman.conf" -K "$T" base linux-cachyos mkinitcpio btrfs-progs snapper limine \
    limine-mkinitcpio-hook limine-snapper-sync efibootmgr acl openssh invictus-guardrails >"$W/pacstrap.log" 2>&1 \
    || { tail -30 "$W/pacstrap.log"; exit 1; }
# What Calamares' machineid, fstab, users and initcpiocfg would have done.
systemd-machine-id-setup --root="$T" >/dev/null
genfstab -U "$T" >"$T/etc/fstab"
printf 'MODULES=()\nBINARIES=()\nFILES=()\nHOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems sd-btrfs-overlayfs)\n' >"$T/etc/mkinitcpio.conf"
arch-chroot "$T" useradd -m -G wheel -s /bin/bash maria
# Calamares' extraMounts.
for m in proc sys dev run; do mount --rbind "/$m" "$T/$m"; mount --make-rslave "$T/$m"; done

mkdir -p "$W/efi"
export INVICTUS_EFI_SYSFS="$W/efi" INVICTUS_INSTALLER_DATA="$W/data"
mkdir -p "$W/data"
cp "$SRC/installer/data/limine-header.conf" "$W/data/"

# ---- bootloader --------------------------------------------------------------------
rc=0; bash "$SRC/installer/jobs/bootloader.sh" "$T" >"$W/boot.log" 2>&1 || rc=$?
check "bootloader job exits 0" test "$rc" -eq 0
[[ $rc -eq 0 ]] || tail -40 "$W/boot.log"
conf="$T/boot/limine.conf"
check "limine.conf keeps our Dusk header" grep -qx 'interface_branding: Invictus' "$conf"
check "limine.conf has an Invictus entry" grep -Eq '^/\+?Invictus' "$conf"
check "limine.conf has the linux-cachyos entry with a kernel path (the one kernel)" bash -c "grep -qx '  //linux-cachyos' '$conf' && ! grep -qx '  //linux-lts' '$conf' && grep -Eq '^ +path: boot\\(\\):/.*/linux-cachyos/vmlinuz' '$conf'"
check "the entry carries our command line" grep -q 'cmdline: root=UUID=.* rootflags=subvol=/@ rw quiet splash' "$conf"
uuid="$(findmnt -n -o UUID --mountpoint "$T")"
check "the entry finds root by the file system's UUID" grep -q "root=UUID=$uuid" "$conf"
check "no live ISO parameters leaked in" bash -c "! grep -Eq 'archiso|invictus\\.' '$conf'"
check "kernel and initramfs are on the ESP" bash -c "compgen -G '$T/boot/*/linux-cachyos/vmlinuz' >/dev/null && compgen -G '$T/boot/*/linux-cachyos/initramfs' >/dev/null"
check "limine EFI binary on the ESP" test -s "$T/boot/EFI/limine/limine_x64.efi"
check "no EFI variables here: limine is the fallback loader" test -s "$T/boot/EFI/BOOT/BOOTX64.EFI"
initrd="$(compgen -G "$T/boot/*/linux-cachyos/initramfs" | head -n 1)"
if [[ -n "$initrd" ]]; then
    # lsinitcpio lives in the target (mkinitcpio), not in this container.
    arch-chroot "$T" lsinitcpio "${initrd#"$T"}" >"$W/lsinit" 2>&1 || true
    check "the initramfs has the snapshot overlay unit" grep -q 'overlayfs-setup' "$W/lsinit"
else
    bad "an initramfs to inspect"
fi

# ---- snapper -----------------------------------------------------------------------
rc=0; bash "$SRC/installer/jobs/snapper.sh" "$T" >"$W/snap.log" 2>&1 || rc=$?
check "snapper job exits 0" test "$rc" -eq 0
[[ $rc -eq 0 ]] || tail -40 "$W/snap.log"
check "/.snapshots is the @snapshots subvolume again" bash -c "findmnt -n -o OPTIONS --mountpoint '$T/.snapshots' | grep -q 'subvol=/@snapshots'"
check "/home/.snapshots is the @home-snapshots subvolume again" bash -c "findmnt -n -o OPTIONS --mountpoint '$T/home/.snapshots' | grep -q 'subvol=/@home-snapshots'"
btrfs subvolume list "$T" >"$W/subvols"
check "no nested .snapshots subvolume left in @" bash -c "! grep -Eq 'path @/\\.snapshots$' '$W/subvols'"
check "no nested .snapshots subvolume left in @home" bash -c "! grep -Eq 'path @home/\\.snapshots$' '$W/subvols'"
arch-chroot "$T" snapper --no-dbus -c root list >"$W/root-list" 2>&1 || true
check "snapshot 1 of / is Fresh install" grep -q 'Fresh install' "$W/root-list"
check "snapshot 1 lives in @snapshots" test -d "$T/.snapshots/1/snapshot/etc"
# Read the config files: snapper's get-config table uses box-drawing
# separators in newer versions, so grepping its table is brittle.
hc="$T/etc/snapper/configs/home"; rc_="$T/etc/snapper/configs/root"
check "home config: ALLOW_GROUPS users" grep -qx 'ALLOW_GROUPS="users"' "$hc"
check "home config: SYNC_ACL yes" grep -qx 'SYNC_ACL="yes"' "$hc"
check "home config: hourly timeline 24, daily 7" bash -c "grep -qx 'TIMELINE_LIMIT_HOURLY=\"24\"' '$hc' && grep -qx 'TIMELINE_LIMIT_DAILY=\"7\"' '$hc'"
check "the users group can open /home/.snapshots (ACL)" bash -c "getfacl -p '$T/home/.snapshots' 2>/dev/null | grep -q '^group:users:r-x'"
check "root config: no timeline" grep -qx 'TIMELINE_CREATE="no"' "$rc_"
check "services enabled" bash -c "for u in snapper-cleanup.timer snapper-timeline.timer limine-snapper-sync.service; do arch-chroot '$T' systemctl is-enabled \$u >/dev/null || exit 1; done"
check "the VM folder is No_COW" bash -c "lsattr -d '$T/var/lib/invictus/vm' | cut -d' ' -f1 | grep -q C"
if grep -q 'snapshot entries added' "$W/snap.log"; then
    check "the boot menu lists the snapshot" grep -qi 'snapshots' "$conf"
else
    echo "note  limine-snapper-sync did not run in the chroot; the service adds the entries at first boot"
fi

# ---- settings: sshd off (design-simple-mode 1.3) -----------------------------------
# With openssh installed, systemd-ssh-generator binds sshd to a local
# AF_UNIX socket. First show that it does on this target (the control), then
# run the settings job and check the generator is masked where PID 1 looks
# first (/etc/systemd/system-generators comes before /usr/lib/...).
gen=/usr/lib/systemd/system-generators/systemd-ssh-generator
mkdir -p "$T/var/tmp/gen"
arch-chroot "$T" "$gen" /var/tmp/gen /var/tmp/gen /var/tmp/gen >"$W/gen.log" 2>&1 || true
check "control: with openssh installed, the generator makes sshd-unix-local.socket" test -f "$T/var/tmp/gen/sshd-unix-local.socket"
rm -rf "$T/var/tmp/gen"
rc=0; bash "$SRC/installer/jobs/settings.sh" "$T" maria atrium custodia >"$W/settings.log" 2>&1 || rc=$?
check "settings job exits 0" test "$rc" -eq 0
[[ $rc -eq 0 ]] || tail -20 "$W/settings.log"
gm="$T/etc/systemd/system-generators/systemd-ssh-generator"
check "settings: systemd-ssh-generator masked (a link to /dev/null)" bash -c "[[ -L '$gm' && \"\$(readlink '$gm')\" == /dev/null ]]"
# Janus I-2: the mask is invictus-sys's file (pacstrapped above, as the live
# image has it through invictus-base), not one the job wrote.
check "settings: pacman says invictus-sys owns the generator mask" \
    bash -c "[[ \"\$(arch-chroot '$T' pacman -Qqo /etc/systemd/system-generators/systemd-ssh-generator)\" == invictus-sys ]]"
check "settings: the job says the mask came from invictus-sys" grep -q 'systemd-ssh-generator masked (invictus-sys)' "$W/settings.log"
check "settings: /etc/systemd/system-generators is searched before /usr/lib/systemd/system-generators" \
    bash -c "arch-chroot '$T' systemd-path systemd-search-system-generator | grep -q '/etc/systemd/system-generators:.*/usr/lib/systemd/system-generators'"
check "settings: sshd.service not enabled" bash -c "! arch-chroot '$T' systemctl is-enabled sshd.service >/dev/null 2>&1"
check "settings: nothing else enables an ssh socket" bash -c "! find '$T/etc/systemd/system' -name '*ssh*' | grep -q ."

echo
echo "e2e-jobs: $pass passed, $fail failed"
((fail == 0))
