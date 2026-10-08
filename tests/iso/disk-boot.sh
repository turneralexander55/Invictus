#!/usr/bin/env bash
# ------------------------------------------------------------
# Installed-disk boot test: boot the disk that `tests/iso/e2e-jobs.sh
# --keep DIR` installed, in QEMU (q35, UEFI with OVMF), from its own ESP
# through limine, and fail when the boot is not what an install promises
# (tests/iso/disk-boot.py has the rules: the CachyOS kernel from limine's
# entry, no failed or timed-out unit, the default target and the login
# screen, the Fresh install snapshot and its boot entry, no ssh, Custodia
# applied; then one boot of the snapshot entry to multi-user).
#
#   tests/iso/disk-boot.sh DIR RUNDIR [--timeout SECONDS] [--mem MB] [--no-snapshot-boot]
#
# DIR holds disk.img and disk.env. The guest writes to a qcow2 overlay in
# the container, so DIR is not changed and the test can run again. Default
# timeout 600 s per boot, memory 4096 MB. Needs /dev/kvm unless ALLOW_TCG=1. Runs QEMU in an Arch
# container like boot-smoke.sh (IMAGE=, CONTAINER_ARGS=, RUNTIME=).
#
# No kernel or command line is passed in: the firmware finds limine as the
# fallback loader (EFI/BOOT/BOOTX64.EFI; there is no NVRAM entry, as when
# the installer could not write one), and limine boots its default entry.
# The root shell comes from the image itself (e2e-jobs.sh --keep enables
# debug-shell.service on ttyS1, the second serial port here).
#
# RUNDIR gets report.txt, journal.txt, journal-snapshot.txt, limine.conf,
# screen.png, serial0.log and qemu.log.
# ------------------------------------------------------------
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
NAME=invictus-disk-boot
# shellcheck source=tests/iso/qemu-lib.sh
. "$HERE/qemu-lib.sh"
qemu_setup disk-boot

dir="$(realpath "${1:?DIR with disk.img and disk.env}")"; run="${2:?RUNDIR}"; shift 2
timeout=600 mem=4096 driver_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) timeout="${2:?}"; shift 2 ;;
        --mem) mem="${2:?}"; shift 2 ;;
        --no-snapshot-boot) driver_args+=(--no-snapshot-boot); shift ;;
        *) echo "disk-boot: unknown argument $1" >&2; exit 2 ;;
    esac
done
[[ "$timeout" =~ ^[0-9]+$ && "$mem" =~ ^[0-9]+$ ]] || { echo "disk-boot: --timeout and --mem take numbers" >&2; exit 2; }
[[ -s "$dir/disk.img" && -s "$dir/disk.env" ]] || { echo "disk-boot: $dir needs disk.img and disk.env (tests/iso/e2e-jobs.sh --keep)" >&2; exit 2; }
mkdir -p "$run"
run="$(cd "$run" && pwd -P)"
rm -f "$run/qmp.sock" "$run/shell.sock"

read -ra extra <<< "${CONTAINER_ARGS:-}"
"$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true
trap '"$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
# shellcheck disable=SC2016  # expanded inside the container
"$RUNTIME" run -d --name "$NAME" "${devs[@]}" "${extra[@]}" \
    -v "$dir:/disk:ro" -v "$run:/run-dir" -e ACCEL="$accel" -e MEM="$mem" \
    "$IMAGE" bash -c '
        set -e
        pacman -Sy --noconfirm --needed qemu-base edk2-ovmf >/dev/null
        cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/vars.fd
        # The guest writes to an overlay; /disk stays read-only.
        qemu-img create -q -f qcow2 -b /disk/disk.img -F raw /tmp/overlay.qcow2
        umask 000  # the host side connects to the sockets as any user
        exec qemu-system-x86_64 -machine q35 -accel "$ACCEL" -cpu max -smp 4 -m "$MEM" \
            -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
            -drive if=pflash,format=raw,file=/tmp/vars.fd \
            -drive file=/tmp/overlay.qcow2,format=qcow2,if=none,id=hd \
            -device virtio-blk-pci,drive=hd,bootindex=0 \
            -device qemu-xhci -device usb-tablet -device usb-kbd \
            -vga std -display none \
            -nic user,model=virtio-net-pci \
            -qmp unix:/run-dir/qmp.sock,server=on,wait=off \
            -serial file:/run-dir/serial0.log \
            -serial unix:/run-dir/shell.sock,server=on,wait=off \
            >/run-dir/qemu.log 2>&1
    ' >/dev/null

qemu_wait disk-boot "$run"
echo "disk-boot: QEMU running ($accel) on $dir/disk.img (writes thrown away)"
python3 "$HERE/disk-boot.py" "$run" --env "$dir/disk.env" --timeout "$timeout" "${driver_args[@]}"
