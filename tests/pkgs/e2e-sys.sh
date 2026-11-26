#!/usr/bin/env bash
# shellcheck disable=SC2024 # root runs this; the redirects are root's on purpose
# ------------------------------------------------------------
# invictus-sys, built and installed for real in a
# throwaway Arch container, with a real polkitd, pkexec, pacman, sudo's
# visudo and, when it starts, journald:
#
#   podman run --rm -v "$PWD:/src:ro" archlinux:base-devel bash /src/tests/pkgs/e2e-sys.sh
#
#   1. makepkg builds it; pacman -U installs it
#   3. polkitd loads the policy: pkaction shows each action's defaults
#   4. pkexec picks the action by argv[1]: with a test rule that allows only
#      org.invictus.sys.snapshot for one user, `snapshot` runs and
#      `install` does not (the real selection, not the test fake)
#   5. the installed root helper ignores INVICTUS_* overrides
#   7. Acta lands in the journal with its fields (when journald runs here)
#   7a. the Cicero panel installed for real and run as tester; the
#      installed copy ignores INVICTUS_* overrides
#   7a2. R2: the real Claude Code (our pin, no account) connects the
#      --plugin-dir plugin's server; the server answers doctor
#   7b. ai off as root signs a real user out through setpriv (their files,
#      their process), writes the browser policy; ai on fails (exit 1, nothing
#      waits) when no repo has the AI set, and goes pending only when no
#      mirror answers; ai-pending exits 1 offline and 2 otherwise (N-L2)
# Not here (no logind session in a container): subject.local/active, so
# those answers are checked by tests/pkgs/sys.sh and by Janus on a VM. snapper is a stub (no btrfs in a container).
# Never run it on a real machine: it edits /etc and replaces snapper.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC="${1:-/src}"

fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

pacman -Syu --noconfirm --needed base-devel polkit snapper sudo python dbus jq >/dev/null 2>&1

WORK="$(mktemp -d)"
cp -r "$SRC/." "$WORK/src"
useradd -m builder 2>/dev/null || true
useradd -m tester 2>/dev/null || true
chown -R builder "$WORK"
(cd "$WORK/src/pkgs/own/invictus-sys" && sudo -u builder PKGDEST="$WORK/out" makepkg -d --noconfirm >"$WORK/make-invictus-sys.log" 2>&1) \
    || { echo "makepkg invictus-sys failed:"; tail -20 "$WORK/make-invictus-sys.log"; exit 1; }
# Janus P-L2: this machine starts as a dev install did, with the unowned
# mask the old installer wrote. lib/pacman.sh's ssh_mask_overwrite (what
# invictus-update and the install verb call) must give real pacman the
# one --overwrite that lets invictus-sys take the link over.
mkdir -p /etc/systemd/system-generators
ln -sfn /dev/null /etc/systemd/system-generators/systemd-ssh-generator
# shellcheck disable=SC2034 # PACMAN is read by lib/pacman.sh
PACMAN=pacman; PACMAN_OVERWRITE=()
# shellcheck source=scripts/lib/pacman.sh
. "$WORK/src/scripts/lib/pacman.sh"
declare -F ssh_mask_overwrite >/dev/null && ssh_mask_overwrite
if [[ "${PACMAN_OVERWRITE[*]}" == "--overwrite /etc/systemd/system-generators/systemd-ssh-generator" ]]; then
    ok "P-L2: an unowned mask link gets exactly --overwrite /etc/systemd/system-generators/systemd-ssh-generator"
else bad "P-L2: ssh_mask_overwrite gave '${PACMAN_OVERWRITE[*]}'"; fi
if pacman -U --noconfirm "${PACMAN_OVERWRITE[@]}" "$WORK"/out/invictus-sys-*.pkg.tar.zst >"$WORK/install.log" 2>&1; then
    ok "makepkg builds invictus-sys; pacman -U installs it"
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
if [[ ${#PACMAN_OVERWRITE[@]} == 0 ]]; then ok "P-L2: once invictus-sys owns the mask, no --overwrite"
else bad "P-L2: still --overwrite after the install: ${PACMAN_OVERWRITE[*]}"; fi
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
if [[ "$(pa install)" == auth_admin_keep && "$(pa update)" == auth_admin_keep ]]; then
    ok "polkitd loads org.invictus.sys.policy: install/update auth_admin_keep"
else
    bad "pkaction: install '$(pa install)', update '$(pa update)'; polkitd: $(tail -3 "$WORK/polkitd.log")"
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

# 7a. The Cicero panel, installed for real (its desktop depends skipped:
# no kitty or Hyprland here), run as tester (A8).
tu="$(id -u tester)"; th="$(getent passwd tester | cut -d: -f6)"
(cd "$WORK/src/pkgs/own/invictus-tribune" && sudo -u builder PKGDEST="$WORK/out" makepkg -d --noconfirm >"$WORK/make-tribune.log" 2>&1) \
    || bad "makepkg invictus-tribune: $(tail -5 "$WORK/make-tribune.log")"
if pacman -U -dd --noconfirm "$WORK"/out/invictus-tribune-*.pkg.tar.zst >"$WORK/tribune-install.log" 2>&1 \
   && [[ "$(stat -c '%U %a' /usr/lib/invictus/cicero/cicero.py /usr/lib/invictus/cicero/mcp.py | sort -u)" == "root 755" ]] \
   && [[ "$(stat -c '%U %a' /usr/share/invictus/providers/*/provider.toml | sort -u)" == "root 644" ]] \
   && [[ "$(stat -c '%U %a' /usr/share/invictus/claude-plugin /usr/share/invictus/providers)" == "$(printf 'root 755\nroot 755')" ]] \
   && [[ "$(readlink -f /usr/bin/tribune)" == /usr/lib/invictus/cicero/cicero.py ]]; then
    ok "A8: invictus-tribune installs root-owned: panel 0755, providers 0644"
else
    bad "invictus-tribune install: $(tail -3 "$WORK/tribune-install.log") $(stat -c '%U %a %n' /usr/lib/invictus/cicero/* 2>&1 | paste -sd' ')"
fi
# R2 (Minerva, release review 2c): the real Claude Code (our pin) loads our
# --plugin-dir plugin's MCP server, as the panel starts it. No account and no credentials: Anthropic's
# and claude.ai's hosts point nowhere while it runs, no proxy variable is
# passed, and nothing here signs in. A tool call through Claude Code needs a
# signed-in account ("Not logged in · Please run /login"), so the doctor is
# asked over JSON-RPC from the same installed command Claude Code connected.
sudo -u builder gpg --import "$WORK/src/pkgs/aur/claude-code/keys/pgp/"*.asc >/dev/null 2>&1
for p in aur/claude-code own/invictus-tools; do
    (cd "$WORK/src/pkgs/$p" && sudo -u builder PKGDEST="$WORK/out" makepkg -d --noconfirm >"$WORK/make-r2.log" 2>&1) \
        || bad "R2: makepkg $p: $(tail -5 "$WORK/make-r2.log")"
done
pacman -U -dd --noconfirm "$WORK"/out/claude-code-*.pkg.tar.zst "$WORK"/out/invictus-tools-*.pkg.tar.zst >"$WORK/r2-install.log" 2>&1 \
    || bad "R2: install claude-code, invictus-tools: $(tail -3 "$WORK/r2-install.log")"
cp /etc/hosts "$WORK/hosts"
for h in api.anthropic.com anthropic.com console.anthropic.com statsig.anthropic.com mcp-proxy.anthropic.com \
    claude.ai www.claude.ai downloads.claude.ai claude.com platform.claude.com; do echo "0.0.0.0 $h" >> /etc/hosts; done
mkdir -p "$th/r2"; chown tester "$th/r2"
cc() { (cd "$th/r2" && timeout 120 sudo -u tester env -i HOME="$th" USER=tester PATH=/usr/bin:/bin TERM=dumb \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 /usr/bin/claude "$@" 2>&1); }
PLUG=(--plugin-dir /usr/share/invictus/claude-plugin)
r2list="$(cc "${PLUG[@]}" mcp list)" || true
r2get="$(cc "${PLUG[@]}" mcp get plugin:invictus:invictus)" || true
if grep -qx 'plugin:invictus:invictus: /usr/bin/python3 -I /usr/lib/invictus/cicero/mcp.py - ✔ Connected' <<< "$r2list" \
   && grep -q 'Status: ✔ Connected' <<< "$r2get"; then
    ok "R2: claude-code $(pacman -Q claude-code | cut -d' ' -f2) connects the --plugin-dir plugin's invictus server"
else bad "R2: mcp list: $(paste -sd'|' <<< "$r2list") get: $(paste -sd'|' <<< "$r2get" | cut -c1-200)"; fi
r2p="$(cc "${PLUG[@]}" -p "run the doctor tool" --output-format text)" || true
r2doc="$(printf '%s\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"doctor","arguments":{}}}' \
    | timeout 120 sudo -u tester env -i HOME="$th" PATH=/usr/bin:/bin /usr/bin/python3 -I /usr/lib/invictus/cicero/mcp.py)" || true
r2txt="$(python3 -c 'import json, sys
for line in sys.stdin:
    m = json.loads(line)
    if m.get("id") == 1:
        print("".join(c.get("text", "") for c in m["result"]["content"]))' <<< "$r2doc" 2>&1)" || true
if grep -qE '^(ok|warn|FAIL|note) +(snapshots|repo): ' <<< "$r2txt" && grep -qE '^(ok|warn|FAIL|note) +hypr: ' <<< "$r2txt"; then
    ok "R2: the installed server answers doctor with the real invictus-doctor's report (Claude Code itself: '$r2p', so a tool call needs a signed-in account)"
else bad "R2: doctor over JSON-RPC: $(head -c 600 <<< "$r2txt")"; fi
cat "$WORK/hosts" > /etc/hosts
rm -rf "$th/.claude.json" "$th/.claude" "$th/.cache/claude-cli-nodejs" "$th/r2"
pacman -R -dd --noconfirm invictus-tools claude-code >/dev/null 2>&1 || bad "R2: could not remove invictus-tools, claude-code"
mkdir -p /etc/invictus; echo on > /etc/invictus/ai   # AI on without the package install; ai on itself is 7b's
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
if waitfor '[[ -S /run/user/$tu/invictus/tribune.sock && -s /tmp/claude.pids ]]' && [[ "$(offered)" == "claude-code generic-cli none openai-compatible" ]]; then
    ok "tribune runs as tester with the shipped claude-code provider; with AI on every shipped provider is offered"
else bad "tribune start: $(cat /tmp/tribune.log) offered '$(offered)'"; fi
if [[ "$(offered INVICTUS_AI_FILE=/dev/null INVICTUS_PROVIDERS_DIR=/tmp)" == "claude-code generic-cli none openai-compatible" ]]; then
    ok "the installed invictus-provider ignores INVICTUS_* overrides (state and providers are the root-owned ones)"
else bad "installed copy honoured an override: '$(offered INVICTUS_AI_FILE=/dev/null INVICTUS_PROVIDERS_DIR=/tmp)'"; fi
kill "$tpid" 2>/dev/null
if waitfor "! kill -0 $tpid 2>/dev/null" && ! pgrep -u tester -f 'sleep 300' >/dev/null && [[ ! -e "/run/user/$tu/invictus/tribune.sock" ]]; then
    ok "the panel ends with its agent and removes its socket"
else bad "panel end: $(cat /tmp/tribune.log) $(pgrep -u tester -a 2>&1 | paste -sd' ')"; fi
rm -f /usr/bin/claude

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
    ok "polkitd: org.invictus.sys.ai-on and ai-off are auth_admin with no keep"
else
    bad "pkaction ai-on '$(pa ai-on)', ai-off '$(pa ai-off)'"
fi
th="$(getent passwd tester | cut -d: -f6)"; tu="$(id -u tester)"
sudo -u tester mkdir -p "$th/.claude/projects/p"
sudo -u tester sh -c 'echo "{}" > ~/.claude/.credentials.json; echo "{\"numStartups\": 2, \"oauthAccount\": {\"e\": 1}}" > ~/.claude.json; echo m > ~/.claude/projects/p/c'
rc=0; invictus-sys ai off > "$WORK/aioff.out" 2>&1 || rc=$?
sleep 0.5
if [[ $rc == 0 && "$(cat /etc/invictus/ai)" == off && ! -e "$th/.claude/.credentials.json" && -f "$th/.claude/projects/p/c" ]] \
   && [[ "$(stat -c %U "$th/.claude.json")" == tester ]] && ! grep -q oauthAccount "$th/.claude.json" && grep -q numStartups "$th/.claude.json" \
   && [[ -f /etc/firefox/policies/policies.json && -f "/var/lib/invictus/ai-off-pending/$tu" ]] \
   && ! pacman -Q invictus-tribune >/dev/null 2>&1; then
    ok "ai off as root: tester's credential file and account block removed by a process running as tester (real setpriv), memory kept, browser policy and pending marker written, the Cicero panel package removed"
else
    bad "ai off: rc $rc: $(cat "$WORK/aioff.out"); $(find "$th" -maxdepth 2 -printf '%u %p\n' 2>&1 | paste -sd' ')"
fi
# The AI set is in no configured repo here: that is not a download
# failure, so ai on fails and nothing waits.
rc=0; invictus-sys ai on > "$WORK/aion.out" 2>&1 || rc=$?
if [[ $rc == 1 && "$(cat /etc/invictus/ai)" == on && ! -e /var/lib/invictus/ai-install-pending && ! -e /etc/firefox/policies/policies.json ]] \
   && [[ -z "$(ls -A /var/lib/invictus/ai-off-pending)" ]] \
   && grep -q 'Update first' "$WORK/aion.out" && grep -q 'invictus-sys: failed' "$WORK/aion.out" \
   && grep -q 'target not found: invictus-cicero' "$WORK/aion.out"; then
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

if [[ $fail == 0 ]]; then echo "e2e-sys: ALL PASSED"; else echo "e2e-sys: SOME TESTS FAILED"; fi
exit $fail
