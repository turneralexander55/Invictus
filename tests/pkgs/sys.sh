# shellcheck shell=bash
# Groups 14 to 16 of tests/pkgs/run.sh (sourced; uses REPO, TMP, ALL, ok, bad):
# invictus-sys (design 4.1, MUSTs A2 to A5, A10, A11), its polkit policy,
# and ai on|off (design-no-ai.md).
# shellcheck disable=SC2153,SC2015 # REPO, TMP and ALL come from run.sh; ok || bad on purpose
#
# What is faked, at the seam (the container has no polkitd, no snapper and
# no root): pkexec (resolves the action from the real .policy file the way
# pkexec's find_action_for_path does, records it and the expanded message,
# then runs the helper), snapper (a counter and a list), pacman, systemctl,
# systemd-run, pkcheck, journalctl, logger (Acta entries to a file) and
# limine-snapper-restore. polkitd's answers come from node
# (tests/pkgs/polkit-rules.js), with its order and defaults.
# Everything the scripts write lands under a fake root (INVICTUS_SYS_ROOT).

# Run on its own, every helper this file needs is missing and each check
# would print "command not found" and still exit 0 (Janus, 2026-10-01).
if [[ "${BASH_SOURCE[0]}" == "$0" ]] || ! declare -F ok bad >/dev/null || [[ -z "${REPO:-}" || -z "${TMP:-}" ]]; then
    echo "tests/pkgs/sys.sh is groups 14 to 16 of tests/pkgs/run.sh: run that" >&2
    # shellcheck disable=SC2317 # exit is reached when run, not sourced
    return 2 2>/dev/null || exit 2
fi

# These groups check exit codes themselves: run them without errexit (a
# failing check must print FAIL, not end the suite) and restore it after.
set +e
echo "== invictus-sys"
SYS="$REPO/scripts/sys"
F="$TMP/sysfake"
mkdir -p "$F"

cat > "$F/snapper" <<'EOF'
#!/bin/bash
# fake snapper: create prints the next number; list prints csv
st="$FAKE_STATE"; echo "snapper $*" >> "$FAKE_LOG"
[[ "${FAKE_SNAPPER_FAIL:-0}" == 1 ]] && exit 1
[[ -n "${FAKE_SNAPPER_SLEEP:-}" ]] && exec sleep "$FAKE_SNAPPER_SLEEP"
csv=0; [[ "$1" == --csvout ]] && { csv=1; shift; }
[[ "$1" == -c ]] && shift 2
case "$1" in
  create)
    shift; type=single desc="" imp=""
    while [[ $# -gt 0 ]]; do case "$1" in
      --type) type="$2"; shift 2 ;; --description) desc="$2"; shift 2 ;;
      --userdata) imp="$2"; shift 2 ;; --pre-number|--cleanup-algorithm) shift 2 ;; *) shift ;; esac; done
    n=$(( $(cat "$st/snapnum" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/snapnum"
    printf '%s,%s,%s,%s\n' "$n" "$type" "$desc" "$imp" >> "$st/snaps"
    echo "$n" ;;
  list)
    echo "number,type"; awk -F, '{ print $1 "," $2 }' "$st/snaps" 2>/dev/null ;;
esac
EOF
cat > "$F/pacman" <<'EOF'
#!/bin/bash
echo "pacman $*" >> "$FAKE_LOG"
echo "pacman-env LC_ALL=${LC_ALL-unset}" >> "$FAKE_LOG"
case "$1" in
  -Q) [[ "$2" == snap-pac && "${FAKE_SNAP_PAC:-1}" == 1 ]]; exit ;;
  -Qq) shift; [[ "${1:-}" == -- ]] && shift; r=1
       for p in "$@"; do [[ " ${FAKE_INSTALLED:-} " == *" $p "* ]] && { echo "$p"; r=0; }; done; exit "$r" ;;
  -Rsp) shift 3; [[ "$1" == -- ]] && shift; printf '%s\n' "$@"; [[ -n "${FAKE_REMOVE_EXTRA:-}" ]] && echo "$FAKE_REMOVE_EXTRA"; exit 0 ;;
esac
# a transaction: snap-pac's pre/post pair
if [[ "${FAKE_SNAP_PAC:-1}" == 1 ]]; then
  "$FAKE_DIR/snapper" -c root create --type pre --print-number --description "pacman $*" >/dev/null
  "$FAKE_DIR/snapper" -c root create --type post --print-number --description "pacman $*" >/dev/null
fi
[[ -n "${FAKE_PACMAN_ERR:-}" ]] && echo "$FAKE_PACMAN_ERR" >&2
exit "${FAKE_PACMAN_RC:-0}"
EOF
cat > "$F/logger" <<'EOF'
#!/bin/bash
{ cat; echo "--"; } >> "$ACTA_LOG"
EOF
cat > "$F/rec" <<'EOF'
#!/bin/bash
# any other command: log it, exit FAKE_RC_<name> (default 0)
n="$(basename "$0")"; echo "$n $*" >> "$FAKE_LOG"
v="FAKE_RC_${n//-/_}"; exit "${!v:-0}"
EOF
cat > "$F/inhibit" <<'EOF'
#!/bin/bash
echo "inhibit" >> "$FAKE_LOG"; exec "$@"
EOF
cat > "$F/pkexec" <<'EOF'
#!/bin/bash
# fake pkexec: pick the action as pkexec does (exec.path, then exec.argv1),
# record it and the message with $(command_line) expanded, then run the
# helper with PKEXEC_UID. FAKE_DENY=1: the person cancels (exit 126).
helper="$1"; shift
path="$helper"; [[ "$helper" == "$INVICTUS_SYS_HELPER" ]] && path=/usr/lib/invictus/invictus-sys
read -r action msg < <(python3 - "$FAKE_POLICY" "$path" "${1:-}" "$path $*" <<'PY'
import sys, xml.etree.ElementTree as ET
pol, path, argv1, cmd = sys.argv[1:5]
for a in ET.parse(pol).getroot().iter("action"):
    ann = {x.get("key"): x.text for x in a.iter("annotate")}
    if ann.get("org.freedesktop.policykit.exec.path") != path: continue
    want = ann.get("org.freedesktop.policykit.exec.argv1")
    if want is not None and want != argv1: continue
    print(a.get("id"), a.find("message").text.replace("$(command_line)", cmd)); break
else:
    print("org.freedesktop.policykit.exec", "run " + cmd + " as the super user")
PY
)
echo "pkexec action=$action message=$msg" >> "$FAKE_LOG"
[[ "${FAKE_DENY:-0}" == 1 ]] && exit 126
PKEXEC_UID="$(id -u)" exec "$helper" "$@"
EOF
cat > "$F/claude" <<'EOF'
#!/bin/bash
echo "claude $* uid=$(id -u)" > "$HOME/claude-called"
EOF
chmod +x "$F"/*
for c in systemctl systemd-run pkcheck journalctl visudo update restore; do ln -sf rec "$F/$c"; done

# A fresh fake root: the data files the packages install, an Arch sudo PAM
# file and a pacman.conf.
new_root() {
    R="$TMP/sysroot-$1"; rm -rf "$R"; mkdir -p "$R/etc/invictus" "$R/etc/pam.d" "$R/run/sudo/ts" "$R/state"
    mkdir -p "$R/usr/share/invictus/sys"
    cp "$SYS/services.allow" "$SYS/protected-packages" "$R/usr/share/invictus/sys/"
    printf '#%%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\nsession\t\toptional\tpam_systemd.so class=none\n' > "$R/etc/pam.d/sudo"
    printf '[options]\nHoldPkg     = pacman glibc\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' > "$R/etc/pacman.conf"
    POL="$R/etc/firefox/policies/policies.json"
    : > "$TMP/sys.log"; : > "$TMP/acta.log"
}
# Environment for every script under test.
export_env() {
    export INVICTUS_SYS_ROOT="$R" INVICTUS_LIB="$REPO/scripts" FAKE_STATE="$R/state" FAKE_LOG="$TMP/sys.log" FAKE_DIR="$F" \
        ACTA_LOGGER="$F/logger" ACTA_LOG="$TMP/acta.log" FAKE_POLICY="$SYS/org.invictus.sys.policy" \
        INVICTUS_SNAPPER="$F/snapper" INVICTUS_PACMAN="$F/pacman" INVICTUS_SYSTEMCTL="$F/systemctl" \
        INVICTUS_SYSTEMD_RUN="$F/systemd-run" INVICTUS_PKCHECK="$F/pkcheck" INVICTUS_JOURNALCTL="$F/journalctl" \
        INVICTUS_VISUDO="$F/visudo" INVICTUS_UPDATE="$F/update" INVICTUS_RESTORE="$F/restore" INVICTUS_INHIBIT="$F/inhibit" \
        INVICTUS_PKEXEC="$F/pkexec" INVICTUS_SYS_HELPER="$SYS/invictus-sys-root.sh" \
        INVICTUS_PROC="$TMP/proc" INVICTUS_AI_SIGNOUT="$SYS/ai-signout.sh" INVICTUS_CLAUDE="$F/claude"
}
# isys ARGS: the user-facing command, as the person (not root: the fake
# pkexec runs the helper). Output in $TMP/sys.out, exit code in $rc.
isys() { rc=0; bash "$SYS/invictus-sys.sh" "$@" > "$TMP/sys.out" 2>&1 || rc=$?; }
acta_has() { grep -qx -- "$1" "$TMP/acta.log"; }
logged() { grep -q -- "$1" "$TMP/sys.log"; }
snaps() { cat "$R/state/snaps" 2>/dev/null; }
mkdir -p "$TMP/proc"


# ---- 14. verbs, policy, Acta ------------------------------------------------------------------
s_fail=0
sfail() { bad "$1"; s_fail=1; }

# A2: one polkit action per root verb, the helper path and argv1 on each,
# keep only where the design says.
. "$REPO/scripts/lib/pacman.sh"; . "$REPO/scripts/lib/sys-verbs.sh"
pol_check="$(python3 - "$SYS/org.invictus.sys.policy" "$SYS_ROOT_VERBS" <<'PY'
import sys, xml.etree.ElementTree as ET
pol, verbs = sys.argv[1], sys.argv[2].split()
nokeep = {"ai-on", "ai-off"}
seen = []
for a in ET.parse(pol).getroot().iter("action"):
    i = a.get("id"); v = i.removeprefix("org.invictus.sys."); seen.append(v)
    ann = {x.get("key"): x.text for x in a.iter("annotate")}
    d = a.find("defaults")
    if ann.get("org.freedesktop.policykit.exec.path") != "/usr/lib/invictus/invictus-sys": print("path", i)
    if ann.get("org.freedesktop.policykit.exec.argv1") != v: print("argv1", i)
    want = "auth_admin" if v in nokeep else "auth_admin_keep"
    if d.find("allow_active").text != want: print("active", i, d.find("allow_active").text)
    if d.find("allow_any").text != "auth_admin" or d.find("allow_inactive").text != "auth_admin": print("any/inactive", i)
    # L2 (Janus): no unchecked arguments in the fallback prompt.
    if "command_line" in a.find("message").text: print("message shows $(command_line), arguments not yet checked", i)
    if "org.freedesktop.policykit.exec.allow_gui" in ann: print("allow_gui", i)
if sorted(seen) != sorted(verbs): print("verbs", sorted(seen), sorted(verbs))
PY
)"
if [[ -z "$pol_check" ]]; then ok "A2/L2: one polkit action per verb (${SYS_ROOT_VERBS// /, }), helper path + argv1, keep only on the design's verbs, no unchecked arguments in the message"
else sfail "A2 policy: $pol_check"; fi

new_root verbs; export_env
# A2: anything that is not a verb never reaches pkexec or the helper.
isys "pacman -Syu; rm -rf /"
if [[ $rc == 2 ]] && ! logged pkexec; then ok "A2: invictus-sys \"pacman -Syu; rm -rf /\" is an unknown verb, refused before any prompt"
else sfail "A2 unknown verb: rc $rc, log $(paste -sd'|' "$TMP/sys.log")"; fi
rc=0; PKEXEC_UID=1000 bash "$SYS/invictus-sys-root.sh" 'pacman -Syu; rm -rf /' > "$TMP/sys.out" 2>&1 || rc=$?
if [[ $rc == 2 ]] && ! logged "pacman -S"; then ok "A2: the root half refuses an unknown verb too (exit 2, nothing run)"
else sfail "A2 root unknown verb: rc $rc"; fi
for evil in "-Syu" "--config=/tmp/x" "./evil.pkg.tar.zst" "https://example.org/x.pkg.tar.zst" "a b" "/tmp/x" "foo;rm"; do
    : > "$TMP/sys.log"; isys install "$evil"
    if [[ $rc != 2 ]] || logged pkexec; then sfail "A3: install accepted '$evil' (rc $rc)"; fi
done
[[ $s_fail == 0 ]] && ok "A3: install refuses options, paths, URLs and shell before the prompt (exit 2)"

# A2, A3, A4: install goes through its own action, names the packages, and
# is one pacman -Syu --needed, never -Sy alone.
: > "$TMP/sys.log"; INVICTUS_REQUEST=thread-42 isys --request thread-42 install firefox vlc
if [[ $rc == 0 ]] && grep -q 'pkexec action=org.invictus.sys.install message=Type your password to install software' "$TMP/sys.log" \
   && logged "pacman -Syu --needed --noconfirm -- firefox vlc" && logged inhibit; then
    ok "A2/A4: install prompts as org.invictus.sys.install, then one pacman -Syu --needed -- firefox vlc under an inhibitor"
else sfail "install: rc $rc: $(paste -sd'|' "$TMP/sys.log") out: $(paste -sd'|' "$TMP/sys.out")"; fi
# A5 + A11: snap-pac's pre snapshot is the one reported and logged.
pre="$(awk -F, '$2 == "pre" { print $1; exit }' "$R/state/snaps" 2>/dev/null)"
if [[ -n "$pre" ]] && grep -q "invictus-sys: ok snapshot=$pre" "$TMP/sys.out" && acta_has "INVICTUS_SNAPSHOT=$pre" \
   && acta_has "INVICTUS_VERB=install" && acta_has "INVICTUS_ARGS=firefox vlc" && acta_has "INVICTUS_RESULT=ok" \
   && acta_has "SYSLOG_IDENTIFIER=invictus-sys" && acta_has "INVICTUS_UID=$(id -u)"; then
    ok "A5/A11: the snap-pac pre snapshot ($pre) is returned and logged; Acta has verb, args, snapshot, uid, result"
else sfail "install Acta: out $(cat "$TMP/sys.out"); acta $(paste -sd'|' "$TMP/acta.log")"; fi
# Without snap-pac, invictus-sys takes the pair itself.
new_root nosnappac; export_env
FAKE_SNAP_PAC=0 isys install htop
if [[ $rc == 0 && "$(snaps | cut -d, -f2 | paste -sd' ')" == "pre post" ]] && grep -q 'snapshot=1' "$TMP/sys.out"; then
    ok "A5: without snap-pac, install makes its own pre/post pair and returns the pre"
else sfail "no snap-pac: $(snaps | paste -sd'|')"; fi

# A10: each verb is its own action.
new_root map; export_env
declare -A want_action=(
    ["update"]=update ["snapshot before the move"]=snapshot ["rollback 3"]=rollback
    ["service restart cups.service"]=service ["set-config flavor.lock on"]=set-config
    ["report-collect"]=report-collect
    ["remove vlc"]=remove ["ai on"]=ai-on ["ai off"]=ai-off)
for call in "${!want_action[@]}"; do
    : > "$TMP/sys.log"; read -ra words <<< "$call"; FAKE_DENY=1 isys "${words[@]}"
    grep -q "pkexec action=org.invictus.sys.${want_action[$call]} " "$TMP/sys.log" || sfail "A10: '$call' did not use org.invictus.sys.${want_action[$call]}: $(cat "$TMP/sys.log")"
    [[ $rc == 126 ]] || sfail "A10: a cancelled prompt for '$call' should exit 126 (got $rc)"
done
[[ $s_fail == 0 ]] && ok "A10: ${#want_action[@]} verbs, each through its own action id; a cancelled prompt runs nothing and exits 126"

# remove: protected names stop before the prompt; a dependency that would
# take a protected package stops in the root half.
new_root remove; export_env
: > "$TMP/sys.log"; isys remove invictus-desktop
if [[ $rc == 2 ]] && ! logged pkexec; then ok "SM9: remove invictus-desktop is refused before the prompt"
else sfail "remove protected: rc $rc"; fi
: > "$TMP/sys.log"; FAKE_REMOVE_EXTRA=invictus-desktop isys remove vlc
if [[ $rc == 3 ]] && ! logged "pacman -Rs --noconfirm" && acta_has "INVICTUS_RESULT=refused"; then
    ok "SM9: remove whose dependencies would take invictus-desktop is refused as root (exit 3, Acta 'refused')"
else sfail "remove via dependency: rc $rc: $(paste -sd'|' "$TMP/sys.log")"; fi
: > "$TMP/sys.log"; isys remove vlc
if [[ $rc == 0 ]] && logged "pacman -Rs --noconfirm -- vlc"; then ok "remove vlc: pacman -Rs --noconfirm -- vlc"
else sfail "remove vlc: rc $rc"; fi

# snapshot: trimmed description, important, numbered.
new_root snap; export_env
long="$(head -c 10000 /dev/zero | tr '\0' 'x')"
isys snapshot "$long"
d="$(snaps | tail -1 | cut -d, -f3)"
if [[ $rc == 0 && ${#d} -le 200 && "$(snaps | tail -1 | cut -d, -f4)" == important=yes ]]; then
    ok "SM22: snapshot with a 10 000-byte description is trimmed to ${#d} bytes, important (kept by NUMBER_LIMIT_IMPORTANT)"
else sfail "snapshot trim: rc $rc len ${#d}"; fi

# service: only the allowlist, and a pre/post pair around it.
new_root svc; export_env
: > "$TMP/sys.log"; isys service enable sshd.service
if [[ $rc != 2 ]] || logged pkexec; then sfail "service sshd.service accepted (rc $rc)"; fi
isys service restart cups.service
if [[ $rc == 0 ]] && logged "systemctl restart cups.service" && [[ "$(snaps | cut -d, -f2 | paste -sd' ')" == "pre post" ]] \
   && snaps | head -1 | grep -q 'invictus-sys service restart cups.service'; then
    ok "A5: service restart cups.service runs between a pre and a post snapshot named after the verb; sshd is not on the list"
else sfail "service: rc $rc: $(snaps | paste -sd'|')"; fi
for g in sshd.service snapper-timeline.timer invictus-auto-update.timer polkit.service; do
    list_has "$SYS/services.allow" "$g" && sfail "services.allow lists $g, which guards the machine"
done
# No safety copy, no change.
: > "$TMP/sys.log"; FAKE_SNAPPER_FAIL=1 isys service restart cups.service
if [[ $rc == 3 ]] && ! logged "systemctl restart"; then ok "A5: when no snapshot can be made, service is refused and nothing runs"
else sfail "service without snapshot: rc $rc"; fi

# rollback: unknown number fails; booted into it restores; otherwise pending.
new_root rb; export_env
isys snapshot "a copy"
: > "$TMP/sys.log"; isys rollback 9
[[ $rc == 1 ]] && ! logged restore || sfail "rollback to a missing snapshot: rc $rc"
echo "BOOT_IMAGE=/vmlinuz rootflags=subvol=/@" > "$TMP/proc/cmdline"
isys rollback 1
if [[ $rc == 0 ]] && grep -q 'snapshot = 1' "$R/var/lib/invictus/rollback-pending" && ! logged restore && grep -q 'invictus-sys: pending' "$TMP/sys.out"; then
    ok "rollback from the running system: writes rollback-pending and says how; no restart"
else sfail "rollback pending: rc $rc"; fi
echo "BOOT_IMAGE=/vmlinuz rootflags=subvol=/@snapshots/1/snapshot" > "$TMP/proc/cmdline"
: > "$TMP/sys.log"; isys rollback 1
if [[ $rc == 0 ]] && logged restore; then ok "rollback while booted into that copy: limine-snapper-restore"
else sfail "rollback restore: rc $rc"; fi
rm -f "$TMP/proc/cmdline"

# report-collect writes only under /var/lib/invictus/report, last 5 kept.
new_root rep; export_env; sleep 0.05; : > "$TMP/rep.mark"; sleep 0.05
for _ in 1 2 3 4 5 6 7; do isys report-collect; done
n="$(find "$R/var/lib/invictus/report" -name 'journal-errors-*' | wc -l)"
other="$(find "$R" -newer "$TMP/rep.mark" -type f ! -path "$R/var/lib/invictus/report/*" ! -path "$R/state/*" | wc -l)"
if [[ $rc == 0 && $n == 5 && $other == 0 ]] && logged "journalctl -b -p err --no-pager -n 500"; then
    ok "SM22: report-collect writes only under /var/lib/invictus/report and keeps the last 5"
else sfail "report-collect: rc $rc, $n files, $other other files"; fi

# Acta: the requesting session and request id come from the process that
# ran pkexec (its cgroup and environment).
mkdir -p "$TMP/proc/$$"
echo "0::/user.slice/user-1000.slice/session-7.scope" > "$TMP/proc/$$/cgroup"
printf 'HOME=/h\0INVICTUS_REQUEST=cicero-thread-9\0' > "$TMP/proc/$$/environ"
new_root acta; export_env
rc=0; PKEXEC_UID="$(id -u)" bash -c 'exec "$0" snapshot test' "$SYS/invictus-sys-root.sh" > "$TMP/sys.out" 2>&1 || rc=$?
if [[ $rc == 0 ]] && acta_has "INVICTUS_SESSION=7" && acta_has "INVICTUS_REQUEST=cicero-thread-9"; then
    ok "A11: Acta records the logind session (7) and request id of the process that ran pkexec"
else sfail "A11 session: rc $rc: $(paste -sd'|' "$TMP/acta.log")"; fi

# H1 (Janus): the update verb never
# hands root the caller's home: no HOME and no home lookup in its branch,
# and invictus-update runs the doctor's system checks only. The caller's
# own checks (their Hyprland config, their defaults) run afterwards in the
# user half, as the caller.
upd_branch="$(awk '/^    update\)/ { on = 1; next } on && /^    [a-z|-]+\)/ { exit } on' "$SYS/invictus-sys-root.sh")"
if [[ -n "$upd_branch" ]] && ! grep -qE 'HOME|getent passwd|CALLER_UID' <<< "$upd_branch"; then
    ok "H1-update-no-home: the root update branch passes no HOME and looks up no home"
else sfail "H1-update-no-home: the root update branch hands root the caller's home: $(grep -nE 'HOME|getent passwd|CALLER_UID' <<< "$upd_branch" | paste -sd'|')"; fi
cat > "$F/doctor" <<'EOF'
#!/bin/bash
echo "doctor $* uid=$(id -u)" >> "$FAKE_LOG"
exit "${FAKE_DOCTOR_RC:-0}"
EOF
chmod +x "$F/doctor"
new_root h1; export_env
mkdir -p "$TMP/h1home/.config/hypr"
: > "$TMP/sys.log"
HOME="$TMP/h1home" INVICTUS_UPDATE="$REPO/scripts/invictus-update.sh" INVICTUS_DOCTOR="$F/doctor" INVICTUS_SUDO="" INVICTUS_PARU=no-such-paru \
    isys update
docs="$(grep '^doctor ' "$TMP/sys.log" | sed 's/ uid=.*//' | paste -sd'|')"
want_docs="doctor --post-update --system|doctor --post-update --user"
[[ $EUID -eq 0 ]] && want_docs="doctor --post-update --system"   # root's own call: no person's files to check
if [[ $rc == 0 && "$docs" == "$want_docs" ]] && logged "pacman -Syu --noconfirm"; then
    ok "H1-doctor-split: update runs pacman -Syu and the doctor's system checks as root, then the per-user checks in the user half"
else sfail "H1-doctor-split: rc $rc, doctor calls '$docs': $(cat "$TMP/sys.out")"; fi
: > "$TMP/sys.log"
HOME="$TMP/h1home" INVICTUS_UPDATE="$REPO/scripts/invictus-update.sh" INVICTUS_DOCTOR="$F/doctor" INVICTUS_SUDO="" INVICTUS_PARU=no-such-paru \
    FAKE_DOCTOR_RC=1 isys update
want_rc=3; [[ $EUID -eq 0 ]] && want_rc=0   # as root only the system half runs; its result line says so
[[ $rc == "$want_rc" ]] && grep -q 'doctor found a problem' "$TMP/sys.out" && ok "H1: a doctor problem after a good update is reported (exit $want_rc here)" || sfail "H1 doctor failure: rc $rc $(cat "$TMP/sys.out")"

# LC_ALL=C in the root helper: the caller's locale never reaches pacman.
new_root locale; export_env
: > "$TMP/sys.log"; LC_ALL=C.UTF-8 isys install htop
[[ $rc == 0 ]] && logged "pacman-env LC_ALL=C$" && ! logged "pacman-env LC_ALL=C.UTF-8" \
    && ok "LC_ALL-C: the root helper runs pacman with LC_ALL=C whatever the caller's locale" || sfail "LC_ALL-C: $(grep pacman-env "$TMP/sys.log" | head -1)"

# This file refuses to run on its own (Janus: it used to exit 0 with
# "ok: command not found").
for f in sys.sh runtime.sh; do
    rc=0; bash "$REPO/tests/pkgs/$f" > "$TMP/alone.out" 2>&1 || rc=$?
    [[ $rc != 0 ]] && grep -q 'tests/pkgs/run.sh' "$TMP/alone.out" || sfail "sys-standalone: bash tests/pkgs/$f alone exits $rc: $(head -2 "$TMP/alone.out")"
done
[[ $s_fail == 0 ]] && ok "sys-standalone: tests/pkgs/sys.sh and runtime.sh refuse to run outside run.sh (exit 2)"

# L3 (Janus): pending-extras runs as root from a service and drops every
# INVICTUS_* override when installed, like the other root scripts.
px="$REPO/scripts/invictus-extras.sh"
grep -q "case \"\$(readlink -f -- \"\$0\")\" in" "$px" && grep -q 'export PATH=/usr/bin' "$px" && grep -q "grep -E '^(INVICTUS_|ACTA_)'" "$px" \
    && ok "L3-extras-guard: pending-extras drops INVICTUS_* overrides and sets PATH when installed" || sfail "L3-extras-guard: pending-extras has no /usr/* override guard"

# Every root script drops test overrides when installed (/usr/...).
for f in "$SYS/invictus-sys-root.sh" "$SYS/ai-pending.sh"; do
    grep -q "case \"\$(readlink -f -- \"\$0\")\" in" "$f" && grep -q 'export PATH=/usr/bin' "$f" \
        && head -1 "$f" | grep -qx '#!/usr/bin/bash' || sfail "$(basename "$f"): no override drop for the installed copy, or not #!/usr/bin/bash"
done
[[ $s_fail == 0 ]] && ok "the two root scripts start with #!/usr/bin/bash, set PATH and drop every INVICTUS_*/ACTA_* override when installed"

# Packages: the trees from group 4.
if [[ -x "$ALL/usr/bin/invictus-sys" && -x "$ALL/usr/lib/invictus/invictus-sys" && -f "$ALL/usr/share/polkit-1/actions/org.invictus.sys.policy" \
      && -f "$ALL/usr/lib/invictus/lib/acta.sh" && -f "$ALL/usr/lib/invictus/lib/ai-set.sh" \
      && -x "$ALL/usr/lib/invictus/ai-signout" && -x "$ALL/usr/lib/invictus/ai-pending" \
      && -f "$ALL/usr/lib/systemd/system/invictus-ai-pending.service" \
      && ! -e "$ALL/usr/lib/systemd/system/multi-user.target.wants/invictus-ai-pending.service" ]]; then
    ok "invictus-sys installs its files; the AI pending service is not enabled by the package"
else sfail "package trees incomplete"; fi
# The guard rails are gone (Alex, 2026-11-26): no package ships their files.
gr_left="$(find "$ALL" \( -name '*guardrails*' -o -name '*custodia*' -o -name 'pre-admin-snapshot' -o -name '40-invictus-hold.hook' -o -path '*/etc/claude-code*' \) -print 2>/dev/null | head -5)"
[[ -z "$gr_left" ]] && ok "no package installs a guard-rails file, a Claude Code managed setting or the hold hook" || sfail "guard-rails files still packaged: $gr_left"
# remount-fs (design.md build note 59): a snapshot boot runs from an overlay
# root, which refuses fstab's btrfs options on a remount, so invictus-sys
# skips systemd-remount-fs exactly when / is an overlay. ExecCondition: exit
# 0 runs the unit, 1 to 254 skips it (not failed), 255 is a failure.
ro="$ALL/usr/lib/systemd/system/systemd-remount-fs.service.d/invictus-snapshot-overlay.conf"
cond="$(sed -n 's/^ExecCondition=//p' "$ro" 2>/dev/null || true)"
run_cond() {  # run_cond COMMAND-LINE: the unit's command, word-split as systemd does for this line
    local c rc=0; c="$1"; eval "$c" >/dev/null 2>&1 || rc=$?; echo "$rc"
}
mkdir -p "$TMP/rfs"
cat > "$TMP/rfs/findmnt" <<'EOF'
#!/bin/bash
# findmnt for one mount table: / is $FAKE_ROOT_FS. Only the query the drop-in makes.
[[ "$*" == "--noheadings --mountpoint / --types overlay" ]] || { echo "findmnt: unexpected $*" >&2; exit 2; }
[[ "$FAKE_ROOT_FS" == overlay ]] && { echo "/ overlay overlay rw"; exit 0; }
exit 1
EOF
chmod 755 "$TMP/rfs/findmnt"
fake_cond="${cond//\/usr\/bin\/findmnt/$TMP/rfs/findmnt}"
host_fs="$(findmnt -n -o FSTYPE --mountpoint / 2>/dev/null || true)"
r_btrfs="$(FAKE_ROOT_FS=btrfs run_cond "$fake_cond")"; r_ov="$(FAKE_ROOT_FS=overlay run_cond "$fake_cond")"
r_host="$(run_cond "$cond")"; r_host_as="$(run_cond "${cond//--types overlay/--types $host_fs}")"
want_host=0; [[ "$host_fs" == overlay ]] && want_host=1
if [[ ! -f "$ro" ]] || [[ "$(grep -c '^ExecCondition=' "$ro")" != 1 ]] || ! grep -qx '\[Service\]' "$ro"; then
    sfail "remount-fs: invictus-sys has no drop-in with one ExecCondition for systemd-remount-fs.service"
elif grep -Eq '^(ExecStart|ExecStartPre|Condition|Assert)' "$ro"; then
    sfail "remount-fs: the drop-in changes more than the condition: $(grep -E '^(ExecStart|Condition|Assert)' "$ro")"
elif [[ "$cond" != /usr/bin/* || "$fake_cond" == "$cond" ]]; then
    sfail "remount-fs: the condition must call /usr/bin/findmnt by its absolute path: $cond"
elif [[ $r_btrfs != 0 ]]; then
    sfail "remount-fs: a btrfs root (a normal boot) skips systemd-remount-fs (condition exit $r_btrfs, want 0)"
elif ((r_ov < 1 || r_ov > 254)); then
    sfail "remount-fs: an overlay root (a snapshot boot) does not skip systemd-remount-fs (condition exit $r_ov, want 1 to 254)"
elif [[ -n "$host_fs" ]] && { [[ $r_host != "$want_host" ]] || [[ $r_host_as != 1 ]]; }; then
    sfail "remount-fs: with the real findmnt on this $host_fs root the condition exits $r_host (want $want_host), asked for $host_fs it exits $r_host_as (want 1)"
else
    ok "remount-fs: invictus-sys skips systemd-remount-fs when / is an overlay (snapshot boot, exit $r_ov) and runs it on a btrfs root (exit 0); the real findmnt agrees on this $host_fs root"
fi
# The same command on a real overlay root, where this user may build one.
if [[ $EUID == 0 && -n "$cond" ]] && unshare -m true 2>/dev/null; then
    cat > "$TMP/rfs/ovroot.sh" <<'EOF'
#!/bin/bash
# In a private mount namespace: / as an overlay over this machine's /, then the condition inside it.
w="$1"; shift
mount -t tmpfs rfs "$w" && mkdir -p "$w/u" "$w/w" "$w/m" \
    && mount -t overlay overlay -o "lowerdir=/,upperdir=$w/u,workdir=$w/w" "$w/m" \
    && mount -t proc proc "$w/m/proc" || exit 99
[[ "$(chroot "$w/m" /usr/bin/findmnt -n -o FSTYPE --mountpoint /)" == overlay ]] || exit 98
rc=0; chroot "$w/m" /usr/bin/sh -c "$1" || rc=$?
exit "$rc"
EOF
    mkdir -p "$TMP/rfs/ov"; c_inner="$(eval "set -- $cond"; echo "$3")"
    rc=0; unshare -m --propagation private bash "$TMP/rfs/ovroot.sh" "$TMP/rfs/ov" "$c_inner" || rc=$?
    if ((rc == 98 || rc == 99)); then echo "skip  remount-fs: no overlay root could be built here (exit $rc)"
    elif ((rc >= 1 && rc <= 254)); then ok "remount-fs: on a real overlay root the drop-in's command skips the unit (exit $rc)"
    else sfail "remount-fs: on a real overlay root the drop-in's command exits $rc (want 1 to 254)"; fi
else
    echo "skip  remount-fs: the real overlay root needs root and unshare (the fake findmnt checks above still ran)"
fi
pb_deps() { bash -c 'source "$1"; printf "%s\n" "${depends[@]}"' _ "$1"; }
pb_var() { bash -c 'source "$1"; printf "%s\n" "${!2}"' _ "$1" "$2[@]"; }
if pb_deps "$REPO/pkgs/meta/invictus-base/PKGBUILD" | grep -x invictus-sys >/dev/null \
   && ! grep -rqx --include=PKGBUILD "  *'invictus-guardrails'" "$REPO/pkgs" \
   && [[ "$(pb_var "$REPO/pkgs/own/invictus-sys/PKGBUILD" replaces)" == invictus-guardrails ]] \
   && ! pb_deps "$REPO/pkgs/own/invictus-sys/PKGBUILD" | grep -x invictus-tools >/dev/null \
   && pb_deps "$REPO/pkgs/own/invictus-tools/PKGBUILD" | grep -xE 'invictus-sys(>=[0-9.:-]+)?' >/dev/null; then
    ok "invictus-base and invictus-tools bring invictus-sys; nothing depends on invictus-guardrails, and invictus-sys replaces it"
else sfail "package depends"; fi
# sshd off on adopted installs too (Janus I-2, SM2): the generator mask is in
# invictus-sys, which every machine has (invictus-tools, so every desktop,
# depends on it; invictus-base is never installed by adopt.sh), and in no
# other package, so pacman never sees two owners.
gm=etc/systemd/system-generators/systemd-ssh-generator
owners=()
for t in "$TREES"/*/; do [[ -L "$t$gm" || -e "$t$gm" ]] && owners+=("$(basename "$t")"); done
if [[ -L "$TREES/invictus-sys/$gm" && "$(readlink "$TREES/invictus-sys/$gm")" == /dev/null && "${owners[*]}" == invictus-sys ]]; then
    ok "SM2: invictus-sys ships /$gm -> /dev/null, and no other package does"
else sfail "SM2: generator mask in invictus-sys: $(ls -l "$TREES/invictus-sys/$gm" 2>&1); packages shipping it: ${owners[*]:-none}"; fi
echo

# ---- 15. polkit rules (node) ------------------------------------------------------------------
echo "== polkit rules"
p_fail=0
pbad() { bad "$1"; p_fail=1; }
if ! command -v node >/dev/null; then
    bad "node is needed to run the polkit rules (CI's ubuntu runner has it)"
else
    RD="$TMP/rules"; rm -rf "$RD"; mkdir -p "$RD/usr" "$RD/etc"
    # polkit's Arch default (admin identity), so the order is real. No
    # Invictus rule file: every verb answers as its policy defaults say.
    printf 'polkit.addAdminRule(function(action, subject) { return ["unix-group:wheel"]; });\n' > "$RD/usr/50-default.rules"
    q() { node "$REPO/tests/pkgs/polkit-rules.js" "$SYS/org.invictus.sys.policy" "$RD/etc" "$RD/usr"; }
    queries() {
        local v
        for v in $SYS_ROOT_VERBS; do
            printf 'org.invictus.sys.%s 1 1 wheel\norg.invictus.sys.%s 1 0 wheel\norg.invictus.sys.%s 0 0 wheel\norg.invictus.sys.%s 1 1 users\n' "$v" "$v" "$v" "$v"
        done
        echo "org.freedesktop.policykit.exec 1 1 wheel"
    }
    while read -r id l a g res; do
        v="${id#org.invictus.sys.}"
        if [[ "$id" == org.freedesktop.policykit.exec ]]; then want=no-such-action
        elif [[ $l == 1 && $a == 1 ]]; then
            case "$v" in ai-on|ai-off) want=auth_admin ;; *) want=auth_admin_keep ;; esac
        else want=auth_admin; fi
        [[ "$res" == "$want" ]] || pbad "$id local=$l active=$a $g -> $res, want $want"
    done < <(paste -d' ' <(queries | cut -d' ' -f1-4) <(queries | q | cut -d' ' -f2))
    [[ $p_fail == 0 ]] && ok "every verb asks for a password (auth_admin_keep; no keep for AI on and off); nothing grants pkexec itself"
fi
echo

# ---- 16. set-config, ai on|off ----------------------------------------------------------------
echo "== ai on|off"
g_fail=0
gbad() { bad "$1"; g_fail=1; }

# set-config never writes the AI or helper files: ai has its own verb,
# with its own prompts.
new_root keys; export_env
for k in guardrails ai assistant helper.conf nets "nets.pre-admin-snapshot" "../etc/shadow" "assistant.full-access"; do
    : > "$TMP/sys.log"; isys set-config "$k" on
    if [[ $rc != 2 ]] || logged pkexec; then gbad "set-config $k was accepted (rc $rc)"; fi
    rc=0; bash "$SYS/invictus-sys-root.sh" set-config "$k" on > "$TMP/sys.out" 2>&1 || rc=$?
    [[ $rc == 2 ]] || gbad "the root half accepted set-config $k (rc $rc)"
done
[[ ! -e "$R/etc/invictus/ai" ]] || gbad "set-config changed a file it must not"
[[ $g_fail == 0 ]] && ok "set-config refuses the AI and helper files, the old guard-rails keys and any key off its list, in both halves"

# ---- ai on|off (design-no-ai.md N1, N3, N4.3, N7; NA1, NA2, NA5, NA6) ----

OURPOL='{"policies": {"GenerativeAI": {"Enabled": false, "Locked": true}}}'
# The user half: on or off, nothing else, before any prompt.
new_root aiargs; export_env
for a in "" "maybe" "on now" "--on"; do
    : > "$TMP/sys.log"; read -ra words <<< "$a"; isys ai "${words[@]}"
    if [[ $rc != 2 ]] || logged pkexec; then gbad "ai '$a' accepted (rc $rc)"; fi
done
[[ $g_fail == 0 ]] && ok "ai: only 'ai on' or 'ai off', refused before any prompt otherwise"

# NA6: ai on: the setting, our browser policy gone, the AI set
# installed in one -Syu --needed, a pre/post pair, Acta.
new_root aion; export_env
echo off > "$R/etc/invictus/ai"; mkdir -p "$(dirname "$POL")"; printf '%s\n' "$OURPOL" > "$POL"
: > "$TMP/sys.log"; isys ai on
if [[ $rc == 0 && "$(cat "$R/etc/invictus/ai")" == on && "$(stat -c %a "$R/etc/invictus/ai")" == 644 && ! -e "$POL" ]] \
   && grep -q 'pkexec action=org.invictus.sys.ai-on ' "$TMP/sys.log" \
   && logged "pacman -Syu --needed --noconfirm -- invictus-cicero" && logged inhibit \
   && [[ "$(snaps | head -1 | cut -d, -f2-3)" == "pre,invictus-sys ai-on " ]] \
   && acta_has "INVICTUS_VERB=ai-on" && acta_has "INVICTUS_RESULT=ok" && grep -q 'invictus-sys: ok snapshot=1' "$TMP/sys.out"; then
    ok "NA6: ai on (org.invictus.sys.ai-on): /etc/invictus/ai on (0644), our browser policy removed, invictus-cicero in one -Syu --needed, pre/post pair, Acta"
else gbad "ai on: rc $rc: $(paste -sd'|' "$TMP/sys.log") out: $(cat "$TMP/sys.out")"; fi
# Offline: the choice stands, the install waits for the connection. The
# error lines are pacman 7's own (e2e-sys.sh checks them in Arch).
NET_ERR='error: failed to synchronize all databases (failed to retrieve some files)'
GET_ERR='error: failed to commit transaction (failed to retrieve some files)'
new_root aioff1; export_env; echo off > "$R/etc/invictus/ai"
: > "$TMP/sys.log"; FAKE_PACMAN_RC=1 FAKE_PACMAN_ERR="$NET_ERR" isys ai on
if [[ $rc == 0 && "$(cat "$R/etc/invictus/ai")" == on && -f "$R/var/lib/invictus/ai-install-pending" ]] \
   && grep -q 'invictus-sys: pending' "$TMP/sys.out" && logged "systemctl enable --now --no-block invictus-ai-pending.service" && acta_has "INVICTUS_RESULT=pending"; then
    ok "N1: ai on with no connection: AI reads on, the pending marker is written and invictus-ai-pending.service enabled"
else gbad "ai on offline: rc $rc: $(cat "$TMP/sys.out")"; fi
# N-L2 (Janus): any other pacman failure is "failed", exit 1, no pending
# marker and no retry unit; AI stays on and the person is told to update.
new_root aiconf; export_env; echo off > "$R/etc/invictus/ai"
: > "$TMP/sys.log"; FAKE_PACMAN_RC=1 FAKE_PACMAN_ERR='error: failed to commit transaction (conflicting files)' isys ai on
if [[ $rc == 1 && "$(cat "$R/etc/invictus/ai")" == on && ! -e "$R/var/lib/invictus/ai-install-pending" ]] \
   && ! logged "invictus-ai-pending" && grep -q 'Update first, then turn AI on again' "$TMP/sys.out" \
   && grep -q 'invictus-sys: failed' "$TMP/sys.out" && acta_has "INVICTUS_RESULT=failed"; then
    ok "N-L2-not-a-download: ai on with a conflict is 'failed' (exit 1): no pending marker, no retry unit, 'update first'"
else gbad "N-L2-not-a-download: rc $rc: $(paste -sd'|' "$TMP/sys.log") out: $(cat "$TMP/sys.out")"; fi
: > "$TMP/sys.log"; FAKE_PACMAN_RC=1 FAKE_PACMAN_ERR="$GET_ERR" isys ai on
[[ $rc == 0 && -f "$R/var/lib/invictus/ai-install-pending" ]] && grep -q 'invictus-sys: pending' "$TMP/sys.out" \
    && ok "N-L2: a package download that fails mid-way also waits for the connection (pending)" || gbad "N-L2 retrieve failure: rc $rc: $(cat "$TMP/sys.out")"
grep -qx 'RestartPreventExitStatus=2' "$REPO/scripts/systemd/invictus-ai-pending.service" \
    && ok "N-L2: invictus-ai-pending.service stops retrying on exit 2" || gbad "N-L2: invictus-ai-pending.service has no RestartPreventExitStatus=2"
# ai-pending: installs only while the marker exists and AI still reads on.
PEND() { rc=0; bash "$SYS/ai-pending.sh" > "$TMP/pend.out" 2>&1 || rc=$?; }
: > "$TMP/sys.log"; FAKE_PACMAN_RC=1 FAKE_PACMAN_ERR="$NET_ERR" PEND
[[ $rc == 1 && -f "$R/var/lib/invictus/ai-install-pending" ]] || gbad "ai-pending: a failed download should keep the marker and fail (rc $rc)"
: > "$TMP/acta.log"; FAKE_PACMAN_RC=1 FAKE_PACMAN_ERR='error: failed to commit transaction (invalid or corrupted package (PGP signature))' PEND
[[ $rc == 2 && -f "$R/var/lib/invictus/ai-install-pending" ]] && acta_has "INVICTUS_RESULT=failed" \
    && ok "N-L2-pending-exit-2: ai-pending exits 2 (no retry) on a failure that is not a download, with an Acta entry" \
    || gbad "N-L2-pending-exit-2: ai-pending on a bad signature: rc $rc $(cat "$TMP/pend.out")"
: > "$TMP/sys.log"; PEND
if [[ $rc == 0 && ! -e "$R/var/lib/invictus/ai-install-pending" ]] && logged "pacman -Syu --needed --noconfirm -- invictus-cicero" \
   && logged "systemctl disable invictus-ai-pending.service" && acta_has "INVICTUS_ARGS=pending"; then :
else gbad "ai-pending install: rc $rc $(cat "$TMP/pend.out")"; fi
printf 'by = x\n' > "$R/var/lib/invictus/ai-install-pending"; echo off > "$R/etc/invictus/ai"
: > "$TMP/sys.log"; PEND
[[ $rc == 0 && ! -e "$R/var/lib/invictus/ai-install-pending" ]] && ! logged "pacman -Syu" || gbad "ai-pending installed after AI was turned off"
[[ $g_fail == 0 ]] && ok "N1: ai-pending installs at the next connection, keeps trying on failure, and installs nothing if AI was turned off since"
# No safety copy, no change.
new_root aisnap; export_env; echo off > "$R/etc/invictus/ai"
FAKE_SNAPPER_FAIL=1 isys ai on
[[ $rc == 3 && "$(cat "$R/etc/invictus/ai")" == off ]] && ! logged "pacman -Syu" && ok "A5: ai on with no safety copy possible changes nothing (exit 3)" || gbad "ai on without snapshot: rc $rc"

# NA2: ai off. One person who asked (the caller), one other person (root
# run only), and a home that is not its owner's.
new_root aioff; export_env
echo on > "$R/etc/invictus/ai"
mkdir -p "$R/var/lib/invictus"; printf 'by = x\n' > "$R/var/lib/invictus/ai-install-pending"
me="$(id -u)"; mg="$(id -g)"
chmod 711 "$TMP"
mkhome() {  # mkhome DIR: a signed-in Claude home
    mkdir -p "$1/.claude/projects/p1" "$1/.local/state/invictus/collegium"
    echo '{"token":"x"}' > "$1/.claude/.credentials.json"; chmod 600 "$1/.claude/.credentials.json"
    echo '{"numStartups": 3, "oauthAccount": {"emailAddress": "a@example.org"}}' > "$1/.claude.json"; chmod 600 "$1/.claude.json"
    echo memory > "$1/.claude/projects/p1/chat.jsonl"
}
HA="$R/home/alice"; HE="$R/home/eve"; HB="$R/home/bob"
mkhome "$HA"; mkhome "$HE"
printf 'alice:%s:%s:%s\neve:4242:4242:%s\n' "$me" "$mg" "$HA" "$HE" > "$TMP/people"
if [[ $EUID -eq 0 ]]; then
    mkhome "$HB"
    # The attacker's links: ~/.claude points at a folder of root's, and
    # ~/.claude.json at a file of root's. Root must touch neither.
    mkdir -p "$TMP/vdir"; echo '{"root":"secret"}' > "$TMP/vdir/.credentials.json"
    echo '{"oauthAccount": {"root": 1}}' > "$TMP/victim.json"; chmod 644 "$TMP/victim.json"
    rm -rf "$HB/.claude" "$HB/.claude.json"; ln -s "$TMP/vdir" "$HB/.claude"; ln -s "$TMP/victim.json" "$HB/.claude.json"
    # N-I4: proof that bob's run happened. Only a run as bob removes this.
    echo x > "$HB/.local/state/invictus/collegium/gh-login"
    chown -R 65534:65534 "$HB"; chown -h 65534:65534 "$HB/.claude" "$HB/.claude.json"
    echo "bob:65534:65534:$HB" >> "$TMP/people"
    HC="$R/home/carol"; mkhome "$HC"; chown -R 65533:65533 "$HC"
    echo "carol:65533:65533:$HC" >> "$TMP/people"
fi
: > "$TMP/sys.log"
INVICTUS_PEOPLE="$TMP/people" FAKE_INSTALLED="claude-code invictus-cicero" isys ai off
if [[ $rc == 0 && "$(cat "$R/etc/invictus/ai")" == off && "$(stat -c %a "$R/etc/invictus/ai")" == 644 ]] \
   && grep -q 'pkexec action=org.invictus.sys.ai-off ' "$TMP/sys.log" \
   && [[ ! -e "$R/var/lib/invictus/ai-install-pending" ]] && logged "systemctl disable --now invictus-ai-pending.service" \
   && logged "pacman -Rs --noconfirm -- claude-code invictus-cicero" \
   && [[ "$(snaps | head -1 | cut -d, -f2-3)" == "pre,invictus-sys ai-off " ]] && acta_has "INVICTUS_VERB=ai-off" && acta_has "INVICTUS_RESULT=ok"; then
    ok "NA2: ai off (org.invictus.sys.ai-off): /etc/invictus/ai off (0644), the pending install cancelled, the installed AI set removed, pre/post pair, Acta"
else gbad "ai off: rc $rc: $(paste -sd'|' "$TMP/sys.log") out: $(cat "$TMP/sys.out")"; fi
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d == {"policies": {"GenerativeAI": {"Enabled": False, "Locked": True}}}' "$POL" 2>/dev/null \
   && [[ "$(stat -c %a "$POL")" == 644 ]]; then ok "N7/NA4: ai off writes the browser policy, root 0644, exactly policies.GenerativeAI off and locked"
else gbad "browser policy: $(cat "$POL" 2>/dev/null)"; fi
if [[ ! -e "$HA/.claude/.credentials.json" && -f "$HA/.claude/projects/p1/chat.jsonl" ]] \
   && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "oauthAccount" not in d and d["numStartups"] == 3' "$HA/.claude.json" \
   && [[ "$(stat -c %a "$HA/.claude.json")" == 600 ]] && grep -q "^claude auth logout uid=$me" "$HA/claude-called" 2>/dev/null; then
    ok "N3/N6: the person who asked: claude auth logout, the credential file deleted, the account block gone from ~/.claude.json (the rest and its 0600 kept), the memory kept"
else gbad "ai off caller's home: $(find "$HA" -maxdepth 2 | paste -sd' ') claude: $(cat "$HA/claude-called" 2>/dev/null)"; fi
[[ -f "$HE/.claude/.credentials.json" && ! -e "$HE/claude-called" ]] && grep -q "skipped eve: $HE is not theirs" "$TMP/sys.out" && ok "N3: a home not owned by the person it belongs to is left alone" || gbad "ai off touched a home that is not its owner's"
[[ -f "$R/var/lib/invictus/ai-off-pending/$me" && -f "$R/var/lib/invictus/ai-off-pending/4242" ]] \
    && ok "N3: every person gets an ai-off-pending marker, so their next login clears the provider keys" || gbad "ai-off-pending markers missing"
if [[ $EUID -eq 0 ]]; then
    if [[ -f "$TMP/vdir/.credentials.json" && "$(cat "$TMP/victim.json")" == '{"oauthAccount": {"root": 1}}' && ! -e "$HB/claude-called" ]] \
       && [[ -L "$HB/.claude" && ! -e "$HB/.local/state/invictus/collegium/gh-login" ]] && ! grep -q 'bob' <(grep -E 'skipped|could not finish' "$TMP/sys.out"); then
        ok "ai-off-as-person: links in a person's home reach none of root's files (the clean-up ran as that person: N-I4, their gh-login record is gone); no logout for someone who did not ask"
    else gbad "ai-off-as-person: root followed a person's link, or bob's run never happened (N-I4): vdir $(ls -A "$TMP/vdir") victim $(cat "$TMP/victim.json") gh-login $(ls "$HB/.local/state/invictus/collegium/" 2>&1) out: $(grep bob "$TMP/sys.out")"; fi
    if [[ ! -e "$HC/.claude/.credentials.json" && "$(stat -c %u "$HC/.claude.json")" == 65533 && ! -e "$HC/claude-called" ]] \
       && ! grep -q oauthAccount "$HC/.claude.json" && [[ -f "$HC/.claude/projects/p1/chat.jsonl" ]]; then
        ok "N3: another person's credential file and account block are removed by a process running as them (the rewritten file is theirs), memory kept, no logout run for them"
    else gbad "ai off, other person: $(find "$HC" -maxdepth 2 -printf '%u %p\n' | paste -sd' ')"; fi
fi
chmod 700 "$TMP"
# G1 (Minerva): ai on again takes away the keyring markers ai off left, so
# invictus-session never clears anyone's keys while AI is on.
n_mark="$(find "$R/var/lib/invictus/ai-off-pending" -mindepth 1 | wc -l)"
isys ai on
[[ $rc == 0 && $n_mark -ge 2 && -d "$R/var/lib/invictus/ai-off-pending" && -z "$(find "$R/var/lib/invictus/ai-off-pending" -mindepth 1)" ]] \
    && ok "G1-ai-on-clears-markers: ai off then ai on leaves no ai-off-pending marker ($n_mark removed)" \
    || gbad "G1-ai-on-clears-markers: rc $rc, left: $(find "$R/var/lib/invictus/ai-off-pending" -mindepth 1 -printf '%f ')"
# A browser policy file that is not ours is never overwritten or removed.
new_root aipol; export_env; echo on > "$R/etc/invictus/ai"
mkdir -p "$(dirname "$POL")"; echo '{"policies": {"DisableTelemetry": true}}' > "$POL"
: > "$TMP/people"; INVICTUS_PEOPLE="$TMP/people" isys ai off
k1="$(cat "$POL")"; isys ai on; k2="$(cat "$POL")"
[[ "$k1" == '{"policies": {"DisableTelemetry": true}}' && "$k2" == "$k1" ]] && grep -q 'not locked off' <(INVICTUS_PEOPLE="$TMP/people" bash "$SYS/invictus-sys.sh" ai off 2>&1) \
    && ok "N7: someone else's policies.json is kept by ai off and ai on, and ai off says AI features are not locked" || gbad "foreign browser policy: '$k1' '$k2'"
# N-L1 (Janus): a person's sign-out run leaves a setsid process behind and
# prints terminal escapes. ai off must not wait for it (it did, through the
# pipe, for as long as the process lived) and must not pass the escapes on.
new_root ail1; export_env; echo on > "$R/etc/invictus/ai"
HL="$R/home/lena"; mkdir -p "$HL"; chmod 755 "$R/home" "$HL"
printf 'lena:%s:%s:%s\n' "$(id -u)" "$(id -g)" "$HL" > "$TMP/people-l1"
cat > "$TMP/signout-stub.sh" <<EOF
setsid sleep 60 &
echo \$! > "$HL/stub.pid"
printf '\033]0;owned\007\nai-signout: hello\033[2J\n'
exit 0
EOF
chmod 755 "$TMP/signout-stub.sh"
t0="$(date +%s)"
INVICTUS_PEOPLE="$TMP/people-l1" INVICTUS_AI_SIGNOUT="$TMP/signout-stub.sh" isys ai off
dt=$(( $(date +%s) - t0 ))
[[ -s "$HL/stub.pid" ]] && kill "$(cat "$HL/stub.pid")" 2>/dev/null
if [[ $rc == 0 && $dt -lt 35 ]] && acta_has "INVICTUS_VERB=ai-off" && acta_has "INVICTUS_RESULT=ok"; then
    ok "N-L1-setsid: ai off returns in ${dt}s when a person's run leaves a setsid process holding its output, with the Acta entry"
else gbad "N-L1-setsid: ai off took ${dt}s (rc $rc): $(cat "$TMP/sys.out")"; fi
if grep -q '^  lena: hello' "$TMP/sys.out" && ! grep -q $'[\001-\010\013-\037\177]' "$TMP/sys.out"; then
    ok "N-L1-escapes: a person's output reaches the caller without control characters"
else gbad "N-L1-escapes: $(od -c "$TMP/sys.out" | head -5)"; fi
# ai-signout's python must not run code from the person's home: their
# ~/json.py (python3 - puts the working folder first) or their user site.
new_root ail1py; export_env; echo on > "$R/etc/invictus/ai"
mkdir -p "$HL/.claude"; echo '{"oauthAccount": {"a": 1}, "n": 1}' > "$HL/.claude.json"
echo 'open(__import__("os").path.expanduser("~/pwned-cwd"), "w").close()' > "$HL/json.py"
usite="$(HOME="$HL" python3 -c 'import site; print(site.getusersitepackages())')"
mkdir -p "$usite"; echo 'open(__import__("os").path.expanduser("~/pwned-site"), "w").close()' > "$usite/usercustomize.py"
INVICTUS_PEOPLE="$TMP/people-l1" isys ai off
if [[ $rc == 0 && ! -e "$HL/pwned-cwd" && ! -e "$HL/pwned-site" ]] && ! grep -q oauthAccount "$HL/.claude.json"; then
    ok "N-L1-python-I: ai-signout's python loads nothing from the person's home (no ~/json.py, no usercustomize) and still removes the account block"
else gbad "N-L1-python-I: $(find "$HL" -mindepth 1 -maxdepth 1 -printf '%f ') $(cat "$HL/.claude.json")"; fi

echo
unset INVICTUS_SYS_ROOT INVICTUS_LIB FAKE_STATE FAKE_LOG FAKE_DIR ACTA_LOGGER ACTA_LOG FAKE_POLICY INVICTUS_SNAPPER INVICTUS_PACMAN \
    INVICTUS_SYSTEMCTL INVICTUS_SYSTEMD_RUN INVICTUS_PKCHECK INVICTUS_JOURNALCTL INVICTUS_VISUDO INVICTUS_UPDATE INVICTUS_RESTORE \
    INVICTUS_INHIBIT INVICTUS_PKEXEC INVICTUS_SYS_HELPER INVICTUS_PROC INVICTUS_AI_SIGNOUT INVICTUS_CLAUDE
set -e
