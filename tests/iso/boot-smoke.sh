#!/usr/bin/env bash
# ------------------------------------------------------------
# Boot smoke test: boot the built ISO in QEMU (UEFI, OVMF) as a USB stick,
# the way people boot it, and fail when a unit fails or times out, or when
# the live session's installer is not running in time
# (tests/iso/boot-smoke.py has the rules).
#
#   tests/iso/boot-smoke.sh ISO RUNDIR [--timeout SECONDS] [--mem MB]
#
# Default timeout 600 s, default memory 6144 MB (enough for archiso to copy
# the image to RAM, as on most real machines). Needs /dev/kvm unless
# ALLOW_TCG=1: without KVM, QEMU emulates the CPU in software and the boot
# takes far longer (use --timeout 3600 or so). Runs QEMU in an Arch
# container like boot-qemu.sh (IMAGE=, CONTAINER_ARGS=, RUNTIME=).
#
# The kernel and initramfs are taken from the ISO and booted directly, with
# the default entry's command line plus systemd.debug_shell=/dev/ttyS1: a
# root shell on the second serial port that the driver uses to ask systemd.
# Nothing in the image changes. The boot menu itself is not exercised here
# (boot-qemu.sh does that).
#
# RUNDIR gets report.txt, journal.txt, screen.png and qemu.log.
# ------------------------------------------------------------
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NAME=invictus-boot-smoke
# shellcheck source=tests/iso/qemu-lib.sh
. "$HERE/qemu-lib.sh"
qemu_setup boot-smoke

iso="$(realpath "${1:?ISO}")"; run="${2:?RUNDIR}"; shift 2
timeout=600 mem=6144
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) timeout="${2:?}"; shift 2 ;;
        --mem) mem="${2:?}"; shift 2 ;;
        *) echo "boot-smoke: unknown argument $1" >&2; exit 2 ;;
    esac
done
[[ "$timeout" =~ ^[0-9]+$ && "$mem" =~ ^[0-9]+$ ]] || { echo "boot-smoke: --timeout and --mem take numbers" >&2; exit 2; }
mkdir -p "$run"
run="$(cd "$run" && pwd -P)"
rm -f "$run/qmp.sock" "$run/shell.sock"

read -ra extra <<< "${CONTAINER_ARGS:-}"
"$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true
trap '"$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
# shellcheck disable=SC2016  # expanded inside the container
"$RUNTIME" run -d --name "$NAME" "${devs[@]}" "${extra[@]}" \
    -v "$iso:/iso.iso:ro" -v "$run:/run-dir" -e ACCEL="$accel" -e MEM="$mem" \
    "$IMAGE" bash -c '
        set -e
        pacman -Sy --noconfirm --needed qemu-base edk2-ovmf libarchive >/dev/null
        mkdir -p /boot-iso
        bsdtar -xf /iso.iso -C /boot-iso loader/entries/01-invictus.conf \
            arch/boot/x86_64/vmlinuz-linux-cachyos arch/boot/x86_64/initramfs-linux-cachyos.img
        cmdline="$(sed -n "s/^options[[:space:]]*//p" /boot-iso/loader/entries/01-invictus.conf)"
        cmdline="$cmdline systemd.debug_shell=/dev/ttyS1"
        echo "$cmdline" >/run-dir/cmdline.txt
        cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/vars.fd
        umask 000  # the host side connects to the sockets as any user
        exec qemu-system-x86_64 -machine q35 -accel "$ACCEL" -cpu max -smp 4 -m "$MEM" \
            -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
            -drive if=pflash,format=raw,file=/tmp/vars.fd \
            -kernel /boot-iso/arch/boot/x86_64/vmlinuz-linux-cachyos \
            -initrd /boot-iso/arch/boot/x86_64/initramfs-linux-cachyos.img \
            -append "$cmdline" \
            -device qemu-xhci \
            -drive if=none,id=stick,format=raw,readonly=on,file=/iso.iso \
            -device usb-storage,drive=stick,removable=on \
            -device usb-tablet -device usb-kbd \
            -vga std -display none \
            -nic user,model=virtio-net-pci \
            -qmp unix:/run-dir/qmp.sock,server=on,wait=off \
            -serial file:/run-dir/serial0.log \
            -serial unix:/run-dir/shell.sock,server=on,wait=off \
            >/run-dir/qemu.log 2>&1
    ' >/dev/null

# Package install and extraction get 10 minutes on top of the boot timeout.
qemu_wait boot-smoke "$run"
echo "boot-smoke: QEMU running ($accel); command line: $(cat "$run/cmdline.txt")"
python3 "$HERE/boot-smoke.py" "$run" --timeout "$timeout"
