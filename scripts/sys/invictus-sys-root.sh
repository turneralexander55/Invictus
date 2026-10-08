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
#   invictus-sys ai-on                   AI on: /etc/invictus/ai, the AI set
#   invictus-sys ai-off                  No AI: everyone signed out, the AI set gone
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
# One locale for every child (pacman, snapper): the caller's LC_* never
# reach root's tools (Janus, 2026-10-01).
export LC_ALL=C

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
# shellcheck source=scripts/lib/ai-set.sh
. "$LIB/lib/ai-set.sh"

R="${INVICTUS_SYS_ROOT:-}"
PROC="${INVICTUS_PROC:-/proc}"
PACMAN="${INVICTUS_PACMAN:-pacman}"
read -ra SNAPPER <<< "${INVICTUS_SNAPPER:-snapper}"
SYSTEMCTL="${INVICTUS_SYSTEMCTL:-systemctl}"
JOURNALCTL="${INVICTUS_JOURNALCTL:-journalctl}"
UPDATE="${INVICTUS_UPDATE:-/usr/bin/invictus-update}"
GUARDRAILS="${INVICTUS_GUARDRAILS:-/usr/lib/invictus/guardrails}"
RESTORE="${INVICTUS_RESTORE:-limine-snapper-restore}"
AI_SIGNOUT="${INVICTUS_AI_SIGNOUT:-/usr/lib/invictus/ai-signout}"
CLAUDE_CMD="${INVICTUS_CLAUDE:-claude}"
# The people whose homes ai-off signs out: name:uid:gid:home lines. From
# the passwd database (UID_MIN to UID_MAX of login.defs); tests give a file.
PEOPLE="${INVICTUS_PEOPLE:-}"
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

# ---- AI on and off (design-no-ai.md N1, N3, N4.3, N7) ---------------------------------------
AI_FILE="$ETC/ai"
AI_PENDING="$R/var/lib/invictus/ai-install-pending"
AI_OFF_PENDING="$R/var/lib/invictus/ai-off-pending"
BROWSER_POLICY="$R/etc/firefox/policies/policies.json"
OUR_POLICY='{"policies": {"GenerativeAI": {"Enabled": false, "Locked": true}}}'

# shellcheck disable=SC2329 # these run inside ai_turn_on and ai_turn_off, through with_pair
write_ai() {  # on | off, root 0644, rename
    echo "$1" > "$AI_FILE.new"; chmod 644 "$AI_FILE.new"; mv -f "$AI_FILE.new" "$AI_FILE"
}
# The browser policy (N7): ours holds exactly one block. A policies.json
# that is not ours is never overwritten or removed; ai-off says so.
# shellcheck disable=SC2329
browser_policy_ours() { [[ -f "$BROWSER_POLICY" && ! -L "$BROWSER_POLICY" && "$(cat "$BROWSER_POLICY")" == "$OUR_POLICY" ]]; }
# shellcheck disable=SC2329
write_browser_policy() {
    if [[ -e "$BROWSER_POLICY" || -L "$BROWSER_POLICY" ]] && ! browser_policy_ours; then
        say "kept $BROWSER_POLICY (not written by Invictus), so the browser's AI features are not locked off"
        return 0
    fi
    mkdir -p "$(dirname "$BROWSER_POLICY")"
    printf '%s\n' "$OUR_POLICY" > "$BROWSER_POLICY.new"; chmod 644 "$BROWSER_POLICY.new"; mv -f "$BROWSER_POLICY.new" "$BROWSER_POLICY"
}
# shellcheck disable=SC2329
people() {
    if [[ -n "$PEOPLE" ]]; then cat -- "$PEOPLE"; return; fi
    local lo hi
    lo="$(awk '$1 == "UID_MIN" { print $2 }' /etc/login.defs 2>/dev/null)"; hi="$(awk '$1 == "UID_MAX" { print $2 }' /etc/login.defs 2>/dev/null)"
    getent passwd | awk -F: -v lo="${lo:-1000}" -v hi="${hi:-60000}" '$3 >= lo && $3 <= hi { print $1 ":" $3 ":" $4 ":" $6 }'
}
# sign_out_everyone: N3 steps 2 and 3 in every home, each run as that
# person (ai-signout), never as root; the logout for the caller only.
# shellcheck disable=SC2329
sign_out_everyone() {
    local name uid gid home out
    local -a as args
    mkdir -p "$AI_OFF_PENDING"; chmod 755 "$AI_OFF_PENDING"
    while IFS=: read -r name uid gid home; do
        [[ "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ && "$home" == /* ]] || continue
        # Provider keys in the keyring: invictus-session clears them at
        # that person's next login.
        : > "$AI_OFF_PENDING/$uid"; chmod 644 "$AI_OFF_PENDING/$uid"
        # A home that is not its owner's own is left alone.
        [[ -d "$home" && "$(stat -c %u -- "$home")" == "$uid" ]] || { say "skipped $name: $home is not theirs"; continue; }
        if [[ "$uid" == "$EUID" ]]; then as=()
        elif [[ $EUID -eq 0 ]]; then as=(setpriv --reuid="$uid" --regid="$gid" --clear-groups)
        else say "skipped $name: not root (a test run)"; continue; fi
        args=(); [[ "$uid" == "$CALLER_UID" ]] && args=(--logout)
        # Janus N-L1: the person's run writes to a root-owned temp file, not
        # a pipe, so nothing they leave running (setsid) can keep root
        # waiting; timeout ends their process group at 30 s (KILL 5 s
        # later). No stdin: the caller's terminal is not theirs to read.
        # Root shows at most 4 KiB of it, without control characters.
        out="$(mktemp)"
        timeout -k 5 30 "${as[@]}" env -i HOME="$home" USER="$name" PATH=/usr/bin LC_ALL=C CLAUDE="$CLAUDE_CMD" \
            "$BASH" "$AI_SIGNOUT" "${args[@]}" </dev/null >"$out" 2>&1 || say "could not finish signing $name out"
        head -c 4096 -- "$out" | tr -d '\000-\010\013-\037\177-\237' | sed "s/^ai-signout:/  $name:/"
        rm -f -- "$out"
    done < <(people)
}
# shellcheck disable=SC2329 # called through with_pair
ai_turn_on() {  # returns 5 when the packages wait for a connection
    local rc=0
    local -a names
    write_ai on
    # The keyring markers ai off left belong to that No AI choice: with AI
    # on again, invictus-session must not clear anyone's keys (Minerva G1).
    rm -f -- "$AI_OFF_PENDING"/*
    if browser_policy_ours; then rm -f "$BROWSER_POLICY"; fi
    read -ra names <<< "$AI_ON_INSTALL"
    pacman_install_classified "${names[@]}" || rc=$?
    if ((rc == 0)); then
        rm -f "$AI_PENDING"; "$SYSTEMCTL" disable invictus-ai-pending.service >/dev/null 2>&1 || true
        return 0
    fi
    # Only a download failure waits for the connection (Janus N-L2): a
    # conflict or a bad signature would fail the same way at every boot.
    if [[ "$PACMAN_FAILURE" != download ]]; then
        say "AI is on, but its programs could not be installed (pacman stopped, exit $rc). Update first, then turn AI on again."
        return 1
    fi
    mkdir -p "$(dirname "$AI_PENDING")"
    printf 'by = %s\nat = %s\n' "$CALLER" "$(date --iso-8601=seconds)" > "$AI_PENDING"
    "$SYSTEMCTL" enable --now --no-block invictus-ai-pending.service >/dev/null 2>&1 || true
    say "AI is on. Its programs could not be downloaded now (no connection?); they install when the internet is back."
    return 5
}
# shellcheck disable=SC2329 # called through with_pair
ai_turn_off() {
    local rc=0 have
    # The setting first: whatever fails below, every reader sees No AI.
    write_ai off
    rm -f "$AI_PENDING"; "$SYSTEMCTL" disable --now invictus-ai-pending.service >/dev/null 2>&1 || true
    # N4.3: full access goes with it, the profile follows, Moneta stops (N3 step 1).
    echo "full-access = off" > "$ETC/assistant.new"; chmod 644 "$ETC/assistant.new"; mv -f "$ETC/assistant.new" "$ETC/assistant"
    if [[ -x "$GUARDRAILS" ]]; then
        "$GUARDRAILS" apply >/dev/null || say "guardrails apply failed; run invictus-sys guardrails check"
        "$GUARDRAILS" signal stop || true
    fi
    write_browser_policy
    sign_out_everyone
    # N3 step 4: the AI set, whichever of it is installed.
    # shellcheck disable=SC2086 # AI_PKGS is a word list
    have="$("$PACMAN" -Qq -- $AI_PKGS 2>/dev/null || true)"
    if [[ -n "$have" ]]; then
        local -a rm_list
        mapfile -t rm_list <<< "$have"
        "${INHIBIT[@]}" "$PACMAN" -Rs --noconfirm -- "${rm_list[@]}" || { rc=$?; say "could not remove ${rm_list[*]} (another package needs them?)"; }
    fi
    return "$rc"
}

# ---- verbs -----------------------------------------------------------------------------------
rc=0
case "$VERB" in
    update)
        # The one update path (design 1.4): pacman -Syu, then the doctor's
        # system checks. Without invictus-tools (a headless machine), the
        # same -Syu alone. Tier 1 under Custodia (no password), so root
        # never reads anything in the caller's home folder (H1): none is
        # passed, and --system skips the per-user checks, which the user
        # half runs afterwards as the caller.
        if [[ -x "$UPDATE" ]]; then
            with_pacman "${INHIBIT[@]}" "$UPDATE" --noconfirm --system || rc=$?
        else
            ssh_mask_overwrite
            with_pacman "${INHIBIT[@]}" "$PACMAN" -Syu --noconfirm "${PACMAN_OVERWRITE[@]}" || rc=$?
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
            *) refuse "set-config cannot change $key" ;;
        esac
        done_rc ;;

    assistant-full-access)
        val="$1"
        [[ "$RAILS" == libertas ]] || refuse "Moneta's full access is off while the guard rails are Custodia"
        [[ "$val" == off || "$(gr_ai)" == on ]] || refuse "there is no AI on this computer (No AI)"
        mkdir -p "$ETC"
        with_pair write_full_access "$val" || rc=$?
        done_rc ;;

    ai-on)
        mkdir -p "$ETC"
        with_pair ai_turn_on || rc=$?
        case "$rc" in 0) finish ok 0 ;; 5) finish pending 0 ;; *) finish failed 1 ;; esac ;;

    ai-off)
        mkdir -p "$ETC"
        with_pair ai_turn_off || rc=$?
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
