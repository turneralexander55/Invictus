# shellcheck shell=bash
# Groups 4 to 13 of tests/pkgs/run.sh (sourced; uses REPO, HERE, TMP, ok, bad).
# shellcheck disable=SC2153 # REPO, HERE and TMP come from run.sh
# Each check prints one ok/FAIL line.
if [[ "${BASH_SOURCE[0]}" == "$0" ]] || ! declare -F ok bad >/dev/null || [[ -z "${REPO:-}" || -z "${TMP:-}" ]]; then
    echo "tests/pkgs/runtime.sh is groups 4 to 13 of tests/pkgs/run.sh: run that" >&2
    # shellcheck disable=SC2317 # exit is reached when run, not sourced
    return 2 2>/dev/null || exit 2
fi

LUA="${LUA:-$(command -v lua5.5 || command -v lua5.4 || command -v lua || true)}"
STUBS="$REPO/tests/hyprland-lua/stubs/hl.meta.lua"

# ---- 4. install trees ------------------------------------------------------------
echo "== install trees"
TREES="$TMP/trees"
mkdir -p "$TREES"
for pb in "$REPO"/pkgs/own/*/PKGBUILD "$REPO"/pkgs/meta/*/PKGBUILD; do
    name="$(basename "$(dirname "$pb")")"
    [[ "$name" == invictus-keyring ]] && continue
    if ! (startdir="$(dirname "$pb")" pkgdir="$TREES/$name" \
          bash -c 'set -euo pipefail; source "$startdir/PKGBUILD"; package' ) >"$TMP/pkg.log" 2>&1; then
        bad "$name: package() failed: $(tail -3 "$TMP/pkg.log")"
    fi
done
ALL="$TMP/all-trees"
mkdir -p "$ALL"
for t in "$TREES"/*/; do cp -a "$t". "$ALL"/; done

# Every absolute /usr/(lib|share)/invictus path, and every invictus-* command,
# that the shipped config names.
t_fail=0
while IFS= read -r p; do
    [[ -e "$ALL$p" ]] || { bad "config calls $p, which no package installs"; t_fail=1; continue; }
    if [[ "$p" == /usr/lib/invictus/* && ! -x "$ALL$p" ]]; then bad "$p is not executable"; t_fail=1; fi
done < <(grep -rhoE '/usr/(lib|share)/invictus/[A-Za-z0-9_./-]+' "$REPO/config" | sed 's/[.,]$//' | sort -u)
while IFS= read -r c; do
    [[ -x "$ALL/usr/bin/$c" ]] || { bad "config runs $c, which is not in /usr/bin of any package"; t_fail=1; }
done < <(grep -rhoE '\binvictus-(update|doctor|theme)\b' "$REPO/config" | sort -u)
[[ $t_fail == 0 ]] && ok "every installed path and command the config names is in a package"

link="$ALL/usr/lib/systemd/user/default.target.wants/invictus-first-login.service"
if [[ -L "$link" && "$(readlink "$link")" == ../invictus-first-login.service && -f "$ALL/usr/lib/systemd/user/invictus-first-login.service" ]]; then
    ok "invictus-first-login user unit is installed and enabled for every user"
else
    bad "first-login unit or its default.target.wants link is wrong"
fi
if [[ -f "$ALL/usr/share/invictus/config/hypr/hyprland.lua" && ! -e "$ALL/usr/share/invictus/config/hypr/invictus" \
      && -f "$ALL/usr/share/invictus/hypr/invictus/core.lua" ]]; then
    ok "defaults under /usr/share/invictus/config, shipped modules under /usr/share/invictus/hypr/invictus"
else
    bad "desktop config layout under /usr/share/invictus is wrong"
fi
n_lock="$(grep -cv '^[[:space:]]*\(#\|$\)' "$REPO/pkgs/pinned/hypr.lock")"
if [[ "$(wc -l < "$ALL/usr/share/invictus/pinned-hypr.txt")" == "$n_lock" ]] \
   && ! grep -qv '^[a-z0-9-]* [0-9][^ ]*-[0-9]*$' "$ALL/usr/share/invictus/pinned-hypr.txt"; then
    ok "pinned-hypr.txt lists the $n_lock pinned packages as 'name version'"
else
    bad "pinned-hypr.txt does not match the lock: $(head -3 "$ALL/usr/share/invictus/pinned-hypr.txt")"
fi
if bash -c 'source "$1"; printf "%s\n" "${depends[@]}"' _ "$REPO/pkgs/meta/invictus-desktop/PKGBUILD" | grep -x invictus-tools >/dev/null; then
    ok "invictus-desktop depends on invictus-tools"
else
    bad "invictus-desktop does not depend on invictus-tools"
fi
echo

# ---- 5. main compatibility -------------------------------------------------------
echo "== main compatibility"
c_fail=0
while read -r path reason; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    if [[ -e "$REPO/$path" ]]; then
        [[ "$path" != scripts/* || -x "$REPO/$path" ]] || { bad "$path is no longer executable"; c_fail=1; }
    elif [[ -z "$reason" ]]; then
        bad "$path is gone, but configs deployed from main call it"; c_fail=1
    fi
done < "$HERE/fixtures/main-references.txt"
[[ $c_fail == 0 ]] && ok "every repo path main's deployed configs call still exists (or is a listed exception)"
echo

# ---- 6. first-login ----------------------------------------------------------------
echo "== first-login"
FL="$REPO/scripts/first-login.sh"
SHARE="$ALL/usr/share/invictus"
first_login() { # HOME, then args
    local h="$1"; shift
    HOME="$h" XDG_CONFIG_HOME="" XDG_STATE_HOME="" INVICTUS_STATE="" INVICTUS_SHARE="$SHARE" \
        INVICTUS_DEFAULTS_SH="$REPO/scripts/lib/defaults.sh" PATH="$TMP/nobin:$PATH" \
        bash "$FL" "$@"
}
# Keep the old init steps from touching this machine.
mkdir -p "$TMP/nobin"
for c in systemctl xdg-user-dirs-update fc-cache; do printf '#!/bin/sh\nexit 0\n' > "$TMP/nobin/$c"; chmod +x "$TMP/nobin/$c"; done
n_defaults="$(cd "$SHARE/config" && find . -type f | wc -l)"

H="$TMP/h-fresh"; mkdir -p "$H"
first_login "$H" > "$TMP/fl.log" 2>&1
got="$( (cd "$SHARE/config" && find . -type f) | while read -r f; do
    f="${f#./}"; [[ "$f" == shell/zshrc ]] && d="$H/.zshrc" || d="$H/.config/$f"; cmp -s "$SHARE/config/$f" "$d" && echo y; done | wc -l)"
if [[ "$got" == "$n_defaults" && -f "$H/.local/state/invictus/first-login.done" \
      && "$(wc -l < "$H/.local/state/invictus/defaults.sha256")" == "$n_defaults" && -d "$H/Screenshots" ]]; then
    ok "fresh home: all $n_defaults defaults copied, recorded, home folders made, sentinel set"
else
    bad "fresh home: $got of $n_defaults copied: $(tail -3 "$TMP/fl.log")"
fi
echo "# mine" > "$H/.config/kitty/kitty.conf"
first_login "$H" > "$TMP/fl2.log" 2>&1
if grep -q "already done" "$TMP/fl2.log" && [[ "$(cat "$H/.config/kitty/kitty.conf")" == "# mine" ]]; then
    ok "second login: the sentinel stops it; nothing is touched"
else
    bad "second login ran again: $(cat "$TMP/fl2.log")"
fi

H="$TMP/h-kept"; mkdir -p "$H/.config/waybar"
echo '{"mine": true}' > "$H/.config/waybar/config.json"
first_login "$H" > "$TMP/fl.log" 2>&1
if [[ "$(cat "$H/.config/waybar/config.json")" == '{"mine": true}' ]] && grep -q "kept as they are" "$TMP/fl.log"; then
    ok "an existing file is kept, never overwritten"
else
    bad "an existing waybar config was changed"
fi

H="$TMP/h-hyprlang"; mkdir -p "$H/.config/hypr"
echo "source = x" > "$H/.config/hypr/hyprland.conf"
first_login "$H" > "$TMP/fl.log" 2>&1
if [[ ! -e "$H/.config/hypr/hyprland.lua" ]] && grep -q "keeping your hyprland.conf" "$TMP/fl.log"; then
    ok "a home on hyprland.conf does not get a hyprland.lua (no silent switch)"
else
    bad "first-login added hyprland.lua next to hyprland.conf"
fi

H="$TMP/h-autogen"; mkdir -p "$H/.config/hypr"
printf '\n-- -- -- -- --\n-- AUTOGENERATED HYPRLAND CONFIG.                        --\nhl.config({})\n' > "$H/.config/hypr/hyprland.lua"
first_login "$H" > "$TMP/fl.log" 2>&1
if cmp -s "$H/.config/hypr/hyprland.lua" "$SHARE/config/hypr/hyprland.lua" \
   && grep -rq "AUTOGENERATED" "$H/.local/state/invictus/backup/"; then
    ok "Hyprland's autogenerated hyprland.lua is backed up and replaced"
else
    bad "autogenerated hyprland.lua not replaced: $(cat "$TMP/fl.log")"
fi

H="$TMP/h-adopt"; mkdir -p "$H/.config/waybar" "$H/.config/hypr"
echo old > "$H/.config/waybar/config.json"
echo "# my zshrc" > "$H/.zshrc"
echo "-- my user.lua" > "$H/.config/hypr/user.lua"
echo "source = x" > "$H/.config/hypr/hyprland.conf"
first_login "$H" --adopt "$TMP/adopt-bk" > "$TMP/fl.log" 2>&1
if cmp -s "$H/.config/waybar/config.json" "$SHARE/config/waybar/config.json" \
   && [[ "$(cat "$TMP/adopt-bk/waybar/config.json")" == old && "$(cat "$H/.zshrc")" == "# my zshrc" \
         && "$(cat "$H/.config/hypr/user.lua")" == "-- my user.lua" && -f "$H/.config/hypr/hyprland.lua" \
         && -f "$H/.config/hypr/hyprland.conf" ]]; then
    ok "--adopt: desktop files replaced with backups; zshrc and user.lua kept; hyprland.lua added"
else
    bad "--adopt did the wrong thing: $(cat "$TMP/fl.log")"
fi

H="$TMP/h-dry"; mkdir -p "$H"
first_login "$H" --dry-run > "$TMP/fl.log" 2>&1
if [[ -z "$(find "$H" -mindepth 1 -print -quit)" ]] && grep -q "would run" "$TMP/fl.log"; then
    ok "--dry-run changes nothing"
else
    bad "--dry-run changed the home: $(find "$H" | head -5)"
fi
echo

# ---- 7. invictus-doctor --------------------------------------------------------------
echo "== invictus-doctor"
DOC="$REPO/scripts/invictus-doctor.sh"
mkdir -p "$TMP/doclib/doctor"
cp "$REPO/scripts/doctor/hypr-check.lua" "$REPO"/tests/hyprland-lua/{mock_hl,api,hyprrequire}.lua "$TMP/doclib/doctor/"
doctor() { # HOME, then args
    local h="$1"; shift
    HOME="$h" XDG_CONFIG_HOME="" INVICTUS_STATE="" INVICTUS_DOCTOR_AS_ROOT="${DOC_AS_ROOT-0}" INVICTUS_SHARE="$SHARE" INVICTUS_LIB="$TMP/doclib" \
        INVICTUS_DEFAULTS_SH="$REPO/scripts/lib/defaults.sh" INVICTUS_HYPRLAND="${DOC_HYPRLAND:-no-such-hyprland}" \
        HL_STUBS="$STUBS" LUA="$LUA" INVICTUS_PACMAN_CONF="$TMP/pacman.conf" INVICTUS_ROOT_FSTYPE=ext4 \
        bash "$DOC" "$@"
}
H="$TMP/h-doc"; mkdir -p "$H"
first_login "$H" > /dev/null 2>&1
# The loader looks for the shipped modules in /usr/share; point it at the tree.
sed -i "s#/usr/share/invictus/hypr/?.lua#$SHARE/hypr/?.lua#" "$H/.config/hypr/hyprland.lua"
printf '[options]\n[invictus-testing]\n[core]\n[extra]\n' > "$TMP/pacman.conf"
# rofi: only the shipped default moved on. kitty: both changed. btop: only
# the user changed it (theirs; not listed).
echo "# my change" >> "$H/.config/kitty/kitty.conf"
echo "# upstream change" >> "$SHARE/config/kitty/kitty.conf"
echo "# upstream change" >> "$SHARE/config/rofi/config.rasi"
echo "# my change" >> "$H/.config/btop/btop.conf"
rc=0; doctor "$H" > "$TMP/doc.log" 2>&1 || rc=$?
if [[ -n "$LUA" ]] && grep -q "^ok    hypr: stub check passes" "$TMP/doc.log" && [[ $rc == 0 ]]; then
    ok "doctor: the shipped config passes the stub check; exit 0"
else
    bad "doctor on a good home: rc $rc: $(grep -E 'FAIL|hypr' "$TMP/doc.log" | head -5)"
fi
if grep -q "new version of rofi/config.rasi (you never edited yours)" "$TMP/doc.log" \
   && grep -q "kitty/kitty.conf differs from the shipped one" "$TMP/doc.log" \
   && [[ "$(grep -c 'note  defaults:' "$TMP/doc.log")" == 2 ]]; then
    ok "doctor: lists 'new default, yours untouched' and 'both changed'; your own edits alone are not listed"
else
    bad "doctor defaults: $(grep 'defaults' "$TMP/doc.log")"
fi
sed -i '$d' "$SHARE/config/rofi/config.rasi"
sed -i '$d' "$SHARE/config/kitty/kitty.conf"
if doctor "$H" --diff kitty/kitty.conf | grep '^-# my change' >/dev/null; then
    ok "doctor --diff shows your change against the shipped default"
else
    bad "doctor --diff output wrong"
fi
if ! doctor "$H" --diff ../../etc/passwd >/dev/null 2>&1; then ok "doctor --diff refuses paths outside the defaults"
else bad "doctor --diff followed ../"; fi
printf '[options]\n[core]\n[extra]\n[invictus-testing]\n' > "$TMP/pacman.conf"
if doctor "$H" > "$TMP/doc.log" 2>&1; then bad "doctor passed with our repo after [extra]"
elif grep -q "FAIL  repo: our repo comes after \[extra\]" "$TMP/doc.log"; then ok "doctor: our repo after [extra] fails (the pin would not hold)"
else bad "doctor repo order: $(grep repo "$TMP/doc.log")"; fi
printf '[options]\n[invictus-testing]\n[core]\n[extra]\n' > "$TMP/pacman.conf"
echo 'hl.config({ general = { no_such_option = 1 } })' >> "$H/.config/hypr/user.lua"
if doctor "$H" --hypr > "$TMP/doc.log" 2>&1; then bad "doctor --hypr passed a user.lua with a bad option"
elif grep -q "unknown config key 'general.no_such_option'" "$TMP/doc.log"; then ok "doctor --hypr: a bad option in user.lua fails and is named"
else bad "doctor --hypr: $(cat "$TMP/doc.log")"; fi
# H1 (Janus) and Felix: root never reads a person's ~/.config. --system (and
# any run as root) skips the per-user checks; --user runs only them. The
# user.lua above is broken, and a fake Hyprland records any call.
printf '#!/bin/sh\necho called > "%s"\nexit 1\n' "$TMP/hypr-called" > "$TMP/fake-hyprland"; chmod +x "$TMP/fake-hyprland"
rm -f "$TMP/hypr-called"; rc=0
DOC_HYPRLAND="$TMP/fake-hyprland" doctor "$H" --post-update --system > "$TMP/doc.log" 2>&1 || rc=$?
if [[ $rc == 0 && ! -e "$TMP/hypr-called" ]] && ! grep -qE '^(ok|FAIL|warn|note) +(hypr|defaults):' "$TMP/doc.log" && grep -q '^ok    repo:' "$TMP/doc.log"; then
    ok "H1-doctor-system: --system runs the system checks only; a broken ~/.config is never read and Hyprland is never run"
else bad "H1-doctor-system: rc $rc, hyprland called: $([[ -e "$TMP/hypr-called" ]] && echo yes || echo no): $(grep -E 'hypr|defaults|unknown' "$TMP/doc.log" | head -3)"; fi
rm -f "$TMP/hypr-called"; rc=0; DOC_HYPRLAND="$TMP/fake-hyprland" doctor "$H" --user > "$TMP/doc.log" 2>&1 || rc=$?
if [[ $rc == 1 && -e "$TMP/hypr-called" ]] && grep -q "unknown config key 'general.no_such_option'" "$TMP/doc.log" && ! grep -q '^ok    repo:' "$TMP/doc.log"; then
    ok "H1-doctor-user: --user runs only the checks on your own files (and finds the bad option)"
else bad "H1-doctor-user: rc $rc: $(head -5 "$TMP/doc.log")"; fi
E="$TMP/h-root"; mkdir -p "$E"
rc=0; DOC_AS_ROOT=1 doctor "$E" > "$TMP/doc.log" 2>&1 || rc=$?
if [[ $rc == 0 ]] && ! grep -q 'FAIL  hypr' "$TMP/doc.log" && grep -q '^note  per-user checks skipped as root' "$TMP/doc.log"; then
    ok "H1-doctor-root: as root the doctor skips the per-user checks (no FAIL for root's own missing ~/.config/hypr)"
else bad "H1-doctor-root: rc $rc: $(grep -E 'FAIL|per-user' "$TMP/doc.log" | head -3)"; fi
if [[ $EUID -eq 0 ]]; then
    rc=0; DOC_AS_ROOT="" doctor "$E" > "$TMP/doc.log" 2>&1 || rc=$?
    if [[ $rc == 0 ]] && grep -q '^note  per-user checks skipped as root' "$TMP/doc.log"; then ok "H1-doctor-root: the same when really run as root"
    else bad "H1-doctor-root (real root): rc $rc"; fi
    rc=0; DOC_AS_ROOT="" doctor "$E" --hypr > "$TMP/doc.log" 2>&1 || rc=$?
    if [[ $rc == 2 ]]; then ok "H1-doctor-root: --hypr as root is refused (run it as yourself)"
    else bad "H1-doctor-root: --hypr as root ran (rc $rc)"; fi
fi
echo

# Janus F3: the doctor reports extras still pending, and loudly once
# pending-extras gave up. A system check: it runs under --system (as root).
rm -f "$TMP/dx-pending" "$TMP/dx-pending.tries"
INVICTUS_EXTRAS_PENDING="$TMP/dx-pending" doctor "$H" --system > "$TMP/doc.log" 2>&1; rc=$?
if [[ $rc == 0 ]] && grep -q 'ok    extras: nothing waiting' "$TMP/doc.log"; then ok "F3-doctor: no pending extras is ok (a system check)"
else bad "F3-doctor none: rc $rc: $(grep extras "$TMP/doc.log")"; fi
# shellcheck disable=SC2016  # a literal $(reboot) that must never be run or shown
printf 'invictus-office\n$(reboot)\n' > "$TMP/dx-pending"; echo "boot-2 2" > "$TMP/dx-pending.tries"
INVICTUS_EXTRAS_PENDING="$TMP/dx-pending" doctor "$H" --system > "$TMP/doc.log" 2>&1; rc=$?
if [[ $rc == 0 ]] && grep -q 'note  extras: still to install when there is internet: invictus-office$' "$TMP/doc.log" && ! grep extras "$TMP/doc.log" | grep -q 'reboot'; then
    ok "F3-doctor: pending extras are a note, names only"
else bad "F3-doctor pending: rc $rc: $(grep extras "$TMP/doc.log")"; fi
echo "boot-5 5" > "$TMP/dx-pending.tries"
INVICTUS_EXTRAS_PENDING="$TMP/dx-pending" doctor "$H" --system > "$TMP/doc.log" 2>&1; rc=$?
if [[ $rc == 0 ]] && grep -q 'warn  extras: Extras not installed: invictus-office\.' "$TMP/doc.log"; then
    ok "F3-doctor: extras that pending-extras gave up on are a warning with the way to try again"
else bad "F3-doctor gave up: rc $rc: $(grep extras "$TMP/doc.log")"; fi
rm -f "$TMP/dx-pending" "$TMP/dx-pending.tries"
echo

# ---- 8. invictus-update --------------------------------------------------------------
echo "== invictus-update"
UPD="$REPO/scripts/invictus-update.sh"
mkdir -p "$TMP/fake"
cat > "$TMP/fake/pacman" <<'EOF'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
[ "$1" = -Qqo ] && exit "${FAKE_QO_RC:-1}"
exit "${FAKE_PACMAN_RC:-0}"
EOF
cat > "$TMP/fake/doctor" <<'EOF'
#!/bin/sh
echo "doctor $*" >> "$FAKE_LOG"
exit "${FAKE_DOCTOR_RC:-0}"
EOF
chmod +x "$TMP/fake/pacman" "$TMP/fake/doctor"
update() {
    FAKE_LOG="$TMP/upd.log" HOME="$TMP/h-upd" INVICTUS_PACMAN="$TMP/fake/pacman" INVICTUS_SUDO="" \
        INVICTUS_DOCTOR="$TMP/fake/doctor" INVICTUS_PARU=no-such-paru INVICTUS_LIB="$REPO/scripts" \
        INVICTUS_SYS_ROOT="${UPD_ROOT:-$TMP/upd-root}" bash "$UPD" "$@" >"$TMP/upd.out" 2>&1
}
want_doc="doctor --post-update"; [[ $EUID -eq 0 ]] && want_doc="doctor --post-update --system"
rm -f "$TMP/upd.log"; rc=0; update --noconfirm || rc=$?
if [[ $rc == 0 && "$(cat "$TMP/upd.log")" == "$(printf -- '-Syu --noconfirm\n%s' "$want_doc")" ]]; then
    ok "one pacman -Syu, then invictus-doctor --post-update"
else
    bad "update calls: rc $rc: $(cat "$TMP/upd.log")"
fi
rm -f "$TMP/upd.log"; rc=0; FAKE_PACMAN_RC=1 update || rc=$?
if [[ $rc == 1 && "$(cat "$TMP/upd.log")" == "-Syu" ]]; then ok "pacman failing stops it (exit 1, no doctor)"
else bad "pacman failure: rc $rc, calls: $(cat "$TMP/upd.log")"; fi
rm -f "$TMP/upd.log"; rc=0; FAKE_DOCTOR_RC=1 update || rc=$?
if [[ $rc == 3 ]]; then ok "a doctor problem after a good update exits 3"; else bad "doctor failure: rc $rc"; fi
# H1: --system (the root helper's call) runs the doctor's system checks and
# touches nothing in a home: no waybar cache, no paru.
mkdir -p "$TMP/h-upd/.cache"; : > "$TMP/h-upd/.cache/waybar-updates.cache"
rm -f "$TMP/upd.log"; rc=0; update --noconfirm --system || rc=$?
if [[ $rc == 0 && "$(cat "$TMP/upd.log")" == "$(printf -- '-Syu --noconfirm\ndoctor --post-update --system')" && -e "$TMP/h-upd/.cache/waybar-updates.cache" ]]; then
    ok "H1-update-system: invictus-update --system runs -Syu, then the doctor's system checks, and leaves the home alone"
else bad "H1-update-system: rc $rc: $(paste -sd'|' "$TMP/upd.log" 2>/dev/null)"; fi
# Janus P-L2: a dev install whose ssh generator mask the installer wrote
# (a link to /dev/null that no package owns) gets --overwrite for exactly
# that path, so invictus-sys 0.2.0-5's own copy does not stop the update.
gmask=/etc/systemd/system-generators/systemd-ssh-generator
mkdir -p "$TMP/upd-dev/etc/systemd/system-generators"; ln -sfn /dev/null "$TMP/upd-dev$gmask"
rm -f "$TMP/upd.log"; rc=0; UPD_ROOT="$TMP/upd-dev" update --noconfirm || rc=$?
if [[ $rc == 0 && "$(sed -n 1,2p "$TMP/upd.log")" == "$(printf -- '-Qqo -- %s\n-Syu --noconfirm --overwrite %s' "$gmask" "$gmask")" ]]; then
    ok "P-L2: an unowned ssh generator mask (-> /dev/null) gets pacman --overwrite for that one path"
else bad "P-L2 unowned mask: rc $rc: $(paste -sd'|' "$TMP/upd.log" 2>/dev/null)"; fi
rm -f "$TMP/upd.log"; rc=0; FAKE_QO_RC=0 UPD_ROOT="$TMP/upd-dev" update --noconfirm || rc=$?
if [[ $rc == 0 && "$(sed -n 2p "$TMP/upd.log")" == "-Syu --noconfirm" ]]; then
    ok "P-L2: once invictus-sys owns the mask, no --overwrite"
else bad "P-L2 owned mask: rc $rc: $(paste -sd'|' "$TMP/upd.log" 2>/dev/null)"; fi
ln -sfn /etc/hosts "$TMP/upd-dev$gmask"
rm -f "$TMP/upd.log"; rc=0; UPD_ROOT="$TMP/upd-dev" update --noconfirm || rc=$?
if [[ $rc == 0 && "$(sed -n 1p "$TMP/upd.log")" == "-Syu --noconfirm" ]] && ! grep -q -- --overwrite "$TMP/upd.log"; then
    ok "P-L2: a link there that is not to /dev/null gets no --overwrite (pacman's conflict stands)"
else bad "P-L2 other link: rc $rc: $(paste -sd'|' "$TMP/upd.log" 2>/dev/null)"; fi
rm -f "$TMP/upd.log"; rc=0; update --noconfirm || rc=$?
if [[ $rc == 0 && "$(sed -n 1p "$TMP/upd.log")" == "-Syu --noconfirm" ]] && ! grep -q -- -Qqo "$TMP/upd.log"; then
    ok "P-L2: no mask link: no ownership question, no --overwrite"
else bad "P-L2 no link: rc $rc: $(paste -sd'|' "$TMP/upd.log" 2>/dev/null)"; fi
# ... and the same for -Syu --needed (install verb, pending extras, ai on: lib/pacman.sh)
ln -sfn /dev/null "$TMP/upd-dev$gmask"
rm -f "$TMP/upd.log"
(
    export INVICTUS_SYS_ROOT="$TMP/upd-dev" FAKE_LOG="$TMP/upd.log"
    PACMAN="$TMP/fake/pacman"; INHIBIT=()
    # shellcheck source=scripts/lib/pacman.sh
    . "$REPO/scripts/lib/pacman.sh"
    pacman_install_needed vlc
)
if [[ "$(sed -n 2p "$TMP/upd.log")" == "-Syu --needed --noconfirm --overwrite $gmask -- vlc" ]]; then
    ok "P-L2: pacman_install_needed (install verb, pending extras, ai on) passes the same --overwrite"
else bad "P-L2 lib: $(paste -sd'|' "$TMP/upd.log" 2>/dev/null)"; fi
rc=0; update --system --aur || rc=$?
if [[ $rc == 2 ]]; then ok "H1-update-system: --aur is refused with --system (AUR builds are per person)"
else bad "H1: --system --aur ran (rc $rc)"; fi
if grep -qE '\bgit\b|stash' <(grep -v '^#' "$UPD"); then bad "invictus-update mentions git or stash"
else ok "invictus-update has no git and no stash"; fi
# No shipped or dev script may run pacman -Sy without u (partial upgrade),
# except against a throwaway --dbpath.
sy="$(grep -rnE 'pacman[^|;&]*[[:space:]]-S[a-tv-z]*y[a-tv-z]*([[:space:]]|$|")' "$REPO/scripts" "$REPO/pkgs" \
      | grep -v -- '--dbpath' | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' || true)"
if [[ -z "$sy" ]]; then ok "no script runs pacman -Sy without -u (throwaway --dbpath excepted)"
else bad "partial upgrade: $sy"; fi
echo

# ---- 9. pinned set and repo names ----------------------------------------------------
echo "== pinned set"
# shellcheck source=scripts/lib/repo-names.sh
. "$REPO/scripts/lib/repo-names.sh"
if [[ "$(repo_file_name 'proton-ge-custom-bin-1:GE_Proton11_7-1-x86_64.pkg.tar.zst')" == proton-ge-custom-bin-1.GE_Proton11_7-1-x86_64.pkg.tar.zst \
      && "$(repo_file_name 'a+b-1.0-1-any.pkg.tar.zst')" == a.b-1.0-1-any.pkg.tar.zst ]]; then
    ok "repo file names swap ':' and '+' for '.'"
else
    bad "repo_file_name wrong"
fi
n_all="$(cat "$REPO"/pkgs/pinned/*.lock | grep -cv '^[[:space:]]*\(#\|$\)')"
if ! cat "$REPO"/pkgs/pinned/*.lock | grep -v '^[[:space:]]*\(#\|$\)' | grep -vE '^[a-z0-9-]+ [0-9:.a-z_+]+-[0-9]+ x86_64 [0-9a-f]{64}$' >/dev/null \
   && [[ "$(bash "$REPO/scripts/fetch-pinned.sh" --list | wc -l)" == "$n_all" ]] \
   && [[ "$(PINNED_LOCK="$REPO/pkgs/pinned/hypr.lock" bash "$REPO/scripts/fetch-pinned.sh" --list | wc -l)" == "$n_lock" ]]; then
    ok "pkgs/pinned/*.lock: $n_all entries ($n_lock hypr), each name version arch sha256; --list names them offline"
else
    bad "a lock's format or --list wrong"
fi
# The kernel (Alex, 2026-09-30): linux-cachyos from CachyOS, verified with
# CachyOS's key only, generic x86-64 build, never the CachyOS repos in an
# installed pacman.conf.
cl="$REPO/pkgs/pinned/cachyos.lock"
cfpr=882DCFE48E2051D48E2562ABF3B607488DB35A47
if grep -qx "#@ source https://mirror.cachyos.org/repo/x86_64/cachyos" "$cl" \
   && grep -qx "#@ key pkgs/pinned/keys/$cfpr.asc $cfpr" "$cl" \
   && grep -q '^linux-cachyos [0-9.]*-[0-9]* x86_64 ' "$cl" && grep -q '^linux-cachyos-headers [0-9.]*-[0-9]* x86_64 ' "$cl" \
   && [[ "$(awk '$1 == "linux-cachyos" { print $2 }' "$cl")" == "$(awk '$1 == "linux-cachyos-headers" { print $2 }' "$cl")" ]]; then
    ok "cachyos.lock: generic x86_64 [cachyos] source, CachyOS's key, kernel and headers at one version"
else
    bad "cachyos.lock: source, key or kernel/headers entries wrong"
fi
if command -v gpg >/dev/null; then
    gh="$TMP/gnupg-cachyos"; mkdir -p "$gh"; chmod 700 "$gh"
    got="$(GNUPGHOME="$gh" gpg --batch --with-colons --show-keys "$REPO/pkgs/pinned/keys/$cfpr.asc" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
    if [[ "$got" == "$cfpr" ]]; then ok "the CachyOS key file holds key $cfpr"
    else bad "pkgs/pinned/keys/$cfpr.asc holds '$got'"; fi
fi
if ! grep -rqi 'cachyos' "$REPO/iso/airootfs/etc/pacman.conf" "$REPO/iso/pacman.conf"; then
    ok "no CachyOS repo in the ISO's or the installed pacman.conf"
else
    bad "a pacman.conf names a CachyOS repo"
fi
# fetch-pinned refuses a lock whose source has no key, or a bad key line.
for bad_lock in "#@ source https://example.org/x" \
                $'#@ source https://example.org/x\n#@ key pkgs/pinned/keys/none.asc '"$cfpr" \
                $'#@ source https://example.org/x\n#@ key /etc/passwd '"$cfpr" \
                $'#@ source http://example.org/x\n#@ key pkgs/pinned/keys/'"$cfpr.asc $cfpr"; do
    printf '%s\nlinux-cachyos 1-1 x86_64 %s\n' "$bad_lock" "$(printf '0%.0s' {1..64})" > "$TMP/bad.lock"
    if PINNED_LOCK="$TMP/bad.lock" bash "$REPO/scripts/fetch-pinned.sh" --list >/dev/null 2>&1; then
        bad "fetch-pinned accepted a bad lock header: $(head -2 "$TMP/bad.lock" | paste -sd'|')"
    fi
done
ok "fetch-pinned refuses a source without a key, a missing or outside key file, and plain http"
for p in hyprland aquamarine hyprutils hyprlang hyprgraphics hyprcursor xdg-desktop-portal-hyprland hyprpaper hypridle hyprlock hyprpolkitagent; do
    grep -q "^$p " "$REPO/pkgs/pinned/hypr.lock" || bad "design 1.5 names $p, the lock does not"
done
want="$(grep -o '0\.[0-9]*\.[0-9]*' <<< "$(grep -m1 'Hyprland [0-9]' "$REPO/config/hypr/invictus/core.lua")")"
have="$(awk '$1 == "hyprland" { print $2 }' "$REPO/pkgs/pinned/hypr.lock")"
if [[ -n "$want" && "$have" == "$want"-* ]]; then ok "pinned hyprland $have is the version the Lua config is written for ($want)"
else bad "pinned hyprland $have, config written for '$want'"; fi
echo

# ---- 10. hyprlang porter ---------------------------------------------------------------
echo "== hyprlang porter"
if [[ -z "$LUA" ]]; then
    bad "no lua: porter not tested"
else
    # shellcheck source=tests/pkgs/lib/legacy-home.sh
    . "$HERE/lib/legacy-home.sh"
    H="$TMP/h-legacy"
    make_legacy_home "$REPO" "$H"
    # Regression (e2e, 2026-09-30): "true" occurs in binds.lua (locked = true),
    # and a substring match took this bind for a shipped one.
    # shellcheck disable=SC2016 # a literal hyprlang variable
    echo 'bind = $mainMod SHIFT, T, exec, true' >> "$H/.config/hypr/config/keybindings.conf"
    # The shipped binds.lua and rules.lua carry nothing of Alex's (his dashboard bind, his monitor pins).
    if grep -q 'dashboard-tmux' "$REPO/config/hypr/invictus/binds.lua" || grep -Eq 'HDMI-A-2|DP-2|discord-assign|zen-assign' "$REPO/config/hypr/invictus/rules.lua"; then
        bad "shipped binds.lua/rules.lua still carry Alex's dashboard bind or monitor pins"
    else
        ok "shipped binds.lua/rules.lua carry no dashboard-tmux bind and no monitor pins"
    fi
    "$LUA" "$REPO/scripts/dev/port-hyprlang.lua" "$H/.config/hypr" "$H/hyprdots/config/hypr" "$REPO/config/hypr/invictus/binds.lua" \
        "$REPO/config/hypr/monitors.lua" "$REPO/config/hypr/user.lua" "$TMP/mon.lua" "$TMP/user.lua" > "$TMP/port.log" 2>&1
    if grep -q 'hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("firefox --private-window")' "$TMP/user.lua" \
       && grep -q 'hl.bind("SUPER + minus", hl.dsp.exec_cmd("kitty --title dashboard -e ~/.local/bin/dashboard-tmux"), { description = "Personal: Toggle dashboard terminal (tmux)" })' "$TMP/user.lua" \
       && grep -q '^-- (config/aesthetics.conf) vfr = false' "$TMP/user.lua" \
       && grep -q 'hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("true")' "$TMP/user.lua" \
       && [[ "$(grep -c '^hl.bind' "$TMP/user.lua")" == 3 ]]; then
        ok "porter: your added binds (even one running 'true') and dashboard-tmux ported, other added lines kept as comments"
    else
        bad "porter user.lua: $(cat "$TMP/port.log"); $(sed -n '/Ported/,$p' "$TMP/user.lua")"
    fi
    if grep -q 'name    = "discord-assign"' "$TMP/user.lua" && grep -q 'monitor = "HDMI-A-2"' "$TMP/user.lua" \
       && grep -q 'match   = { class = "^(discord)\$" }' "$TMP/user.lua" \
       && grep -q 'name    = "zen-assign"' "$TMP/user.lua" && grep -q 'monitor = "DP-2"' "$TMP/user.lua" \
       && [[ "$(grep -c '^hl.window_rule' "$TMP/user.lua")" == 2 ]]; then
        ok "porter: Discord and Zen monitor pins become hl.window_rule in user.lua"
    else
        bad "porter window rules: $(cat "$TMP/port.log"); $(sed -n '/Ported/,$p' "$TMP/user.lua")"
    fi
    # A bind or rule the shipped files already have is not added twice.
    mkdir -p "$TMP/shipped2"
    cp "$REPO/config/hypr/invictus/binds.lua" "$TMP/shipped2/binds.lua"
    { cat "$REPO/config/hypr/invictus/rules.lua"; printf 'hl.window_rule({ name = "discord-assign", match = { class = "^(discord)$" }, monitor = "X" })\n'; } > "$TMP/shipped2/rules.lua"
    printf 'hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("firefox --private-window"), {})\n' >> "$TMP/shipped2/binds.lua"
    "$LUA" "$REPO/scripts/dev/port-hyprlang.lua" "$H/.config/hypr" "$H/hyprdots/config/hypr" "$TMP/shipped2/binds.lua" \
        "$REPO/config/hypr/monitors.lua" "$REPO/config/hypr/user.lua" "$TMP/mon2.lua" "$TMP/user2.lua" > "$TMP/port2.log" 2>&1
    if grep -q "already in the shipped binds: firefox" "$TMP/port2.log" \
       && ! grep -q 'firefox --private-window' "$TMP/user2.lua" \
       && ! grep -q discord-assign "$TMP/user2.lua" && grep -q zen-assign "$TMP/user2.lua"; then
        ok "porter: a bind or rule the shipped files already have is not added twice"
    else
        bad "porter duplicates: $(cat "$TMP/port2.log"); $(sed -n '/Ported/,$p' "$TMP/user2.lua")"
    fi
    if grep -q 'output   = "DP-1"' "$TMP/mon.lua" && grep -q 'mode     = "2560x1440@165"' "$TMP/mon.lua"; then
        ok "porter: monitor lines become hl.monitor{}"
    else
        bad "porter monitors.lua: $(tail -8 "$TMP/mon.lua")"
    fi
    # Workspace pins become hl.workspace_rule{}; what the porter does not scan is listed as not ported.
    H2="$TMP/h-legacy2"
    make_legacy_home "$REPO" "$H2"
    printf 'workspace = 1, monitor:DP-1, default:true\nworkspace = 4, monitor:HDMI-A-1, persistent:true, rounding:false\nworkspace = 7, monitor:DP-2, weird:thing\n' \
        >> "$H2/.config/hypr/config/assign-workspaces.conf"
    mkdir -p "$H2/extra"
    printf 'workspace = 9, monitor:DP-3\nbind = SUPER, F11, exec, notify-send sourced\n' > "$H2/extra/more.conf"
    # shellcheck disable=SC2016 # literal hyprlang text
    printf 'source = ~/extra/more.conf\nsource = $HOME/extra/gone.conf\nsource = $FOO/x.conf\nbind = SUPER, F12, exec, notify-send own\nmonitorv2 {\n    output = DP-3\n    mode = 1920x1080@60\n}\n' \
        >> "$H2/.config/hypr/hyprland.conf"
    HOME="$H2" "$LUA" "$REPO/scripts/dev/port-hyprlang.lua" "$H2/.config/hypr" "$H2/hyprdots/config/hypr" "$REPO/config/hypr/invictus/binds.lua" \
        "$REPO/config/hypr/monitors.lua" "$REPO/config/hypr/user.lua" "$TMP/mon3.lua" "$TMP/user3.lua" > "$TMP/port3.log" 2>&1
    if grep -q '^    workspace = "1",' "$TMP/user3.lua" && grep -q '^    monitor = "DP-1",' "$TMP/user3.lua" \
       && grep -q '^    default = true,' "$TMP/user3.lua" && grep -q '^    no_rounding = true,' "$TMP/user3.lua" \
       && grep -q '^    workspace = "9",' "$TMP/user3.lua" \
       && [[ "$(grep -c '^hl.workspace_rule' "$TMP/user3.lua")" == 4 ]]; then
        ok "porter: workspace = N, monitor:X lines (also from a sourced file outside config/) become hl.workspace_rule{}"
    else
        bad "porter workspace rules: $(cat "$TMP/port3.log"); $(sed -n '/Ported/,$p' "$TMP/user3.lua")"
    fi
    # shellcheck disable=SC2016 # literal text with a $
    if grep -q '^  not ported: hyprland.conf:[0-9]*: monitorv2 block' "$TMP/port3.log" \
       && grep -q '^-- monitorv2 {' "$TMP/user3.lua" \
       && grep -q 'not ported: hyprland.conf:[0-9]*: sourced file not found' "$TMP/port3.log" \
       && grep -q 'not ported: hyprland.conf:[0-9]*: source = \$FOO/x.conf' "$TMP/port3.log" \
       && grep -q 'not ported: config/assign-workspaces.conf:[0-9]*: workspace option weird:thing' "$TMP/port3.log" \
       && grep -q 'hl.bind("SUPER + F12", hl.dsp.exec_cmd("notify-send own")' "$TMP/user3.lua" \
       && grep -q 'hl.bind("SUPER + F11", hl.dsp.exec_cmd("notify-send sourced")' "$TMP/user3.lua"; then
        ok "porter: monitorv2, a missing or variable source, an unknown workspace option are listed as not ported with file:line; hyprland.conf and sourced files are scanned"
    else
        bad "porter not-ported report: $(cat "$TMP/port3.log")"
    fi
    # With no old clone, binds that cannot be told from stock ones are counted, not silently dropped.
    HOME="$H2" "$LUA" "$REPO/scripts/dev/port-hyprlang.lua" "$H2/.config/hypr" "" "$REPO/config/hypr/invictus/binds.lua" \
        "$REPO/config/hypr/monitors.lua" "$REPO/config/hypr/user.lua" "$TMP/mon4.lua" "$TMP/user4.lua" > "$TMP/port4.log" 2>&1
    if grep -q 'not ported: (all files): [0-9]* bind line(s)' "$TMP/port4.log"; then
        ok "porter: with no old clone the binds it cannot judge are reported as not ported"
    else
        bad "porter no-clone report: $(cat "$TMP/port4.log")"
    fi
    # The workspace rules load with the shipped modules (stub check).
    mkdir -p "$TMP/ported3"
    sed "s#/usr/share/invictus/hypr/?.lua#$REPO/config/hypr/?.lua#" "$REPO/config/hypr/hyprland.lua" > "$TMP/ported3/hyprland.lua"
    cp "$TMP/mon3.lua" "$TMP/ported3/monitors.lua"; cp "$TMP/user3.lua" "$TMP/ported3/user.lua"
    if (cd "$TMP" && "$LUA" "$REPO/scripts/doctor/hypr-check.lua" "$TMP/ported3/hyprland.lua" "$STUBS") > "$TMP/pc3.log" 2>&1; then
        ok "porter output with workspace rules passes the stub check"
    else
        bad "workspace-rule output fails the stub check: $(grep error "$TMP/pc3.log" | head -3)"
    fi
    # The ported files must load with the shipped modules.
    mkdir -p "$TMP/ported"
    sed "s#/usr/share/invictus/hypr/?.lua#$REPO/config/hypr/?.lua#" "$REPO/config/hypr/hyprland.lua" > "$TMP/ported/hyprland.lua"
    cp "$TMP/mon.lua" "$TMP/ported/monitors.lua"; cp "$TMP/user.lua" "$TMP/ported/user.lua"
    if (cd "$TMP" && "$LUA" "$REPO/scripts/doctor/hypr-check.lua" "$TMP/ported/hyprland.lua" "$STUBS") > "$TMP/pc.log" 2>&1; then
        ok "porter output loads with the shipped modules (stub check)"
    else
        bad "ported config fails the stub check: $(grep error "$TMP/pc.log" | head -3)"
    fi
fi
echo

# ---- 11. a fresh home: theme in place, every style import resolves ----------------
echo "== fresh home"
H="$TMP/h-theme"; mkdir -p "$H"
if HOME="$H" INVICTUS_THEME_CMD="$ALL/usr/bin/invictus-theme" INVICTUS_THEME_DIR="$ALL/usr/share/invictus/theme" \
     INVICTUS_WALLPAPERS="$ALL/usr/share/invictus/wallpapers" INVICTUS_HYPRCTL=false INVICTUS_NOTIFY=true \
     INVICTUS_GSETTINGS=true INVICTUS_SWAYNC_CLIENT=false \
     first_login "$H" > "$TMP/fl.log" 2>&1 && [[ -f "$H/.config/invictus/current/waybar-colors.css" ]]; then
    ok "first login on a fresh home applies the default theme (~/.config/invictus/current), exit 0"
else
    bad "fresh home has no current theme: $(tail -5 "$TMP/fl.log")"
fi
# waybar exits and swaync loses its style if an @import is missing (Felix, 2026-09-30).
i_fail=0
for css in waybar/style.css swaync/style.css; do
    while IFS= read -r imp; do
        [[ -e "$H/.config/$(dirname "$css")/$imp" ]] || { bad "$css imports $imp, which a fresh home does not have"; i_fail=1; }
    done < <(sed -n 's/^@import url("\([^"]*\)").*/\1/p' "$H/.config/$css")
done
while IFS= read -r imp; do
    imp="${imp/#\~/$H}"
    [[ -e "$imp" ]] || { bad "rofi imports $imp, which a fresh home does not have"; i_fail=1; }
done < <(sed -n 's/^@import "\([^"]*\)".*/\1/p' "$H/.config/rofi/themes/theme.rasi" "$H/.config/rofi/config.rasi")
while IFS= read -r inc; do
    inc="${inc/#\~/$H}"; [[ "$inc" == /* ]] || inc="$H/.config/kitty/$inc"
    [[ "$inc" == */motion.d/kitty.conf || -e "$inc" ]] || { bad "kitty includes $inc, which a fresh home does not have"; i_fail=1; }
done < <(sed -n 's/^include \(.*\)$/\1/p' "$H/.config/kitty/kitty.conf")
[[ $i_fail == 0 ]] && ok "every waybar, swaync, rofi and kitty import resolves in a fresh home"
echo

# ---- 12. invictus-motion ----------------------------------------------------------------
echo "== invictus-motion"
MOT="$REPO/scripts/invictus-motion.sh"
cat > "$TMP/fake/tool" <<'EOF2'
#!/bin/sh
echo "$(basename "$0") $*" >> "$FAKE_LOG"
exit 0
EOF2
chmod +x "$TMP/fake/tool"
for t in hyprctl gsettings swaync-client; do ln -sf tool "$TMP/fake/$t"; done
cat > "$TMP/fake/pkill" <<'EOF2'
#!/bin/sh
echo "pkill $*" >> "$FAKE_LOG"
exit 1
EOF2
chmod +x "$TMP/fake/pkill"
motion() {
    FAKE_LOG="$TMP/mot.log" HOME="$H" XDG_CONFIG_HOME="" INVICTUS_SHARE="$SHARE" INVICTUS_HYPRCTL="$TMP/fake/hyprctl" \
        INVICTUS_GSETTINGS="$TMP/fake/gsettings" INVICTUS_SWAYNC_CLIENT="$TMP/fake/swaync-client" \
        INVICTUS_PKILL="$TMP/fake/pkill" INVICTUS_GAMEMODE_FILE="$TMP/game-mode" bash "$MOT" "$@"
}
rm -f "$TMP/mot.log"
if [[ "$(motion get)" == showcase ]] && motion set calm \
   && [[ "$(motion get)" == calm && "$(readlink "$H/.config/invictus/motion.d/kitty.conf")" == "$H/.config/kitty/motion/calm.conf" ]] \
   && cmp -s "$H/.config/waybar/motion.css" "$SHARE/config/waybar/motion/calm.css" \
   && cmp -s "$H/.config/swaync/motion.css" "$SHARE/config/swaync/motion/calm.css" \
   && grep -q '"transition-time": 150' "$H/.config/swaync/config.json" \
   && grep -q 'gsettings set org.gnome.desktop.interface enable-animations false' "$TMP/mot.log" \
   && grep -q 'hyprctl reload' "$TMP/mot.log"; then
    ok "motion set calm: state file, kitty link, waybar and swaync files, 150 ms, GTK off, Hyprland reloaded"
else
    bad "motion set calm: $(cat "$TMP/mot.log")"
fi
if motion set showcase && cmp -s "$H/.config/waybar/motion.css" "$SHARE/config/waybar/motion.css" \
   && cmp -s "$H/.config/swaync/config.json" "$SHARE/config/swaync/config.json" \
   && grep -q 'enable-animations true' "$TMP/mot.log"; then
    ok "motion set showcase puts the shipped files back (config.json identical)"
else
    bad "motion set showcase did not restore the defaults"
fi
touch "$TMP/game-mode"; rm -f "$TMP/mot.log"
motion set off 2>/dev/null
if ! grep -q 'hyprctl' "$TMP/mot.log" && [[ "$(motion get)" == off ]]; then ok "game mode on: level saved, Hyprland not reloaded"
else bad "motion in game mode: $(cat "$TMP/mot.log")"; fi
rm -f "$TMP/game-mode"
before="$(motion get)"
if ! motion set wobbly 2>/dev/null && [[ "$(motion get)" == "$before" ]]; then ok "an unknown level is refused and changes nothing"
else bad "motion accepted an unknown level"; fi
echo

# ---- 13. installer extras: pending-extras and its service ------------------------------------
echo "== pending extras"
PX="$REPO/scripts/invictus-extras.sh"
if [[ -x "$ALL/usr/lib/invictus/pending-extras" && -f "$ALL/usr/share/invictus/extras.list" \
      && -f "$ALL/usr/lib/systemd/system/invictus-extras.service" \
      && ! -e "$ALL/usr/lib/systemd/system/multi-user.target.wants/invictus-extras.service" ]]; then
    ok "invictus-tools ships pending-extras, extras.list and the service, not enabled (the installer enables it)"
else
    bad "pending-extras, extras.list or invictus-extras.service missing, or the service enabled by the package"
fi
unit="$REPO/scripts/systemd/invictus-extras.service"
if grep -qx 'ConditionPathExists=/var/lib/invictus/pending-extras' "$unit" && grep -qx 'After=network-online.target' "$unit" \
   && grep -qx 'ExecStart=/usr/lib/invictus/pending-extras' "$unit" && grep -qx 'RestartPreventExitStatus=2' "$unit" \
   && grep -qx 'ConditionPathIsSymbolicLink=!/var/lib/invictus/pending-extras' "$unit" && grep -qx 'Nice=10' "$unit" \
   && grep -qx 'IOSchedulingClass=idle' "$unit" && ! grep -Eq '^Protect(System|Home)' "$unit"; then
    ok "F5: the service runs only with something pending (never a symlink), after the network, at low priority, and does not retry a bad file"
else
    bad "invictus-extras.service conditions wrong"
fi
cat > "$TMP/fake/sysctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$FAKE_LOG"
EOF
cat > "$TMP/fake/inhibit" <<'EOF'
#!/bin/sh
echo "inhibit" >> "$FAKE_LOG"
exec "$@"
EOF
chmod +x "$TMP/fake/sysctl" "$TMP/fake/inhibit"
# The pending file must be root's; tests run as anyone, so the expected owner is ours.
echo boot-1 > "$TMP/px-boot"
pending() {
    FAKE_LOG="$TMP/px.log" INVICTUS_PACMAN="$TMP/fake/pacman" INVICTUS_SYSTEMCTL="$TMP/fake/sysctl" \
        INVICTUS_INHIBIT="$TMP/fake/inhibit" INVICTUS_EXTRAS_PENDING="$TMP/px-pending" \
        INVICTUS_EXTRAS_OWNER="${PX_OWNER:-$(id -u)}" INVICTUS_BOOT_ID="$TMP/px-boot" INVICTUS_DOCTOR="$TMP/fake/doctor" \
        INVICTUS_EXTRAS_LIST="$REPO/scripts/lib/extras.list" INVICTUS_LIB="$REPO/scripts" bash "$PX" >"$TMP/px.out" 2>&1
}
printf 'invictus-office\ninvictus-gaming\n' > "$TMP/px-pending"; rm -f "$TMP/px.log"; rc=0; pending || rc=$?
if [[ $rc == 0 && "$(cat "$TMP/px.log")" == "$(printf 'inhibit\n-Syu --needed --noconfirm -- invictus-office invictus-gaming\nsystemctl disable invictus-extras.service\ndoctor --system')" \
      && ! -e "$TMP/px-pending" && ! -e "$TMP/px-pending.tries" ]]; then
    ok "F1: pending extras: one pacman -Syu --needed under a shutdown inhibitor, then the file goes, the service is disabled and invictus-doctor --system runs (never a home, H1)"
else
    bad "pending extras run: rc $rc: $(paste -sd'|' "$TMP/px.log")"
fi
printf 'noto-fonts-cjk\n' > "$TMP/px-pending"; rm -f "$TMP/px.log"; rc=0; FAKE_PACMAN_RC=1 pending || rc=$?
if [[ $rc == 1 && -s "$TMP/px-pending" ]] && ! grep -q systemctl "$TMP/px.log"; then
    ok "pending extras: pacman failing keeps the file and the service for the next start"
else
    bad "pending extras failure: rc $rc, file $(cat "$TMP/px-pending" 2>/dev/null), log $(paste -sd'|' "$TMP/px.log")"
fi
for evil in "linux" "invictus-moneta" "--config=/tmp/x" "a b"; do
    printf 'invictus-office\n%s\n' "$evil" > "$TMP/px-pending"; rm -f "$TMP/px.log"; rc=0; pending || rc=$?
    if [[ $rc == 2 && ! -s "$TMP/px.log" ]]; then :; else bad "pending extras accepted '$evil' (rc $rc)"; fi
done
ok "pending extras: a name not in extras.list stops it before pacman (exit 2)"
# Janus F2: the pending file must be a plain file owned by root; a bad line is reported by number, never echoed.
printf 'invictus-office\n' > "$TMP/px-pending"; rm -f "$TMP/px.log"; rc=0; PX_OWNER=$(($(id -u) + 1)) pending || rc=$?
if [[ $rc == 2 && ! -s "$TMP/px.log" ]] && grep -q 'not a plain file owned by root' "$TMP/px.out"; then
    ok "F2: pending extras: a pending file owned by someone else is refused (exit 2), no pacman"
else bad "F2 pending extras wrong owner: rc $rc, $(cat "$TMP/px.out")"; fi
printf 'invictus-office\n' > "$TMP/px-real"; rm -f "$TMP/px-pending" "$TMP/px.log"; ln -s "$TMP/px-real" "$TMP/px-pending"; rc=0; pending || rc=$?
if [[ $rc == 2 && ! -s "$TMP/px.log" ]]; then ok "F2: pending extras: a symlink is refused (exit 2), no pacman"
else bad "F2 pending extras symlink: rc $rc, $(cat "$TMP/px.out")"; fi
rm -f "$TMP/px-pending" "$TMP/px-real"
# shellcheck disable=SC2016  # a literal $(reboot) that must never be run or shown
printf 'invictus-office\nSECRET-$(reboot)\n' > "$TMP/px-pending"; rc=0; pending || rc=$?
if [[ $rc == 2 ]] && grep -q 'bad line 2' "$TMP/px.out" && ! grep -q 'SECRET' "$TMP/px.out"; then ok "F2: pending extras: a bad line is logged as 'bad line N', its text is not echoed"
else bad "F2 pending extras bad line message: $(cat "$TMP/px.out")"; fi
# Janus F3: five boots at most, counted per boot, then one clear line and the file stays.
rm -f "$TMP/px-pending" "$TMP/px-pending.tries"; printf 'invictus-office\ninvictus-gaming\n' > "$TMP/px-pending"
for b in 1 2 3 4 5; do
    echo "boot-$b" > "$TMP/px-boot"; rm -f "$TMP/px.log"; rc=0; FAKE_PACMAN_RC=1 pending || rc=$?
    [[ $rc == 1 && "$(grep -c -- '-Syu' "$TMP/px.log")" == 1 ]] || bad "F3 pending extras boot $b: rc $rc, $(paste -sd'|' "$TMP/px.log")"
done
rm -f "$TMP/px.log"; rc=0; FAKE_PACMAN_RC=1 pending || rc=$?   # a retry inside boot 5 still tries
if [[ $rc == 1 && "$(grep -c -- '-Syu' "$TMP/px.log")" == 1 && "$(awk '{print $2}' "$TMP/px-pending.tries")" == 5 ]]; then
    ok "F3: pending extras: retries within one boot do not use up an attempt; boots 1 to 5 each try"
else bad "F3 pending extras retry inside a boot: rc $rc, tries $(cat "$TMP/px-pending.tries")"; fi
if grep -q 'Extras not installed: invictus-office invictus-gaming' "$TMP/px.out"; then
    ok "F3: pending extras: the fifth failed boot logs 'Extras not installed: <names>'"
else bad "F3 pending extras 5th boot message: $(cat "$TMP/px.out")"; fi
echo boot-6 > "$TMP/px-boot"; rm -f "$TMP/px.log"; rc=0; pending || rc=$?
if [[ $rc == 0 && "$(paste -sd'|' "$TMP/px.log")" == "systemctl disable invictus-extras.service" ]] \
   && grep -q 'Extras not installed: invictus-office invictus-gaming' "$TMP/px.out" && [[ -s "$TMP/px-pending" ]]; then
    ok "F3: pending extras: from the sixth boot no pacman, the file stays, one log line, service disabled, exit 0"
else bad "F3 pending extras sixth boot: rc $rc, log $(paste -sd'|' "$TMP/px.log" 2>/dev/null), $(cat "$TMP/px.out")"; fi
rm -f "$TMP/px-pending" "$TMP/px-pending.tries"; echo boot-1 > "$TMP/px-boot"
rm -f "$TMP/px-pending" "$TMP/px.log"; rc=0; pending || rc=$?
if [[ $rc == 0 && ! -s "$TMP/px.log" ]]; then ok "pending extras: nothing pending does nothing"
else bad "pending extras with no file: rc $rc"; fi
echo
