# shellcheck shell=bash disable=SC2034  # accel, devs: read by the sourcing script
# ------------------------------------------------------------
# Shared by the QEMU boot tests that drive a guest's root shell on its
# second serial port (tests/iso/boot-smoke.sh, tests/iso/disk-boot.sh).
# Each runs QEMU in an Arch container (IMAGE=, CONTAINER_ARGS=, RUNTIME=)
# named $NAME, with RUNDIR mounted at /run-dir, where QEMU serves
# shell.sock (the root shell) and qmp.sock.
# ------------------------------------------------------------

IMAGE="${IMAGE:-docker.io/library/archlinux:base-devel}"
RUNTIME="${RUNTIME:-$(command -v podman || command -v docker || true)}"

# qemu_setup TOOL: check the runtime and pick the accelerator. Sets accel
# (for -accel) and devs (container arguments). Exits 2 without /dev/kvm
# unless ALLOW_TCG=1.
qemu_setup() {
    [[ -n "$RUNTIME" ]] || { echo "$1: needs podman or docker" >&2; exit 2; }
    accel="tcg,thread=multi" devs=()
    if [[ -e /dev/kvm ]]; then
        accel=kvm devs=(--device /dev/kvm)
    elif [[ "${ALLOW_TCG:-}" != 1 ]]; then
        echo "$1: no /dev/kvm here; set ALLOW_TCG=1 to boot with software emulation (slow)" >&2
        exit 2
    fi
}

# qemu_wait TOOL RUNDIR: wait for QEMU's shell socket; package install and
# extraction in the container get 10 minutes. Exits 1 if QEMU never starts.
qemu_wait() {
    local tool="$1" run="$2"
    for _ in $(seq 1 600); do
        [[ -S "$run/shell.sock" ]] && break
        if ! "$RUNTIME" inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -qx true; then break; fi
        sleep 1
    done
    if [[ ! -S "$run/shell.sock" ]]; then
        echo "$tool: QEMU did not start" >&2
        "$RUNTIME" logs "$NAME" 2>&1 | tail -n 20 >&2 || true
        cat "$run/qemu.log" >&2 2>/dev/null || true
        exit 1
    fi
}
