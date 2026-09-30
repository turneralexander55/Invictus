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
#   4. lint          every ISO and installer shell script, with the
#                    ShellCheck binary on PATH and, when SHELLCHECK_OLD
#                    points at one, an older release too (CI pins 0.9.0)
#
# The ISO itself is checked by tests/iso/e2e-iso.sh (container, after a
# build) and booted by tests/iso/boot-qemu.sh.
# ------------------------------------------------------------
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
failed=()

run() {
    local name="$1"; shift
    echo "=== $name"
    if "$@"; then echo; else failed+=("$name"); echo; fi
}

run profile bash "$HERE/profile.sh"
run calamares python3 "$HERE/calamares.py"
run jobs bash "$HERE/jobs.sh"

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
