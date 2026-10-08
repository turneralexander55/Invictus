#!/usr/bin/env bash
# ------------------------------------------------------------
# ISO and installer tests (Phase 3). No container, root or network needed.
#
#   tests/iso/run.sh
#
#   1. profile.sh    the archiso profile, secrets scan, staged build
#   2. calamares.py  installer configs: YAML, modules, schemas, decisions
#                    (needs python3 with yaml and jsonschema)
#   3. jobs.sh       the install jobs and live scripts on a fake target
#   3b. boot-smoke-rules.py  the boot smoke test's verdicts, against a
#                    fake root shell (the boot itself: boot-smoke.sh)
#   3c. disk-boot-rules.py   the installed-disk boot test's limine.conf
#                    logic and verdicts, against a fake root shell that
#                    reboots (the boot itself: disk-boot.sh, after
#                    e2e-jobs.sh --keep)
#   4. lint          every ISO and installer shell script, with the
#                    ShellCheck binary on PATH and, when SHELLCHECK_OLD
#                    points at one, an older release too (CI pins 0.9.0)
#
# The ISO itself is scanned for secrets by scripts/build-iso.sh, booted by
# tests/iso/boot-smoke.sh (CI, after the build), installed onto a btrfs
# disk image by tests/iso/e2e-jobs.sh, whose disk tests/iso/disk-boot.sh
# boots (CI), and driven by hand with tests/iso/boot-qemu.sh.
# ------------------------------------------------------------
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
failed=()

run() {
    local name="$1" out rc=0; shift
    echo "=== $name"
    out="$(mktemp)"
    "$@" >"$out" 2>&1 || rc=$?
    cat "$out"
    # A check whose command does not exist can pass by accident (the
    # "! -e" check in profile.sh did, 2026-09-30): any "command not found"
    # fails the group.
    if grep -q 'command not found' "$out"; then
        echo "FAIL  $name printed 'command not found': a check runs a command that does not exist"
        rc=1
    fi
    rm -f "$out"
    if ((rc == 0)); then echo; else failed+=("$name"); echo; fi
}

run profile bash "$HERE/profile.sh"
run calamares python3 "$HERE/calamares.py"
run jobs bash "$HERE/jobs.sh"
run "boot-smoke rules" python3 "$HERE/boot-smoke-rules.py"
run "disk-boot rules" python3 "$HERE/disk-boot-rules.py"

scripts=(
    "$REPO/scripts/build-iso.sh"
    "$REPO/iso/secrets-scan.sh"
    "$REPO/iso/render-art.sh"
    "$REPO/iso/profiledef.sh"
    "$REPO/iso/airootfs/root/customize_airootfs.sh"
    "$REPO/iso/own-needed/invictus-boot-branding/invictus-boot-branding.install"
    "$REPO"/installer/jobs/*.sh
    "$REPO/installer/live/invictus-install"
    "$REPO/installer/live/session"
    "$HERE"/*.sh
    "$HERE"/fakes/*
)
pkgbuilds=("$REPO"/iso/own-needed/*/PKGBUILD)
shellcheck_with() {
    local sc="$1"
    echo "$("$sc" --version | sed -n 2p): ${#scripts[@]} scripts, ${#pkgbuilds[@]} PKGBUILDs"
    (cd "$REPO" && "$sc" -x -s bash "${scripts[@]}") || return 1
    # As .github/workflows/checks.yml lints PKGBUILDs: makepkg sets srcdir,
    # pkgdir and reads the metadata variables.
    (cd "$REPO" && "$sc" -s bash -e SC2034,SC2154,SC2164 "${pkgbuilds[@]}")
}
run "shellcheck (PATH)" shellcheck_with shellcheck
if [[ -n "${SHELLCHECK_OLD:-}" ]]; then
    run "shellcheck ($SHELLCHECK_OLD)" shellcheck_with "$SHELLCHECK_OLD"
fi

if ((${#failed[@]})); then
    echo "tests/iso: FAILED: ${failed[*]}"
    exit 1
fi
echo "tests/iso: all groups passed"
