#!/usr/bin/bash
# ------------------------------------------------------------
# The root half of invictus-sys, the only door to root (design 4.1, MUSTs
# A2, A4, A5, A11). Installed as /usr/lib/invictus/invictus-sys, root-owned
# 0755, by invictus-sys. Never run by hand: /usr/bin/invictus-sys runs it
# through pkexec, and pkexec picks the polkit action
# org.invictus.sys.<ROOT VERB> from argv[1] (policy annotation
# org.freedesktop.policykit.exec.argv1), so each verb has its own action and
# its own prompt with the exact arguments.
#
#   invictus-sys update
#   invictus-sys install PKG...          from the repos in pacman.conf only
#   invictus-sys remove PKG...           never the protected packages
#   invictus-sys snapshot DESCRIPTION
#   invictus-sys rollback ID
#   invictus-sys service enable|disable|restart UNIT   (services.allow)
#   invictus-sys set-config KEY on|off   nets.<net>, flavor.lock
#   invictus-sys assistant-full-access on|off
#   invictus-sys report-collect
#   invictus-sys guardrails-libertas [--for DURATION]
#   invictus-sys guardrails-custodia
#
# Every call ends in one Acta entry (journal tag invictus-sys: verb, args,
# snapshot id, requesting session, request id, result) and one last line on
# stdout: "invictus-sys: RESULT snapshot=ID|none".
# Exit: 0 ok; 1 the change failed; 2 bad arguments; 3 refused (guard
# rails, protected package, no safety copy possible); 4 busy.
# ------------------------------------------------------------
set -euo pipefail
umask 022

REQUEST_ENV="${INVICTUS_REQUEST:-}"
# The installed copy honours no test overrides, whoever runs it.
INSTALLED=0
case "$(readlink -f -- "$0")" in
    /usr/*) INSTALLED=1
            export PATH=/usr/bin
            while read -r v; do unset "$v"; done < <(compgen -v | grep -E '^(INVICTUS_|ACTA_)' || true) ;;
esac

LIB="${INVICTUS_LIB:-/usr/lib/invictus}"
# shellcheck source=scripts/lib/pacman.sh
. "$LIB/lib/pacman.sh"
# shellcheck source=scripts/lib/sys-verbs.sh
. "$LIB/lib/sys-verbs.sh"
# shellcheck source=scripts/lib/guardrails-state.sh
. "$LIB/lib/guardrails-state.sh"
# shellcheck source=scripts/lib/acta.sh
. "$LIB/lib/acta.sh"

R="${INVICTUS_SYS_ROOT:-}"
PROC="${INVICTUS_PROC:-/proc}"
PACMAN="${INVICTUS_PACMAN:-pacman}"
read -ra SNAPPER <<< "${INVICTUS_SNAPPER:-snapper}"
SYSTEMCTL="${INVICTUS_SYSTEMCTL:-systemctl}"
JOURNALCTL="${INVICTUS_JOURNALCTL:-journalctl}"
UPDATE="${INVICTUS_UPDATE:-/usr/bin/invictus-update}"
GUARDRAILS="${INVICTUS_GUARDRAILS:-/usr/lib/invictus/guardrails}"
RESTORE="${INVICTUS_RESTORE:-limine-snapper-restore}"
if [[ -n "${INVICTUS_INHIBIT+x}" ]]; then read -ra INHIBIT <<< "$INVICTUS_INHIBIT"
else INHIBIT=(systemd-inhibit --what=shutdown:sleep --who="Invictus" --why="Changing software" --mode=block); fi
ETC="$R/etc/invictus"

say() { echo "invictus-sys: $*"; }

# ---- who asked ---------------------------------------------------------------------------
[[ $EUID -eq 0 || ( $INSTALLED == 0 && -n "$R" ) ]] || { say "needs root: use /usr/bin/invictus-sys"; exit 2; }
CALLER_UID="${PKEXEC_UID:-${INVICTUS_TEST_UID:-${SUDO_UID:-$EUID}}}"
[[ "$CALLER_UID" =~ ^[0-9]+$ ]] || CALLER_UID=$EUID
CALLER="$(getent passwd "$CALLER_UID" 2>/dev/null | cut -d: -f1)"
[[ -n "$CALLER" ]] || CALLER="uid$CALLER_UID"
# The process that ran pkexec is our parent (pkexec execs us in place):
# its logind session, and the request id it carries (the Moneta thread),
# both only labels for the record.
SESSION="$(sed -nE 's/.*session-([A-Za-z0-9]+)\.scope.*/\1/p' "$PROC/$PPID/cgroup" 2>/dev/null | head -1 || true)"
if [[ -n "${PKEXEC_UID:-}" ]]; then
    REQUEST="$( { tr '\0' '\n' < "$PROC/$PPID/environ"; } 2>/dev/null | sed -n 's/^INVICTUS_REQUEST=//p' | head -1 || true)"
else
    REQUEST="$REQUEST_ENV"
fi
[[ "$REQUEST" =~ ^[A-Za-z0-9._:-]{0,64}$ ]] || REQUEST="(not a valid id)"
export SYS_USER="$CALLER" SYS_UID="$CALLER_UID" SYS_SESSION="$SESSION" SYS_REQUEST="$REQUEST"

VERB="${1:-}"; shift || true
ARGS="$*"
SNAP=""

finish() {  # finish RESULT EXIT [MESSAGE]
    local result="$1" code="$2" msg="${3:-}"
    acta "${msg:-invictus-sys $VERB $ARGS: $result} (by $CALLER)" VERB="$VERB" ARGS="$ARGS" \
        SNAPSHOT="${SNAP:-none}" RESULT="$result" SESSION="$SESSION" REQUEST="$REQUEST" UID="$CALLER_UID" USER="$CALLER"
    echo "invictus-sys: $result snapshot=${SNAP:-none}"
    exit "$code"
}
refuse() { say "$1"; finish refused 3 "invictus-sys $VERB $ARGS refused: $1"; }
done_rc() { if ((rc == 0)); then finish ok 0; else finish failed 1; fi; }

sys_validate "$VERB" "$@" || finish "bad-arguments" 2

# A timed Libertas whose end has passed ends before any verb runs (12.1
# step 3), so a lost timer can never extend it.
if [[ "$(gr_rails)" == libertas && "$(gr_effective_rails)" == custodia && -x "$GUARDRAILS" ]]; then
    "$GUARDRAILS" expire || say "could not end the timed Libertas; continuing under Custodia rules"
fi
RAILS="$(gr_effective_rails)"

# ---- snapshots (MUST A5) -------------------------------------------------------------------
snap_create() {  # snap_create TYPE DESCRIPTION [PRE] [important]: prints the number
    local -a a=(-c root create --type "$1" --print-number --cleanup-algorithm number --description "$2")
    [[ "$1" == post ]] && a+=(--pre-number "$3")
    [[ "${4:-}" == important ]] && a+=(--userdata important=yes)
    local n
    n="$("${SNAPPER[@]}" "${a[@]}" 2>/dev/null)" && [[ "$n" =~ ^[0-9]+$ ]] && echo "$n"
}
snap_latest() {
    "${SNAPPER[@]}" --csvout -c root list --columns number 2>/dev/null | awk -F, 'NR > 1 && $1 ~ /^[0-9]+$/ { n = $1 } END { print n + 0 }'
}
snap_pre_after() {  # the first pre snapshot numbered above $1 (snap-pac's)
    "${SNAPPER[@]}" --csvout -c root list --columns number,type 2>/dev/null \
        | awk -F, -v n="$1" 'NR > 1 && $1 + 0 > n && $2 == "pre" { print $1; exit }'
}
snap_exists() {
    "${SNAPPER[@]}" --csvout -c root list --columns number 2>/dev/null | awk -F, -v n="$1" 'NR > 1 && $1 == n { f = 1 } END { exit !f }'
}
has_snap_pac() { "$PACMAN" -Q snap-pac >/dev/null 2>&1; }
short_desc() { local d="invictus-sys $VERB $ARGS"; d="${d//[$'\001'-$'\037'$'\177']/ }"; printf '%s' "${d:0:200}"; }

# with_pair CMD...: a pre/post pair of our own around CMD (set-config,
# service, and pacman when snap-pac is missing). No pre, no change.
with_pair() {
    local pre rc=0
    pre="$(snap_create pre "$(short_desc)")" || refuse "no safety copy could be made, so nothing was changed"
    SNAP="$pre"
    "$@" || rc=$?
    snap_create post "$(short_desc)" "$pre" >/dev/null || say "the after-copy failed (the before-copy $pre exists)"
    return "$rc"
}
# with_pacman CMD...: snap-pac takes the pair inside pacman; we find its
# number. Without snap-pac we take our own.
with_pacman() {
    local before rc=0
    if ! has_snap_pac; then with_pair "$@"; return; fi
    before="$(snap_latest)"
    "$@" || rc=$?
    SNAP="$(snap_pre_after "$before")"
    return "$rc"
}

# ---- the files set-config and full access write (root 0644, rename) -------------------
# shellcheck disable=SC2329 # called through with_pair
write_nets() {  # write_nets NET VALUE: one "NET = VALUE" line, other nets kept
    { if [[ -r "$ETC/nets" ]]; then grep -vE "^[[:space:]]*${1}[[:space:]]*=" "$ETC/nets" || true; fi
      echo "$1 = $2"; } > "$ETC/nets.new"
    chmod 644 "$ETC/nets.new"; mv -f "$ETC/nets.new" "$ETC/nets"
}
# shellcheck disable=SC2329
write_flavor_lock() {  # on | off (design-simple-mode 1.5, M9)
    if [[ "$1" == on ]]; then
        printf 'locked by %s at %s\n' "$CALLER" "$(date --iso-8601=seconds)" > "$ETC/flavor.lock.new"
        chmod 644 "$ETC/flavor.lock.new"; mv -f "$ETC/flavor.lock.new" "$ETC/flavor.lock"
    else rm -f "$ETC/flavor.lock"; fi
}
# shellcheck disable=SC2329
write_full_access() {  # on | off, then the profile link and the panel (12.3)
    echo "full-access = $1" > "$ETC/assistant.new"; chmod 644 "$ETC/assistant.new"; mv -f "$ETC/assistant.new" "$ETC/assistant"
    "$GUARDRAILS" apply >/dev/null && "$GUARDRAILS" signal
}

# ---- verbs -----------------------------------------------------------------------------------
rc=0
case "$VERB" in
    update)
        # The one update path (design 1.4): pacman -Syu, then the doctor.
        # Without invictus-tools (a headless machine), the same -Syu alone.
        home="$(getent passwd "$CALLER_UID" 2>/dev/null | cut -d: -f6)"
        if [[ -x "$UPDATE" ]]; then
            with_pacman "${INHIBIT[@]}" env HOME="${home:-/root}" "$UPDATE" --noconfirm || rc=$?
        else
            with_pacman "${INHIBIT[@]}" "$PACMAN" -Syu --noconfirm || rc=$?
        fi
        case "$rc" in
            0) finish ok 0 ;;
            3) finish "ok, the doctor found a problem" 0 ;;
            *) finish failed 1 ;;
        esac ;;

    install)
        with_pacman pacman_install_needed "$@" || rc=$?
        done_rc ;;

    remove)
        # What pacman would take away, dependencies included: none of it may
        # be protected (the check before the prompt only saw the names).
        set +e; would="$("$PACMAN" -Rsp --print-format '%n' -- "$@" 2>&1)"; prc=$?; set -e
        ((prc == 0)) || { say "$would"; finish failed 1; }
        while read -r p; do
            [[ -n "$p" ]] || continue
            if protected_packages | grep -x -- "$p" >/dev/null; then refuse "removing that would take $p with it, which keeps this computer working"; fi
        done <<< "$would"
        with_pacman "${INHIBIT[@]}" "$PACMAN" -Rs --noconfirm -- "$@" || rc=$?
        done_rc ;;

    snapshot)
        d="${1//[$'\001'-$'\037'$'\177']/ }"
        SNAP="$(snap_create single "${d:0:200}" "" important)" || finish failed 1
        finish ok 0 ;;

    rollback)
        snap_exists "$1" || { say "there is no safety copy number $1"; finish failed 1; }
        if grep -qE "rootflags=.*subvol=[^ ]*/$1/snapshot( |$)" "$PROC/cmdline" 2>/dev/null; then
            # Booted into that copy: make it the system (limine-snapper-sync
            # keeps a copy of what it replaces).
            SNAP="$1"
            "$RESTORE" || finish failed 1
            say "Put back. Restart when you're ready."
            finish ok 0
        fi
        # Not booted into it: say so and leave the restart to the person
        # (no automatic restarts, ever; Alex 2026-09-30). The boot guard job
        # can read this file to pick the entry on the next start.
        mkdir -p "$R/var/lib/invictus"
        printf 'snapshot = %s\nby = %s\nat = %s\n' "$1" "$CALLER" "$(date --iso-8601=seconds)" > "$R/var/lib/invictus/rollback-pending"
        SNAP="$1"
        say "Restart, choose Snapshots in the boot menu, pick $1, then press Put back."
        finish pending 0 ;;

    service)
        act="$1" unit="$2"
        case "$act" in
            enable) set -- enable --now "$unit" ;;
            disable) set -- disable --now "$unit" ;;
            restart) set -- restart "$unit" ;;
        esac
        with_pair "$SYSTEMCTL" "$@" || rc=$?
        done_rc ;;

    set-config)
        key="$1" val="$2"
        case "$key" in
            nets.*)
                # Custodia keeps every net on; the switches are Libertas only (1.6).
                [[ "$RAILS" == libertas ]] || refuse "Custodia keeps the safety copies on"
                net="${key#nets.}"
                mkdir -p "$ETC"
                with_pair write_nets "$net" "$val" || rc=$? ;;
            flavor.lock)
                mkdir -p "$ETC"
                with_pair write_flavor_lock "$val" || rc=$? ;;
        esac
        done_rc ;;

    assistant-full-access)
        val="$1"
        [[ "$RAILS" == libertas ]] || refuse "Moneta's full access is off while the guard rails are Custodia"
        [[ "$val" == off || "$(gr_ai)" == on ]] || refuse "there is no AI on this computer (No AI)"
        mkdir -p "$ETC"
        with_pair write_full_access "$val" || rc=$?
        done_rc ;;

    report-collect)
        # The collectors that need root (design 4.5), by allowlist: the
        # boot's errors from the journal. Written only under
        # /var/lib/invictus/report (SM22), readable by wheel, last 5 kept.
        dir="$R/var/lib/invictus/report"
        mkdir -p "$dir"; chmod 750 "$dir"; chgrp wheel "$dir" 2>/dev/null || true
        out="$dir/journal-errors-$(date +%Y%m%d-%H%M%S.%N).txt"
        "$JOURNALCTL" -b -p err --no-pager -n 500 > "$out" 2>&1 || true
        chmod 640 "$out"; chgrp wheel "$out" 2>/dev/null || true
        find "$dir" -maxdepth 1 -name 'journal-errors-*.txt' -printf '%T@ %p\n' | sort -rn | tail -n +6 | cut -d' ' -f2- \
            | while read -r old; do rm -f -- "$old"; done
        say "collected: $out"
        finish ok 0 ;;

    guardrails-libertas|guardrails-custodia)
        [[ -x "$GUARDRAILS" ]] || refuse "invictus-guardrails is not installed"
        # The guardrails tool writes the Acta line for the switch itself (it
        # also runs from the timer and at boot); ours records the call.
        set +e
        if [[ "$VERB" == guardrails-libertas ]]; then out="$("$GUARDRAILS" set libertas "$@" --by "$CALLER" 2>&1)"
        else out="$("$GUARDRAILS" set custodia --how click --by "$CALLER" 2>&1)"; fi
        rc=$?
        set -e
        printf '%s\n' "$out" | grep -v '^snapshot=' || true
        SNAP="$(sed -n 's/^snapshot=//p' <<< "$out")"
        case "$rc" in 0) finish ok 0 ;; 4) finish busy 4 ;; *) finish failed 1 ;; esac ;;
esac
finish failed 1
