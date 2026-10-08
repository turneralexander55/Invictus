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
# The pending file must be a plain file owned by root (a user-writable
# one would let anyone choose what root installs); anything else is refused.
#
# Success: the pending file is removed, the service disabled, and
# invictus-doctor run once. Failure (still no internet, a mirror down): the
# file stays and the next start tries again, on at most 5 boots (counted in
# PENDING.tries as "boot-id count"). After that it stops, leaves the file,
# disables the service and logs "Extras not installed: <names>", which
# invictus-doctor reports. To try again: remove PENDING.tries, run this.
# Exit: pacman's code, 2 for a bad pending file.
# Env (tests): INVICTUS_PACMAN, INVICTUS_SYSTEMCTL, INVICTUS_INHIBIT,
#              INVICTUS_EXTRAS_PENDING, INVICTUS_EXTRAS_LIST,
#              INVICTUS_EXTRAS_OWNER (uid the pending file must have, 0),
#              INVICTUS_BOOT_ID (file with the boot id), INVICTUS_DOCTOR
# ------------------------------------------------------------
set -euo pipefail

PENDING="${INVICTUS_EXTRAS_PENDING:-/var/lib/invictus/pending-extras}"
LIST="${INVICTUS_EXTRAS_LIST:-/usr/share/invictus/extras.list}"
PACMAN="${INVICTUS_PACMAN:-pacman}"
SYSTEMCTL="${INVICTUS_SYSTEMCTL:-systemctl}"
OWNER="${INVICTUS_EXTRAS_OWNER:-0}"
BOOT_ID="${INVICTUS_BOOT_ID:-/proc/sys/kernel/random/boot_id}"
DOCTOR="${INVICTUS_DOCTOR:-invictus-doctor}"
TRIES="$PENDING.tries"
MAX_BOOTS=5
if [[ -n "${INVICTUS_INHIBIT+x}" ]]; then read -ra INHIBIT <<<"$INVICTUS_INHIBIT"
else INHIBIT=(systemd-inhibit --what=shutdown:sleep --who="Invictus extras" --why="Installing the extras you picked" --mode=block); fi

say() { echo "pending-extras: $*"; }

if [[ ! -s "$PENDING" ]]; then
    say "nothing pending"
    exit 0
fi
[[ -f "$LIST" ]] || { say "no $LIST"; exit 2; }
if [[ -L "$PENDING" || ! -f "$PENDING" || "$(stat -c %u "$PENDING")" != "$OWNER" ]]; then
    say "refusing $PENDING: not a plain file owned by root"
    exit 2
fi
allowed=" $(awk '!/^[[:space:]]*#/ && NF { print $1 }' "$LIST" | paste -sd' ') "

names=()
lineno=0
while IFS= read -r n || [[ -n "$n" ]]; do
    lineno=$((lineno + 1))
    [[ -z "$n" ]] && continue
    if [[ ! "$n" =~ ^[a-z0-9][a-z0-9@._+-]*$ || "$allowed" != *" $n "* ]]; then
        say "bad line $lineno: not an extra (see $LIST)"
        exit 2
    fi
    names+=("$n")
done < "$PENDING"
((${#names[@]} > 0)) || { say "nothing pending"; exit 0; }

# At most MAX_BOOTS boots try: a new boot id bumps the count, the retries
# within one boot do not.
boot="$(cat "$BOOT_ID" 2>/dev/null || echo unknown)"
last="" count=0
if [[ -f "$TRIES" ]]; then read -r last count < "$TRIES" || true; fi
[[ "$count" =~ ^[0-9]+$ ]] || count=0
if [[ "$last" != "$boot" ]]; then
    if ((count >= MAX_BOOTS)); then
        say "Extras not installed: ${names[*]} (gave up after $MAX_BOOTS boots; to try again remove $TRIES and run $0)"
        "$SYSTEMCTL" disable invictus-extras.service >/dev/null 2>&1 || true
        exit 0
    fi
    count=$((count + 1))
    printf '%s %s\n' "$boot" "$count" > "$TRIES"
fi

say "installing: ${names[*]}"
rc=0
"${INHIBIT[@]}" "$PACMAN" -Syu --needed --noconfirm "${names[@]}" || rc=$?
if ((rc != 0)); then
    if ((count >= MAX_BOOTS)); then
        say "Extras not installed: ${names[*]} (pacman stopped, exit $rc; that was try $count of $MAX_BOOTS, so it will not try again)"
    else
        say "pacman stopped (exit $rc); trying again on the next start"
    fi
    exit "$rc"
fi
rm -f "$PENDING" "$TRIES"
"$SYSTEMCTL" disable invictus-extras.service >/dev/null 2>&1 || true
say "done"
# New software may need a look (the shipped checks); the extras are in
# already, so what the doctor finds does not fail this run.
"$DOCTOR" || say "invictus-doctor reported a problem (run it to see)"
