#!/usr/bin/env bash
# ------------------------------------------------------------
# End-to-end test of scripts/dev/adopt.sh on a machine set up by the
# old hyprdots scripts. Run as root in a throwaway Arch container:
#
#   podman run --rm -v "$PWD:/src:ro" archlinux:base-devel bash /src/tests/pkgs/e2e-adopt.sh
#
# Builds the repo (signed with a throwaway key, as e2e-arch.sh does),
# makes user "alex" with a legacy home (tests/pkgs/lib/legacy-home.sh:
# a ~/hyprdots clone, deployed hyprlang configs, his own bind and
# monitor line), stand-ins for the AUR packages he installed with paru,
# and the Arch packages the old install had. Then checks:
#   dry run   shows the plan (repo block, packages from our repo, the
#             replaced files, the ported bind) and changes nothing;
#             refuses an unsigned remote repo and the placeholder key
#   adopt     signed: ends on hyprland.lua (Hyprland --verify-config
#             passes), user.lua and monitors.lua ported, backups kept,
#             packages in (desktop and tessera), the spaceship prompt
#             loads, theme applied; invictus-doctor and
#             invictus-update pass; a second adopt is refused
#   epoch     a package with an epoch (1:...) installs from the repo
#             under its GitHub-safe file name
#   undo      home, /etc/pacman.conf and the package list are back
#             exactly as before; the key is gone; a second undo is refused
#   rollback  unsigned-local mode, with a personal bind Hyprland rejects:
#             adopt stops at the check and puts the config back; undo
#             removes the rest
# Never run it on a real machine: it edits /etc/pacman.conf.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC="${1:-/src}"

fail=0 passed=0
ok()  { echo "ok    $1"; passed=$((passed + 1)); }
bad() { echo "FAIL  $1"; fail=1; }

echo "==> Preparing the container"
# Like a real install: multilib on (the dry run resolves invictus-gaming)
# and pacman's keyring initialised (adopt locally signs our key).
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
grep -qx '\[multilib\]' /etc/pacman.conf || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinux >/dev/null 2>&1
pacman -Syu --noconfirm --needed git sudo fakeroot lua >/dev/null

WORK="$(mktemp -d)"
chmod 755 "$WORK"
cp -r "$SRC/." "$WORK/src"
rm -rf "$WORK/src/out" "$WORK/src/.git"
# shellcheck source=tests/pkgs/lib/aur-heavy.sh
. "$SRC/tests/pkgs/lib/aur-heavy.sh"
stand_in_heavy_aur "$WORK/src"

# ---- throwaway key, as Alex will make the real one ----------------------------
export GNUPGHOME="$WORK/keys"
install -dm700 "$GNUPGHOME"
PASS="e2e-$(date +%s%N)"
gpg --batch --quiet --pinentry-mode loopback --passphrase "$PASS" \
    --quick-gen-key 'Invictus adopt test key (throwaway)' ed25519 sign 1d
FPR="$(gpg --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')"
gpg --armor --export "$FPR" > "$WORK/src/pkgs/own/invictus-keyring/invictus.gpg"
SECRET="$(gpg --batch --pinentry-mode loopback --passphrase "$PASS" --armor --export-secret-keys "$FPR")"
gpgconf --kill gpg-agent
unset GNUPGHOME

# A package with an epoch, served from our repo (proton-ge-custom-bin has
# one; this stand-in replaces the real pin or its version-0 stand-in).
rm -rf "$WORK/src/pkgs/aur/proton-ge-custom-bin"
mkdir -p "$WORK/src/pkgs/aur/proton-ge-custom-bin"
cat > "$WORK/src/pkgs/aur/proton-ge-custom-bin/PKGBUILD" <<'EOF'
pkgname=proton-ge-custom-bin
epoch=1
pkgver=GE_Proton11_7
pkgrel=1
pkgdesc='test stand-in with an epoch'
arch=('any')
license=('custom')
package() { install -Dm644 /dev/null "$pkgdir/usr/share/doc/$pkgname/stand-in"; }
EOF

# ---- build the repo ---------------------------------------------------------------
OUT="$WORK/repo"
mkdir -p "$OUT"
if [[ -n "${E2E_SEED:-}" && -d "$E2E_SEED" ]]; then
    # local runs: reuse packages already built (same names, so reused as is)
    cp "$E2E_SEED"/*.pkg.tar.zst "$OUT"/ 2>/dev/null || true
    rm -f "$OUT"/invictus-*.pkg.tar.zst
fi
bash "$WORK/src/scripts/build-repo.sh" --no-container --build-only --out "$OUT" > "$WORK/build.log" 2>&1 \
    || { tail -30 "$WORK/build.log"; exit 1; }
INVICTUS_SIGNING_KEY="$SECRET" INVICTUS_SIGNING_PASSPHRASE="$PASS" \
    bash "$WORK/src/scripts/build-repo.sh" --no-container --repo-only --out "$OUT" >> "$WORK/build.log" 2>&1 \
    || { tail -30 "$WORK/build.log"; exit 1; }
chmod -R a+rX "$WORK"
if ls "$OUT"/proton-ge-custom-bin-1.GE_Proton11_7-1-any.pkg.tar.zst >/dev/null 2>&1 && ! ls "$OUT"/*:* >/dev/null 2>&1; then
    ok "the epoch package is stored as proton-ge-custom-bin-1.GE_Proton11_7-1-any (no ':' in any repo file)"
else
    bad "repo file names: $(find "$OUT" -name "proton*" -printf "%f ")"
fi

# ---- the legacy machine ---------------------------------------------------------------
echo "==> Making the legacy machine"
# Stand-ins for what Alex installed from the AUR with paru, and for Arch's
# Code - OSS (`code`), which our visual-studio-code-bin conflicts with.
id builder >/dev/null 2>&1 || useradd -m builder
# Version 9999: newer than [extra]'s real code, so pacman -Syu keeps the
# stand-in (with a low version it pulled the real one and its electron).
for p in zen-browser-bin claude-code code; do
    d="$WORK/aur-standins/$p"; mkdir -p "$d"
    printf "pkgname=%s\npkgver=9999\npkgrel=1\narch=('any')\nlicense=('custom')\npackage() { :; }\n" "$p" > "$d/PKGBUILD"
done
chown -R builder "$WORK/aur-standins"
for d in "$WORK"/aur-standins/*/; do
    # shellcheck disable=SC2024 # root writes the log, on purpose
    (cd "$d" && sudo -u builder makepkg --noconfirm > "$WORK/standin.log" 2>&1) || { tail -5 "$WORK/standin.log"; exit 1; }
done
pacman -U --noconfirm "$WORK"/aur-standins/*/*.pkg.tar.zst > "$WORK/standin.log" 2>&1 || { tail -5 "$WORK/standin.log"; exit 1; }
# What the old install had from Arch.
pacman -S --noconfirm --needed hyprland hyprpaper hypridle hyprlock waybar kitty rofi > "$WORK/legacy-pkgs.log" 2>&1 \
    || { tail -5 "$WORK/legacy-pkgs.log"; exit 1; }

# waybar needs "jack"; pacman's default provider is jack2, so the old
# install has it, as Alex's machine almost certainly does. Adopt must
# work around it (regression adopt-jack2-conflict).
if pacman -Q jack2 >/dev/null 2>&1; then ok "the legacy machine has jack2 (from waybar), like a real one"
else bad "legacy machine: jack2 not installed, the jack2 regression is not covered"; fi

useradd -m -s /bin/bash alex
echo 'alex ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/alex
# shellcheck source=tests/pkgs/lib/legacy-home.sh
. "$WORK/src/tests/pkgs/lib/legacy-home.sh"
make_legacy_home "$WORK/src" /home/alex
mkdir -p /home/alex/src
cp -r "$WORK/src" /home/alex/src/invictus
chown -R alex:alex /home/alex

as_alex() { sudo -u alex -H env XDG_RUNTIME_DIR=/tmp/alex-run "$@"; }
install -dm700 -o alex /tmp/alex-run
ADOPT=/home/alex/src/invictus/scripts/dev/adopt.sh

snapshot() {
    # dconf: the theme's gsettings; undo leaves those (adopt.sh says so)
    ( cd /home/alex && { find .config .zshrc .local/state Pictures \( -type f -o -type l \) 2>/dev/null || true; } \
        | grep -v '^\.local/state/invictus/adopt/\|^\.config/dconf/' | sort | while read -r f; do
            if [[ -L "$f" ]]; then echo "L $(readlink "$f") $f"; else echo "$(sha256sum < "$f" | cut -c1-16) $f"; fi
        done
      find .config -type d | grep -v '^\.config/dconf' | sort )
    sha256sum /etc/pacman.conf
}
snapshot > "$WORK/before.snap"
pacman -Qq | sort > "$WORK/before.pkgs"

# ---- dry run ------------------------------------------------------------------------
echo "==> Dry run"
rc=0; as_alex bash "$ADOPT" --server "file://$OUT" > "$WORK/dry.log" 2>&1 || rc=$?
if [[ $rc == 0 ]] && grep -q "^+\[invictus-testing\]" <(sed 's/^    //' "$WORK/dry.log") \
   && grep -qE '^ +invictus-desktop [^ ]+ invictus-testing$' "$WORK/dry.log" \
   && grep -qE '^ +invictus-tessera [^ ]+ invictus-testing$' "$WORK/dry.log" \
   && grep -qE '^ +spaceship-prompt [^ ]+ invictus-testing$' "$WORK/dry.log" \
   && grep -qE '^ +invictus-gaming [^ ]+ invictus-testing$' "$WORK/dry.log" \
   && grep -q "replacing /home/alex/.config/waybar/config.json" "$WORK/dry.log" \
   && grep -q 'hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("firefox --private-window")' "$WORK/dry.log" \
   && grep -q "pacman will ask to remove code for visual-studio-code-bin" "$WORK/dry.log" \
   && grep -q "Dry run finished. Nothing was changed" "$WORK/dry.log"; then
    ok "dry run shows the repo block, the packages from our repo, the replaced files, the ported bind and the code/VS Code swap"
else
    bad "dry run (rc $rc): $(tail -25 "$WORK/dry.log")"
fi
snapshot > "$WORK/after-dry.snap"
if cmp -s "$WORK/before.snap" "$WORK/after-dry.snap" && [[ ! -e /home/alex/.local/state/invictus/adopt ]] \
   && cmp -s <(pacman -Qq | sort) "$WORK/before.pkgs"; then
    ok "dry run changed nothing (home, pacman.conf, packages)"
else
    bad "dry run changed something: $(diff "$WORK/before.snap" "$WORK/after-dry.snap" | head -5)"
fi
# Regression, adopt-conflict-noconfirm (2026-09-30): with --yes pacman
# answers No to "remove code?" and stops the whole update; adopt must say so
# before changing anything.
rc=0; as_alex bash "$ADOPT" --server "file://$OUT" --yes > "$WORK/yes.log" 2>&1 || rc=$?
if [[ $rc == 1 ]] && grep -q "visual-studio-code-bin replaces code, which is installed; with --yes" "$WORK/yes.log"; then
    ok "adopt-conflict-noconfirm: --yes with code installed stops at the plan and says why"
else
    bad "adopt-conflict-noconfirm: rc $rc $(grep -E 'PROBLEM|problem|code' "$WORK/yes.log" | head -3)"
fi
rc=0; as_alex bash "$ADOPT" --unsigned-local https://example.org/repo > "$WORK/remote.log" 2>&1 || rc=$?
if [[ $rc != 0 ]] && grep -q "never allowed" "$WORK/remote.log"; then ok "unsigned mode refuses a URL"
else bad "unsigned remote: rc $rc $(tail -2 "$WORK/remote.log")"; fi
cp "$SRC/pkgs/own/invictus-keyring/invictus.gpg" /tmp/placeholder.gpg; chmod 644 /tmp/placeholder.gpg
rc=0; as_alex bash "$ADOPT" --server "file://$OUT" --key /tmp/placeholder.gpg --apply > "$WORK/ph.log" 2>&1 || rc=$?
if [[ $rc == 1 ]] && grep -q "still the placeholder" "$WORK/ph.log" && snapshot | cmp -s - "$WORK/before.snap"; then
    ok "--apply with the placeholder key stops before changing anything"
else
    bad "placeholder key: rc $rc $(tail -3 "$WORK/ph.log")"
fi

# ---- adopt, signed --------------------------------------------------------------------
echo "==> Adopt (signed)"
rc=0; as_alex bash "$ADOPT" --server "file://$OUT" --skip gaming --skip dev --yes --apply > "$WORK/adopt.log" 2>&1 || rc=$?
if [[ $rc == 0 ]] && grep -q "==> Adopted" "$WORK/adopt.log"; then ok "adopt --apply finished"
else bad "adopt failed (rc $rc): $(tail -30 "$WORK/adopt.log")"; fi
H=/home/alex/.config/hypr
if cmp -s "$H/hyprland.lua" /usr/share/invictus/config/hypr/hyprland.lua && [[ -f "$H/hyprland.conf" && -f "$H/config/keybindings.conf" ]]; then
    ok "hyprland.lua is the loader; hyprland.conf and config/*.conf are still there"
else
    bad "hypr folder after adopt: $(ls "$H")"
fi
if as_alex bash -c 'cd /tmp/alex-run && Hyprland --verify-config -c ~/.config/hypr/hyprland.lua' > "$WORK/verify.log" 2>&1 \
   && grep -q "config ok" "$WORK/verify.log"; then
    ok "Hyprland --verify-config accepts the adopted config"
else
    bad "verify-config: $(tail -8 "$WORK/verify.log")"
fi
if grep -q 'hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("firefox --private-window")' "$H/user.lua" \
   && grep -q 'output   = "DP-1"' "$H/monitors.lua"; then
    ok "user.lua has his own bind; monitors.lua has his monitor"
else
    bad "user.lua / monitors.lua not ported"
fi
# Alex's Discord and Zen monitor pins are no longer shipped; the porter carries them into user.lua,
# and Hyprland (verify-config above) accepts the result.
if [[ "$(grep -c '^hl.window_rule' "$H/user.lua")" == 2 ]] \
   && grep -q 'name    = "discord-assign"' "$H/user.lua" && grep -q 'monitor = "HDMI-A-2"' "$H/user.lua" \
   && grep -q 'name    = "zen-assign"' "$H/user.lua" && grep -q 'monitor = "DP-2"' "$H/user.lua" \
   && ! grep -q 'discord-assign\|zen-assign' /usr/share/invictus/hypr/invictus/rules.lua; then
    ok "user.lua carries his Discord and Zen monitor pins; the shipped rules.lua has none"
else
    bad "monitor pins not ported: $(grep -c '^hl.window_rule' "$H/user.lua") rules in user.lua"
fi
B="$(readlink -f /home/alex/.local/state/invictus/adopt/latest)"
if cmp -s "$B/config/waybar/config.json" "$SRC/tests/pkgs/fixtures/legacy-home/waybar/config.json" \
   && cmp -s /home/alex/.config/waybar/config.json /usr/share/invictus/config/waybar/config.json \
   && [[ -f "$B/pacman.conf" && -s "$B/packages-installed.txt" && -f "$B/wallpapers/Berserk.jpg" \
         && -f /home/alex/Pictures/Wallpapers/Berserk.jpg ]]; then
    ok "old configs, pacman.conf, package list and the old wallpaper are in the backup"
else
    bad "backup incomplete: $(ls "$B")"
fi
if pacman -Q invictus-keyring invictus-desktop invictus-tessera invictus-tools invictus-branding xwaylandvideobridge spaceship-prompt >/dev/null \
   && [[ -x /usr/lib/invictus/waybar/updates && -x /usr/bin/invictus-update ]] \
   && [[ "$(grep -m1 -E '^\[' <(grep -v '^\[options\]' /etc/pacman.conf))" == "[invictus-testing]" ]] \
   && pacman-key --list-keys "$FPR" >/dev/null 2>&1; then
    ok "packages installed; [invictus-testing] is the first repo; the key is in pacman's keyring"
else
    bad "packages or repo: $(pacman -Q invictus-desktop 2>&1)"
fi
# The shipped ~/.zshrc runs `prompt spaceship`; our pkgs/aur copy must put
# the theme on zsh's default fpath.
if out="$(as_alex zsh -fc 'autoload -U promptinit; promptinit; prompt spaceship' 2>&1)" && [[ -z "$out" ]]; then
    ok "zsh finds the spaceship prompt (from our repo), no errors"
else
    bad "prompt spaceship: $out"
fi
if [[ -e /home/alex/.config/invictus/current/waybar-colors.css && -f /home/alex/.local/state/invictus/first-login.done ]] \
   && as_alex /usr/lib/invictus/first-login | grep -q "already done"; then
    ok "theme applied, first-login marked done (the unit will not run again)"
else
    bad "theme or first-login state missing"
fi
rc=0; as_alex invictus-doctor > "$WORK/doctor.log" 2>&1 || rc=$?
if [[ $rc == 0 ]] && grep -q "^ok    hypr: stub check passes" "$WORK/doctor.log" && grep -q "^ok    repo: invictus-testing comes before" "$WORK/doctor.log"; then
    ok "invictus-doctor passes on the adopted machine"
else
    bad "doctor (rc $rc): $(grep -E 'FAIL|warn' "$WORK/doctor.log")"
fi
rc=0; as_alex invictus-update --noconfirm > "$WORK/update.log" 2>&1 || rc=$?
if [[ $rc == 0 ]] && grep -q "Update complete" "$WORK/update.log"; then ok "invictus-update runs pacman -Syu and the doctor"
else bad "invictus-update (rc $rc): $(tail -8 "$WORK/update.log")"; fi
rc=0; as_alex bash "$ADOPT" --server "file://$OUT" --apply > "$WORK/again.log" 2>&1 || rc=$?
if [[ $rc == 1 ]] && grep -q "adopt already ran" "$WORK/again.log"; then ok "a second adopt is refused"
else bad "second adopt: rc $rc"; fi

# ---- epoch -----------------------------------------------------------------------------
if pacman -S --noconfirm proton-ge-custom-bin > "$WORK/epoch.log" 2>&1 \
   && [[ "$(pacman -Q proton-ge-custom-bin)" == "proton-ge-custom-bin 1:GE_Proton11_7-1" ]]; then
    ok "a package with an epoch installs from the signed repo under its renamed file"
else
    bad "epoch install: $(tail -3 "$WORK/epoch.log")"
fi
pacman -Rn --noconfirm proton-ge-custom-bin >/dev/null

# ---- undo ------------------------------------------------------------------------------
echo "==> Undo"
snapshot > "$WORK/adopted.snap"
rc=0; as_alex bash "$ADOPT" --undo > "$WORK/undo-dry.log" 2>&1 || rc=$?
if [[ $rc == 0 ]] && snapshot | cmp -s - "$WORK/adopted.snap" && pacman -Q invictus-desktop >/dev/null; then
    ok "undo dry run changes nothing"
else
    bad "undo dry run: rc $rc $(tail -3 "$WORK/undo-dry.log")"
fi
rc=0; as_alex bash "$ADOPT" --undo --apply --yes > "$WORK/undo.log" 2>&1 || rc=$?
snapshot > "$WORK/undone.snap"
if [[ $rc == 0 ]] && cmp -s "$WORK/before.snap" "$WORK/undone.snap"; then
    ok "undo: home and /etc/pacman.conf are exactly as before"
else
    bad "undo (rc $rc): $(diff "$WORK/before.snap" "$WORK/undone.snap" | head -8); $(tail -5 "$WORK/undo.log")"
fi
if cmp -s <(pacman -Qq | sort) "$WORK/before.pkgs" && ! pacman-key --list-keys "$FPR" >/dev/null 2>&1; then
    ok "undo: the package list is as before and the key is deleted"
else
    bad "undo packages: $(comm -3 <(pacman -Qq | sort) "$WORK/before.pkgs" | head -5 | tr '\n' ' ')"
fi
rc=0; as_alex bash "$ADOPT" --undo --apply > "$WORK/undo2.log" 2>&1 || rc=$?
if [[ $rc != 0 ]]; then ok "a second undo is refused"; else bad "second undo ran"; fi

# ---- rollback (unsigned-local) --------------------------------------------------------------
echo "==> Adopt with a bind Hyprland rejects (unsigned-local)"
cp -r "$OUT" "$WORK/unsigned"
rm -f "$WORK"/unsigned/*.sig "$WORK"/unsigned/invictus-testing.*
bash "$WORK/src/scripts/build-repo.sh" --no-container --repo-only --out "$WORK/unsigned" > "$WORK/unsigned.log" 2>&1 \
    || { bad "unsigned repo: $(tail -3 "$WORK/unsigned.log")"; }
chmod -R a+rX "$WORK/unsigned"
# shellcheck disable=SC2016 # a literal hyprlang variable
echo 'bind = $mainMod, NotAKeyName, exec, notify-send rollback-test' >> /home/alex/.config/hypr/config/keybindings.conf
snapshot > "$WORK/before2.snap"
rc=0; as_alex bash "$ADOPT" --unsigned-local "$WORK/unsigned" --skip gaming --skip dev --yes --apply > "$WORK/rb.log" 2>&1 || rc=$?
if [[ $rc == 1 ]] && grep -q "did not load. Putting the config folders back" "$WORK/rb.log" \
   && snapshot | grep -v '\.local/state/invictus/\|/etc/pacman.conf' \
      | cmp -s - <(grep -v '\.local/state/invictus/\|/etc/pacman.conf' "$WORK/before2.snap"); then
    ok "rollback: a config Hyprland rejects is put back at once (home as before; repo and packages stay for undo)"
else
    bad "rollback (rc $rc): $(tail -12 "$WORK/rb.log")"
fi
rc=0; as_alex bash "$ADOPT" --undo --apply --yes > "$WORK/undo3.log" 2>&1 || rc=$?
if [[ $rc == 0 ]] && snapshot | cmp -s - "$WORK/before2.snap" && cmp -s <(pacman -Qq | sort) "$WORK/before.pkgs"; then
    ok "undo after a rollback removes the packages and the repo block"
else
    bad "undo after rollback (rc $rc): $(tail -5 "$WORK/undo3.log")"
fi

# ---- a failing step prints the undo hint -----------------------------------------------
echo "==> Adopt with pacman failing (unsigned-local)"
# ADOPT_SUDO wraps sudo: the -Syu step fails, everything else runs as usual.
cat > "$WORK/failing-sudo" <<'WRAP'
#!/bin/sh
case "$*" in *"pacman -Syu"*) echo "forced pacman failure" >&2; exit 1 ;; esac
exec sudo "$@"
WRAP
chmod 755 "$WORK/failing-sudo"
rc=0; as_alex env ADOPT_SUDO="$WORK/failing-sudo" bash "$ADOPT" --unsigned-local "$WORK/unsigned" --skip gaming --skip dev --yes --apply > "$WORK/fail.log" 2>&1 || rc=$?
if [[ $rc != 0 ]] && grep -q "adopt.sh stopped at step" "$WORK/fail.log" && grep -q -- "--undo --apply" "$WORK/fail.log"; then
    ok "a failing pacman inside a step prints where it stopped and the undo command"
else
    bad "failed step (rc $rc): $(tail -6 "$WORK/fail.log")"
fi
rc=0; as_alex bash "$ADOPT" --undo --apply --yes > "$WORK/undo4.log" 2>&1 || rc=$?
if [[ $rc == 0 ]] && snapshot | cmp -s - "$WORK/before2.snap"; then
    ok "undo after the failed step puts the machine back"
else
    bad "undo after failed step (rc $rc): $(tail -5 "$WORK/undo4.log")"
fi

# Keep the logs when asked (local debugging).
if [[ -n "${E2E_LOGS:-}" ]]; then cp "$WORK"/*.log "$WORK"/*.snap "$E2E_LOGS"/ 2>/dev/null || true; fi

echo
echo "$passed passed"
[[ $fail == 0 ]] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit $fail
