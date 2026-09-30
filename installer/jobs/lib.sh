# shellcheck shell=bash disable=SC2034
# ------------------------------------------------------------
# Shared helpers for the Invictus Calamares jobs (installer/jobs/*.sh).
#
# The jobs run on the live system (shellprocess with dontChroot: true) and
# are handed the target's root mount point. Anything that must run inside
# the target goes through in_target, which is `chroot` by default. Calamares
# has already bind-mounted /proc, /sys, /dev, /run and efivarfs into the
# target (mount.conf extraMounts).
#
# Tests (tests/iso/jobs.sh) point INVICTUS_CHROOT at a fake that logs the
# command instead of running it, and put stubs for findmnt, mount, umount,
# btrfs, blkid and cryptsetup first on PATH.
# ------------------------------------------------------------

# Where the per-user desktop flavor and the machine's guard rails are kept.
# Names from Alex (2026-09-30): flavor atrium|tessera, guard rails
# custodia|libertas. Minerva is settling the exact keys; change them here only.
INVICTUS_FLAVOR_REL=".config/invictus/flavor"      # in the user's home
INVICTUS_GUARDRAILS_FILE="/etc/invictus/guardrails" # in the target
INVICTUS_FLAVORS="atrium tessera"
INVICTUS_GUARDRAILS="custodia libertas"

# Data shipped with the installer package (live-only list, limine header,
# release file). Tests point this at the checkout.
INVICTUS_INSTALLER_DATA="${INVICTUS_INSTALLER_DATA:-/usr/share/invictus/installer}"

JOB_NAME="${JOB_NAME:-invictus-job}"

say() { echo "$JOB_NAME: $*"; }
die() { echo "$JOB_NAME: ERROR: $*" >&2; exit 1; }

# in_target CMD ARGS...: run a command inside the target root.
in_target() {
    ${INVICTUS_CHROOT:-chroot} "$ROOT" "$@"
}

# need_root ROOT: check the argument is an absolute path to a directory that
# is not the live system's own /.
need_root() {
    local r="${1:-}"
    [[ -n "$r" && "$r" == /* ]] || die "target root must be an absolute path (got '${r}')"
    [[ -d "$r" ]] || die "target root $r does not exist"
    [[ "$(cd "$r" && pwd -P)" != / ]] || die "refusing to work on the live system's own /"
    ROOT="$(cd "$r" && pwd -P)"
}

# one_of VALUE LIST: VALUE is one of the space-separated words in LIST.
one_of() {
    local v="$1" w
    for w in $2; do [[ "$v" == "$w" ]] && return 0; done
    return 1
}

# user_ids NAME: print "uid gid" for NAME from the target's /etc/passwd.
user_ids() {
    awk -F: -v u="$1" '$1 == u { print $3, $4; found = 1 } END { exit !found }' "$ROOT/etc/passwd"
}

# write_file PATH MODE: write stdin to a file in the target (PATH is
# absolute inside the target), creating parent folders, root-owned.
write_file() {
    local dest="$ROOT$1" mode="$2" tmp
    install -d -m 755 "$(dirname "$dest")"
    tmp="$(mktemp "$dest.XXXXXX")"
    cat >"$tmp"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$dest"
}
