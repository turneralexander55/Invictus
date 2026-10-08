#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-extras ROOT [PACKAGE...]
#
# Installs the extras picked on the Extras page (Calamares netinstall,
# installer/calamares/common/modules/netinstall.conf, handed over by
# installer/modules/invictusextras) into the target, from our signed repo:
# pacman runs inside the target with the target's pacman.conf, so every
# package is checked against invictus-keyring and Arch's keyring
# (SigLevel Required; this job never changes it).
#
#  - Only names in the target's /usr/share/invictus/extras.list
#    (scripts/lib/extras.list, from invictus-tools) are accepted; anything
#    else stops the job.
#  - An NVIDIA graphics card (PCI vendor 10de, display class) adds
#    linux-firmware-nvidia, which the ISO leaves out.
#  - pacman -Syu --needed, never -Sy alone: the image's package lists are
#    as old as the ISO, and new extras must not meet older libraries.
#  - No internet, or pacman fails: the install still finishes. The names
#    go to /var/lib/invictus/pending-extras and invictus-extras.service
#    (invictus-tools) installs them on the first start with internet.
#
# Runs after the bootloader job (a kernel update in the -Syu then finds
# limine set up) and before the snapper job.
# Env (tests): INVICTUS_PCI_SYSFS, INVICTUS_LIVE_RESOLV.
# ------------------------------------------------------------
set -euo pipefail
JOB_NAME=invictus-extras
# shellcheck source=installer/jobs/lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

need_root "${1:-}"
shift
LIST="$ROOT/usr/share/invictus/extras.list"
PENDING=/var/lib/invictus/pending-extras
PCI="${INVICTUS_PCI_SYSFS:-/sys/bus/pci/devices}"
LIVE_RESOLV="${INVICTUS_LIVE_RESOLV:-/etc/resolv.conf}"

[[ -f "$LIST" ]] || die "no /usr/share/invictus/extras.list in the target (invictus-tools)"
allowed="$(awk '!/^[[:space:]]*#/ && NF { print $1 }' "$LIST" | paste -sd' ')"

want=()
add() { one_of "$1" "${want[*]:-}" || want+=("$1"); }
# A name the list does not know is skipped with a warning, not fatal: an
# extra missing from this build must not stop the whole install. Only names
# on the list ever reach pacman.
for n in "$@"; do
    if [[ ! "$n" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || ! one_of "$n" "$allowed"; then
        say "warning: skipping '${n//[^[:print:]]/?}': not an extra (see /usr/share/invictus/extras.list)"
        continue
    fi
    add "$n"
done

# NVIDIA graphics: vendor 0x10de, class 0x03xxxx (VGA, 3D, display).
has_nvidia() {
    local d
    for d in "$PCI"/*; do
        [[ -f "$d/vendor" && -f "$d/class" ]] || continue
        [[ "$(<"$d/vendor")" == 0x10de && "$(<"$d/class")" == 0x03* ]] && return 0
    done
    return 1
}
if has_nvidia && one_of linux-firmware-nvidia "$allowed"; then
    say "NVIDIA graphics card found: adding linux-firmware-nvidia"
    add linux-firmware-nvidia
fi

if ((${#want[@]} == 0)); then
    say "no extras picked"
    exit 0
fi
say "extras: ${want[*]}"

# Name resolution inside the target: the live system's resolv.conf for the
# length of the pacman run (as arch-chroot does), then the target's own back.
resolv="$ROOT/etc/resolv.conf"
keep="$(mktemp -d)"
had_resolv=false
if [[ -e "$resolv" || -L "$resolv" ]]; then cp -a "$resolv" "$keep/resolv.conf"; had_resolv=true; fi
# shellcheck disable=SC2329  # called by the EXIT trap
restore_resolv() {
    rm -f "$resolv"
    if $had_resolv; then cp -a "$keep/resolv.conf" "$resolv"; fi
    rm -rf "$keep"
}
trap restore_resolv EXIT
if [[ -f "$LIVE_RESOLV" ]]; then
    install -d -m 755 "$ROOT/etc"
    rm -f "$resolv"
    cp -L "$LIVE_RESOLV" "$resolv"
fi

rc=0
in_target pacman -Syu --needed --noconfirm "${want[@]}" || rc=$?
if ((rc == 0)); then
    rm -f "$ROOT$PENDING"
    say "extras installed"
    exit 0
fi

say "could not install the extras now (pacman exit $rc; no internet?)"
printf '%s\n' "${want[@]}" | write_file "$PENDING" 644
if in_target systemctl enable invictus-extras.service >/dev/null 2>&1; then
    say "they will install the first time Invictus starts with internet"
else
    say "WARNING: could not enable invictus-extras.service; run 'sudo /usr/lib/invictus/pending-extras' later"
fi
exit 0
