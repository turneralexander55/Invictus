#!/usr/bin/env bash
# ------------------------------------------------------------
# pacman-sandbox-hotfix.sh: for a machine where `sudo pacman -Syu` fails
# with "Resolving timed out" on every mirror while
# `sudo pacman -Syu --disable-sandbox` works (Alex's first install,
# 2026-10-09; design build note 63). Run once, as root:
#
#   sudo bash pacman-sandbox-hotfix.sh            find the cause, apply the smallest fix
#   sudo bash pacman-sandbox-hotfix.sh --check    find the cause, change nothing
#
# It writes a report to /var/tmp/invictus-pacman-sandbox.txt (send it to
# the team: it holds no secrets, only versions, file modes and pacman's
# error lines), then refreshes the package lists into a throwaway folder
# with pacman's download sandbox in full, without its syscall filter,
# without its file-system rules, and without it at all. The first that
# resolves names decides the one line added to [options] in
# /etc/pacman.conf (a backup is kept next to it):
#   sandbox in full works       nothing to change
#   DisableSandboxSyscalls      keeps the alpm user and the file-system rules
#   DisableSandboxFilesystem    keeps the alpm user and the syscall filter
#   DisableSandbox              last resort: downloads run as root again
# Undo: delete the line marked "invictus hotfix" from /etc/pacman.conf.
#
# Only name-resolution errors decide: a mirror's other errors (a 503) do
# not count against a step, so a flaky mirror cannot talk it into turning
# more of the sandbox off.
#
# Exit: 0 fixed or nothing to fix; 1 nothing resolves names even without
# the sandbox (not a sandbox problem: check the network); 2 bad use.
# Env (tests, tests/pkgs/hotfix.sh): INVICTUS_PACMAN (pacman command; set,
#   it also skips the root check), INVICTUS_PACMAN_CONF, INVICTUS_PACMAN_CONF_CMD,
#   INVICTUS_REPORT, INVICTUS_PROBE_HOST.
# ------------------------------------------------------------
set -uo pipefail

PACMAN="${INVICTUS_PACMAN:-pacman}"
CONF="${INVICTUS_PACMAN_CONF:-/etc/pacman.conf}"
PACMAN_CONF_CMD="${INVICTUS_PACMAN_CONF_CMD:-pacman-conf}"
REPORT="${INVICTUS_REPORT:-/var/tmp/invictus-pacman-sandbox.txt}"
HOST="${INVICTUS_PROBE_HOST:-geo.mirror.pkgbuild.com}"
MARK="# invictus hotfix (build note 63): pacman's download sandbox could not resolve names here"
RESOLVE='Resolving timed out|Could not resolve host|Couldn'"'"'t resolve host'

apply=true
case "${1:-}" in
    "") ;;
    --check) apply=false ;;
    *) echo "usage: pacman-sandbox-hotfix.sh [--check]" >&2; exit 2 ;;
esac
[[ $EUID -eq 0 || -n "${INVICTUS_PACMAN:-}" ]] || { echo "pacman-sandbox-hotfix: run it with sudo" >&2; exit 2; }
[[ -f "$CONF" ]] || { echo "pacman-sandbox-hotfix: no $CONF" >&2; exit 2; }

say() { echo "$*" | tee -a "$REPORT"; }
: >"$REPORT"
work="$(mktemp -d)"
chmod 755 "$work"  # the download child runs as alpm
trap 'rm -rf "$work"' EXIT

{
    echo "== $(date -Is) $(uname -r)"
    pacman -Q pacman curl glibc systemd nss-mdns avahi 2>&1
    echo "== pacman-conf"; $PACMAN_CONF_CMD --config "$CONF" 2>&1 | grep -E '^(DownloadUser|DisableSandbox)'
    echo "== hosts line"; grep '^hosts:' /etc/nsswitch.conf
    echo "== files"; namei -l /etc/resolv.conf /etc/nsswitch.conf /etc/hosts 2>&1; ls -lL /etc/resolv.conf /etc/gai.conf /etc/host.conf 2>&1
    echo "== services"; systemctl is-active NetworkManager systemd-resolved avahi-daemon 2>&1
    echo "== resolv.conf"; grep -v '^#' /etc/resolv.conf 2>&1
    echo "== getent as alpm (no sandbox)"; SECONDS=0; timeout 30 runuser -u alpm -- getent ahosts "$HOST"; echo "exit $? after ${SECONDS}s"
} >>"$REPORT" 2>&1

# try FLAG: refresh the package lists into $work; 0 when every name resolved
# (and pacman did not hang).
try() {
    local flag="$1" db="$work/db${1:-full}" log rc
    mkdir -p "$db"; chmod 755 "$db"
    log="$work/log${flag:-full}"
    SECONDS=0
    # shellcheck disable=SC2086  # an empty flag is no argument
    timeout 300 $PACMAN -Sy --dbpath "$db" --logfile /dev/null --debug $flag >"$log" 2>&1
    rc=$?
    {
        echo "== refresh ${flag:-(sandbox in full)}: exit $rc after ${SECONDS}s"
        grep -E "Landlock|seccomp|error:|$RESOLVE" "$log" | head -n 20
    } >>"$REPORT"
    ! grep -Eq "$RESOLVE" "$log" && [[ $rc -ne 124 ]]
}

if grep -qxF "$MARK" "$CONF"; then
    say "$CONF already has the hotfix line ($(grep -xF -A1 "$MARK" "$CONF" | tail -n 1)); delete it to test again."
    say "Report: $REPORT"
    exit 0
fi
choice=""
if try ""; then
    say "pacman's download sandbox resolves names here: nothing to change."
    say "Report: $REPORT"
    exit 0
fi
for flag in --disable-sandbox-syscalls --disable-sandbox-filesystem --disable-sandbox; do
    if try "$flag"; then
        case "$flag" in
            --disable-sandbox-syscalls) choice=DisableSandboxSyscalls ;;
            --disable-sandbox-filesystem) choice=DisableSandboxFilesystem ;;
            --disable-sandbox) choice=DisableSandbox ;;
        esac
        break
    fi
done
if [[ -z "$choice" ]]; then
    say "pacman cannot resolve the mirrors even without its sandbox: this is the network, not the sandbox."
    say "Report: $REPORT"
    exit 1
fi
say "pacman resolves names with $choice (the smallest step that works)."
if $apply; then
    cp -a "$CONF" "$CONF.invictus-hotfix.bak"
    # After DownloadUser, inside [options].
    sed -i "/^DownloadUser[[:space:]]*=/a $MARK\n$choice" "$CONF"
    # pacman-conf prints DisableSandbox as its two parts.
    want="$choice"; [[ "$choice" == DisableSandbox ]] && want=DisableSandboxSyscalls
    if $PACMAN_CONF_CMD --config "$CONF" 2>/dev/null | grep -qx "$want"; then
        say "Added $choice to $CONF (backup: $CONF.invictus-hotfix.bak). Plain 'sudo pacman -Syu' works again."
    else
        cp -a "$CONF.invictus-hotfix.bak" "$CONF"
        say "Could not add $choice to $CONF; put it back as it was."; exit 1
    fi
else
    say "--check: $CONF not changed. Without --check this adds '$choice' to [options]."
fi
say "Report: $REPORT (send it to the team)"
