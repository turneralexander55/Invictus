#!/usr/bin/env bash
# shellcheck disable=SC2024 # root runs this; the redirects are root's on purpose
# ------------------------------------------------------------
# invictus-sys and invictus-guardrails, built and installed for real in a
# throwaway Arch container, with a real polkitd, pkexec, pacman, sudo's
# visudo and, when it starts, journald:
#
#   podman run --rm -v "$PWD:/src:ro" archlinux:base-devel bash /src/tests/pkgs/e2e-sys.sh
#
#   1. makepkg builds both; pacman -U installs them; the install hook ran
#      guardrails apply (Custodia: drop-in, Include, HoldPkg, tier 1 rule)
#   2. pacman reads the include (HoldPkg) and visudo accepts all of sudoers
#   3. polkitd loads the policy: pkaction shows each action's defaults
#   4. pkexec picks the action by argv[1]: with a test rule that allows only
#      org.invictus.sys.snapshot for one user, `snapshot` runs and
#      `install` does not (the real selection, not the test fake)
#   5. the installed root helper ignores INVICTUS_* overrides
#   6. HoldPkg under Custodia stops `pacman -R --noconfirm` of a held
#      package; after `guardrails set libertas` it goes through
#   7. Acta lands in the journal with its fields (when journald runs here)
#   7a. the Moneta panel installed for real and run as tester: Full access
#      on and the switch to Custodia (the real verbs) restart its agent
#      under the new profile, generic-cli comes and goes from the list, and
#      root's stop ends the panel and its agent; the installed copy ignores
#      INVICTUS_* overrides
#   7b. ai off as root signs a real user out through setpriv (their files,
#      their process), writes the browser policy; the panel's socket is
#      reached as its folder's owner (L1); ai on fails (exit 1, nothing
#      waits) when no repo has the AI set, and goes pending only when no
#      mirror answers; ai-pending exits 1 offline and 2 otherwise (N-L2)
#   8. removing invictus-guardrails takes the derived files and lines away
#      and pacman still works
# Not here (no logind session in a container): subject.local/active, so
# tier 1 and the guard-rails-on rule are checked by tests/pkgs/sys.sh and
# by Janus on a VM. snapper is a stub (no btrfs in a container).
# Never run it on a real machine: it edits /etc and replaces snapper.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC="${1:-/src}"

fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

pacman -Syu --noconfirm --needed base-devel polkit snapper sudo python dbus >/dev/null 2>&1

WORK="$(mktemp -d)"
cp -r "$SRC/." "$WORK/src"
useradd -m builder 2>/dev/null || true
useradd -m tester 2>/dev/null || true
chown -R builder "$WORK"
for p in invictus-sys invictus-guardrails; do
    (cd "$WORK/src/pkgs/own/$p" && sudo -u builder PKGDEST="$WORK/out" makepkg -d --noconfirm >"$WORK/make-$p.log" 2>&1) \
        || { echo "makepkg $p failed:"; tail -20 "$WORK/make-$p.log"; exit 1; }
done
# Janus P-L2: this machine starts as a dev install did, with the unowned
# mask the old installer wrote. lib/pacman.sh's ssh_mask_overwrite (what
# invictus-update and the install verb call) must give real pacman the
# one --overwrite that lets invictus-sys take the link over.
mkdir -p /etc/systemd/system-generators
ln -sfn /dev/null /etc/systemd/system-generators/systemd-ssh-generator
# shellcheck source=scripts/lib/pacman.sh
PACMAN=pacman; PACMAN_OVERWRITE=(); . "$WORK/src/scripts/lib/pacman.sh"
declare -F ssh_mask_overwrite >/dev/null && ssh_mask_overwrite
if [[ "${PACMAN_OVERWRITE[*]}" == "--overwrite /etc/systemd/system-generators/systemd-ssh-generator" ]]; then
    ok "P-L2: an unowned mask link gets exactly --overwrite /etc/systemd/system-generators/systemd-ssh-generator"
else bad "P-L2: ssh_mask_overwrite gave '${PACMAN_OVERWRITE[*]}'"; fi
if pacman -U --noconfirm "${PACMAN_OVERWRITE[@]}" "$WORK"/out/invictus-sys-*.pkg.tar.zst "$WORK"/out/invictus-guardrails-*.pkg.tar.zst >"$WORK/install.log" 2>&1; then
    ok "makepkg builds invictus-sys and invictus-guardrails; pacman -U installs them"
else
    bad "install: $(tail -5 "$WORK/install.log")"; exit 1
fi
# sshd off on every machine, adopted ones too (design-simple-mode 1.3, SM2;
# Janus I-2): invictus-sys owns the systemd-ssh-generator mask.
gm=/etc/systemd/system-generators/systemd-ssh-generator
if [[ -L "$gm" && "$(readlink "$gm")" == /dev/null ]] && [[ "$(pacman -Qqo "$gm" 2>/dev/null)" == invictus-sys ]]; then
    ok "SM2: invictus-sys owns $gm -> /dev/null (pacman -Qo), so an adopted install gets the mask too"
else
    bad "SM2: $gm: $(ls -l "$gm" 2>&1) owner: $(pacman -Qo "$gm" 2>&1)"
fi
ssh_mask_overwrite
[[ ${#PACMAN_OVERWRITE[@]} == 0 ]] && ok "P-L2: once invictus-sys owns the mask, no --overwrite" \
    || bad "P-L2: still --overwrite after the install: ${PACMAN_OVERWRITE[*]}"
# Janus N-L1: the hook the profiles call is the /bin/sh wrapper; the guard
# beside it is 0644 (nothing runs it without the wrapper). Run as tester:
# a denied file gives 2, an allowed one 0.
G=/usr/lib/invictus/claude-config-guard
tg="$(getent passwd tester | cut -d: -f6)"
mkdir -p "$tg/.config/waybar"; chown -R tester "$tg/.config"
g_deny="$(printf '{"tool_input": {"file_path": "%s/.bashrc"}}' "$tg" | sudo -u tester "$G" pre fixed >/dev/null 2>&1; echo $?)"
g_ok="$(printf '{"tool_input": {"file_path": "%s/.config/waybar/x.css"}}' "$tg" | sudo -u tester "$G" pre fixed >/dev/null 2>&1; echo $?)"
if [[ "$(head -1 "$G")" == "#!/bin/sh" && "$(stat -c '%U %a' "$G")" == "root 755" && "$(stat -c '%U %a' "$G.py")" == "root 644" \
      && "$g_deny" == 2 && "$g_ok" == 0 ]]; then
    ok "N-L1: the installed hook is the /bin/sh wrapper (0755) around claude-config-guard.py (0644); as tester ~/.bashrc 2, waybar/x.css 0"
else
    bad "N-L1 installed guard: $(head -1 "$G") $(stat -c '%U %a %n' "$G" "$G.py" 2>&1 | paste -sd' '), deny $g_deny, allow $g_ok"
fi

# 1. The install hook applied Custodia (no guardrails file yet: custodia).
if [[ "$(cat /etc/invictus/guardrails)" == custodia && -f /etc/sudoers.d/40-invictus-guardrails \
      && -f /etc/polkit-1/rules.d/40-invictus-custodia.rules && -L /etc/claude-code/managed-settings.json ]] \
   && grep -qx 'Include = /etc/pacman.d/invictus-guardrails.conf' /etc/pacman.conf \
   && grep -q pre-admin-snapshot /etc/pam.d/sudo && /usr/lib/invictus/guardrails apply --check >/dev/null; then
    ok "post_install ran guardrails apply: Custodia files in place, apply --check consistent"
else
    bad "after install: $(/usr/lib/invictus/guardrails apply --check 2>&1 | head -5)"
fi
# The doctor runs `guardrails check` as the person, who cannot look into
# /etc/sudoers.d or /etc/polkit-1/rules.d: the rest still reads consistent.
if sudo -u tester /usr/lib/invictus/guardrails apply --check > "$WORK/check.out" 2>&1 \
   && grep -q 'not checked as tester: /etc/sudoers.d/40-invictus-guardrails /etc/polkit-1/rules.d/40-invictus-custodia.rules' "$WORK/check.out"; then
    ok "guardrails check as an ordinary user: consistent, and names the two root-only files it could not see"
else
    bad "guardrails check as tester: $(sudo -u tester /usr/lib/invictus/guardrails apply --check 2>&1 | head -3)"
fi
# 2. pacman and sudo read what apply wrote.
if pacman-conf HoldPkg | grep -x invictus-desktop >/dev/null && visudo -cq; then
    ok "pacman-conf lists the Custodia HoldPkg names; visudo -c accepts the whole sudoers tree"
else
    bad "HoldPkg or visudo: $(pacman-conf HoldPkg | paste -sd' '); $(visudo -c 2>&1 | tail -2)"
fi

# snapper stub (no btrfs here): create prints the next number, list is csv.
cat > /usr/bin/snapper <<'EOF'
#!/bin/bash
f=/var/tmp/snaps
[[ "$1" == --csvout ]] && { shift; csv=1; }
[[ "$1" == -c ]] && shift 2
case "$1" in
  create) n=$(( $(wc -l < "$f" 2>/dev/null || echo 0) + 1 )); echo "$n,$*" >> "$f"; echo "$n" ;;
  list) echo number,type; awk -F, '{ print $1 ",single" }' "$f" 2>/dev/null ;;
esac
EOF
chmod 755 /usr/bin/snapper

# 3. polkitd with the policy loaded.
mkdir -p /run/dbus
dbus-daemon --system --fork >/dev/null 2>&1 || true
/usr/lib/polkit-1/polkitd --no-debug >"$WORK/polkitd.log" 2>&1 &
for _ in $(seq 50); do pkaction >/dev/null 2>&1 && break; sleep 0.2; done
pa() { pkaction --verbose --action-id "org.invictus.sys.$1" 2>/dev/null | sed -n 's/^ *implicit active: *//p'; }
if [[ "$(pa install)" == auth_admin_keep && "$(pa guardrails-libertas)" == auth_admin && "$(pa assistant-full-access)" == auth_admin \
      && "$(pa update)" == auth_admin_keep ]]; then
    ok "polkitd loads org.invictus.sys.policy: install/update auth_admin_keep, guardrails-libertas and full access auth_admin"
else
    bad "pkaction: install '$(pa install)', libertas '$(pa guardrails-libertas)'; polkitd: $(tail -3 "$WORK/polkitd.log")"
fi

# 4. Real pkexec picks the action from argv[1].
cat > /etc/polkit-1/rules.d/10-e2e.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user == "tester" && action.id == "org.invictus.sys.snapshot") return polkit.Result.YES;
    if (subject.user == "tester" && action.id.indexOf("org.invictus.") == 0) return polkit.Result.NO;
});
EOF
sleep 1
rc=0; sudo -u tester invictus-sys snapshot "e2e copy" > "$WORK/snap.out" 2>&1 || rc=$?
rc2=0; sudo -u tester invictus-sys install vlc > "$WORK/inst.out" 2>&1 || rc2=$?
if [[ $rc == 0 ]] && grep -q 'invictus-sys: ok snapshot=1' "$WORK/snap.out" && grep -q 'e2e copy' /var/tmp/snaps \
   && [[ $rc2 != 0 ]] && ! pacman -Q vlc >/dev/null 2>&1; then
    ok "pkexec: org.invictus.sys.snapshot allowed runs the snapshot verb; the same user's install (org.invictus.sys.install, denied) runs nothing (exit $rc2)"
else
    bad "pkexec selection: snapshot rc $rc '$(cat "$WORK/snap.out")', install rc $rc2 '$(cat "$WORK/inst.out")'"
fi
rm -f /etc/polkit-1/rules.d/10-e2e.rules

# 5. The installed root helper ignores test overrides, even from root.
printf '#!/bin/sh\ntouch /tmp/evil-ran\n' > /tmp/evil; chmod 755 /tmp/evil
rc=0; INVICTUS_SNAPPER=/tmp/evil INVICTUS_LIB=/tmp ACTA_LOGGER=/tmp/evil /usr/lib/invictus/invictus-sys snapshot "override test" >/dev/null 2>&1 || rc=$?
if [[ $rc == 0 && ! -e /tmp/evil-ran ]] && grep -q 'override test' /var/tmp/snaps; then
    ok "the installed root helper drops INVICTUS_*/ACTA_* overrides (the real snapper stub ran, /tmp/evil did not)"
else
    bad "override drop: rc $rc, evil ran: $([[ -e /tmp/evil-ran ]] && echo yes || echo no)"
fi

# 6. HoldPkg under Custodia, gone under Libertas.
mkdir -p "$WORK/held" && cat > "$WORK/held/PKGBUILD" <<'EOF'
pkgname=invictus-desktop
pkgver=9999
pkgrel=1
arch=('any')
package() { mkdir -p "$pkgdir/usr/share/e2e"; }
EOF
chown -R builder "$WORK/held"
(cd "$WORK/held" && sudo -u builder PKGDEST="$WORK/held" makepkg --noconfirm >/dev/null 2>&1)
pacman -U --noconfirm "$WORK"/held/invictus-desktop-9999-*.pkg.tar.zst >/dev/null 2>&1
rc=0; pacman -R --noconfirm invictus-desktop > "$WORK/hold.log" 2>&1 || rc=$?
if [[ $rc != 0 ]] && pacman -Q invictus-desktop >/dev/null 2>&1; then
    ok "Custodia: pacman -R --noconfirm invictus-desktop stops at HoldPkg (exit $rc)"
else
    bad "HoldPkg did not hold: rc $rc: $(tail -3 "$WORK/hold.log")"
fi
invictus-sys guardrails set libertas > "$WORK/lib.log" 2>&1 || bad "set libertas as root: $(cat "$WORK/lib.log")"
rc=0; pacman -R --noconfirm invictus-desktop > "$WORK/hold2.log" 2>&1 || rc=$?
if [[ $rc == 0 && "$(cat /etc/invictus/guardrails)" == libertas && ! -e /etc/sudoers.d/40-invictus-guardrails ]] \
   && grep -q 'Before: guard rails off' /var/tmp/snaps; then
    ok "Libertas (snapshot 'Before: guard rails off' first): the hold is gone and the removal goes through"
else
    bad "after libertas: rc $rc: $(tail -3 "$WORK/hold2.log")"
fi

# 7. Acta in the journal, when journald can run in this container.
if [[ -x /usr/lib/systemd/systemd-journald ]]; then
    /usr/lib/systemd/systemd-journald >/dev/null 2>&1 &
    for _ in $(seq 25); do [[ -S /run/systemd/journal/socket ]] && break; sleep 0.2; done
fi
if [[ -S /run/systemd/journal/socket ]]; then
    invictus-sys --request e2e-thread snapshot "acta test" >/dev/null 2>&1
    sleep 1
    j="$(journalctl -t invictus-sys -o json --no-pager 2>/dev/null | tail -1)"
    if python3 -c 'import json,sys; e=json.loads(sys.argv[1]); assert e["INVICTUS_VERB"]=="snapshot" and e["INVICTUS_REQUEST"]=="e2e-thread" and e["INVICTUS_SNAPSHOT"].isdigit() and e["INVICTUS_RESULT"]=="ok"' "$j" 2>/dev/null; then
        ok "Acta: journalctl -t invictus-sys -o json has verb, request id, snapshot and result as fields"
    else
        bad "Acta entry: $j"
    fi
else
    echo "note  journald does not run in this container: Acta's journal fields are checked on a VM"
fi

# 7a. The Moneta panel, installed for real (its desktop depends skipped:
# no kitty or Hyprland here), run as tester, driven by the real verbs: Full
# access on restarts it with the full profile, the switch to Custodia
# restarts it with the fixed one and takes generic-cli off the list, and
# `guardrails signal stop` ends it and its agent (SM10, SM26, G7, A8).
tu="$(id -u tester)"; th="$(getent passwd tester | cut -d: -f6)"
(cd "$WORK/src/pkgs/own/invictus-tribune" && sudo -u builder PKGDEST="$WORK/out" makepkg -d --noconfirm >"$WORK/make-tribune.log" 2>&1) \
    || bad "makepkg invictus-tribune: $(tail -5 "$WORK/make-tribune.log")"
if pacman -U -dd --noconfirm "$WORK"/out/invictus-tribune-*.pkg.tar.zst >"$WORK/tribune-install.log" 2>&1 \
   && [[ "$(stat -c '%U %a' /usr/lib/invictus/moneta/moneta.py /usr/lib/invictus/moneta/mcp.py /usr/lib/invictus/claude-config-guard | sort -u)" == "root 755" ]] \
   && [[ "$(stat -c '%U %a' /usr/share/invictus/providers/*/provider.toml /usr/share/invictus/guardrails/claude/*.json | sort -u)" == "root 644" ]] \
   && [[ "$(stat -c '%U %a' /etc/claude-code /usr/share/invictus/claude-plugin /usr/share/invictus/providers)" == "$(printf 'root 755\nroot 755\nroot 755')" ]] \
   && [[ "$(readlink -f /usr/bin/tribune)" == /usr/lib/invictus/moneta/moneta.py ]]; then
    ok "A8: invictus-tribune installs root-owned: panel 0755, providers and both profiles 0644, /etc/claude-code 0755 (no drop-ins from a home)"
else
    bad "invictus-tribune install: $(tail -3 "$WORK/tribune-install.log") $(stat -c '%U %a %n' /usr/lib/invictus/moneta/* /etc/claude-code 2>&1 | paste -sd' ')"
fi
echo on > /etc/invictus/ai   # AI on without the package install; ai on itself is 7b's
printf '#!/bin/bash\necho "$$" >> /tmp/claude.pids\nexec sleep 300\n' > /usr/bin/claude
chmod 755 /usr/bin/claude
: > /tmp/claude.pids; chmod 666 /tmp/claude.pids
mkdir -p "/run/user/$tu"; chown tester "/run/user/$tu"; chmod 700 "/run/user/$tu"
offered() { sudo -u tester env XDG_RUNTIME_DIR="/run/user/$tu" HOME="$th" "$@" invictus-provider list --json \
            | python3 -c 'import json,sys; print(" ".join(sorted(x["name"] for x in json.load(sys.stdin) if x["offered"])))'; }
# waitfor CODE: CODE is evaluated on each try, so callers single-quote it.
waitfor() { for _ in $(seq 1 100); do eval "$1" && return 0; sleep 0.1; done; return 1; }
sudo -u tester env XDG_RUNTIME_DIR="/run/user/$tu" HOME="$th" tribune run < /dev/null > /tmp/tribune.log 2>&1 &
tpid=$!
# shellcheck disable=SC2016 # evaluated on each try
if waitfor '[[ -S /run/user/$tu/invictus/tribune.sock && -s /tmp/claude.pids ]]' && [[ "$(offered)" == "claude-code none openai-compatible" ]]; then
    ok "tribune runs as tester with the shipped claude-code provider; Libertas without Full access offers no command-line agent"
else bad "tribune start: $(cat /tmp/tribune.log) offered '$(offered)'"; fi
c1="$(head -1 /tmp/claude.pids)"
invictus-sys set-config assistant.full-access on > "$WORK/fa.log" 2>&1 || bad "full access on: $(cat "$WORK/fa.log")"
# shellcheck disable=SC2016 # evaluated on each try
if waitfor '[[ $(grep -c "started claude-code" /tmp/tribune.log) == 2 ]]' && ! kill -0 "$c1" 2>/dev/null \
   && [[ "$(readlink /etc/claude-code/managed-settings.json)" == */full.json && "$(offered)" == "claude-code generic-cli none openai-compatible" ]]; then
    ok "SM26: Full access on (real verb) restarts the panel's agent under the full profile (old pid gone) and offers generic-cli"
else bad "full access restart: $(cat /tmp/tribune.log) link $(readlink /etc/claude-code/managed-settings.json) offered '$(offered)'"; fi
if [[ "$(offered INVICTUS_GUARDRAILS=/bin/false INVICTUS_PROVIDERS_DIR=/tmp)" == "claude-code generic-cli none openai-compatible" ]]; then
    ok "the installed invictus-provider ignores INVICTUS_* overrides (state and providers are the root-owned ones)"
else bad "installed copy honoured an override: '$(offered INVICTUS_GUARDRAILS=/bin/false INVICTUS_PROVIDERS_DIR=/tmp)'"; fi
c2="$(sed -n 2p /tmp/claude.pids)"
invictus-sys guardrails set custodia > "$WORK/cust.log" 2>&1 || bad "set custodia: $(cat "$WORK/cust.log")"
# shellcheck disable=SC2016 # evaluated on each try
if waitfor '[[ $(grep -c "started claude-code" /tmp/tribune.log) == 3 ]]' && ! kill -0 "$c2" 2>/dev/null \
   && [[ "$(readlink /etc/claude-code/managed-settings.json)" == */fixed.json && "$(offered)" == "claude-code none openai-compatible" ]]; then
    ok "SM10/SM21: the switch to Custodia restarts the agent under the fixed profile; generic-cli is offered nowhere"
else bad "custodia restart: $(cat /tmp/tribune.log) offered '$(offered)'"; fi
/usr/lib/invictus/guardrails signal stop > "$WORK/stop.log" 2>&1
if waitfor "! kill -0 $tpid 2>/dev/null" && ! pgrep -u tester -f 'sleep 300' >/dev/null && [[ ! -e "/run/user/$tu/invictus/tribune.sock" ]] \
   && grep -q 'told 1 Moneta panel' "$WORK/stop.log"; then
    ok "NA2/G7: root's stop reaches the real panel through setpriv; the panel, its agent and its socket are gone"
else bad "stop: $(cat "$WORK/stop.log") $(cat /tmp/tribune.log) $(pgrep -u tester -a 2>&1 | paste -sd' ')"; fi
rm -f /usr/bin/claude
invictus-sys guardrails set libertas > /dev/null 2>&1 || true

# 7b. ai on|off (design-no-ai.md N1, N3) with the real passwd, setpriv and
# pacman. pkaction first, then the verbs as root (no logind session here).
# Real pacman decides from here on. systemd-inhibit needs logind, which does
# not run here (it failed, so before this stub pacman never ran in these
# checks, and ai off never removed anything): a pass-through stand-in, like
# the snapper stub.
mv /usr/bin/systemd-inhibit /usr/bin/systemd-inhibit.real
# shellcheck disable=SC2016 # the stand-in's own text
printf '#!/bin/bash\nwhile [[ "$1" == --* ]]; do shift; done\nexec "$@"\n' > /usr/bin/systemd-inhibit
chmod 755 /usr/bin/systemd-inhibit
if [[ "$(pa ai-on)" == auth_admin && "$(pa ai-off)" == auth_admin ]]; then
    ok "polkitd: org.invictus.sys.ai-on and ai-off are auth_admin with no keep (ai-off's YES at your own desktop is the rules file's)"
else
    bad "pkaction ai-on '$(pa ai-on)', ai-off '$(pa ai-off)'"
fi
th="$(getent passwd tester | cut -d: -f6)"; tu="$(id -u tester)"
sudo -u tester mkdir -p "$th/.claude/projects/p"
sudo -u tester sh -c 'echo "{}" > ~/.claude/.credentials.json; echo "{\"numStartups\": 2, \"oauthAccount\": {\"e\": 1}}" > ~/.claude.json; echo m > ~/.claude/projects/p/c'
# L1: the panel's socket in tester's /run/user folder; root connects as tester.
mkdir -p "/run/user/$tu/invictus"; chown -R tester "/run/user/$tu"
sudo -u tester python3 -c '
import socket, struct, sys, os
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1); s.settimeout(20)
if os.fork() == 0:
    c, _ = s.accept(); uid = struct.unpack("3i", c.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[1]
    open("/tmp/tribune.got", "w").write("%s uid=%d" % (c.recv(100).decode().strip(), uid)); os._exit(0)
' "/run/user/$tu/invictus/tribune.sock"
rc=0; invictus-sys ai off > "$WORK/aioff.out" 2>&1 || rc=$?
sleep 0.5
if [[ $rc == 0 && "$(cat /etc/invictus/ai)" == off && ! -e "$th/.claude/.credentials.json" && -f "$th/.claude/projects/p/c" ]] \
   && [[ "$(stat -c %U "$th/.claude.json")" == tester ]] && ! grep -q oauthAccount "$th/.claude.json" && grep -q numStartups "$th/.claude.json" \
   && [[ -f /etc/firefox/policies/policies.json && -f "/var/lib/invictus/ai-off-pending/$tu" ]] \
   && ! pacman -Q invictus-tribune >/dev/null 2>&1; then
    ok "ai off as root: tester's credential file and account block removed by a process running as tester (real setpriv), memory kept, browser policy and pending marker written, the Moneta panel package removed"
else
    bad "ai off: rc $rc: $(cat "$WORK/aioff.out"); $(find "$th" -maxdepth 2 -printf '%u %p\n' 2>&1 | paste -sd' ')"
fi
if [[ "$(cat /tmp/tribune.got 2>/dev/null)" == "stop uid=$tu" ]]; then ok "L1: root reached the panel's socket as its folder's owner (uid $tu), with stop"
else bad "L1 real setpriv: tribune got '$(cat /tmp/tribune.got 2>/dev/null)'"; fi
# The AI set is in no configured repo here: that is not a download
# failure, so ai on fails and nothing waits.
rc=0; invictus-sys ai on > "$WORK/aion.out" 2>&1 || rc=$?
if [[ $rc == 1 && "$(cat /etc/invictus/ai)" == on && ! -e /var/lib/invictus/ai-install-pending && ! -e /etc/firefox/policies/policies.json ]] \
   && [[ -z "$(ls -A /var/lib/invictus/ai-off-pending)" ]] \
   && grep -q 'Update first' "$WORK/aion.out" && grep -q 'invictus-sys: failed' "$WORK/aion.out" \
   && grep -q 'target not found: invictus-moneta' "$WORK/aion.out"; then
    ok "ai on with the AI set in no configured repo (real pacman): failed, exit 1, no pending marker; AI reads on, our browser policy and the ai-off markers are gone"
else
    bad "ai on, not in a repo: rc $rc: $(tail -3 "$WORK/aion.out")"
fi
# No mirror answers (connection refused): pacman 7's own lines must read as
# a download failure, so ai on waits for the connection.
cp /etc/pacman.d/mirrorlist "$WORK/mirrorlist"
# shellcheck disable=SC2016 # pacman expands $repo and $arch
echo 'Server = http://127.0.0.1:9/$repo/os/$arch' > /etc/pacman.d/mirrorlist
rc=0; invictus-sys ai on > "$WORK/aion2.out" 2>&1 || rc=$?
if [[ $rc == 0 && -f /var/lib/invictus/ai-install-pending ]] && grep -q 'invictus-sys: pending' "$WORK/aion2.out" \
   && grep -q 'failed to synchronize all databases' "$WORK/aion2.out"; then
    ok "ai on with no mirror reachable (real pacman): pending, the install waits for the connection"
else
    bad "ai on offline: rc $rc: $(tail -4 "$WORK/aion2.out")"
fi
rc=0; /usr/lib/invictus/ai-pending > "$WORK/pend1.out" 2>&1 || rc=$?
if [[ $rc == 1 && -f /var/lib/invictus/ai-install-pending ]]; then ok "ai-pending with no mirror reachable: exit 1 (the unit tries again), marker kept"
else bad "ai-pending offline: rc $rc: $(tail -3 "$WORK/pend1.out")"; fi
cp "$WORK/mirrorlist" /etc/pacman.d/mirrorlist
rc=0; /usr/lib/invictus/ai-pending > "$WORK/pend2.out" 2>&1 || rc=$?
if [[ $rc == 2 ]]; then ok "ai-pending online with the AI set in no repo: exit 2 (RestartPreventExitStatus, no retry loop)"
else bad "ai-pending, not a download failure: rc $rc: $(tail -3 "$WORK/pend2.out")"; fi
mv -f /usr/bin/systemd-inhibit.real /usr/bin/systemd-inhibit

# 8. Removing the guard rails leaves nothing pointing at removed files.
pacman -R --noconfirm invictus-guardrails > "$WORK/rm.log" 2>&1 || bad "remove invictus-guardrails: $(tail -3 "$WORK/rm.log")"
if ! grep -q invictus-guardrails /etc/pacman.conf && ! grep -q pre-admin-snapshot /etc/pam.d/sudo \
   && [[ ! -e /etc/sudoers.d/40-invictus-guardrails && ! -e /etc/claude-code/managed-settings.json ]] \
   && pacman -Q pacman >/dev/null 2>&1 && pacman-conf >/dev/null 2>&1 && visudo -cq; then
    ok "removing invictus-guardrails takes the Include, PAM line, drop-in and profile link away; pacman and sudo still work"
else
    bad "after removal: $(grep -n invictus /etc/pacman.conf /etc/pam.d/sudo 2>&1 | head -3)"
fi

if [[ $fail == 0 ]]; then echo "e2e-sys: ALL PASSED"; else echo "e2e-sys: SOME TESTS FAILED"; fi
exit $fail
