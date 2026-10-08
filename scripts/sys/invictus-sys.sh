#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-sys: the only door to root (design 4.1). Installed as
# /usr/bin/invictus-sys by invictus-sys. Runs as you; every system change
# goes through pkexec to /usr/lib/invictus/invictus-sys, with one polkit
# action per verb, so the password prompt names the exact change.
# Reference for the Cicero panel and other callers: docs/invictus-sys.md.
#
#   invictus-sys [--request ID] VERB [ARGS]
#
#   update                         update everything (pacman -Syu and the doctor's
#                                  system checks as root, then its checks on
#                                  your own files as you)
#   install PKG...                 install from the configured repos (with -Syu)
#   remove PKG...                  remove (never the packages that keep it working)
#   snapshot DESCRIPTION...        make a safety copy now
#   rollback ID                    put the system back to safety copy ID
#   service enable|disable|restart UNIT
#   set-config KEY on|off          nets.pre-admin-snapshot, nets.auto-update,
#                                  nets.boot-guard, nets.home-snapshots,
#                                  flavor.lock, assistant.full-access
#   ai on|off                      AI on this computer, or No AI (design-no-ai.md
#                                  N1, N3): on asks for your password every time;
#                                  off signs everyone out and removes the AI set
#   report-collect                 collect the logs a problem report needs root for
#   vm start|stop                  the Windows VM (runs as you; not set up yet)
#   guardrails status              key=value lines (no password)
#   guardrails check               would apply change anything? (exit 1 if so)
#   guardrails set custodia        guard rails on (instant from your own desktop)
#   guardrails set libertas [--for 1h]   guard rails off (password; --for ends it)
#   guardrails apply | expire      root only: installer, package, boot, timer
#   help                           this list
#
# --request ID labels the call in Acta (the Cicero thread that asked).
# Exit: 0 ok; 1 the change failed; 2 bad arguments; 3 refused; 4 busy;
# 126 the password prompt was cancelled; 127 not allowed, or pkexec failed.
# Env (tests): INVICTUS_LIB, INVICTUS_PKEXEC, INVICTUS_SYS_HELPER,
#   INVICTUS_GUARDRAILS, INVICTUS_SYS_ROOT, INVICTUS_DOCTOR
# ------------------------------------------------------------
set -euo pipefail

LIB="${INVICTUS_LIB:-/usr/lib/invictus}"
# shellcheck source=scripts/lib/pacman.sh
. "$LIB/lib/pacman.sh"
# shellcheck source=scripts/lib/sys-verbs.sh
. "$LIB/lib/sys-verbs.sh"
HELPER="${INVICTUS_SYS_HELPER:-/usr/lib/invictus/invictus-sys}"
PKEXEC="${INVICTUS_PKEXEC:-pkexec}"
GUARDRAILS="${INVICTUS_GUARDRAILS:-/usr/lib/invictus/guardrails}"
DOCTOR="${INVICTUS_DOCTOR:-invictus-doctor}"

usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; }

if [[ "${1:-}" == --request ]]; then
    [[ "${2:-}" =~ ^[A-Za-z0-9._:-]{1,64}$ ]] || { sys_err "--request takes an id of letters, digits and ._:-"; exit 2; }
    export INVICTUS_REQUEST="$2"; shift 2
fi
verb="${1:-help}"; shift || true

run_root() {  # run_root ROOTVERB ARGS...: check, then pkexec (or run, as root); sets rc
    sys_validate "$@" || exit 2
    rc=0
    # As root (the installer, a root terminal) no prompt is needed; tests
    # that set INVICTUS_PKEXEC go through the fake pkexec even as root.
    if [[ $EUID -eq 0 && -z "${INVICTUS_PKEXEC:-}" ]]; then "$HELPER" "$@" || rc=$?
    else "$PKEXEC" "$HELPER" "$@" || rc=$?; fi
    case "$rc" in
        126) sys_err "not done: no password was given, or this account may not do that" ;;
        127) sys_err "not done: this account is not allowed to do that, or pkexec could not run" ;;
    esac
}
as_root() { run_root "$@"; exit "$rc"; }

# update_user_half: after a good update, what root must not do (Janus H1):
# the doctor's checks on your own files, run as you, and your waybar's
# update counter. Exit 3 if the doctor finds a problem, as invictus-update.
update_user_half() {
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar-updates.cache"
    pkill -RTMIN+8 -u "$EUID" waybar 2>/dev/null || true
    command -v "$DOCTOR" >/dev/null || return 0
    echo "==> Checking your own settings after the update"
    "$DOCTOR" --post-update --user || { echo "==> Updated, but invictus-doctor found a problem in your settings (above)."; return 3; }
}

case "$verb" in
    help|-h|--help) usage ;;
    update)
        run_root update "$@"
        ((rc != 0)) || [[ $EUID -eq 0 ]] || update_user_half || rc=$?
        exit "$rc" ;;
    install|remove|rollback|service|report-collect)
        as_root "$verb" "$@" ;;
    snapshot)
        as_root snapshot "$*" ;;
    set-config)
        if [[ "${1:-}" == assistant.full-access ]]; then as_root assistant-full-access "${@:2}"
        else as_root set-config "$@"; fi ;;
    ai)
        # Two actions, two answers (N1): ai-on is a password every time,
        # ai-off is instant from your own desktop (it only removes).
        [[ $# -eq 1 && "$1" =~ ^(on|off)$ ]] || { sys_err "ai on|off"; exit 2; }
        as_root "ai-$1" ;;
    vm)
        # Listed here so there is one entry point (design 4.1); it needs no
        # root. The Windows module (0.4.0) fills it in.
        [[ "${1:-}" =~ ^(start|stop)$ && $# -eq 1 ]] || { sys_err "vm start|stop"; exit 2; }
        sys_err "the Windows VM is not set up on this computer yet"
        exit 3 ;;
    guardrails)
        sub="${1:-}"; shift || true
        case "$sub" in
            status) exec "$GUARDRAILS" status ;;
            check) exec "$GUARDRAILS" apply --check ;;
            set)
                case "${1:-}" in
                    custodia) (($# == 1)) || { sys_err "guardrails set custodia takes nothing else"; exit 2; }
                              as_root guardrails-custodia ;;
                    libertas) as_root guardrails-libertas "${@:2}" ;;
                    *) sys_err "guardrails set custodia|libertas"; exit 2 ;;
                esac ;;
            apply|expire)
                [[ $EUID -eq 0 ]] || { sys_err "guardrails $sub is run as root by the installer, the package and the boot service"; exit 2; }
                exec "$GUARDRAILS" "$sub" "$@" ;;
            *) sys_err "guardrails status|check|set custodia|set libertas [--for D]"; exit 2 ;;
        esac ;;
    *)
        sys_err "unknown verb '$verb' (invictus-sys help lists them)"
        exit 2 ;;
esac
