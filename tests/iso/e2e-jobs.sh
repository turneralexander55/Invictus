#!/usr/bin/env bash
# ------------------------------------------------------------
# End-to-end test of the install jobs with the real tools (unsquashfs,
# pacman, limine-entry-tool, limine-snapper-sync, snapper, btrfs) on a real
# btrfs disk image, installing the ISO's own system the way Calamares does.
# Run as root in a throwaway PRIVILEGED Arch container (loop devices, mounts):
#
#   docker run --rm --privileged -v "$PWD:/src:ro" -v "$PWD/out/disk:/keep" \
#       archlinux:base-devel bash /src/tests/iso/e2e-jobs.sh \
#       --iso /src/out/iso/invictus-....iso --keep /keep
#
#   --iso ISO   the built ISO (required)
#   --keep DIR  leave the installed disk in DIR/disk.img (raw, GPT, 16 GiB
#               sparse), with DIR/disk.env (what tests/iso/disk-boot.sh
#               checks) and DIR/logs/ (each job's output). The image gets a
#               root shell on the second serial port for disk-boot.sh
#               (debug-shell.service, TTYPath=/dev/ttyS1), written before
#               the snapper job so the Fresh install snapshot has it too.
#               Never ship such an image. Without --keep the image is
#               deleted at the end.
#   --src DIR   the checkout (default /src)
#
# It lays the disk out the way Calamares does (GPT, 1 GiB FAT ESP at /boot,
# btrfs with the mount.conf subvolumes and options), unpacks the ISO's
# airootfs.sfs into it (Calamares' unpackfs), then runs the install
# sequence of installer/calamares/plain/settings.conf: machineid, the
# cleanup job, fstab, locale and keyboard, users, the settings job,
# initcpiocfg, services-systemd, the bootloader job and the snapper job.
# The Invictus jobs and their data are the ISO's own copies
# (/usr/lib/invictus/installer, /usr/share/invictus/installer), taken
# before the cleanup job removes the installer package; the steps that are
# Calamares' own C++ or Python modules are done here by hand, as noted at
# each. Not run: the extras job (nothing picked on the plain path) and
# Calamares' umount. The container has no EFI variables and the ESP is a
# loop device, not a disk partition, so the bootloader job takes its
# fallback path (limine at EFI/BOOT/BOOTX64.EFI) and INVICTUS_EFI_SYSFS
# points at a stand-in folder; the NVRAM entry itself is only tested on
# hardware.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC=/src ISO="" KEEP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso) ISO="${2:?}"; shift 2 ;;
        --keep) KEEP="${2:?}"; shift 2 ;;
        --src) SRC="${2:?}"; shift 2 ;;
        *) echo "e2e-jobs: unknown argument $1" >&2; exit 2 ;;
    esac
done
[[ -f "$ISO" ]] || { echo "e2e-jobs: --iso ISO is required (got '${ISO}')" >&2; exit 2; }
[[ -z "$KEEP" || -d "$KEEP" ]] || { echo "e2e-jobs: --keep $KEEP is not a folder" >&2; exit 2; }
grep -qw btrfs /proc/filesystems || { echo "The host kernel has no btrfs; this test cannot run here." >&2; exit 2; }

pass=0 fail=0
ok()  { echo "ok    $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

pacman -Syu --noconfirm --needed arch-install-scripts btrfs-progs dosfstools gptfdisk acl squashfs-tools >/dev/null

W="$(mktemp -d)"
T="$W/target"
L="$W/logs"
mkdir -p "$L"
img="${KEEP:-$W}/disk.img"
rm -f "$img"
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
# Kill whatever the jobs left running in the target (pacman-key's
# gpg-agent): it keeps the mounts busy.
kill_target_procs() {
    local p r
    for p in /proc/[0-9]*; do
        r="$(readlink "$p/root" 2>/dev/null)" || continue
        [[ "$r" == "$T" || "$r" == "$T"/* ]] && kill -9 "${p#/proc/}" 2>/dev/null
    done
    return 0
}
cleanup() {
    [[ -z "$KEEP" ]] || cp -a "$L" "$KEEP/" 2>/dev/null || true
    kill_target_procs
    # The rbind mounts of /dev, /proc, /sys and /run can stay busy for a
    # moment; detach them lazily so cleanup never decides the result.
    umount -R "$T" 2>/dev/null || umount -R -l "$T" 2>/dev/null || true
    umount "$W/iso" 2>/dev/null || true
    losetup -d "$esp" "$rootdev" 2>/dev/null || true
    rm -rf "$W" 2>/dev/null || true
}
trap cleanup EXIT
mkfs.fat -F 32 -n EFI "$esp" >/dev/null
[[ "$(blkid -o value -s TYPE "$esp")" == vfat ]] || { echo "e2e-jobs: the ESP is not FAT after mkfs.fat" >&2; exit 1; }
mkfs.btrfs -q -f "$rootdev"
[[ "$(blkid -o value -s TYPE "$esp")" == vfat ]] || { echo "e2e-jobs: mkfs.btrfs on root overwrote the ESP" >&2; exit 1; }

# mount.conf's subvolumes and options.
SUBVOLS="/home /@home
/home/.snapshots /@home-snapshots
/var/log /@log
/var/cache /@cache
/var/cache/pacman/pkg /@pkg
/.snapshots /@snapshots
/var/lib/invictus/vm /@vm"
mkdir -p "$T"
mount "$rootdev" "$T"
for s in @ @home @home-snapshots @log @cache @pkg @snapshots @vm; do btrfs -q subvolume create "$T/$s"; done
umount "$T"
opts="noatime,compress=zstd:1"
mount -o "subvol=/@,$opts" "$rootdev" "$T"
while read -r mp sv; do
    mkdir -p "$T$mp"
    mount -o "subvol=$sv,$opts" "$rootdev" "$T$mp"
done <<<"$SUBVOLS"

# ---- unpackfs: the ISO's system ----------------------------------------------------
# The ESP is mounted after the unpack (Calamares mounts it before): the
# image's /boot is empty (mkarchiso empties it), and unsquashfs cannot set
# owners on FAT.
mkdir -p "$W/iso"
mount -o loop,ro "$ISO" "$W/iso"
sfs="$W/iso/arch/x86_64/airootfs.sfs"
[[ -f "$sfs" ]] || { echo "e2e-jobs: no arch/x86_64/airootfs.sfs in $ISO" >&2; exit 1; }
rc=0; unsquashfs -n -f -d "$T" "$sfs" >"$L/unpack.log" 2>&1 || rc=$?
check "unpackfs: the ISO's airootfs.sfs unpacks onto the btrfs subvolumes" test "$rc" -eq 0
[[ $rc -eq 0 ]] || { tail -30 "$L/unpack.log"; exit 1; }
umount "$W/iso"
mkdir -p "$T/boot"
mount -t vfat -o umask=0077 "$esp" "$T/boot"
blkid "$esp" "$rootdev" || true
# Calamares' extraMounts.
for m in proc sys dev run; do mount --rbind "/$m" "$T/$m"; mount --make-rslave "$T/$m"; done

# The jobs and their data as the ISO ships them (the cleanup job removes
# the installer package from the target, so copy them out first).
J="$W/jobs" D="$W/data"
mkdir -p "$J" "$D" "$W/efi"
cp -a "$T/usr/lib/invictus/installer/." "$J/"
cp -a "$T/usr/share/invictus/installer/." "$D/"
for f in lib.sh cleanup-live.sh settings.sh bootloader.sh snapper.sh; do
    [[ -f "$J/$f" ]] || { echo "e2e-jobs: the ISO has no /usr/lib/invictus/installer/$f" >&2; exit 1; }
done
release="$W/iso-release"
cp "$T/etc/invictus/iso-release" "$release" 2>/dev/null || : >"$release"
export INVICTUS_EFI_SYSFS="$W/efi" INVICTUS_INSTALLER_DATA="$D" INVICTUS_ISO_RELEASE="$release"
job() {  # job NAME SCRIPT ARGS...: run one of the ISO's jobs, log in $L/NAME.log
    local name="$1" script="$2" rc=0; shift 2
    bash "$J/$script" "$@" >"$L/$name.log" 2>&1 || rc=$?
    check "$name job exits 0" test "$rc" -eq 0
    [[ $rc -eq 0 ]] || tail -40 "$L/$name.log"
    return 0
}

# ---- machineid (Calamares module: systemd, dbus-symlink) ---------------------------
rm -f "$T/etc/machine-id"
systemd-machine-id-setup --root="$T" >/dev/null
mkdir -p "$T/var/lib/dbus"
ln -sf /etc/machine-id "$T/var/lib/dbus/machine-id"

# ---- shellprocess@invictus-cleanup -------------------------------------------------
job cleanup cleanup-live.sh "$T"
check "cleanup: the live user is gone" bash -c "! grep -q '^liber:' '$T/etc/passwd' && [[ ! -e '$T/home/liber' ]]"
check "cleanup: Calamares and the installer are not installed" bash -c "! chroot '$T' pacman -Q calamares invictus-installer cage >/dev/null 2>&1"
check "cleanup: root is locked" bash -c "awk -F: '\$1 == \"root\" { exit (\$2 ~ /^!/) ? 0 : 1 }' '$T/etc/shadow'"
check "cleanup: the live mkinitcpio drop-in is gone" test ! -e "$T/etc/mkinitcpio.conf.d/archiso.conf"

# ---- fstab (Calamares module: by UUID, the mount options, no subvolid) -------------
# genfstab would add subvolid=, which a snapshot boot's remount of / fails on.
uuid="$(findmnt -n -o UUID --mountpoint "$T")"
esp_uuid="$(blkid -o value -s UUID "$esp")"
{
    echo "UUID=$uuid / btrfs subvol=/@,defaults,$opts 0 0"
    while read -r mp sv; do echo "UUID=$uuid $mp btrfs subvol=$sv,defaults,$opts 0 0"; done <<<"$SUBVOLS"
    echo "UUID=$esp_uuid /boot vfat defaults,umask=0077 0 2"
} >"$T/etc/fstab"

# ---- locale, keyboard (Calamares modules) ------------------------------------------
[[ -f "$T/etc/locale.conf" ]] || echo "LANG=en_US.UTF-8" >"$T/etc/locale.conf"
echo "KEYMAP=us" >"$T/etc/vconsole.conf"
ln -sf /usr/share/zoneinfo/UTC "$T/etc/localtime"

# ---- users (Calamares module, users.conf of the plain path) ------------------------
chroot "$T" getent group kvm >/dev/null || chroot "$T" groupadd -r kvm
chroot "$T" useradd -m -U -s /bin/zsh -c Maria maria
chroot "$T" usermod -aG users,wheel,audio,video,input,storage,network,kvm maria
chmod 700 "$T/home/maria"
echo 'maria:e2e-only-password' | chroot "$T" chpasswd
install -m 440 /dev/null "$T/etc/sudoers.d/10-installer"
echo '%wheel ALL=(ALL:ALL) ALL' >"$T/etc/sudoers.d/10-installer"

# ---- shellprocess@invictus-settings (plain path) -----------------------------------
# With openssh installed, systemd-ssh-generator binds sshd to a local
# AF_UNIX socket. First show that it does on this target (the control), then
# check the settings job left it masked where PID 1 looks first
# (/etc/systemd/system-generators comes before /usr/lib/...).
gen=/usr/lib/systemd/system-generators/systemd-ssh-generator
mkdir -p "$T/var/tmp/gen"
arch-chroot "$T" "$gen" /var/tmp/gen /var/tmp/gen /var/tmp/gen >"$L/gen.log" 2>&1 || true
check "control: with openssh installed, the generator makes sshd-unix-local.socket" test -f "$T/var/tmp/gen/sshd-unix-local.socket"
rm -rf "$T/var/tmp/gen"
job settings settings.sh "$T" maria atrium custodia --hostname-from-user
gm="$T/etc/systemd/system-generators/systemd-ssh-generator"
check "settings: systemd-ssh-generator masked (a link to /dev/null)" bash -c "[[ -L '$gm' && \"\$(readlink '$gm')\" == /dev/null ]]"
# Janus I-2: the mask is invictus-sys's file (from the ISO's airootfs, which
# has it through invictus-base), not one the job wrote.
check "settings: pacman says invictus-sys owns the generator mask" \
    bash -c "[[ \"\$(arch-chroot '$T' pacman -Qqo /etc/systemd/system-generators/systemd-ssh-generator)\" == invictus-sys ]]"
check "settings: the job says the mask came from invictus-sys" grep -q 'systemd-ssh-generator masked (invictus-sys)' "$L/settings.log"
check "settings: /etc/systemd/system-generators is searched before /usr/lib/systemd/system-generators" \
    bash -c "arch-chroot '$T' systemd-path systemd-search-system-generator | grep -q '/etc/systemd/system-generators:.*/usr/lib/systemd/system-generators'"
check "settings: sshd.service not enabled" bash -c "! arch-chroot '$T' systemctl is-enabled sshd.service >/dev/null 2>&1"
check "settings: nothing else enables an ssh socket" bash -c "! find '$T/etc/systemd/system' -name '*ssh*' | grep -q ."
check "settings: guard rails Custodia, applied" bash -c "grep -qx custodia '$T/etc/invictus/guardrails' && chroot '$T' invictus-sys guardrails check >/dev/null"
check "settings: hostname from the user" grep -qx maria-invictus "$T/etc/hostname"

# ---- initcpiocfg (Calamares module, useSystemdHook: true) --------------------------
# Calamares builds the HOOKS line from the target: plymouth after block when
# plymouth is installed, no fsck for btrfs, then initcpiocfg.conf's append.
hooks="systemd autodetect microcode modconf kms keyboard sd-vconsole block"
[[ -x "$T/usr/bin/plymouth" ]] && hooks+=" plymouth"
hooks+=" filesystems sd-btrfs-overlayfs"
sed -i -E "s/^HOOKS=.*/HOOKS=($hooks)/" "$T/etc/mkinitcpio.conf"
check "initcpiocfg: HOOKS line written" grep -qx "HOOKS=($hooks)" "$T/etc/mkinitcpio.conf"

# ---- services-systemd (Calamares module, services-systemd.conf) --------------------
svc_ok=true
while read -r unit; do
    chroot "$T" systemctl enable "$unit" >>"$L/services.log" 2>&1 || { echo "could not enable $unit" >>"$L/services.log"; svc_ok=false; }
done < <(awk '$1 == "-" && $2 == "name:" { print $3 }' "$SRC/installer/calamares/common/modules/services-systemd.conf")
check "services-systemd: every unit enabled" $svc_ok
check "services-systemd: the login screen (sddm) is the display manager" test -L "$T/etc/systemd/system/display-manager.service"

# ---- shellprocess@invictus-bootloader ----------------------------------------------
job bootloader bootloader.sh "$T"
conf="$T/boot/limine.conf"
check "limine.conf keeps our Dusk header" grep -qx 'interface_branding: Invictus' "$conf"
check "limine.conf has an Invictus entry" grep -Eq '^/\+?Invictus' "$conf"
check "limine.conf has the linux-cachyos entry with a kernel path (the one kernel)" bash -c "grep -qx '  //linux-cachyos' '$conf' && ! grep -qx '  //linux-lts' '$conf' && grep -Eq '^ +path: boot\\(\\):/.*/linux-cachyos/vmlinuz' '$conf'"
check "the entry carries our command line" grep -q 'cmdline: root=UUID=.* rootflags=subvol=/@ rw quiet splash' "$conf"
check "the entry finds root by the file system's UUID" grep -q "root=UUID=$uuid" "$conf"
check "no live ISO parameters leaked in" bash -c "! grep -Eq 'archiso|invictus\\.' '$conf'"
check "kernel and initramfs are on the ESP" bash -c "compgen -G '$T/boot/*/linux-cachyos/vmlinuz' >/dev/null && compgen -G '$T/boot/*/linux-cachyos/initramfs' >/dev/null"
check "limine EFI binary on the ESP" test -s "$T/boot/EFI/limine/limine_x64.efi"
check "no EFI variables here: limine is the fallback loader" test -s "$T/boot/EFI/BOOT/BOOTX64.EFI"
initrd="$(compgen -G "$T/boot/*/linux-cachyos/initramfs" | head -n 1)"
if [[ -n "$initrd" ]]; then
    arch-chroot "$T" lsinitcpio "${initrd#"$T"}" >"$L/lsinit" 2>&1 || true
    check "the initramfs has the snapshot overlay unit" grep -q 'overlayfs-setup' "$L/lsinit"
else
    bad "an initramfs to inspect"
fi

# ---- the test image's root shell (--keep only; before the snapshot) ----------------
if [[ -n "$KEEP" ]]; then
    mkdir -p "$T/etc/systemd/system/debug-shell.service.d"
    printf '# tests/iso/e2e-jobs.sh --keep: a root shell for tests/iso/disk-boot.sh.\n# A test image only; never on a shipped system.\n[Service]\nTTYPath=/dev/ttyS1\n' \
        >"$T/etc/systemd/system/debug-shell.service.d/serial.conf"
    chroot "$T" systemctl enable debug-shell.service >/dev/null 2>&1
    check "test image: debug-shell.service enabled on ttyS1" test -L "$T/etc/systemd/system/sysinit.target.wants/debug-shell.service"
fi

# ---- shellprocess@invictus-snapper -------------------------------------------------
job snapper snapper.sh "$T"
check "/.snapshots is the @snapshots subvolume again" bash -c "findmnt -n -o OPTIONS --mountpoint '$T/.snapshots' | grep -q 'subvol=/@snapshots'"
check "/home/.snapshots is the @home-snapshots subvolume again" bash -c "findmnt -n -o OPTIONS --mountpoint '$T/home/.snapshots' | grep -q 'subvol=/@home-snapshots'"
btrfs subvolume list "$T" >"$L/subvols"
check "no nested .snapshots subvolume left in @" bash -c "! grep -Eq 'path @/\\.snapshots$' '$L/subvols'"
check "no nested .snapshots subvolume left in @home" bash -c "! grep -Eq 'path @home/\\.snapshots$' '$L/subvols'"
arch-chroot "$T" snapper --no-dbus -c root list >"$L/root-list" 2>&1 || true
check "snapshot 1 of / is Fresh install" grep -q 'Fresh install' "$L/root-list"
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
if grep -q 'snapshot entries added' "$L/snapper.log"; then
    check "the boot menu lists the snapshot" grep -qi 'snapshots' "$conf"
else
    echo "note  limine-snapper-sync did not run in the chroot; the service adds the entries at first boot"
fi
if [[ -n "$KEEP" ]]; then
    check "test image: the Fresh install snapshot has the root shell too" \
        test -f "$T/.snapshots/1/snapshot/etc/systemd/system/debug-shell.service.d/serial.conf"
fi

# ---- keep the disk -----------------------------------------------------------------
if [[ -n "$KEEP" ]]; then
    kernel=""
    for pb in "$T"/usr/lib/modules/*/pkgbase; do
        [[ -f "$pb" && "$(<"$pb")" == linux-cachyos ]] && kernel="$(basename "$(dirname "$pb")")"
    done
    check "test image: the linux-cachyos kernel's release found" test -n "$kernel"
    printf 'kernel=%s\nkernel_pkgbase=linux-cachyos\nroot_uuid=%s\nrails=custodia\nuser=maria\n' \
        "$kernel" "$uuid" >"$KEEP/disk.env"
    cp "$conf" "$L/limine.conf"
    # Unmount for real (no lazy detach): the image must be clean before it boots.
    kill_target_procs
    sync
    # The host's /proc, /sys, /dev and /run are not on the image: detach
    # them lazily. The image's own mounts must unmount for real.
    for m in run dev sys proc; do umount -R -l "$T/$m" 2>/dev/null || true; done
    umount_ok=false
    for _ in 1 2 3 4 5; do
        if umount -R "$T" 2>>"$L/umount.log"; then umount_ok=true; break; fi
        sleep 2
    done
    check "test image: unmounted cleanly" $umount_ok
    losetup -d "$esp" "$rootdev" 2>/dev/null || true
    check "test image: $img kept" test -s "$img"
fi

echo
echo "e2e-jobs: $pass passed, $fail failed"
((fail == 0))
