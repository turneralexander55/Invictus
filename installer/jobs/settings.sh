#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-settings ROOT USER FLAVOR GUARDRAILS [--hostname-from-user]
#
# Writes the two install-time defaults Alex asked for (2026-09-30), both
# switchable later on the running system (design-simple-mode 1.3, 1.6, SM24):
#   flavor      atrium | tessera     per user: ~USER/.config/invictus/flavor
#   guard rails custodia | libertas  machine:  /etc/invictus/guardrails
# and /etc/invictus/ai = off: AI is chosen at first start, and only
# `invictus-sys ai on` (a password) turns it on (design-no-ai.md N1).
# The plain install path passes "atrium custodia"; the Advanced path passes
# what the person picked (Calamares packagechooser@flavor and
# packagechooser@guardrails).
#
# Also writes /etc/invictus/release from the ISO's release file, and with
# --hostname-from-user (plain path, where the hostname field is hidden)
# names the machine <user>-invictus.
# Runs after the users job, so the account exists.
# ------------------------------------------------------------
set -euo pipefail
JOB_NAME=invictus-settings
# shellcheck source=installer/jobs/lib.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

need_root "${1:-}"
USER_NAME="${2:-}"
FLAVOR="${3:-}"
GUARDRAILS="${4:-}"
HOSTNAME_FROM_USER=false
[[ "${5:-}" == --hostname-from-user ]] && HOSTNAME_FROM_USER=true

[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "bad user name '$USER_NAME'"
one_of "$FLAVOR" "$INVICTUS_FLAVORS" || die "flavor must be one of: $INVICTUS_FLAVORS (got '$FLAVOR')"
one_of "$GUARDRAILS" "$INVICTUS_GUARDRAILS" || die "guard rails must be one of: $INVICTUS_GUARDRAILS (got '$GUARDRAILS')"
ids="$(user_ids "$USER_NAME")" || die "user $USER_NAME not found in the target"
read -r uid gid <<<"$ids"

# ---- machine: guard rails and release -----------------------------------------
printf '%s\n' "$GUARDRAILS" | write_file "$INVICTUS_GUARDRAILS_FILE" 644
say "guard rails: $GUARDRAILS"
printf 'off\n' | write_file /etc/invictus/ai 644
say "AI: off until first start"
# The ISO's own release file (written by scripts/build-iso.sh) is read from
# the live system; the target's copy was removed with the live-only files.
iso_release="${INVICTUS_ISO_RELEASE:-/etc/invictus/iso-release}"
if [[ -f "$iso_release" ]]; then
    { grep -E '^[a-z_]+=[A-Za-z0-9._:+-]*$' "$iso_release" || true
      echo "installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } | write_file /etc/invictus/release 644
else
    say "no $iso_release on the live system: /etc/invictus/release not written"
fi
# design-simple-mode 1.3: the installer runs `invictus-sys guardrails apply`
# once so the derived files match (invictus-guardrails, from invictus-base).
# An image without invictus-sys gets the file only.
if in_target sh -c 'command -v invictus-sys' >/dev/null 2>&1; then
    in_target invictus-sys guardrails apply || die "invictus-sys guardrails apply failed"
    say "guard rails applied"
else
    say "invictus-sys is not installed yet: guard rails file written, nothing applied"
fi
# sshd is off on every install (design-simple-mode 1.3), whether or not
# openssh is present.
if [[ -e "$ROOT/usr/lib/systemd/system/sshd.service" ]]; then
    in_target systemctl disable sshd.service >/dev/null 2>&1 || true
    say "sshd disabled"
fi

# ---- machine: mDNS names (docs/packages.md, "For the ISO") -------------------
# Driverless printers and scanners are found by .local names: nss-mdns
# (invictus-atrium) answers them when mdns_minimal comes before resolve on
# the hosts line.
nss="$ROOT/etc/nsswitch.conf"
if [[ -f "$nss" ]] && ! grep -Eq '^hosts:.*\bmdns_minimal\b' "$nss"; then
    tmp="$(mktemp "$nss.XXXXXX")"
    awk '/^hosts:/ {
            if (sub(/ resolve/, " mdns_minimal [NOTFOUND=return] resolve")) { print; next }
            if (sub(/ dns/, " mdns_minimal [NOTFOUND=return] dns")) { print; next }
            print $0 " mdns_minimal [NOTFOUND=return]"; next
         } { print }' "$nss" >"$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$nss"
    say "nsswitch: mdns_minimal added to hosts"
fi

# ---- user: flavor ---------------------------------------------------------------
home="$ROOT/home/$USER_NAME"
[[ -d "$home" ]] || die "no home folder for $USER_NAME"
dest="$home/$INVICTUS_FLAVOR_REL"
# Create each missing folder owned by the user, not by root.
dir="$(dirname "$dest")"
missing=()
d="$dir"
while [[ "$d" != "$home" && ! -d "$d" ]]; do missing=("$d" "${missing[@]}"); d="$(dirname "$d")"; done
for d in "${missing[@]}"; do
    install -d -m 755 -o "$uid" -g "$gid" "$d"
done
printf '%s\n' "$FLAVOR" >"$dest"
chown "$uid:$gid" "$dest"
chmod 644 "$dest"
say "flavor for $USER_NAME: $FLAVOR"

# ---- hostname (plain path) ------------------------------------------------------
if $HOSTNAME_FROM_USER; then
    host="$USER_NAME-invictus"
    host="${host//_/-}"
    printf '%s\n' "$host" | write_file /etc/hostname 644
    printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s\n' "$host" | write_file /etc/hosts 644
    say "hostname: $host"
fi
