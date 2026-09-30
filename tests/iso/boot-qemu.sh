#!/usr/bin/env bash
# ------------------------------------------------------------
# Boot the ISO in QEMU with UEFI firmware (OVMF), headless, from an Arch
# container, and drive it through QMP (tests/iso/qmp.py).
#
#   tests/iso/boot-qemu.sh start ISO RUNDIR [--disk GB] [--mem MB] [--from-disk]
#   tests/iso/boot-qemu.sh stop RUNDIR
#
#   then: tests/iso/qmp.py RUNDIR/qmp.sock shot RUNDIR/screen.png
#         tests/iso/qmp.py RUNDIR/qmp.sock keys ret
#
# RUNDIR gets qmp.sock, serial.log, qemu.log, the target disk (disk.qcow2,
# default 64 GB, sparse) and the firmware's variable store (ovmf-vars.fd),
# which keeps the boot entries the installer writes. --from-disk boots the
# installed disk without the ISO (after an install).
#
# Uses KVM when /dev/kvm exists, otherwise TCG (software emulation, slow:
# minutes to the desktop). The display is QEMU's standard VGA: no 3D and no
# GPU render node, so the live session takes its cage fallback.
# IMAGE= and CONTAINER_ARGS= as for build-iso.sh.
# ------------------------------------------------------------
set -euo pipefail

IMAGE="${IMAGE:-docker.io/library/archlinux:base-devel}"
NAME=invictus-qemu
RUNTIME="$(command -v podman || command -v docker || true)"
[[ -n "$RUNTIME" ]] || { echo "needs podman or docker" >&2; exit 2; }

cmd="${1:-}"; shift || true
case "$cmd" in
    stop)
        run="${1:?RUNDIR}"
        python3 "$(dirname "$0")/qmp.py" "$run/qmp.sock" quit 2>/dev/null || true
        "$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true
        exit 0 ;;
    start) ;;
    *) sed -n '2,21p' "$0"; exit 2 ;;
esac

iso="$(realpath "${1:?ISO}")"; run="${2:?RUNDIR}"; shift 2
disk_gb=64 mem=6144 from_disk=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) disk_gb="$2"; shift 2 ;;
        --mem) mem="$2"; shift 2 ;;
        --from-disk) from_disk=true; shift ;;
        *) echo "unknown argument $1" >&2; exit 2 ;;
    esac
done
mkdir -p "$run"
run="$(cd "$run" && pwd -P)"
rm -f "$run/qmp.sock"

accel="tcg,thread=multi"
devs=()
if [[ -e /dev/kvm ]]; then accel=kvm; devs=(--device /dev/kvm); fi

cdrom=(-drive "file=/iso,media=cdrom,if=none,id=cd,readonly=on" -device "ide-cd,drive=cd,bootindex=0")
$from_disk && cdrom=()

read -ra extra <<< "${CONTAINER_ARGS:-}"
"$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true
"$RUNTIME" run -d --name "$NAME" "${devs[@]}" "${extra[@]}" \
    -v "$iso:/iso:ro" -v "$run:/run-dir" \
    "$IMAGE" bash -c '
        set -e
        pacman -Sy --noconfirm --needed qemu-base edk2-ovmf >/dev/null
        [[ -f /run-dir/ovmf-vars.fd ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /run-dir/ovmf-vars.fd
        [[ -f /run-dir/disk.qcow2 ]] || qemu-img create -q -f qcow2 /run-dir/disk.qcow2 '"${disk_gb}"'G
        exec qemu-system-x86_64 -machine q35 -accel '"$accel"' -cpu max -smp 4 -m '"$mem"' \
            -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
            -drive if=pflash,format=raw,file=/run-dir/ovmf-vars.fd \
            '"${cdrom[*]}"' \
            -drive file=/run-dir/disk.qcow2,if=none,id=hd -device virtio-blk-pci,drive=hd,bootindex=1 \
            -vga std -display none \
            -device qemu-xhci -device usb-tablet -device usb-kbd \
            -nic user,model=virtio-net-pci \
            -qmp unix:/run-dir/qmp.sock,server=on,wait=off \
            -serial file:/run-dir/serial.log \
            >/run-dir/qemu.log 2>&1
    ' >/dev/null

for _ in $(seq 1 120); do
    [[ -S "$run/qmp.sock" ]] && break
    sleep 1
done
[[ -S "$run/qmp.sock" ]] || { echo "QEMU did not start; see $run/qemu.log and: $RUNTIME logs $NAME" >&2; exit 1; }
echo "QEMU running ($accel) in container $NAME; QMP at $run/qmp.sock"
