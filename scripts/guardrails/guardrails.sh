#!/usr/bin/bash
# ------------------------------------------------------------
# guardrails: switching and applying the guard rails (design-simple-mode.md
# 1.6, 6.1, 12.1, 12.3). Installed as /usr/lib/invictus/guardrails by
# invictus-guardrails. People and the assistant never call this directly:
# `invictus-sys guardrails ...` does, after polkit has said yes.
#
#   guardrails status                  key=value lines: rails, until, since,
#                                      by, full-access, ai, each net
#   guardrails apply [--check] [--boot]
#                                      make the four derived files match
#                                      /etc/invictus/guardrails (idempotent);
#                                      --check changes nothing and exits 1
#                                      if anything would change (SM24);
#                                      --boot is the boot service's run (a
#                                      timed Libertas that ended while the
#                                      computer was off ends here)
#   guardrails set custodia [--how H] [--by USER]
#   guardrails set libertas [--for 1h] [--by USER]
#   guardrails expire                  the timer's run: ends a timed
#                                      Libertas whose end has passed
#   guardrails signal                  tell a running Moneta panel to
#                                      restart with the profile now in place
#   guardrails hold-warning            the pacman hook's text (Custodia only)
#   guardrails uninstall               the package's pre_remove: take the
#                                      derived files and lines away
#
# One file decides: /etc/invictus/guardrails, custodia or libertas, written
# with a temp file and rename(2). The derived files (all rewritten by
# apply, never by hand):
#   1. /etc/sudoers.d/40-invictus-guardrails   sudo lecture (Custodia)
#   2. /etc/pacman.d/invictus-guardrails.conf  HoldPkg (Custodia; comment
#                                              only under Libertas)
#   3. /etc/claude-code/managed-settings.json  symlink to the fixed or the
#                                              full profile (12.3)
#   4. /etc/polkit-1/rules.d/40-invictus-custodia.rules  tier 1 (Custodia)
# apply also makes sure /etc/pacman.conf includes file 2 and /etc/pam.d/sudo
# runs pre-admin-snapshot (G2); both lines are added once and never moved.
#
# Exit: 0 done; 1 failed (nothing switched); 2 bad arguments; 4 another
# switch or apply is running.
# Env (tests): INVICTUS_SYS_ROOT (prefix for every path), INVICTUS_LIB,
#   INVICTUS_SNAPPER, INVICTUS_SYSTEMCTL, INVICTUS_SYSTEMD_RUN,
#   INVICTUS_PKCHECK, INVICTUS_VISUDO, ACTA_LOGGER, INVICTUS_NOW (epoch)
# Honoured only when run from a checkout; the installed copy (/usr/...)
# drops every INVICTUS_* and ACTA_* variable first.
# ------------------------------------------------------------
set -euo pipefail
umask 022

# The installed copy honours no test overrides at all, whoever runs it.
case "$(readlink -f -- "$0")" in
    /usr/*) export PATH=/usr/bin
            while read -r v; do unset "$v"; done < <(compgen -v | grep -E '^(INVICTUS_|ACTA_)' || true) ;;
esac

LIB="${INVICTUS_LIB:-/usr/lib/invictus}"
# shellcheck source=scripts/lib/guardrails-state.sh
. "$LIB/lib/guardrails-state.sh"
# shellcheck source=scripts/lib/acta.sh
. "$LIB/lib/acta.sh"
# shellcheck source=scripts/lib/sys-verbs.sh
. "$LIB/lib/sys-verbs.sh"

R="${INVICTUS_SYS_ROOT:-}"
SHARE="$R/usr/share/invictus/guardrails"
RAILS_FILE="$R/etc/invictus/guardrails"
UNTIL_FILE="$R/etc/invictus/guardrails-until"
ASSISTANT_FILE="$R/etc/invictus/assistant"
SUDOERS_DROPIN="$R/etc/sudoers.d/40-invictus-guardrails"
PACMAN_INCLUDE="$R/etc/pacman.d/invictus-guardrails.conf"
PACMAN_CONF="$R/etc/pacman.conf"
MANAGED_LINK="$R/etc/claude-code/managed-settings.json"
CUSTODIA_RULES="$R/etc/polkit-1/rules.d/40-invictus-custodia.rules"
PAM_SUDO="$R/etc/pam.d/sudo"
RUN="$R/run/invictus"
SUDO_TS="$R/run/sudo/ts"
# Link targets and lines written into files carry real paths, never $R.
PROFILE_DIR=/usr/share/invictus/guardrails/claude
LECTURE=/usr/share/invictus/guardrails/sudo-lecture
INCLUDE_LINE="Include = /etc/pacman.d/invictus-guardrails.conf"
PAM_LINE="auth       optional     pam_exec.so quiet type=auth /usr/lib/invictus/pre-admin-snapshot"
EXPIRY_UNIT=invictus-guardrails-expiry

read -ra SNAPPER <<< "${INVICTUS_SNAPPER:-snapper}"
SYSTEMCTL="${INVICTUS_SYSTEMCTL:-systemctl}"
SYSTEMD_RUN="${INVICTUS_SYSTEMD_RUN:-systemd-run}"
PKCHECK="${INVICTUS_PKCHECK:-pkcheck}"
VISUDO="${INVICTUS_VISUDO:-visudo}"

say() { echo "guardrails: $*"; }
die() { echo "guardrails: $*" >&2; exit "${2:-1}"; }
now() { echo "${INVICTUS_NOW:-$(date +%s)}"; }
iso() { date -d "@$1" --iso-8601=seconds; }

# Who and where, for Acta: invictus-sys exports these for its children.
BY="${SYS_USER:-$(id -un 2>/dev/null || echo root)}"
ctx() { echo "SESSION=${SYS_SESSION:-}" "REQUEST=${SYS_REQUEST:-}" "UID=${SYS_UID:-$EUID}"; }

# write_atomic PATH MODE: stdin to PATH via a temp file in the same folder
# and rename(2), so no reader ever sees half a file.
write_atomic() {
    local dest="$1" mode="$2" tmp
    mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp "$(dirname "$dest")/.$(basename "$dest").XXXXXX")"
    cat > "$tmp"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$dest"
}

lock() {  # lock WAIT_SECONDS: one apply or switch at a time
    mkdir -p "$RUN"
    exec 9> "$RUN/guardrails.lock"
    if [[ "$1" == 0 ]]; then flock -n 9 || die "another guard-rails change is running; try again in a moment" 4
    else flock -w "$1" 9 || die "another guard-rails change is still running" 4; fi
}

# ---- what each derived file should be ------------------------------------------
want_sudoers() {
    printf '# Written by /usr/lib/invictus/guardrails apply (Custodia). Do not edit:\n'
    printf '# it is removed under Libertas and rewritten on every switch.\n'
    printf 'Defaults lecture=always, lecture_file=%s\n' "$LECTURE"
}
want_include() {
    printf '# Written by /usr/lib/invictus/guardrails apply. Included by /etc/pacman.conf.\n'
    if [[ "$1" == custodia ]]; then
        printf 'HoldPkg = %s\n' "$(protected_packages | paste -sd' ')"
    else
        printf '# Libertas: no extra holds.\n'
    fi
}
want_profile() {  # the managed-settings profile for rails $1 (12.3)
    if [[ "$1" == libertas && "$(gr_full_access)" == on ]]; then echo "$PROFILE_DIR/full.json"
    else echo "$PROFILE_DIR/fixed.json"; fi
}

# pacman.conf: the Include line right after [options], once.
pacman_conf_ok() { [[ ! -f "$PACMAN_CONF" ]] || grep -qxF "$INCLUDE_LINE" "$PACMAN_CONF"; }
fix_pacman_conf() {
    [[ -f "$PACMAN_CONF" ]] || return 0
    awk -v line="$INCLUDE_LINE" '{ print } /^\[options\][[:space:]]*$/ && !done { print line; done = 1 }' "$PACMAN_CONF" \
        | write_atomic "$PACMAN_CONF" 644
    grep -qxF "$INCLUDE_LINE" "$PACMAN_CONF" || die "could not add the Include line to $PACMAN_CONF (no [options] section?)"
}
# /etc/pam.d/sudo: pre-admin-snapshot after the last auth line, once.
pam_ok() { [[ ! -f "$PAM_SUDO" ]] || grep -qF "/usr/lib/invictus/pre-admin-snapshot" "$PAM_SUDO"; }
fix_pam() {
    [[ -f "$PAM_SUDO" ]] || return 0
    awk -v line="$PAM_LINE" '
        { l[NR] = $0 } $1 == "auth" { last = NR }
        END { for (i = 1; i <= NR; i++) { print l[i]; if (i == last) print line } if (!last) print line }' "$PAM_SUDO" \
        | write_atomic "$PAM_SUDO" 644
}

# ---- apply ------------------------------------------------------------------------------
# apply_files CHECK: make the derived files match the rails (CHECK=1: only
# report). Prints one line per difference; returns 1 in check mode if any.
apply_files() {
    local check="$1" rails drift=0 want cur
    rails="$(gr_rails)"
    note() { if [[ "$check" == 1 ]]; then echo "would change: $*"; else say "$*"; fi; drift=1; }

    if [[ ! -f "$RAILS_FILE" ]]; then
        note "$RAILS_FILE is missing: custodia"
        [[ "$check" == 1 ]] || echo custodia | write_atomic "$RAILS_FILE" 644
    fi
    if [[ "$rails" == custodia ]]; then
        if [[ -e "$UNTIL_FILE" ]]; then note "remove $UNTIL_FILE (Custodia)"; [[ "$check" == 1 ]] || rm -f "$UNTIL_FILE"; fi
        if [[ "$(gr_full_access)" == on ]]; then
            note "assistant full-access off (Custodia)"
            if [[ "$check" != 1 ]]; then
                echo "full-access = off" | write_atomic "$ASSISTANT_FILE" 644
                # shellcheck disable=SC2046
                acta "assistant full access: on -> off, guard rails are Custodia" VERB=assistant-full-access ARGS=off RESULT=ok HOW=custodia $(ctx)
            fi
        fi
    fi

    # 1. sudoers drop-in
    if [[ "$rails" == custodia ]]; then
        want="$(want_sudoers)"; cur="$(cat "$SUDOERS_DROPIN" 2>/dev/null || true)"
        if [[ "$want" != "$cur" || "$(stat -c %a "$SUDOERS_DROPIN" 2>/dev/null)" != 440 ]]; then
            note "write $SUDOERS_DROPIN (sudo lecture)"
            if [[ "$check" != 1 ]]; then
                local tmp
                mkdir -p "$(dirname "$SUDOERS_DROPIN")"
                tmp="$(mktemp "$(dirname "$SUDOERS_DROPIN")/.40-invictus-guardrails.XXXXXX")"
                printf '%s\n' "$want" > "$tmp"; chmod 440 "$tmp"
                if command -v "$VISUDO" >/dev/null && ! "$VISUDO" -cqf "$tmp" >/dev/null 2>&1; then
                    rm -f "$tmp"; die "the sudoers drop-in did not pass visudo; nothing written"
                fi
                mv -f "$tmp" "$SUDOERS_DROPIN"
            fi
        fi
    elif [[ -e "$SUDOERS_DROPIN" ]]; then
        note "remove $SUDOERS_DROPIN"; [[ "$check" == 1 ]] || rm -f "$SUDOERS_DROPIN"
    fi

    # 2. pacman include (always exists: a missing Include target is an error)
    want="$(want_include "$rails")"; cur="$(cat "$PACMAN_INCLUDE" 2>/dev/null || true)"
    if [[ "$want" != "$cur" ]]; then
        note "write $PACMAN_INCLUDE ($rails)"; [[ "$check" == 1 ]] || printf '%s\n' "$want" | write_atomic "$PACMAN_INCLUDE" 644
    fi
    if ! pacman_conf_ok; then note "add the Include line to $PACMAN_CONF"; [[ "$check" == 1 ]] || fix_pacman_conf; fi

    # 3. managed-settings symlink, swapped with rename(2)
    want="$(want_profile "$rails")"; cur="$(readlink "$MANAGED_LINK" 2>/dev/null || true)"
    if [[ "$want" != "$cur" || ! -L "$MANAGED_LINK" ]]; then
        note "point $MANAGED_LINK at $want"
        if [[ "$check" != 1 ]]; then
            mkdir -p "$(dirname "$MANAGED_LINK")"
            ln -sfn "$want" "$MANAGED_LINK.new"
            mv -fT "$MANAGED_LINK.new" "$MANAGED_LINK"
        fi
    fi

    # 4. tier 1 polkit rule; polkitd re-reads rules.d on any change
    if [[ "$rails" == custodia ]]; then
        if ! cmp -s "$SHARE/40-invictus-custodia.rules" "$CUSTODIA_RULES"; then
            note "write $CUSTODIA_RULES (tier 1)"
            [[ "$check" == 1 ]] || write_atomic "$CUSTODIA_RULES" 644 < "$SHARE/40-invictus-custodia.rules"
        fi
    elif [[ -e "$CUSTODIA_RULES" ]]; then
        note "remove $CUSTODIA_RULES"; [[ "$check" == 1 ]] || rm -f "$CUSTODIA_RULES"
    fi

    # G2's PAM line (a net: the script itself reads the rails and nets)
    if ! pam_ok; then note "add pre-admin-snapshot to $PAM_SUDO"; [[ "$check" == 1 ]] || fix_pam; fi

    [[ "$check" == 1 && "$drift" == 1 ]] && return 1
    return 0
}

systemd_up() { [[ -d "$R/run/systemd/system" ]]; }

arm_timer() {  # arm_timer EPOCH: the transient root timer that ends a timed Libertas
    systemd_up || { say "systemd is not running here: the timer is armed at boot"; return 0; }
    "$SYSTEMCTL" stop "$EXPIRY_UNIT.timer" >/dev/null 2>&1 || true
    "$SYSTEMCTL" reset-failed "$EXPIRY_UNIT.service" >/dev/null 2>&1 || true
    "$SYSTEMD_RUN" --quiet --unit "$EXPIRY_UNIT" --on-calendar "$(date -u -d "@$1" '+%Y-%m-%d %H:%M:%S') UTC" \
        --timer-property=AccuracySec=1s /usr/lib/invictus/guardrails expire \
        || say "could not arm the expiry timer; invictus-sys and the boot check still end it"
}
disarm_timer() {
    systemd_up || return 0
    "$SYSTEMCTL" stop "$EXPIRY_UNIT.timer" >/dev/null 2>&1 || true
}

notice() {  # for invictus-session to show at the next chance (design 12.1)
    mkdir -p "$RUN"
    printf '%s\n' "$1" | write_atomic "$RUN/guardrails-notice" 644
}

# ---- the assistant -----------------------------------------------------------------------
# The Moneta panel (tribune, part 6) listens on
# /run/user/<uid>/invictus/tribune.sock; "restart-profile" makes it end the
# running agent (SIGTERM to its process group, SIGKILL after 5 s) and start
# it again under the profile now in place. No socket: nothing to tell.
signal_assistant() {
    local s sent=0
    for s in "$R"/run/user/*/invictus/tribune.sock; do
        [[ -S "$s" ]] || continue
        if timeout 3 python3 -c 'import socket,sys; c=socket.socket(socket.AF_UNIX); c.connect(sys.argv[1]); c.sendall(b"restart-profile\n")' "$s" 2>/dev/null; then
            sent=$((sent + 1))
        fi
    done
    if ((sent)); then say "told $sent Moneta panel(s) to restart with the new rules"; fi
}

# ---- switching ---------------------------------------------------------------------------
wait_for_update() {  # an update in progress finishes before the pacman include changes
    mkdir -p "$RUN"
    exec 8> "$RUN/update.lock"
    if ! flock -n 8; then
        say "Finishing an update first"
        flock -w 3600 8 || die "an update is still running; try again later"
    fi
}

to_custodia() {  # to_custodia HOW
    local how="$1" from was_full
    from="$(gr_rails)"
    was_full="$(gr_full_access)"
    wait_for_update
    # The until-file goes first: an until-file next to custodia is ignored.
    rm -f "$UNTIL_FILE"
    echo custodia | write_atomic "$RAILS_FILE" 644
    [[ "$was_full" == off ]] || echo "full-access = off" | write_atomic "$ASSISTANT_FILE" 644
    apply_files 0 >/dev/null
    disarm_timer
    # Cached admin credentials go, so the next admin action is snapshotted
    # first (G2 row): sudo's timestamps for everyone, polkit's temporary
    # authorizations for the session that asked.
    rm -f "$SUDO_TS"/* 2>/dev/null || true
    "$PKCHECK" --revoke-temp >/dev/null 2>&1 || true
    rm -f "$RUN/pre-admin-snapshot.stamp"
    signal_assistant
    notice "Guard rails are back on"
    local extra=""
    [[ "$was_full" == on ]] && extra=", Moneta's full access turned off"
    # shellcheck disable=SC2046
    acta "guard rails: $from -> custodia by $BY, $how$extra" VERB=guardrails-custodia ARGS="" RESULT=ok \
        FROM="$from" TO=custodia HOW="$how" FULL_ACCESS_WAS="$was_full" $(ctx)
    say "custodia"
}

to_libertas() {  # to_libertas SECONDS|""
    local secs="$1" from snap end
    from="$(gr_rails)"
    # The snapshot the switch cannot skip (TS11), taken by the verb itself
    # so it exists even if PAM is misconfigured.
    snap="$("${SNAPPER[@]}" -c root create --type single --print-number --cleanup-algorithm number \
            --userdata important=yes --description "Before: guard rails off" 2>/dev/null)" \
        || die "could not make the safety copy, so the guard rails stay on"
    [[ "$snap" =~ ^[0-9]+$ ]] || die "snapper gave no snapshot number, so the guard rails stay on"
    wait_for_update
    if [[ -n "$secs" ]]; then
        end=$(( $(now) + secs ))
        # Written before the guardrails file (12.1): a crash in between
        # leaves an until-file next to custodia, which everything ignores.
        printf 'until = %s\nsince = %s\nby = %s\n' "$(iso "$end")" "$(iso "$(now)")" "$BY" | write_atomic "$UNTIL_FILE" 644
    else
        rm -f "$UNTIL_FILE"
    fi
    echo libertas | write_atomic "$RAILS_FILE" 644
    apply_files 0 >/dev/null
    if [[ -n "$secs" ]]; then arm_timer "$end"; else disarm_timer; fi
    signal_assistant
    if [[ -n "$secs" ]]; then notice "Guard rails are off until $(date -d "@$end" +%H:%M)"
    else notice "Guard rails are off"; fi
    # shellcheck disable=SC2046
    acta "guard rails: $from -> libertas by $BY${secs:+, until $(iso "$end")}" VERB=guardrails-libertas \
        ARGS="${secs:+--for ${secs}s}" SNAPSHOT="$snap" RESULT=ok FROM="$from" TO=libertas HOW=password \
        UNTIL="${end:+$(iso "$end")}" $(ctx)
    say "libertas${secs:+ until $(iso "$end")} (safety copy $snap)"
    echo "snapshot=$snap"
}

# expire_if_due HOW: end a timed Libertas whose end has passed, or re-arm it.
expire_if_due() {
    local how="$1" u
    [[ "$(gr_rails)" == libertas ]] || return 0
    u="$(gr_until_epoch)"
    [[ -n "$u" ]] || return 0
    if (( $(now) >= u )); then to_custodia "$how"
    else arm_timer "$u"; fi
}

# ---- main ---------------------------------------------------------------------------------
cmd="${1:-}"; shift || true
case "$cmd" in
    status)
        echo "rails=$(gr_rails)"
        echo "effective=$(gr_effective_rails)"
        echo "until=$(kv_get "$UNTIL_FILE" until)"
        echo "since=$(kv_get "$UNTIL_FILE" since)"
        echo "by=$(kv_get "$UNTIL_FILE" by)"
        echo "full-access=$(gr_full_access)"
        echo "ai=$(gr_ai)"
        for n in $GR_NETS; do if gr_net_on "$n"; then echo "net.$n=on"; else echo "net.$n=off"; fi; done
        ;;
    apply)
        check=0 boot=0
        for a in "$@"; do
            case "$a" in --check) check=1 ;; --boot) boot=1 ;; *) die "apply: unknown option $a" 2 ;; esac
        done
        if [[ "$check" == 1 ]]; then
            apply_files 1 && echo "consistent: $(gr_rails)"
            exit $?
        fi
        [[ $EUID -eq 0 || -n "$R" ]] || die "apply needs root (it is run by the installer, the package and the boot service)"
        lock 30
        if [[ "$boot" == 1 ]]; then expire_if_due "expired while the computer was off, applied $(date -d "@$(now)" +%H:%M)"
        else expire_if_due expired; fi
        apply_files 0
        ;;
    set)
        [[ $EUID -eq 0 || -n "$R" ]] || die "set needs root: use invictus-sys guardrails set"
        to="${1:-}"; shift || true
        how=click secs=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --how) how="${2:-}"; [[ "$how" =~ ^[a-z][a-z0-9:,-]{0,60}$ ]] || die "bad --how" 2; shift 2 ;;
                --by) BY="${2:-}"; [[ "$BY" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "bad --by" 2; shift 2 ;;
                --for) secs="$(duration_seconds "${2:-}")" || die "--for takes 1m to 7d" 2; shift 2 ;;
                *) die "set: unknown option $1" 2 ;;
            esac
        done
        lock 0
        case "$to" in
            custodia) [[ -z "$secs" ]] || die "--for is for libertas" 2; to_custodia "$how" ;;
            libertas) to_libertas "$secs" ;;
            *) die "guard rails are custodia or libertas, not '$to'" 2 ;;
        esac
        ;;
    expire)
        [[ $EUID -eq 0 || -n "$R" ]] || die "expire needs root"
        lock 30
        expire_if_due expired
        ;;
    signal)
        signal_assistant
        ;;
    uninstall)
        # The package's pre_remove: nothing may point at files about to go.
        [[ $EUID -eq 0 || -n "$R" ]] || die "uninstall needs root"
        rm -f "$SUDOERS_DROPIN" "$CUSTODIA_RULES"
        [[ "$(readlink "$MANAGED_LINK" 2>/dev/null)" == "$PROFILE_DIR"/* ]] && rm -f "$MANAGED_LINK"
        if [[ -f "$PACMAN_CONF" ]] && grep -qxF "$INCLUDE_LINE" "$PACMAN_CONF"; then
            grep -vxF "$INCLUDE_LINE" "$PACMAN_CONF" | write_atomic "$PACMAN_CONF" 644
        fi
        if [[ -f "$PAM_SUDO" ]] && grep -qxF "$PAM_LINE" "$PAM_SUDO"; then
            grep -vxF "$PAM_LINE" "$PAM_SUDO" | write_atomic "$PAM_SUDO" 644
        fi
        say "derived files removed"
        ;;
    hold-warning)
        # PreTransaction hook on removing a held package (G4). Custodia only;
        # prints and lets pacman's own question decide, so it always exits 0.
        if [[ "$(gr_effective_rails)" == custodia ]]; then
            held="$(paste -sd' ' || true)"
            echo "You are about to remove part of what keeps this computer working: ${held:-a held package}."
            echo "If someone on the phone or a website told you to do this, stop and use Ask Support in Help."
        fi
        exit 0
        ;;
    *)
        die "usage: guardrails status | apply [--check] [--boot] | set custodia|libertas [--for D] | expire | signal | hold-warning | uninstall" 2
        ;;
esac
