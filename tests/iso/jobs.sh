#!/usr/bin/env bash
# ------------------------------------------------------------
# Script-level tests of the installer jobs (installer/jobs/*.sh) and the
# live launcher against a fake target root. Commands that would run inside
# the target go through tests/iso/fakes/chroot (INVICTUS_CHROOT), and
# findmnt, mount, umount, btrfs, lsblk, cryptsetup, blkid and chattr are
# fakes first on PATH, so nothing touches a real disk. Runs as any user.
#
#   tests/iso/jobs.sh        prints ok/FAIL lines, exit 1 on any failure
# ------------------------------------------------------------
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
JOBS="$REPO/installer/jobs"

pass=0 fail=0
ok()  { echo "ok    $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export PATH="$HERE/fakes:$PATH"
export INVICTUS_CHROOT="$HERE/fakes/chroot"
export FAKE_LOG FAKE_STATE

# A fake installed-system tree as Calamares leaves it after unpackfs.
# $1 = case name. Sets ROOTDIR, FAKE_LOG, FAKE_STATE, DATA.
new_target() {
    local c="$T/$1"
    ROOTDIR="$c/root"; FAKE_STATE="$c/state"; FAKE_LOG="$c/log"; DATA="$c/data"
    mkdir -p "$ROOTDIR"/{etc,home/.snapshots,boot,var/lib/pacman/local,var/lib/invictus/vm,.snapshots} "$FAKE_STATE" "$DATA"
    : >"$FAKE_LOG"
    printf 'root:x:0:0:root:/root:/usr/bin/bash\nliber:x:1000:100:Invictus live:/home/liber:/usr/bin/bash\n' >"$ROOTDIR/etc/passwd"
    printf 'root::14871::::::\nliber:!*:14871::::::\n' >"$ROOTDIR/etc/shadow"
    printf 'root:x:0:root\nusers:x:100:\nwheel:x:998:\n' >"$ROOTDIR/etc/group"
    mkdir -p "$ROOTDIR/home/liber/.config/hypr" "$ROOTDIR/etc/sudoers.d" "$ROOTDIR/etc/mkinitcpio.conf.d" \
        "$ROOTDIR/etc/systemd/system/getty@tty1.service.d" "$ROOTDIR/etc/invictus"
    echo 'liber ALL=(ALL:ALL) NOPASSWD: ALL' >"$ROOTDIR/etc/sudoers.d/liber"
    echo 'HOOKS=(base udev archiso)' >"$ROOTDIR/etc/mkinitcpio.conf.d/archiso.conf"
    echo '[Service]' >"$ROOTDIR/etc/systemd/system/getty@tty1.service.d/autologin.conf"
    echo 'version=x' >"$ROOTDIR/etc/invictus/iso-release"
    echo 'invictus' >"$ROOTDIR/etc/hostname"
    printf 'passwd: files systemd\nhosts: mymachines resolve [!UNAVAIL=return] files myhostname dns\n' >"$ROOTDIR/etc/nsswitch.conf"
    printf 'MODULES=()\nHOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole block plymouth filesystems)\n' >"$ROOTDIR/etc/mkinitcpio.conf"
    for p in invictus-installer-0.1.0-1 calamares-3.4.2-2.1 cage-0.3.1-1 linux-cachyos-7.2.7-1; do mkdir -p "$ROOTDIR/var/lib/pacman/local/$p"; done
    mkdir -p "$ROOTDIR/usr/lib/modules/7.2.7-1-cachyos"
    echo linux-cachyos >"$ROOTDIR/usr/lib/modules/7.2.7-1-cachyos/pkgbase"
    cp "$REPO/iso/live-only.txt" "$DATA/live-only.txt"
    cp "$REPO/installer/data/limine-header.conf" "$DATA/limine-header.conf"
    # Mount table: plain btrfs root on sda2, ESP sda1.
    cat >"$FAKE_STATE/mounts" <<EOF
$ROOTDIR /dev/sda2[/@] btrfs aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee rw,noatime,compress=zstd:1,subvol=/@
$ROOTDIR/boot /dev/sda1 vfat 1234-ABCD rw,umask=0077
$ROOTDIR/.snapshots /dev/sda2[/@snapshots] btrfs aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee rw,noatime,compress=zstd:1,subvolid=262,subvol=/@snapshots
$ROOTDIR/home/.snapshots /dev/sda2[/@home-snapshots] btrfs aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee rw,noatime,compress=zstd:1,subvolid=258,subvol=/@home-snapshots
EOF
    mkdir -p "$c/efi"
    export INVICTUS_INSTALLER_DATA="$DATA" INVICTUS_EFI_SYSFS="$c/efi"
}

run_job() { local job="$1"; shift; bash "$JOBS/$job" "$@" >"$T/out" 2>&1; }
logged() { grep -qF -- "$1" "$FAKE_LOG"; }
out_has() { grep -qF -- "$1" "$T/out"; }

# ---- cleanup-live.sh ------------------------------------------------------------
new_target cleanup
run_job cleanup-live.sh "$ROOTDIR"; rc=$?
check "cleanup: exits 0" test "$rc" -eq 0
check "cleanup: live sudo rule gone" test ! -e "$ROOTDIR/etc/sudoers.d/liber"
check "cleanup: tty1 autologin gone" test ! -e "$ROOTDIR/etc/systemd/system/getty@tty1.service.d/autologin.conf"
check "cleanup: archiso mkinitcpio drop-in gone" test ! -e "$ROOTDIR/etc/mkinitcpio.conf.d/archiso.conf"
check "cleanup: the ISO release file is not left in the target" test ! -e "$ROOTDIR/etc/invictus/iso-release"
check "cleanup: kept files stay (hostname, passwd)" test -f "$ROOTDIR/etc/hostname" -a -f "$ROOTDIR/etc/passwd"
check "cleanup: live user removed" bash -c "! grep -q '^liber:' '$ROOTDIR/etc/passwd' && test ! -e '$ROOTDIR/home/liber'"
check "cleanup: root locked in shadow" grep -q '^root:!\*:' "$ROOTDIR/etc/shadow"
check "cleanup: shadow stays mode 600" test "$(stat -c %a "$ROOTDIR/etc/shadow")" = 600
check "cleanup: live packages removed together" logged "chroot pacman -Rns --noconfirm invictus-installer calamares cage"
check "cleanup: pacman keyring initialised and populated" bash -c "grep -q 'chroot pacman-key --init' '$FAKE_LOG' && grep -q 'chroot pacman-key --populate' '$FAKE_LOG'"

new_target cleanup-nopkgs
rm -rf "$ROOTDIR/var/lib/pacman/local/cage-"* "$ROOTDIR/var/lib/pacman/local/calamares-"*
run_job cleanup-live.sh "$ROOTDIR"
check "cleanup: removes only the live packages that are installed" logged "chroot pacman -Rns --noconfirm invictus-installer"
check "cleanup: does not name missing packages" bash -c "! grep -q 'Rns.*cage' '$FAKE_LOG'"

new_target cleanup-refuse
run_job cleanup-live.sh /; check "cleanup: refuses the live system's own /" test $? -ne 0
run_job cleanup-live.sh relative/path; check "cleanup: refuses a relative root" test $? -ne 0
echo '/etc/../etc/passwd' >>"$DATA/live-only.txt"
run_job cleanup-live.sh "$ROOTDIR"; rc=$?
check "cleanup: refuses a live-only entry with .." test "$rc" -ne 0
check "cleanup: and says why" out_has "bad path in live-only.txt"
new_target cleanup-top
echo '/etc' >>"$DATA/live-only.txt"
run_job cleanup-live.sh "$ROOTDIR"; rc=$?
check "cleanup: refuses to delete a top-level folder" test "$rc" -ne 0
check "cleanup: /etc still there after the refusal" test -f "$ROOTDIR/etc/passwd"

# ---- settings.sh ---------------------------------------------------------------------
new_target settings
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
printf 'maria:x:1000:1000:Maria:/home/maria:/bin/zsh\n' >>"$ROOTDIR/etc/passwd"
mkdir -p "$ROOTDIR/home/maria"
# shellcheck disable=SC2016  # a literal $(reboot) the job must drop
printf 'version=2026.09.30\nchannel=testing\nbuild=dev\nevil=$(reboot)\n' >"$T/iso-release"
export INVICTUS_ISO_RELEASE="$T/iso-release"
run_job settings.sh "$ROOTDIR" maria atrium custodia --hostname-from-user; rc=$?
check "settings: plain path exits 0" test "$rc" -eq 0
check "settings: guard rails file says custodia" test "$(cat "$ROOTDIR/etc/invictus/guardrails")" = custodia
check "settings: guard rails file is 644" test "$(stat -c %a "$ROOTDIR/etc/invictus/guardrails")" = 644
check "settings: AI file says off (NA1: AI is chosen at first start)" test "$(cat "$ROOTDIR/etc/invictus/ai")" = off
check "settings: AI file is 644" test "$(stat -c %a "$ROOTDIR/etc/invictus/ai")" = 644
check "settings: flavor file says atrium" test "$(cat "$ROOTDIR/home/maria/.config/invictus/flavor")" = atrium
if [[ $EUID -eq 0 ]]; then
    check "settings: flavor file owned by the user" test "$(stat -c %u:%g "$ROOTDIR/home/maria/.config/invictus/flavor")" = 1000:1000
    check "settings: created folders owned by the user" test "$(stat -c %u:%g "$ROOTDIR/home/maria/.config")" = 1000:1000
fi
check "settings: hostname made from the user" test "$(cat "$ROOTDIR/etc/hostname")" = maria-invictus
check "settings: release file written with the install time" grep -q '^installed=' "$ROOTDIR/etc/invictus/release"
check "settings: release file keeps plain values" grep -q '^channel=testing$' "$ROOTDIR/etc/invictus/release"
check "settings: release file drops a line with shell in it" bash -c "! grep -q evil '$ROOTDIR/etc/invictus/release'"
check "settings: says guard rails not applied while invictus-sys is missing" out_has "invictus-sys is not installed yet"
check "settings: mdns_minimal before resolve on the hosts line" grep -qx 'hosts: mymachines mdns_minimal \[NOTFOUND=return\] resolve \[!UNAVAIL=return\] files myhostname dns' "$ROOTDIR/etc/nsswitch.conf"
check "settings: other nsswitch lines untouched" grep -qx 'passwd: files systemd' "$ROOTDIR/etc/nsswitch.conf"

touch "$FAKE_STATE/has-invictus-sys"
run_job settings.sh "$ROOTDIR" maria tessera libertas
check "settings: Advanced values written (tessera, libertas)" bash -c "[[ \$(cat '$ROOTDIR/home/maria/.config/invictus/flavor') == tessera && \$(cat '$ROOTDIR/etc/invictus/guardrails') == libertas ]]"
check "settings: runs invictus-sys guardrails apply when present" logged "chroot invictus-sys guardrails apply"
check "settings: a second run does not add mdns_minimal twice" test "$(grep -o mdns_minimal "$ROOTDIR/etc/nsswitch.conf" | wc -l)" -eq 1
check "settings: hostname untouched without --hostname-from-user" test "$(cat "$ROOTDIR/etc/hostname")" = maria-invictus

for badargs in "maria classic custodia" "maria atrium simple" "maria atrium" "nobody atrium custodia" "Maria atrium custodia"; do
    echo keep >"$ROOTDIR/etc/invictus/guardrails"
    # shellcheck disable=SC2086
    run_job settings.sh "$ROOTDIR" $badargs; rc=$?
    check "settings: rejects '$badargs'" test "$rc" -ne 0 -a "$(cat "$ROOTDIR/etc/invictus/guardrails")" = keep
done

# ---- bootloader.sh ---------------------------------------------------------------------
new_target boot
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
run_job bootloader.sh "$ROOTDIR"; rc=$?
check "bootloader: exits 0" test "$rc" -eq 0
dl="$ROOTDIR/etc/default/limine"
check "bootloader: /etc/default/limine names the ESP" grep -qx 'ESP_PATH="/boot"' "$dl"
check "bootloader: OS entry is Invictus" grep -qx 'TARGET_OS_NAME="Invictus"' "$dl"
check "bootloader: cmdline has root by UUID, @, quiet splash" grep -qx 'KERNEL_CMDLINE\[default\]=root=UUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee rootflags=subvol=/@ rw quiet splash' "$dl"
check "bootloader: snapshots path is @snapshots" grep -qx 'ROOT_SNAPSHOTS_PATH="/@snapshots"' "$dl"
check "bootloader: no live ISO parameters in the cmdline" bash -c "! grep -Eq 'archiso|invictus\.(safe|install)' '$dl'"
check "bootloader: limine.conf starts with the Dusk header" bash -c "head -n 20 '$ROOTDIR/boot/limine.conf' | grep -qx 'term_background: 0014120F'"
check "bootloader: branding is Invictus in sol" bash -c "grep -qx 'interface_branding: Invictus' '$ROOTDIR/boot/limine.conf' && grep -qx 'interface_branding_colour: E0A64B' '$ROOTDIR/boot/limine.conf'"
check "bootloader: limine.conf has the linux-cachyos entry" grep -q 'path: boot():/0123/linux-cachyos/vmlinuz' "$ROOTDIR/boot/limine.conf"
check "bootloader: sd-btrfs-overlayfs added right after filesystems" grep -qx 'HOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole block plymouth filesystems sd-btrfs-overlayfs)' "$ROOTDIR/etc/mkinitcpio.conf"
check "bootloader: limine-install without NVRAM, then limine-mkinitcpio" bash -c "grep -n 'chroot limine' '$FAKE_LOG' | head -2 | tr '\n' ' ' | grep -q 'limine-install --no-efi-register.*limine-mkinitcpio'"
check "bootloader: firmware entry labelled Invictus on sda partition 1" logged 'chroot efibootmgr --create --disk /dev/sda --part 1 --label Invictus --loader \EFI\limine\limine_x64.efi --unicode'

# Run again on the result (a re-run after a retry): hooks untouched, old conf kept aside.
cp "$ROOTDIR/etc/mkinitcpio.conf" "$T/mk.before"
run_job bootloader.sh "$ROOTDIR"
check "bootloader: second run does not add the hook twice" cmp -s "$T/mk.before" "$ROOTDIR/etc/mkinitcpio.conf"
check "bootloader: an existing limine.conf is kept aside" test -f "$ROOTDIR/boot/limine.conf.before-invictus"

# Every installed kernel must get an entry (one kernel, linux-cachyos,
# since 2026-09-30: a missing entry is an unbootable machine).
new_target boot-kernel-missing
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
echo linux-cachyos >"$FAKE_STATE/limine-skips"
run_job bootloader.sh "$ROOTDIR"; rc=$?
check "bootloader: fails when the kernel has no limine entry" bash -c "[[ $rc -ne 0 ]] && grep -q 'no limine.conf entry for the linux-cachyos kernel' '$T/out'"
new_target boot-no-kernel
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
rm -rf "$ROOTDIR/usr/lib/modules"
run_job bootloader.sh "$ROOTDIR"; rc=$?
check "bootloader: fails when the target has no kernel" bash -c "[[ $rc -ne 0 ]] && grep -q 'no kernel installed' '$T/out'"

new_target boot-luks
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
sed -i "1s|.*|$ROOTDIR /dev/mapper/luks-9f3a[/@] btrfs aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee rw,noatime,subvol=/@|" "$FAKE_STATE/mounts"
printf 'HOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole block plymouth sd-encrypt filesystems sd-btrfs-overlayfs)\n' >"$ROOTDIR/etc/mkinitcpio.conf"
run_job bootloader.sh "$ROOTDIR"; rc=$?
check "bootloader (LUKS): exits 0" test "$rc" -eq 0
check "bootloader (LUKS): cmdline opens the LUKS volume by UUID" grep -qx 'KERNEL_CMDLINE\[default\]=rd.luks.name=11111111-2222-3333-4444-555555555555=luks-9f3a root=/dev/mapper/luks-9f3a rootflags=subvol=/@ rw quiet splash' "$ROOTDIR/etc/default/limine"

new_target boot-nvram
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
touch "$FAKE_STATE/efibootmgr-fails"
run_job bootloader.sh "$ROOTDIR"; rc=$?
check "bootloader: firmware refuses the entry -> limine as fallback loader" bash -c "[[ $rc -eq 0 ]] && grep -q 'chroot limine-install --no-efi-register --fallback' '$FAKE_LOG' && test -f '$ROOTDIR/boot/EFI/BOOT/BOOTX64.EFI'"
check "bootloader: and warns" out_has "limine is the fallback loader"

new_target boot-loopesp
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
touch "$FAKE_STATE/lsblk-empty"
run_job bootloader.sh "$ROOTDIR"; rc=$?
check "bootloader: ESP not on a disk partition -> fallback loader, no efibootmgr --create" bash -c "[[ $rc -eq 0 ]] && ! grep -q 'efibootmgr --create' '$FAKE_LOG' && grep -q -- '--fallback' '$FAKE_LOG'"

new_target boot-bios
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
rmdir "$INVICTUS_EFI_SYSFS"
run_job bootloader.sh "$ROOTDIR"; rc=$?
check "bootloader: refuses a BIOS boot (UEFI only, D5)" bash -c "[[ $rc -ne 0 ]] && grep -q UEFI '$T/out'"
check "bootloader: and writes nothing" test ! -e "$ROOTDIR/etc/default/limine"

new_target boot-noesp
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
sed -i '/ vfat /d' "$FAKE_STATE/mounts"
run_job bootloader.sh "$ROOTDIR"; check "bootloader: refuses without a FAT ESP at /boot" test $? -ne 0

new_target boot-ext4
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
sed -i "1s|.*|$ROOTDIR /dev/sda2 ext4 aaaa rw|" "$FAKE_STATE/mounts"
run_job bootloader.sh "$ROOTDIR"; check "bootloader: refuses a non-btrfs root" test $? -ne 0

new_target boot-subvol
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
sed -i "1s|subvol=/@$|subvol=/@root|" "$FAKE_STATE/mounts"
run_job bootloader.sh "$ROOTDIR"; check "bootloader: refuses a root that is not the @ subvolume" test $? -ne 0

new_target boot-archiso
run_job bootloader.sh "$ROOTDIR"; rc=$?
check "bootloader: refuses while the archiso mkinitcpio drop-in is still there" bash -c "[[ $rc -ne 0 ]] && grep -q 'cleanup did not run' '$T/out'"

new_target boot-busybox
bash "$JOBS/cleanup-live.sh" "$ROOTDIR" >/dev/null 2>&1
printf 'HOOKS=(base udev autodetect block filesystems fsck)\n' >"$ROOTDIR/etc/mkinitcpio.conf"
run_job bootloader.sh "$ROOTDIR"; check "bootloader: refuses busybox hooks (sd-btrfs-overlayfs needs systemd)" test $? -ne 0

# ---- extras.sh ---------------------------------------------------------------------------
# $1 = case; sets up the target's extras list, the live resolv.conf and a PCI tree.
extras_target() {
    new_target "$1"
    mkdir -p "$ROOTDIR/usr/share/invictus" "$T/$1/pci"
    cp "$REPO/scripts/lib/extras.list" "$ROOTDIR/usr/share/invictus/extras.list"
    echo 'nameserver 192.0.2.53' >"$T/$1/live-resolv"
    echo '# the target' >"$ROOTDIR/etc/resolv.conf"
    export INVICTUS_PCI_SYSFS="$T/$1/pci" INVICTUS_LIVE_RESOLV="$T/$1/live-resolv"
}
pci_dev() { mkdir -p "$INVICTUS_PCI_SYSFS/$1"; echo "$2" >"$INVICTUS_PCI_SYSFS/$1/vendor"; echo "$3" >"$INVICTUS_PCI_SYSFS/$1/class"; }

extras_target extras
pci_dev 0000:03:00.0 0x1002 0x030000   # AMD graphics
run_job extras.sh "$ROOTDIR" invictus-office invictus-gaming; rc=$?
check "extras: exits 0 online" test "$rc" -eq 0
check "extras: one pacman -Syu --needed with the picks, inside the target" logged 'chroot pacman -Syu --needed --noconfirm invictus-office invictus-gaming'
check "extras: never pacman -Sy alone" bash -c "! grep -Eq 'pacman -Sy( |$)' '$FAKE_LOG'"
check "extras: pacman ran with the live system's name servers" grep -qx 'nameserver 192.0.2.53' "$FAKE_STATE/resolv-during"
check "extras: the target's own resolv.conf is put back" grep -qx '# the target' "$ROOTDIR/etc/resolv.conf"
check "extras: nothing left pending online" test ! -e "$ROOTDIR/var/lib/invictus/pending-extras"
check "extras: no NVIDIA firmware on an AMD machine" bash -c "! grep -q linux-firmware-nvidia '$FAKE_LOG'"
check "extras: no code in the job touches pacman.conf or SigLevel" bash -c "! grep -v '^[[:space:]]*#' '$JOBS/extras.sh' | grep -Eqi 'pacman\.conf|siglevel|--config|--gpgdir'"

extras_target extras-offline
touch "$FAKE_STATE/pacman-fails"
run_job extras.sh "$ROOTDIR" invictus-dev noto-fonts-cjk; rc=$?
check "extras: no internet still exits 0 (the install finishes)" test "$rc" -eq 0
check "extras: no internet leaves the picks pending, one per line" bash -c "printf 'invictus-dev\nnoto-fonts-cjk\n' | cmp -s - '$ROOTDIR/var/lib/invictus/pending-extras'"
check "extras: the pending file is root's, 644" bash -c "[[ \$(stat -c %a '$ROOTDIR/var/lib/invictus/pending-extras') == 644 ]]"
check "extras: no internet enables invictus-extras.service" logged 'chroot systemctl enable invictus-extras.service'
check "extras: says when they will install" out_has 'first time Invictus starts with internet'
check "extras: resolv.conf put back after a failure too" grep -qx '# the target' "$ROOTDIR/etc/resolv.conf"

extras_target extras-none
run_job extras.sh "$ROOTDIR"; rc=$?
check "extras: nothing picked runs no pacman" bash -c "[[ $rc -eq 0 ]] && ! grep -q pacman '$FAKE_LOG'"

extras_target extras-nvidia
pci_dev 0000:01:00.0 0x10de 0x030000   # NVIDIA VGA
pci_dev 0000:01:00.1 0x10de 0x040300   # its audio function
run_job extras.sh "$ROOTDIR"; rc=$?
check "extras: an NVIDIA card adds linux-firmware-nvidia even with nothing ticked" \
    bash -c "[[ $rc -eq 0 ]] && grep -qx 'chroot pacman -Syu --needed --noconfirm linux-firmware-nvidia' '$FAKE_LOG'"
extras_target extras-nvidia-audio
pci_dev 0000:01:00.1 0x10de 0x040300   # NVIDIA audio only (no graphics)
run_job extras.sh "$ROOTDIR"
check "extras: an NVIDIA non-graphics device adds nothing" bash -c "! grep -q pacman '$FAKE_LOG'"

for badpick in "linux" "invictus-moneta" "--config=/tmp/x" "invictus-office;reboot" "../etc/passwd"; do
    extras_target extras-bad
    run_job extras.sh "$ROOTDIR" invictus-office "$badpick"; rc=$?
    check "extras: refuses '$badpick' and runs no pacman" bash -c "[[ $rc -ne 0 ]] && ! grep -q pacman '$FAKE_LOG'"
done
extras_target extras-nolist
rm "$ROOTDIR/usr/share/invictus/extras.list"
run_job extras.sh "$ROOTDIR" invictus-office; rc=$?
check "extras: no extras.list in the target refuses" test "$rc" -ne 0
check "extras: refuses the live system's own /" bash -c "! bash '$JOBS/extras.sh' / invictus-office >/dev/null 2>&1"
unset INVICTUS_PCI_SYSFS INVICTUS_LIVE_RESOLV

# ---- snapper.sh ------------------------------------------------------------------------
new_target snap
run_job snapper.sh "$ROOTDIR"; rc=$?
check "snapper: exits 0" test "$rc" -eq 0
first() { grep -n "" "$FAKE_LOG" | grep -E -e "$1" | head -n 1 | cut -d: -f1; }
export -f first
check "snapper: unmounts @snapshots before root's create-config" bash -c "[[ \$(first 'umount $ROOTDIR/.snapshots') -lt \$(first 'create-config /$') ]]"
check "snapper: root's create-config is for /" logged "chroot snapper --no-dbus -c root create-config /"
check "snapper: deletes snapper's nested /.snapshots subvolume" logged "btrfs subvolume delete $ROOTDIR/.snapshots"
check "snapper: mounts @snapshots back with the same options" logged "mount -o subvol=/@snapshots,rw,noatime,compress=zstd:1 /dev/sda2 $ROOTDIR/.snapshots"
cfg="$ROOTDIR/etc/snapper/configs/root"
check "snapper root: no timeline snapshots" grep -qx 'TIMELINE_CREATE="no"' "$cfg"
check "snapper root: keeps 10 numbered and 10 important" bash -c "grep -qx 'NUMBER_LIMIT=\"10\"' '$cfg' && grep -qx 'NUMBER_LIMIT_IMPORTANT=\"10\"' '$cfg'"
check "snapper root: number cleanup on" grep -qx 'NUMBER_CLEANUP="yes"' "$cfg"
# design-simple-mode 12.2: home snapshots on their own subvolume, readable by users.
check "snapper home: unmounts @home-snapshots before its create-config" bash -c "[[ \$(first 'umount $ROOTDIR/home/.snapshots') -lt \$(first 'create-config /home') ]]"
check "snapper home: config for /home" logged "chroot snapper --no-dbus -c home create-config /home"
check "snapper home: deletes the nested /home/.snapshots subvolume" logged "btrfs subvolume delete $ROOTDIR/home/.snapshots"
check "snapper home: mounts @home-snapshots back at /home/.snapshots" logged "mount -o subvol=/@home-snapshots,rw,noatime,compress=zstd:1 /dev/sda2 $ROOTDIR/home/.snapshots"
hcfg="$ROOTDIR/etc/snapper/configs/home"
check "snapper home: ALLOW_GROUPS=users" grep -qx 'ALLOW_GROUPS="users"' "$hcfg"
check "snapper home: SYNC_ACL=yes" grep -qx 'SYNC_ACL="yes"' "$hcfg"
check "snapper home: ACLs applied through set-config (not a file edit)" bash -c "grep -q 'chroot snapper --no-dbus -c home set-config .*ALLOW_GROUPS=users SYNC_ACL=yes' '$FAKE_LOG'"
check "snapper home: ACLs set after @home-snapshots is mounted back" bash -c "[[ \$(first 'mount -o subvol=/@home-snapshots') -lt \$(first '-c home set-config') ]]"
check "snapper home: hourly timeline, 24 hourly, 7 daily, nothing longer (DS12)" bash -c "grep -qx 'TIMELINE_CREATE=\"yes\"' '$hcfg' && grep -qx 'TIMELINE_LIMIT_HOURLY=\"24\"' '$hcfg' && grep -qx 'TIMELINE_LIMIT_DAILY=\"7\"' '$hcfg' && grep -qx 'TIMELINE_LIMIT_WEEKLY=\"0\"' '$hcfg' && grep -qx 'TIMELINE_LIMIT_MONTHLY=\"0\"' '$hcfg' && grep -qx 'TIMELINE_LIMIT_YEARLY=\"0\"' '$hcfg'"
check "snapper: enables cleanup and timeline timers and limine-snapper-sync" logged "chroot systemctl enable snapper-cleanup.timer snapper-timeline.timer limine-snapper-sync.service"
check "snapper: snapshot 1 is Fresh install, important" logged 'chroot snapper --no-dbus -c root create --type single --cleanup-algorithm number --userdata important=yes --description Fresh install'
check "snapper: syncs the boot menu once" logged "chroot limine-snapper-sync"
check "snapper: No_COW on the VM folder" logged "chattr +C $ROOTDIR/var/lib/invictus/vm"

new_target snap-wrong
sed -i '/ \/.snapshots\? /d; /\/@snapshots$/d' "$FAKE_STATE/mounts"
run_job snapper.sh "$ROOTDIR"; rc=$?
check "snapper: refuses when /.snapshots is not @snapshots" test "$rc" -ne 0
check "snapper: and does not run create-config" bash -c "! grep -q create-config '$FAKE_LOG'"

new_target snap-home-wrong
sed -i '/@home-snapshots$/d' "$FAKE_STATE/mounts"
run_job snapper.sh "$ROOTDIR"; rc=$?
check "snapper: refuses when /home/.snapshots is not @home-snapshots" bash -c "[[ $rc -ne 0 ]] && grep -q 'home-snapshots' '$T/out'"
check "snapper: and does not create the home config" bash -c "! grep -q 'create-config /home' '$FAKE_LOG'"

# ---- live launcher ------------------------------------------------------------------------
export INVICTUS_INSTALLER_DATA="$T/share"
mkdir -p "$T/share"
cp -r "$REPO/installer/calamares" "$T/share/calamares"
L="$REPO/installer/live/invictus-install"
bash "$L" --assemble-only --etc "$T/etc-plain" >/dev/null 2>&1
check "launcher: plain tree has the plain settings" grep -q 'diskcheck' "$T/etc-plain/settings.conf"
check "launcher: plain tree has no packagechooser pages" bash -c "! grep -q packagechooser '$T/etc-plain/settings.conf'"
check "launcher: plain users.conf wins over nothing shared" grep -q 'location: None' "$T/etc-plain/modules/users.conf"
check "launcher: shared modules copied" test -f "$T/etc-plain/modules/mount.conf"
bash "$L" --assemble-only --advanced --etc "$T/etc-adv" >/dev/null 2>&1
check "launcher: Advanced tree has the flavor chooser" test -f "$T/etc-adv/modules/packagechooser@flavor.conf"
check "launcher: Advanced settings job reads the choices" grep -q 'gs\[packagechooser_flavor\]' "$T/etc-adv/modules/shellprocess@invictus-settings.conf"
echo "BOOT_IMAGE=/arch/boot/x86_64/vmlinuz-linux quiet splash invictus.install=advanced" >"$T/cmdline-adv"
echo "BOOT_IMAGE=/arch/boot/x86_64/vmlinuz-linux quiet splash" >"$T/cmdline-plain"
INVICTUS_CMDLINE="$T/cmdline-adv" bash "$L" --auto --assemble-only --etc "$T/etc-auto" >/dev/null 2>&1
check "launcher: --auto picks Advanced from the boot entry" grep -q packagechooser "$T/etc-auto/settings.conf"
INVICTUS_CMDLINE="$T/cmdline-plain" bash "$L" --auto --assemble-only --etc "$T/etc-auto2" >/dev/null 2>&1
check "launcher: --auto is plain otherwise" bash -c "! grep -q packagechooser '$T/etc-auto2/settings.conf'"
mkdir -p "$T/etc-stale/modules"; touch "$T/etc-stale/modules/stale.conf"
bash "$L" --assemble-only --etc "$T/etc-stale" >/dev/null 2>&1
check "launcher: an old /etc/calamares is replaced, not merged" test ! -e "$T/etc-stale/modules/stale.conf"

# ---- live session ---------------------------------------------------------------------------
S="$REPO/installer/live/session"
session() { FAKE_LOG="$T/session.log"; : >"$FAKE_LOG"; env XDG_RUNTIME_DIR="$T" "$@" bash "$S" >/dev/null 2>&1; }
mkdir -p "$T/dri"; touch "$T/dri/renderD128"
session INVICTUS_CMDLINE="$T/cmdline-plain" INVICTUS_RENDER_GLOB="$T/dri/renderD*"
check "session: Hyprland with a GPU" grep -q '^start-hyprland' "$T/session.log"
check "session: no kiosk when Hyprland runs" bash -c "! grep -q '^cage' '$T/session.log'"
echo "quiet invictus.safe=1" >"$T/cmdline-safe"
session INVICTUS_CMDLINE="$T/cmdline-safe" INVICTUS_RENDER_GLOB="$T/dri/renderD*"
check "session: safe graphics goes straight to the installer kiosk" bash -c "grep -q '^cage -s -- /usr/lib/invictus/live/invictus-install --auto' '$T/session.log' && ! grep -q hyprland '$T/session.log'"
session INVICTUS_CMDLINE="$T/cmdline-plain" INVICTUS_RENDER_GLOB="$T/nodri/renderD*"
check "session: no render node -> kiosk with software rendering" grep -q '^cage .*WLR_RENDERER=pixman' "$T/session.log"
session INVICTUS_CMDLINE="$T/cmdline-plain" INVICTUS_RENDER_GLOB="$T/dri/renderD*" FAKE_EXIT_start_hyprland=1
check "session: Hyprland failing at once -> kiosk" grep -q '^cage' "$T/session.log"

echo
echo "jobs: $pass passed, $fail failed"
((fail == 0))
