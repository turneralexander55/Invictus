#!/usr/bin/env bash
# ------------------------------------------------------------
# pending-extras: install the extras the installer could not (no internet
# during the install). Installed as /usr/lib/invictus/pending-extras by
# invictus-tools; run as root by invictus-extras.service on a start with
# the network up, or by hand.
#
# Reads /var/lib/invictus/pending-extras (one package per line, written by
# installer/jobs/extras.sh), accepts only names in
# /usr/share/invictus/extras.list, and runs pacman -Syu --needed with
# them: the whole system at once, never -Sy alone (same rule as
# invictus-update), with the system's own pacman.conf and signature
# checks. Shutdown and sleep are held off while pacman runs, so a
# half-done transaction cannot be cut short from the desktop.
#
# Success: the pending file is removed and the service disabled.
# Failure (still no internet, a mirror down): the file stays and the next
# start tries again. Exit: pacman's code, 2 for a bad pending file.
# Env (tests): INVICTUS_PACMAN, INVICTUS_SYSTEMCTL, INVICTUS_INHIBIT,
#              INVICTUS_EXTRAS_PENDING, INVICTUS_EXTRAS_LIST, INVICTUS_LIB
# ------------------------------------------------------------
set -euo pipefail
# The installed copy runs as root and honours no test overrides (Janus L3).
case "$(readlink -f -- "$0")" in
    /usr/*) export PATH=/usr/bin
            while read -r v; do unset "$v"; done < <(compgen -v | grep -E '^(INVICTUS_|ACTA_)' || true) ;;
esac
# shellcheck source=scripts/lib/pacman.sh
. "${INVICTUS_LIB:-/usr/lib/invictus}/lib/pacman.sh"

PENDING="${INVICTUS_EXTRAS_PENDING:-/var/lib/invictus/pending-extras}"
LIST="${INVICTUS_EXTRAS_LIST:-/usr/share/invictus/extras.list}"
PACMAN="${INVICTUS_PACMAN:-pacman}"
SYSTEMCTL="${INVICTUS_SYSTEMCTL:-systemctl}"
if [[ -n "${INVICTUS_INHIBIT+x}" ]]; then read -ra INHIBIT <<<"$INVICTUS_INHIBIT"
else INHIBIT=(systemd-inhibit --what=shutdown:sleep --who="Invictus extras" --why="Installing the extras you picked" --mode=block); fi

say() { echo "pending-extras: $*"; }

if [[ ! -s "$PENDING" ]]; then
    say "nothing pending"
    exit 0
fi
[[ -f "$LIST" ]] || { say "no $LIST"; exit 2; }
allowed=" $(awk '!/^[[:space:]]*#/ && NF { print $1 }' "$LIST" | paste -sd' ') "

names=()
while IFS= read -r n || [[ -n "$n" ]]; do
    [[ -z "$n" ]] && continue
    if ! valid_package_name "$n" || [[ "$n" == */* || "$allowed" != *" $n "* ]]; then
        say "refusing '$n': not an extra (see $LIST)"
        exit 2
    fi
    names+=("$n")
done < "$PENDING"
((${#names[@]} > 0)) || { say "nothing pending"; exit 0; }

say "installing: ${names[*]}"
rc=0
pacman_install_needed "${names[@]}" || rc=$?
if ((rc != 0)); then
    say "pacman stopped (exit $rc); trying again on the next start"
    exit "$rc"
fi
rm -f "$PENDING"
"$SYSTEMCTL" disable invictus-extras.service >/dev/null 2>&1 || true
say "done"
