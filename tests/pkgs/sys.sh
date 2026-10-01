# shellcheck shell=bash
# Groups 14 to 16 of tests/pkgs/run.sh (sourced; uses REPO, TMP, ALL, ok, bad):
# invictus-sys (design 4.1, MUSTs A2 to A5, A10, A11), its polkit policy and
# rules, and the guard rails (design-simple-mode 1.3 to 1.6, 6, 12; SM9,
# SM15, SM17, SM21 to SM26).
# shellcheck disable=SC2153,SC2015 # REPO, TMP and ALL come from run.sh; ok || bad on purpose
#
# What is faked, at the seam (the container has no polkitd, no snapper and
# no root): pkexec (resolves the action from the real .policy file the way
# pkexec's find_action_for_path does, records it and the expanded message,
# then runs the helper), snapper (a counter and a list), pacman, systemctl,
# systemd-run, pkcheck, journalctl, logger (Acta entries to a file) and
# limine-snapper-restore. The polkit .rules files run for real in node
# (tests/pkgs/polkit-rules.js), with polkitd's order and defaults.
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
GRD="$REPO/scripts/guardrails"
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
    mkdir -p "$R/usr/share/invictus/sys" "$R/usr/share/invictus/guardrails/claude"
    cp "$SYS/services.allow" "$SYS/protected-packages" "$R/usr/share/invictus/sys/"
    cp "$GRD/40-invictus-custodia.rules" "$GRD/sudo-lecture" "$GRD/messages.tsv" "$GRD/hold-list.txt" "$R/usr/share/invictus/guardrails/"
    cp "$GRD"/claude/*.json "$R/usr/share/invictus/guardrails/claude/"
    printf '#%%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\nsession\t\toptional\tpam_systemd.so class=none\n' > "$R/etc/pam.d/sudo"
    printf '[options]\nHoldPkg     = pacman glibc\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' > "$R/etc/pacman.conf"
    echo "${2:-custodia}" > "$R/etc/invictus/guardrails"
    D="$R/etc/sudoers.d/40-invictus-guardrails"; POL="$R/etc/firefox/policies/policies.json"
    : > "$TMP/sys.log"; : > "$TMP/acta.log"
}
# Environment for every script under test.
export_env() {
    export INVICTUS_SYS_ROOT="$R" INVICTUS_LIB="$REPO/scripts" FAKE_STATE="$R/state" FAKE_LOG="$TMP/sys.log" FAKE_DIR="$F" \
        ACTA_LOGGER="$F/logger" ACTA_LOG="$TMP/acta.log" FAKE_POLICY="$SYS/org.invictus.sys.policy" \
        INVICTUS_SNAPPER="$F/snapper" INVICTUS_PACMAN="$F/pacman" INVICTUS_SYSTEMCTL="$F/systemctl" \
        INVICTUS_SYSTEMD_RUN="$F/systemd-run" INVICTUS_PKCHECK="$F/pkcheck" INVICTUS_JOURNALCTL="$F/journalctl" \
        INVICTUS_VISUDO="$F/visudo" INVICTUS_UPDATE="$F/update" INVICTUS_RESTORE="$F/restore" INVICTUS_INHIBIT="$F/inhibit" \
        INVICTUS_PKEXEC="$F/pkexec" INVICTUS_SYS_HELPER="$SYS/invictus-sys-root.sh" INVICTUS_GUARDRAILS="$GRD/guardrails.sh" \
        INVICTUS_PROC="$TMP/proc" INVICTUS_AI_SIGNOUT="$SYS/ai-signout.sh" INVICTUS_CLAUDE="$F/claude"
}
# isys ARGS: the user-facing command, as the person (not root: the fake
# pkexec runs the helper). Output in $TMP/sys.out, exit code in $rc.
isys() { rc=0; bash "$SYS/invictus-sys.sh" "$@" > "$TMP/sys.out" 2>&1 || rc=$?; }
grd() { rc=0; bash "$GRD/guardrails.sh" "$@" > "$TMP/grd.out" 2>&1 || rc=$?; }
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
nokeep = {"assistant-full-access", "guardrails-libertas", "guardrails-custodia", "ai-on", "ai-off"}
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

new_root verbs custodia; export_env
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
new_root nosnappac custodia; export_env
FAKE_SNAP_PAC=0 isys install htop
if [[ $rc == 0 && "$(snaps | cut -d, -f2 | paste -sd' ')" == "pre post" ]] && grep -q 'snapshot=1' "$TMP/sys.out"; then
    ok "A5: without snap-pac, install makes its own pre/post pair and returns the pre"
else sfail "no snap-pac: $(snaps | paste -sd'|')"; fi

# A10: each verb is its own action; full access and the rails have theirs.
new_root map libertas; export_env
declare -A want_action=(
    ["update"]=update ["snapshot before the move"]=snapshot ["rollback 3"]=rollback
    ["service restart cups.service"]=service ["set-config nets.auto-update off"]=set-config
    ["set-config assistant.full-access on"]=assistant-full-access ["report-collect"]=report-collect
    ["guardrails set libertas --for 1h"]=guardrails-libertas ["guardrails set custodia"]=guardrails-custodia
    ["remove vlc"]=remove ["ai on"]=ai-on ["ai off"]=ai-off)
for call in "${!want_action[@]}"; do
    : > "$TMP/sys.log"; read -ra words <<< "$call"; FAKE_DENY=1 isys "${words[@]}"
    grep -q "pkexec action=org.invictus.sys.${want_action[$call]} " "$TMP/sys.log" || sfail "A10: '$call' did not use org.invictus.sys.${want_action[$call]}: $(cat "$TMP/sys.log")"
    [[ $rc == 126 ]] || sfail "A10: a cancelled prompt for '$call' should exit 126 (got $rc)"
done
[[ $s_fail == 0 ]] && ok "A10: ${#want_action[@]} verbs, each through its own action id; a cancelled prompt runs nothing and exits 126"

# remove: protected names stop before the prompt; a dependency that would
# take a protected package stops in the root half.
new_root remove custodia; export_env
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
new_root snap custodia; export_env
long="$(head -c 10000 /dev/zero | tr '\0' 'x')"
isys snapshot "$long"
d="$(snaps | tail -1 | cut -d, -f3)"
if [[ $rc == 0 && ${#d} -le 200 && "$(snaps | tail -1 | cut -d, -f4)" == important=yes ]]; then
    ok "SM22: snapshot with a 10 000-byte description is trimmed to ${#d} bytes, important (kept by NUMBER_LIMIT_IMPORTANT)"
else sfail "snapshot trim: rc $rc len ${#d}"; fi

# service: only the allowlist, and a pre/post pair around it.
new_root svc libertas; export_env
: > "$TMP/sys.log"; isys service enable sshd.service
if [[ $rc != 2 ]] || logged pkexec; then sfail "service sshd.service accepted (rc $rc)"; fi
isys service restart cups.service
if [[ $rc == 0 ]] && logged "systemctl restart cups.service" && [[ "$(snaps | cut -d, -f2 | paste -sd' ')" == "pre post" ]] \
   && snaps | head -1 | grep -q 'invictus-sys service restart cups.service'; then
    ok "A5: service restart cups.service runs between a pre and a post snapshot named after the verb; sshd is not on the list"
else sfail "service: rc $rc: $(snaps | paste -sd'|')"; fi
for g in sshd.service snapper-timeline.timer invictus-guardrails.service invictus-auto-update.timer polkit.service; do
    list_has "$SYS/services.allow" "$g" && sfail "services.allow lists $g, which guards the machine"
done
# No safety copy, no change.
: > "$TMP/sys.log"; FAKE_SNAPPER_FAIL=1 isys service restart cups.service
if [[ $rc == 3 ]] && ! logged "systemctl restart"; then ok "A5: when no snapshot can be made, service is refused and nothing runs"
else sfail "service without snapshot: rc $rc"; fi

# rollback: unknown number fails; booted into it restores; otherwise pending.
new_root rb libertas; export_env
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
new_root rep custodia; export_env; sleep 0.05; : > "$TMP/rep.mark"; sleep 0.05
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
printf 'HOME=/h\0INVICTUS_REQUEST=moneta-thread-9\0' > "$TMP/proc/$$/environ"
new_root acta custodia; export_env
rc=0; PKEXEC_UID="$(id -u)" bash -c 'exec "$0" snapshot test' "$SYS/invictus-sys-root.sh" > "$TMP/sys.out" 2>&1 || rc=$?
if [[ $rc == 0 ]] && acta_has "INVICTUS_SESSION=7" && acta_has "INVICTUS_REQUEST=moneta-thread-9"; then
    ok "A11: Acta records the logind session (7) and request id of the process that ran pkexec"
else sfail "A11 session: rc $rc: $(paste -sd'|' "$TMP/acta.log")"; fi

# H1 (Janus): the update verb (tier 1, no password under Custodia) never
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
new_root h1 custodia; export_env
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
new_root locale custodia; export_env
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
for f in "$SYS/invictus-sys-root.sh" "$GRD/guardrails.sh" "$GRD/pre-admin-snapshot.sh" "$SYS/ai-pending.sh"; do
    grep -q "case \"\$(readlink -f -- \"\$0\")\" in" "$f" && grep -q 'export PATH=/usr/bin' "$f" \
        && head -1 "$f" | grep -qx '#!/usr/bin/bash' || sfail "$(basename "$f"): no override drop for the installed copy, or not #!/usr/bin/bash"
done
[[ $s_fail == 0 ]] && ok "the four root scripts start with #!/usr/bin/bash, set PATH and drop every INVICTUS_*/ACTA_* override when installed"

# Packages: the trees from group 4.
if [[ -x "$ALL/usr/bin/invictus-sys" && -x "$ALL/usr/lib/invictus/invictus-sys" && -f "$ALL/usr/share/polkit-1/actions/org.invictus.sys.policy" \
      && -x "$ALL/usr/lib/invictus/guardrails" && -x "$ALL/usr/lib/invictus/pre-admin-snapshot" \
      && -f "$ALL/usr/share/polkit-1/rules.d/40-invictus-guardrails.rules" && ! -e "$ALL/etc/polkit-1/rules.d/40-invictus-custodia.rules" \
      && -L "$ALL/usr/lib/systemd/system/multi-user.target.wants/invictus-guardrails.service" \
      && -f "$ALL/etc/pam.d/polkit-1" && -f "$ALL/usr/lib/invictus/lib/acta.sh" && -f "$ALL/usr/lib/invictus/lib/ai-set.sh" \
      && -x "$ALL/usr/lib/invictus/ai-signout" && -x "$ALL/usr/lib/invictus/ai-pending" \
      && -f "$ALL/usr/lib/systemd/system/invictus-ai-pending.service" \
      && ! -e "$ALL/usr/lib/systemd/system/multi-user.target.wants/invictus-ai-pending.service" ]]; then
    if grep -q '^\[Install\]' "$ALL/usr/lib/systemd/system/invictus-guardrails.service"; then sfail "invictus-guardrails.service has an [Install] section"
    else ok "invictus-sys and invictus-guardrails install their files; the boot service is static and always wanted; the tier 1 rule is not packaged in /etc"; fi
else sfail "package trees incomplete"; fi
hook="$ALL/usr/share/libalpm/hooks/40-invictus-hold.hook"
if [[ "$(grep -c '^Target = ' "$hook")" == "$(grep -cv '^[[:space:]]*\(#\|$\)' "$SYS/protected-packages")" ]] \
   && grep -qx 'Target = invictus-desktop' "$hook" && grep -qx 'When = PreTransaction' "$hook"; then
    ok "G4: the hold hook targets every protected package ($(grep -c '^Target = ' "$hook"))"
else sfail "hold hook targets"; fi
pb_deps() { bash -c 'source "$1"; printf "%s\n" "${depends[@]}"' _ "$1"; }
if pb_deps "$REPO/pkgs/meta/invictus-base/PKGBUILD" | grep -x invictus-guardrails >/dev/null \
   && ! pb_deps "$REPO/pkgs/own/invictus-sys/PKGBUILD" | grep -x invictus-tools >/dev/null \
   && pb_deps "$REPO/pkgs/own/invictus-tools/PKGBUILD" | grep -x invictus-sys >/dev/null; then
    ok "invictus-base brings the guard rails and invictus-sys with no desktop package; invictus-tools brings invictus-sys"
else sfail "package depends"; fi
echo

# ---- 15. polkit rules (node) ------------------------------------------------------------------
echo "== polkit rules"
p_fail=0
pbad() { bad "$1"; p_fail=1; }
if ! command -v node >/dev/null; then
    bad "node is needed to run the polkit rules (CI's ubuntu runner has it)"
else
    RD="$TMP/rules"; rm -rf "$RD"; mkdir -p "$RD/usr" "$RD/etc"
    cp "$GRD/40-invictus-guardrails.rules" "$RD/usr/"
    # polkit's Arch default (admin identity), so the order is real.
    printf 'polkit.addAdminRule(function(action, subject) { return ["unix-group:wheel"]; });\n' > "$RD/usr/50-default.rules"
    q() { node "$REPO/tests/pkgs/polkit-rules.js" "$SYS/org.invictus.sys.policy" "$RD/etc" "$RD/usr"; }
    queries() {
        local v
        for v in $SYS_ROOT_VERBS; do
            printf 'org.invictus.sys.%s 1 1 wheel\norg.invictus.sys.%s 1 0 wheel\norg.invictus.sys.%s 0 0 wheel\norg.invictus.sys.%s 1 1 users\n' "$v" "$v" "$v" "$v"
        done
        echo "org.freedesktop.policykit.exec 1 1 wheel"
    }
    TIER1="update snapshot report-collect"
    expect() {  # expect RAILS: compare every answer with the design
        local id l a g res v want
        while read -r id l a g res; do
            v="${id#org.invictus.sys.}"
            if [[ "$id" == org.freedesktop.policykit.exec ]]; then want=no-such-action
            elif [[ "$v" =~ ^(guardrails-custodia|ai-off)$ && $l == 1 && $a == 1 ]]; then want=yes
            elif [[ "$1" == custodia && " $TIER1 " == *" $v "* && $l == 1 && $a == 1 && $g == wheel ]]; then want=yes
            elif [[ $l == 1 && $a == 1 ]]; then
                case "$v" in assistant-full-access|guardrails-libertas|guardrails-custodia|ai-on|ai-off) want=auth_admin ;; *) want=auth_admin_keep ;; esac
            else want=auth_admin; fi
            [[ "$res" == "$want" ]] || pbad "$1: $id local=$l active=$a $g -> $res, want $want"
        done < <(paste -d' ' <(queries | cut -d' ' -f1-4) <(queries | q | cut -d' ' -f2))
    }
    expect libertas
    [[ $p_fail == 0 ]] && ok "Libertas: every verb asks for a password (auth_admin_keep; no keep for full access, the rails and AI), except guard rails on and No AI from your own desktop"
    cp "$GRD/40-invictus-custodia.rules" "$RD/etc/"
    expect custodia
    [[ $p_fail == 0 ]] && ok "Custodia: tier 1 (update, snapshot, report-collect) is YES only for wheel at a local active desktop; tier 2 keeps its password; nothing grants pkexec itself"
    # SM22 standing rule: the tier 1 list may only shrink without Minerva.
    SM22="update update-undo snapshot report-collect help-start help-stop doctor"
    got="$(sed -n 's/.*"org\.invictus\.sys\.\([a-z-]*\)".*/\1/p' "$GRD/40-invictus-custodia.rules" | paste -sd' ')"
    for v in $got; do [[ " $SM22 " == *" $v "* ]] || pbad "SM22: tier 1 has $v, which is not on Minerva's list"; done
    [[ "$got" == "$TIER1" ]] || pbad "SM22: tier 1 is '$got'; this test says '$TIER1' (changing it needs Minerva's review)"
    for v in $got; do sys_validate "$v" "/bin/sh" 2>/dev/null && [[ "$v" != snapshot ]] && pbad "SM22: tier 1 verb $v takes an argument"; done
    [[ $p_fail == 0 ]] && ok "SM22: tier 1 is exactly '$TIER1', all on Minerva's list, none takes a command, path or URL"
fi
echo

# ---- 16. guard rails ----------------------------------------------------------------------------
echo "== guard rails"
g_fail=0
gbad() { bad "$1"; g_fail=1; }

# SM24: apply makes the derived files match; --check then finds nothing.
new_root apply custodia; export_env
grd apply --check
[[ $rc == 1 ]] || gbad "apply --check on a fresh root should report changes (rc $rc)"
grd apply
if [[ $rc == 0 && -f "$D" && "$(stat -c %a "$D")" == 440 ]] && grep -qx 'Defaults lecture=always, lecture_file=/usr/share/invictus/guardrails/sudo-lecture' "$D" \
   && grep -q '^HoldPkg = .*invictus-desktop' "$R/etc/pacman.d/invictus-guardrails.conf" \
   && grep -qx 'Include = /etc/pacman.d/invictus-guardrails.conf' "$R/etc/pacman.conf" \
   && [[ "$(sed -n '2p' "$R/etc/pacman.conf")" == 'Include = /etc/pacman.d/invictus-guardrails.conf' ]] \
   && [[ "$(readlink "$R/etc/claude-code/managed-settings.json")" == /usr/share/invictus/guardrails/claude/fixed.json ]] \
   && cmp -s "$GRD/40-invictus-custodia.rules" "$R/etc/polkit-1/rules.d/40-invictus-custodia.rules" \
   && [[ "$(grep -n pre-admin-snapshot "$R/etc/pam.d/sudo" | cut -d: -f1)" == 3 ]]; then
    ok "SM24: apply (Custodia) writes the lecture drop-in (0440), HoldPkg include, fixed profile link, tier 1 rule, the Include line in [options] and the PAM line after auth"
else gbad "apply custodia: rc $rc $(cat "$TMP/grd.out")"; fi
grd apply --check
[[ $rc == 0 ]] && grep -q 'consistent: custodia' "$TMP/grd.out" && ok "SM24: apply --check after apply: consistent (exit 0)" || gbad "apply --check after apply: rc $rc $(cat "$TMP/grd.out")"
grd apply; cp -a "$R/etc" "$TMP/etc-once"; grd apply
diff -r --no-dereference "$TMP/etc-once" "$R/etc" >/dev/null && ok "apply is idempotent (a second run changes nothing)" || gbad "apply not idempotent"
rm -rf "$TMP/etc-once"
rm -f "$D"; grd apply --check
[[ $rc == 1 ]] && grep -q "would change: write $D" "$TMP/grd.out" && ok "SM24: a removed derived file shows up in apply --check (exit 1)" || gbad "check after tamper: rc $rc"
grd apply
# The doctor runs `guardrails check` as the person, who cannot look into
# /etc/sudoers.d or /etc/polkit-1/rules.d (0750 root). Here as a non-root
# user (CI's runner) with the folder closed; as root, e2e-sys.sh checks it.
if [[ $EUID -ne 0 ]]; then
    chmod 000 "$R/etc/sudoers.d"; grd apply --check; chmod 755 "$R/etc/sudoers.d"
    [[ $rc == 0 ]] && grep -q "not checked as $(id -un): $D" "$TMP/grd.out" \
        && ok "check as the person: a folder they cannot open is named as not checked, the rest is checked" || gbad "check with a closed folder: rc $rc $(cat "$TMP/grd.out")"
else
    echo "note  running as root: the closed-folder check runs in CI (non-root) and in e2e-sys.sh"
fi
# The real visudo (as any user: with -f it checks syntax, not ownership).
if command -v visudo >/dev/null; then
    visudo -cqf "$D" >/dev/null 2>&1 && ok "the sudoers drop-in passes the real visudo" || gbad "real visudo rejects the drop-in"
else
    gbad "visudo is not installed, so the sudoers drop-in is unchecked (install sudo)"
fi
# Missing guardrails file reads as custodia and is written.
rm -f "$R/etc/invictus/guardrails"; grd apply
[[ "$(cat "$R/etc/invictus/guardrails")" == custodia ]] && ok "a missing /etc/invictus/guardrails reads as custodia and apply writes it" || gbad "missing rails file"

# SM15/SM21 to Libertas: snapshot first, derived files follow, nothing restarts.
new_root live custodia; export_env; mkdir -p "$R/run/systemd/system"
grd apply
echo "full-access = off" > "$R/etc/invictus/assistant"
SYS_USER=alex grd set libertas
first="$(snaps | head -1)"
if [[ $rc == 0 && "$first" == "1,single,Before: guard rails off,important=yes" && "$(cat "$R/etc/invictus/guardrails")" == libertas \
      && ! -e "$D" && ! -e "$R/etc/polkit-1/rules.d/40-invictus-custodia.rules" && ! -e "$R/etc/invictus/guardrails-until" ]] \
   && ! grep -q HoldPkg "$R/etc/pacman.d/invictus-guardrails.conf" \
   && grep -qx 'Include = /etc/pacman.d/invictus-guardrails.conf' "$R/etc/pacman.conf" \
   && acta_has "INVICTUS_VERB=guardrails-libertas" && acta_has "INVICTUS_SNAPSHOT=1" && acta_has "INVICTUS_TO=libertas" \
   && grep -q 'Guard rails are off' "$R/run/invictus/guardrails-notice" && [[ "$(stat -c %a "$R/etc/invictus/guardrails")" == 644 ]]; then
    ok "SM15/SM21: set libertas: 'Before: guard rails off' first, then the file (0644), no lecture, no HoldPkg (include stays), no tier 1 rule, Acta and the notice"
else gbad "to libertas: rc $rc first '$first': $(cat "$TMP/grd.out")"; fi
grd apply --check; [[ $rc == 0 ]] || gbad "after set libertas, apply --check is not consistent: $(cat "$TMP/grd.out")"
# No safety copy, no switch.
new_root nosnap custodia; export_env; grd apply
FAKE_SNAPPER_FAIL=1 grd set libertas
[[ $rc == 1 && "$(cat "$R/etc/invictus/guardrails")" == custodia && -e "$D" ]] && ok "TS11: when the safety copy fails, the rails stay Custodia" || gbad "set libertas without snapshot: rc $rc"
grd set sideways; [[ $rc == 2 ]] || gbad "set sideways accepted"
grd set libertas --for 9y; [[ $rc == 2 && "$(cat "$R/etc/invictus/guardrails")" == custodia ]] || gbad "--for 9y accepted"
[[ $g_fail == 0 ]] && ok "SM15: only custodia or libertas, --for only 1m to 7d"

# SM21 back to Custodia: caches cleared, full access off, rules back.
new_root back libertas; export_env; mkdir -p "$R/run/systemd/system" "$R/run/invictus"
grd apply
echo "full-access = on" > "$R/etc/invictus/assistant"; echo on > "$R/etc/invictus/ai"
grd apply
[[ "$(readlink "$R/etc/claude-code/managed-settings.json")" == */full.json ]] || gbad "12.3: Libertas + full access on should link the full profile"
touch "$R/run/sudo/ts/alex" "$R/run/invictus/pre-admin-snapshot.stamp"
: > "$TMP/sys.log"; SYS_USER=alex grd set custodia --how click
if [[ $rc == 0 && "$(cat "$R/etc/invictus/guardrails")" == custodia && ! -e "$R/run/sudo/ts/alex" && ! -e "$R/run/invictus/pre-admin-snapshot.stamp" \
      && -e "$D" && -e "$R/etc/polkit-1/rules.d/40-invictus-custodia.rules" ]] && grep -q HoldPkg "$R/etc/pacman.d/invictus-guardrails.conf" \
   && logged "pkcheck --revoke-temp" && grep -qx 'full-access = off' "$R/etc/invictus/assistant" \
   && [[ "$(readlink "$R/etc/claude-code/managed-settings.json")" == */fixed.json ]] \
   && acta_has "INVICTUS_FULL_ACCESS_WAS=on" && acta_has "INVICTUS_HOW=click" && [[ -z "$(snaps)" ]]; then
    ok "SM21/SM26: set custodia: no snapshot needed, sudo timestamps and polkit temp auths cleared, the G2 stamp reset, full access off, fixed profile, lecture, HoldPkg and tier 1 back"
else gbad "to custodia: rc $rc: $(cat "$TMP/grd.out")"; fi

# The assistant is told to restart (tribune socket). The listener records
# what it got and the uid that connected (SO_PEERCRED).
listen_tribune() {  # listen_tribune SOCKET OUTFILE
    rm -f "$2"
    python3 -c '
import socket, struct, sys, os
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); os.chmod(sys.argv[1], 0o777); s.listen(1); s.settimeout(10)
if os.fork() == 0:
    try:
        c, _ = s.accept()
        pid, uid, gid = struct.unpack("3i", c.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
        open(sys.argv[2], "w").write("%s uid=%d" % (c.recv(100).decode().strip(), uid))
    except Exception:
        pass
    os._exit(0)
' "$1" "$2"
}
# got FILE: wait up to 3 s for the listener to write FILE (load-proof).
got() { local i; for i in $(seq 30); do [[ -s "$1" ]] && break; sleep 0.1; done; cat "$1" 2>/dev/null; }
me="$(id -u)"
new_root sock libertas; export_env; grd apply
mkdir -p "$R/run/user/$me/invictus"
listen_tribune "$R/run/user/$me/invictus/tribune.sock" "$TMP/tribune.got"
grd set custodia
[[ "$(got "$TMP/tribune.got")" == "restart-profile uid=$me" ]] && ok "G7: a switch sends restart-profile to the Moneta panel's socket" || gbad "tribune socket got '$(cat "$TMP/tribune.got" 2>/dev/null)'"
# L1 (Janus): a /run/user/N folder whose owner is not N gets nothing.
new_root sock2 libertas; export_env; grd apply
other=4242; [[ "$me" == 4242 ]] && other=4243
mkdir -p "$R/run/user/$other/invictus"
listen_tribune "$R/run/user/$other/invictus/tribune.sock" "$TMP/tribune2.got"
grd set custodia
! grep -q 'told .* Moneta panel' "$TMP/grd.out" && [[ ! -s "$TMP/tribune2.got" ]] && ok "L1-socket-owner: a /run/user/$other folder owned by uid $me is skipped" || gbad "L1-socket-owner: root signalled a socket in a folder its uid does not own: '$(cat "$TMP/tribune2.got")'"
# L1 as root: the connection is made as the folder's owner, not as root.
if [[ $EUID -eq 0 ]]; then
    new_root sock3 libertas; export_env; grd apply
    chmod 711 "$TMP"
    mkdir -p "$R/run/user/65534/invictus"; chown -R 65534 "$R/run/user/65534"
    listen_tribune "$R/run/user/65534/invictus/tribune.sock" "$TMP/tribune3.got"
    grd set custodia
    t3="$(got "$TMP/tribune3.got")"
    chmod 700 "$TMP"
    [[ "$t3" == "restart-profile uid=65534" ]] && ok "L1-socket-owner: root connects to /run/user/65534's socket as uid 65534" \
        || gbad "L1-socket-owner: root connected as '$(cat "$TMP/tribune3.got" 2>/dev/null)', not as the folder's owner"
else
    echo "note  not root: connecting as the folder's owner is checked in the root run"
fi

# SM25: timed Libertas.
new_root timed custodia; export_env; mkdir -p "$R/run/systemd/system"; grd apply
t0=1790000000
: > "$TMP/sys.log"; INVICTUS_NOW=$t0 SYS_USER=alex grd set libertas --for 3m
U="$R/etc/invictus/guardrails-until"
if [[ $rc == 0 && "$(date -d "$(sed -n 's/^until = //p' "$U")" +%s)" == $((t0 + 180)) ]] && grep -qx 'by = alex' "$U" && [[ "$(stat -c %a "$U")" == 644 ]] \
   && logged "systemd-run --quiet --unit invictus-guardrails-expiry --on-calendar $(date -u -d "@$((t0 + 180))" '+%Y-%m-%d %H:%M:%S') UTC --timer-property=AccuracySec=1s /usr/lib/invictus/guardrails expire"; then
    ok "SM25: set libertas --for 3m writes the until-file (0644, until/since/by) and arms the expiry timer at that wall-clock time"
else gbad "timed libertas: rc $rc: $(paste -sd'|' "$TMP/sys.log")"; fi
: > "$TMP/sys.log"; INVICTUS_NOW=$((t0 + 60)) grd expire
[[ "$(cat "$R/etc/invictus/guardrails")" == libertas ]] && logged "systemd-run" && ok "SM25: expire before the end re-arms the timer and changes nothing" || gbad "early expire"
INVICTUS_NOW=$((t0 + 180)) grd expire
if [[ "$(cat "$R/etc/invictus/guardrails")" == custodia && ! -e "$U" && -e "$D" ]] && acta_has "INVICTUS_HOW=expired" \
   && grep -qx 'Guard rails are back on' "$R/run/invictus/guardrails-notice"; then
    ok "SM25: at the end, expire switches to Custodia, removes the until-file, Acta 'expired', the notice"
else gbad "expire at the end: $(cat "$TMP/grd.out")"; fi
# Ended while the computer was off: the boot service.
INVICTUS_NOW=$t0 grd set libertas --for 3m
INVICTUS_NOW=$((t0 + 3600)) grd apply --boot
[[ "$(cat "$R/etc/invictus/guardrails")" == custodia ]] && grep -q 'INVICTUS_HOW=expired while the computer was off' "$TMP/acta.log" \
    && ok "SM25: apply --boot ends a timed Libertas that ran out while the computer was off" || gbad "boot expiry"
# Lost timer: the next invictus-sys verb ends it first.
date_end="$(date -d '-1 minute' --iso-8601=seconds)"
echo libertas > "$R/etc/invictus/guardrails"; printf 'until = %s\nsince = x\nby = alex\n' "$date_end" > "$U"
isys snapshot "check"
[[ "$(cat "$R/etc/invictus/guardrails")" == custodia ]] && ok "SM25: with the timer gone, any invictus-sys verb ends an expired Libertas before it runs" || gbad "verb-time expiry"
. "$REPO/scripts/lib/guardrails-state.sh"
echo libertas > "$R/etc/invictus/guardrails"; printf 'until = %s\n' "$date_end" > "$U"
[[ "$(INVICTUS_SYS_ROOT=$R bash -c '. "$1"; gr_effective_rails' _ "$REPO/scripts/lib/guardrails-state.sh")" == custodia ]] \
    && ok "SM25: every reader treats a Libertas past its end as Custodia" || gbad "gr_effective_rails"

# set-config never writes the rails, AI, assistant or helper files: those
# have their own verbs (or none), with their own prompts.
new_root keys libertas; export_env
for k in guardrails guardrails-until ai assistant helper.conf nets "nets.x" "../etc/shadow" "assistant.full-access=on"; do
    : > "$TMP/sys.log"; isys set-config "$k" on
    if [[ $rc != 2 ]] || logged pkexec; then gbad "set-config $k was accepted (rc $rc)"; fi
    rc=0; bash "$SYS/invictus-sys-root.sh" set-config "$k" on > "$TMP/sys.out" 2>&1 || rc=$?
    [[ $rc == 2 ]] || gbad "the root half accepted set-config $k (rc $rc)"
done
[[ "$(cat "$R/etc/invictus/guardrails")" == libertas && ! -e "$R/etc/invictus/ai" ]] || gbad "set-config changed a file it must not"
[[ $g_fail == 0 ]] && ok "set-config refuses the guard-rails, AI, assistant and helper files and any key off its list, in both halves"

# Nets: Libertas only, Custodia ignores the file and re-arms everything.
new_root nets custodia; export_env; grd apply
isys set-config nets.pre-admin-snapshot off
[[ $rc == 3 && ! -e "$R/etc/invictus/nets" ]] || gbad "nets off under Custodia: rc $rc"
echo libertas > "$R/etc/invictus/guardrails"; grd apply
isys set-config nets.pre-admin-snapshot off
r_net() { INVICTUS_SYS_ROOT=$R bash -c '. "$1"; gr_net_on pre-admin-snapshot && echo on || echo off' _ "$REPO/scripts/lib/guardrails-state.sh"; }
if [[ $rc == 0 ]] && grep -qx 'pre-admin-snapshot = off' "$R/etc/invictus/nets" && [[ "$(r_net)" == off && "$(snaps | cut -d, -f2 | paste -sd' ')" == "pre post" ]]; then
    echo custodia > "$R/etc/invictus/guardrails"
    if [[ "$(r_net)" == on ]] && grep -qx 'pre-admin-snapshot = off' "$R/etc/invictus/nets"; then
        ok "1.6 nets: set-config nets.* is refused under Custodia; under Libertas it writes nets (pre/post pair); Custodia reads every net as on and leaves the file"
    else gbad "custodia should read nets as on"; fi
else gbad "nets under libertas: rc $rc $(cat "$TMP/sys.out")"; fi

# SM26: full access.
new_root full custodia; export_env; grd apply; echo on > "$R/etc/invictus/ai"
isys set-config assistant.full-access on
[[ $rc == 3 ]] && grep -q 'Custodia' "$TMP/sys.out" || gbad "full access under Custodia: rc $rc"
rm -f "$R/etc/invictus/ai"
echo libertas > "$R/etc/invictus/guardrails"; grd apply
isys set-config assistant.full-access on
[[ $rc == 3 ]] && grep -q 'No AI' "$TMP/sys.out" || gbad "full access with AI off: rc $rc"
echo on > "$R/etc/invictus/ai"
isys set-config assistant.full-access on
if [[ $rc == 0 && "$(readlink "$R/etc/claude-code/managed-settings.json")" == */full.json ]] && grep -qx 'full-access = on' "$R/etc/invictus/assistant"; then
    isys set-config assistant.full-access off
    [[ "$(readlink "$R/etc/claude-code/managed-settings.json")" == */fixed.json ]] \
        && ok "SM26: full access is refused under Custodia and with No AI; under Libertas on links the full profile, off the fixed one" \
        || gbad "full access off"
else gbad "full access on: rc $rc: $(cat "$TMP/sys.out")"; fi
python3 -c 'import json,sys; f=json.load(open(sys.argv[1])); d=f["permissions"]["deny"]; assert "Bash" in d and "Edit" in d and "Write" in d; g=json.load(open(sys.argv[2]))["permissions"]["deny"]; assert "Bash" not in g and "Bash(sudo *)" in g and "Bash(pacman *)" in g' \
    "$GRD/claude/fixed.json" "$GRD/claude/full.json" && ok "A7/4.3: the fixed profile denies Bash, Edit and Write; the full one keeps Bash under A7's deny rules" || gbad "managed profiles"

# ---- ai on|off (design-no-ai.md N1, N3, N4.3, N7; NA1, NA2, NA5, NA6) ----

OURPOL='{"policies": {"GenerativeAI": {"Enabled": false, "Locked": true}}}'
# The user half: on or off, nothing else, before any prompt.
new_root aiargs custodia; export_env
for a in "" "maybe" "on now" "--on"; do
    : > "$TMP/sys.log"; read -ra words <<< "$a"; isys ai "${words[@]}"
    if [[ $rc != 2 ]] || logged pkexec; then gbad "ai '$a' accepted (rc $rc)"; fi
done
[[ $g_fail == 0 ]] && ok "ai: only 'ai on' or 'ai off', refused before any prompt otherwise"

# NA6: ai on (Custodia too): the setting, our browser policy gone, the AI set
# installed in one -Syu --needed, a pre/post pair, Acta.
new_root aion custodia; export_env; grd apply
echo off > "$R/etc/invictus/ai"; mkdir -p "$(dirname "$POL")"; printf '%s\n' "$OURPOL" > "$POL"
: > "$TMP/sys.log"; isys ai on
if [[ $rc == 0 && "$(cat "$R/etc/invictus/ai")" == on && "$(stat -c %a "$R/etc/invictus/ai")" == 644 && ! -e "$POL" ]] \
   && grep -q 'pkexec action=org.invictus.sys.ai-on ' "$TMP/sys.log" \
   && logged "pacman -Syu --needed --noconfirm -- invictus-moneta" && logged inhibit \
   && [[ "$(snaps | head -1 | cut -d, -f2-3)" == "pre,invictus-sys ai-on " ]] \
   && acta_has "INVICTUS_VERB=ai-on" && acta_has "INVICTUS_RESULT=ok" && grep -q 'invictus-sys: ok snapshot=1' "$TMP/sys.out"; then
    ok "NA6: ai on (org.invictus.sys.ai-on): /etc/invictus/ai on (0644), our browser policy removed, invictus-moneta in one -Syu --needed, pre/post pair, Acta"
else gbad "ai on: rc $rc: $(paste -sd'|' "$TMP/sys.log") out: $(cat "$TMP/sys.out")"; fi
# Offline: the choice stands, the install waits for the connection.
new_root aioff1 custodia; export_env; grd apply; echo off > "$R/etc/invictus/ai"
: > "$TMP/sys.log"; FAKE_PACMAN_RC=1 isys ai on
if [[ $rc == 0 && "$(cat "$R/etc/invictus/ai")" == on && -f "$R/var/lib/invictus/ai-install-pending" ]] \
   && grep -q 'invictus-sys: pending' "$TMP/sys.out" && logged "systemctl enable --now --no-block invictus-ai-pending.service" && acta_has "INVICTUS_RESULT=pending"; then
    ok "N1: ai on with no connection: AI reads on, the pending marker is written and invictus-ai-pending.service enabled"
else gbad "ai on offline: rc $rc: $(cat "$TMP/sys.out")"; fi
# ai-pending: installs only while the marker exists and AI still reads on.
PEND() { rc=0; bash "$SYS/ai-pending.sh" > "$TMP/pend.out" 2>&1 || rc=$?; }
: > "$TMP/sys.log"; FAKE_PACMAN_RC=1 PEND
[[ $rc == 1 && -f "$R/var/lib/invictus/ai-install-pending" ]] || gbad "ai-pending: a failed install should keep the marker and fail (rc $rc)"
: > "$TMP/sys.log"; PEND
if [[ $rc == 0 && ! -e "$R/var/lib/invictus/ai-install-pending" ]] && logged "pacman -Syu --needed --noconfirm -- invictus-moneta" \
   && logged "systemctl disable invictus-ai-pending.service" && acta_has "INVICTUS_ARGS=pending"; then :
else gbad "ai-pending install: rc $rc $(cat "$TMP/pend.out")"; fi
printf 'by = x\n' > "$R/var/lib/invictus/ai-install-pending"; echo off > "$R/etc/invictus/ai"
: > "$TMP/sys.log"; PEND
[[ $rc == 0 && ! -e "$R/var/lib/invictus/ai-install-pending" ]] && ! logged "pacman -Syu" || gbad "ai-pending installed after AI was turned off"
[[ $g_fail == 0 ]] && ok "N1: ai-pending installs at the next connection, keeps trying on failure, and installs nothing if AI was turned off since"
# No safety copy, no change.
new_root aisnap custodia; export_env; echo off > "$R/etc/invictus/ai"
FAKE_SNAPPER_FAIL=1 isys ai on
[[ $rc == 3 && "$(cat "$R/etc/invictus/ai")" == off ]] && ! logged "pacman -Syu" && ok "A5: ai on with no safety copy possible changes nothing (exit 3)" || gbad "ai on without snapshot: rc $rc"

# NA2: ai off. One person who asked (the caller), one other person (root
# run only), and a home that is not its owner's.
new_root aioff libertas; export_env
echo on > "$R/etc/invictus/ai"; echo "full-access = on" > "$R/etc/invictus/assistant"; grd apply
printf 'by = x\n' > "$R/var/lib/invictus/ai-install-pending" 2>/dev/null || { mkdir -p "$R/var/lib/invictus"; printf 'by = x\n' > "$R/var/lib/invictus/ai-install-pending"; }
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
    chown -R 65534:65534 "$HB"; chown -h 65534:65534 "$HB/.claude" "$HB/.claude.json"
    echo "bob:65534:65534:$HB" >> "$TMP/people"
    HC="$R/home/carol"; mkhome "$HC"; chown -R 65533:65533 "$HC"
    echo "carol:65533:65533:$HC" >> "$TMP/people"
fi
mkdir -p "$R/run/user/$me/invictus"; listen_tribune "$R/run/user/$me/invictus/tribune.sock" "$TMP/tribune-ai.got"
: > "$TMP/sys.log"
INVICTUS_PEOPLE="$TMP/people" FAKE_INSTALLED="claude-code invictus-moneta" isys ai off
got "$TMP/tribune-ai.got" >/dev/null
if [[ $rc == 0 && "$(cat "$R/etc/invictus/ai")" == off && "$(stat -c %a "$R/etc/invictus/ai")" == 644 ]] \
   && grep -q 'pkexec action=org.invictus.sys.ai-off ' "$TMP/sys.log" \
   && grep -qx 'full-access = off' "$R/etc/invictus/assistant" && [[ "$(readlink "$R/etc/claude-code/managed-settings.json")" == */fixed.json ]] \
   && [[ ! -e "$R/var/lib/invictus/ai-install-pending" ]] && logged "systemctl disable --now invictus-ai-pending.service" \
   && logged "pacman -Rs --noconfirm -- claude-code invictus-moneta" \
   && [[ "$(snaps | head -1 | cut -d, -f2-3)" == "pre,invictus-sys ai-off " ]] && acta_has "INVICTUS_VERB=ai-off" && acta_has "INVICTUS_RESULT=ok"; then
    ok "NA2: ai off (org.invictus.sys.ai-off): /etc/invictus/ai off (0644), full access off and the fixed profile, the pending install cancelled, the installed AI set removed, pre/post pair, Acta"
else gbad "ai off: rc $rc: $(paste -sd'|' "$TMP/sys.log") out: $(cat "$TMP/sys.out")"; fi
[[ "$(cat "$TMP/tribune-ai.got" 2>/dev/null)" == "stop uid=$me" ]] && ok "N3 step 1: ai off tells the Moneta panel to stop" || gbad "ai off: tribune got '$(cat "$TMP/tribune-ai.got" 2>/dev/null)'"
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
       && [[ -L "$HB/.claude" ]]; then
        ok "ai-off-as-person: links in a person's home reach none of root's files (the clean-up runs as that person); no logout for someone who did not ask"
    else gbad "ai-off-as-person: root followed a person's link: vdir $(ls -A "$TMP/vdir") victim $(cat "$TMP/victim.json")"; fi
    if [[ ! -e "$HC/.claude/.credentials.json" && "$(stat -c %u "$HC/.claude.json")" == 65533 && ! -e "$HC/claude-called" ]] \
       && ! grep -q oauthAccount "$HC/.claude.json" && [[ -f "$HC/.claude/projects/p1/chat.jsonl" ]]; then
        ok "N3: another person's credential file and account block are removed by a process running as them (the rewritten file is theirs), memory kept, no logout run for them"
    else gbad "ai off, other person: $(find "$HC" -maxdepth 2 -printf '%u %p\n' | paste -sd' ')"; fi
fi
chmod 700 "$TMP"
grd apply --check; [[ $rc == 0 ]] || gbad "NA5: after ai off, guardrails check is not consistent: $(cat "$TMP/grd.out")"
isys set-config assistant.full-access on
[[ $rc == 3 ]] && grep -q 'No AI' "$TMP/sys.out" && ok "NA2/NA5: after ai off the rails stay consistent and full access is refused (No AI)" || gbad "full access after ai off: rc $rc"
# A browser policy file that is not ours is never overwritten or removed.
new_root aipol libertas; export_env; grd apply; echo on > "$R/etc/invictus/ai"
mkdir -p "$(dirname "$POL")"; echo '{"policies": {"DisableTelemetry": true}}' > "$POL"
: > "$TMP/people"; INVICTUS_PEOPLE="$TMP/people" isys ai off
k1="$(cat "$POL")"; isys ai on; k2="$(cat "$POL")"
[[ "$k1" == '{"policies": {"DisableTelemetry": true}}' && "$k2" == "$k1" ]] && grep -q 'not locked off' <(INVICTUS_PEOPLE="$TMP/people" bash "$SYS/invictus-sys.sh" ai off 2>&1) \
    && ok "N7: someone else's policies.json is kept by ai off and ai on, and ai off says AI features are not locked" || gbad "foreign browser policy: '$k1' '$k2'"

# SM17 / G2: pre-admin-snapshot.
new_root g2 custodia; export_env
pas() { PAM_TYPE="${PAM_TYPE:-auth}" PAM_SERVICE="${1:-sudo}" PAM_USER=alex bash "$GRD/pre-admin-snapshot.sh"; }
pas sudo; pas sudo
if [[ "$(snaps | wc -l)" == 1 && "$(snaps)" == "1,single,Before: sudo, alex,important=yes" ]] && acta_has "INVICTUS_VERB=pre-admin-snapshot"; then
    ok "SM17: 'Before: sudo, alex' (important) after a good password; a second within 10 minutes adds none; Acta has it"
else gbad "pre-admin-snapshot: $(snaps | paste -sd'|')"; fi
rm -f "$R/run/invictus/pre-admin-snapshot.stamp"
PAM_TYPE=account pas sudo
[[ "$(snaps | wc -l)" == 1 ]] || gbad "pre-admin-snapshot ran for PAM_TYPE=account"
echo libertas > "$R/etc/invictus/guardrails"; echo "pre-admin-snapshot = off" > "$R/etc/invictus/nets"
pas polkit-1
[[ "$(snaps | wc -l)" == 1 ]] || gbad "pre-admin-snapshot ran with the net off under Libertas"
echo custodia > "$R/etc/invictus/guardrails"; pas polkit-1
[[ "$(snaps | tail -1)" == "2,single,Before: polkit-1, alex,important=yes" ]] || gbad "Custodia ignores nets: no snapshot: $(snaps | tail -1)"
rc=0; FAKE_SNAPPER_FAIL=1 PAM_SERVICE=sudo PAM_USER=alex bash "$GRD/pre-admin-snapshot.sh" || rc=$?
[[ $rc == 0 ]] || gbad "pre-admin-snapshot failed the authentication when snapper failed"
rm -f "$R/run/invictus/pre-admin-snapshot.stamp" "$R/run/invictus/pre-admin-snapshot.failed"
PAM_SERVICE='sudo;rm -rf /' PAM_USER='$(id)' bash "$GRD/pre-admin-snapshot.sh"
[[ "$(snaps | tail -1)" == "3,single,Before: sudorm-rf, id,important=yes" ]] || gbad "PAM_SERVICE/PAM_USER not cleaned: $(snaps | tail -1)"
[[ $g_fail == 0 ]] && ok "SM17: only for auth, off only under Libertas with the net off, never fails the password (exit 0)"
# M1 (Janus): a failing snapper costs one wait, not one per password. The
# failure is stamped too and retried after 2 minutes; snapper gets 8 s.
new_root m1 custodia; export_env
: > "$TMP/sys.log"
for _ in 1 2 3; do FAKE_SNAPPER_FAIL=1 pas sudo; done
n_try="$(grep -c 'snapper -c root create' "$TMP/sys.log")"
touch -d '-3 minutes' "$R/run/invictus/pre-admin-snapshot.failed"
FAKE_SNAPPER_FAIL=1 pas sudo
n_try2="$(grep -c 'snapper -c root create' "$TMP/sys.log")"
touch -d '-3 minutes' "$R/run/invictus/pre-admin-snapshot.failed"; pas sudo
if [[ $n_try == 1 && $n_try2 == 2 && "$(snaps | wc -l)" == 1 && -f "$R/run/invictus/pre-admin-snapshot.stamp" && ! -e "$R/run/invictus/pre-admin-snapshot.failed" ]] \
   && [[ "$(grep -c 'INVICTUS_RESULT=failed' "$TMP/acta.log")" == 2 ]]; then
    ok "M1-failure-stamp: three auths with snapper failing call it once; it is tried again after 2 minutes; a later success stamps as usual"
else gbad "M1-failure-stamp: snapper called $n_try then $n_try2 times, snaps $(snaps | wc -l)"; fi
new_root m1t custodia; export_env
t0="$(date +%s)"; rc=0; FAKE_SNAPPER_SLEEP=60 pas sudo || rc=$?; dt=$(( $(date +%s) - t0 ))
[[ $rc == 0 && $dt -le 11 ]] && ok "M1-timeout: a hanging snapper holds the password for ${dt}s (at most about 8), and never fails it" \
    || gbad "M1-timeout: a hanging snapper held the password for ${dt}s (rc $rc)"
new_root m1c libertas; export_env; grd apply; mkdir -p "$R/run/invictus"
touch "$R/run/invictus/pre-admin-snapshot.failed"; SYS_USER=alex grd set custodia
[[ ! -e "$R/run/invictus/pre-admin-snapshot.failed" ]] && ok "M1: the switch to Custodia clears the failure stamp too, so the next admin action tries a copy" \
    || gbad "M1: set custodia left the failure stamp"

# The PAM file: polkit's own lines plus ours, right after auth include.
want_pam="$(printf 'auth include system-auth\nauth optional pam_exec.so quiet type=auth /usr/lib/invictus/pre-admin-snapshot\naccount include system-auth\npassword include system-auth\nsession include system-auth')"
[[ "$(grep -v '^#\|^$' "$GRD/polkit-1.pam" | tr -s ' \t' ' ')" == "$want_pam" ]] \
    && ok "G2: /etc/pam.d/polkit-1 is polkit's file (checked 2026-10-01) plus the pam_exec line after auth include system-auth" || gbad "polkit-1.pam"

# G4 hook text.
new_root hold custodia; export_env
out="$(echo invictus-desktop | bash "$GRD/guardrails.sh" hold-warning; echo "rc=$?")"
echo libertas > "$R/etc/invictus/guardrails"
out2="$(echo invictus-desktop | bash "$GRD/guardrails.sh" hold-warning; echo "rc=$?")"
[[ "$out" == *"invictus-desktop"*"Ask Support"*"rc=0" && "$out2" == "rc=0" ]] && ok "G4: the hook warns with the scam line under Custodia, says nothing under Libertas, always exits 0" || gbad "hold-warning: '$out' '$out2'"

# uninstall: nothing left pointing at removed files.
new_root un custodia; export_env; grd apply; grd uninstall
if [[ ! -e "$D" && ! -e "$R/etc/polkit-1/rules.d/40-invictus-custodia.rules" && ! -L "$R/etc/claude-code/managed-settings.json" ]] \
   && ! grep -q invictus-guardrails "$R/etc/pacman.conf" && ! grep -q pre-admin-snapshot "$R/etc/pam.d/sudo"; then
    ok "pre_remove: the drop-in, tier 1 rule, profile link, Include line and PAM line are taken away"
else gbad "uninstall left something"; fi

# SM23: nothing in the guard rails reads the flavor.
fl="$(grep -rl 'flavor' "$GRD" "$REPO/scripts/lib/guardrails-state.sh" "$REPO/scripts/lib/acta.sh" "$SYS/org.invictus.sys.policy" 2>/dev/null || true)"
[[ -z "$fl" ]] && ok "SM23: no guard-rails file mentions the flavor" || gbad "SM23: flavor in $fl"

# The installer's settings job runs apply when invictus-sys is there (SM24).
grep -q 'in_target invictus-sys guardrails apply' "$REPO/installer/jobs/settings.sh" && ok "SM24: the installer's settings job runs invictus-sys guardrails apply" || gbad "settings.sh no longer runs apply"
echo
unset INVICTUS_SYS_ROOT INVICTUS_LIB FAKE_STATE FAKE_LOG FAKE_DIR ACTA_LOGGER ACTA_LOG FAKE_POLICY INVICTUS_SNAPPER INVICTUS_PACMAN \
    INVICTUS_SYSTEMCTL INVICTUS_SYSTEMD_RUN INVICTUS_PKCHECK INVICTUS_JOURNALCTL INVICTUS_VISUDO INVICTUS_UPDATE INVICTUS_RESTORE \
    INVICTUS_INHIBIT INVICTUS_PKEXEC INVICTUS_SYS_HELPER INVICTUS_GUARDRAILS INVICTUS_PROC INVICTUS_AI_SIGNOUT INVICTUS_CLAUDE
set -e
