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
if pacman -U --noconfirm "$WORK"/out/invictus-sys-*.pkg.tar.zst "$WORK"/out/invictus-guardrails-*.pkg.tar.zst >"$WORK/install.log" 2>&1; then
    ok "makepkg builds invictus-sys and invictus-guardrails; pacman -U installs them"
else
    bad "install: $(tail -5 "$WORK/install.log")"; exit 1
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
