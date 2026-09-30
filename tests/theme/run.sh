#!/usr/bin/env bash
# ------------------------------------------------------------
# Tests for theme/invictus-theme. Needs no running desktop.
#
#   tests/theme/run.sh
#
# 1. check passes on all four themes.
# 2. Broken themes fail check: missing token, low contrast, focus too
#    close to an error colour for colour-blind users, over-long concept.
# 3. generate writes every template's file for every theme; files parse
#    (Lua via luac -p, SVG via python xml, CSS/rasi braces balance, no
#    leftover placeholders).
# 4. apply against a temp HOME with every reload command stubbed:
#    link swapped, reload commands run in order, game mode skips the
#    Hyprland reload, a failing step gives one notification, a failing
#    theme changes nothing.
# 5. pick with a stub rofi.
# 6. The shipped app configs in config/: no hand-written colours outside the
#    fallback files, fallbacks equal generated Dusk, every app loads the generated
#    file, waybar/swaync/rofi/kitty/fastfetch settings from docs/look.md, alert.sh.
# 7. shellcheck of this file and scripts/waybar/alert.sh.
# ------------------------------------------------------------
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
TOOL="$REPO/theme/invictus-theme"
THEMES=(dusk porphyry aegean alexandria)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
expect() { # description, then a command that must succeed
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}
expect_not() {
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi
}

# A HOME with stubs. Each stub appends "<name> <args>" to $TMP/calls.
new_env() { # sets HOME and stub env vars; $1 = subdir name
    export HOME="$TMP/$1/home"
    mkdir -p "$HOME" "$TMP/$1/bin"
    : > "$TMP/$1/calls"
    for s in hyprctl pkill swaync-client gsettings notify-send rofi; do
        cat > "$TMP/$1/bin/$s" <<STUB
#!/usr/bin/env bash
echo "$s \$*" >> "$TMP/$1/calls"
if [[ "\$*" == *"-j monitors"* ]]; then
  echo '[{"name":"DP-1","width":5120,"height":1440},{"name":"DP-2","width":2560,"height":1440}]'
elif [[ "$s" == gsettings && "\$1" == get ]]; then
  echo "'adw-gtk3-dark'"
elif [[ "$s" == rofi ]]; then
  cat > "$TMP/$1/rofi-stdin"
  echo "\${STUB_ROFI_CHOICE:-}"
fi
[[ -n "\${STUB_FAIL:-}" && "\$*" == *"\$STUB_FAIL"* ]] && exit 3
exit 0
STUB
        chmod +x "$TMP/$1/bin/$s"
    done
    export INVICTUS_HYPRCTL="$TMP/$1/bin/hyprctl" INVICTUS_PKILL="$TMP/$1/bin/pkill" \
        INVICTUS_SWAYNC_CLIENT="$TMP/$1/bin/swaync-client" INVICTUS_GSETTINGS="$TMP/$1/bin/gsettings" \
        INVICTUS_NOTIFY="$TMP/$1/bin/notify-send" INVICTUS_ROFI="$TMP/$1/bin/rofi"
    export INVICTUS_GAMEMODE_FILE="$TMP/$1/game-mode"
    export INVICTUS_WALLPAPERS="$TMP/$1/wallpapers"
    mkdir -p "$INVICTUS_WALLPAPERS"
    unset INVICTUS_CONFIG INVICTUS_STATE STUB_FAIL STUB_ROFI_CHOICE
}
calls() { cat "$TMP/$1/calls"; }

echo "1. check on the four themes"
new_env t1
for t in "${THEMES[@]}"; do expect "check $t" "$TOOL" check "$t"; done
expect "check (all)" "$TOOL" check
expect "list shows four" test "$("$TOOL" list | wc -l)" -eq 4
expect "list puts dusk first" bash -c "'$TOOL' list | head -1 | grep -q dusk"

echo "2. broken themes fail check"
new_env t2
mkdir -p "$HOME/.config/invictus/themes"
U="$HOME/.config/invictus/themes"
mk() { # id, sed expression applied to dusk.toml
    sed -e "s/^id = .*/id = \"$1\"/" -e "$2" "$REPO/theme/dusk.toml" > "$U/$1.toml"
}
mk missing '/^tyrian = /d'
mk lowcontrast 's/^ash = .*/ash = "#3A352D"/'
mk lightfail 's/^ink-muted = .*/ink-muted = "#C0B8A8"/'
mk nobright 's/^color8 = .*/color8 = "#27241F"/'
mk cvd 's/^sol = .*/sol = "#D9866A"/'
mk longconcept 's/^concept = .*/concept = "This concept line is far too long to fit in the picker row of a theme."/'
mk badhex 's/^laurel = .*/laurel = "green"/'
# shellcheck disable=SC2016
mk nosection '/^\[terminal\]/,$d'
for b in missing lowcontrast lightfail nobright cvd longconcept badhex nosection; do
    expect_not "check $b fails" "$TOOL" check "$b"
done
expect "missing names the token" bash -c "'$TOOL' check missing | grep -q 'dark.tyrian missing'"
expect "contrast names the pair" bash -c "'$TOOL' check lowcontrast | grep -q 'ash on night'"
expect "cvd names the pair" bash -c "'$TOOL' check cvd | grep -q 'colour-blind'"
expect "user themes appear in list after built-ins" bash -c "'$TOOL' list | tail -1 | grep -q ' nosection\$\| nosection '"
# a theme with an unknown token in a template must not generate
mkdir -p "$TMP/badtpl/templates"
cp "$REPO/theme/dusk.toml" "$TMP/badtpl/"
echo '{{nope}}' > "$TMP/badtpl/templates/x.txt"
expect_not "unknown template token fails" env INVICTUS_THEME_DIR="$TMP/badtpl" "$TOOL" generate dusk "$TMP/badtpl-out"
expect "and writes nothing" test ! -e "$TMP/badtpl-out/x.txt"

echo "3. generate"
new_env t3
n_tpl=$(find "$REPO/theme/templates" -maxdepth 1 -type f | wc -l)
for t in "${THEMES[@]}"; do
    out="$TMP/gen-$t"
    expect "generate $t" "$TOOL" generate "$t" "$out"
    expect "$t: $n_tpl template files + id" test "$(find "$out" -maxdepth 1 -type f \( ! -name '*.png' \) | wc -l)" -eq $((n_tpl + 1))
    for tpl in "$REPO"/theme/templates/*; do
        expect "$t: $(basename "$tpl") written" test -s "$out/$(basename "$tpl")"
    done
    expect "$t: no placeholders left" bash -c "! grep -rl '{{' '$out'"
    expect "$t: Lua parses" luac -p "$out/hyprland-colors.lua"
    expect "$t: Lua returns sol" lua -e "local c = dofile('$out/hyprland-colors.lua'); assert(c.sol:match('^rgb%(%x%x%x%x%x%x%)$'))"
    for f in "$out"/*.svg; do expect "$t: $(basename "$f") is XML" python3 -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$f"; done
    for f in waybar-colors.css swaync-colors.css gtk-colors.css gtk-colors-light.css desk-tokens.css rofi-colors.rasi rofi-picker.rasi; do
        expect "$t: $f braces balance" python3 -c "
import sys; s=open(sys.argv[1]).read(); assert s.count('{')==s.count('}') and s.count('(')==s.count(')')" "$out/$f"
    done
    for f in waybar-colors.css swaync-colors.css gtk-colors.css gtk-colors-light.css; do
        expect "$t: $f defines end in ;" bash -c "! grep '@define-color' '$out/$f' | grep -qv ';\$'"
    done
    expect "$t: kitty has 16 colours" test "$(grep -c '^color[0-9]* #' "$out/kitty-colors.conf")" -eq 16
    expect "$t: btop theme lines" bash -c "grep -q '^theme\[hi_fg\]=\"#' '$out/btop.theme'"
    expect "$t: qt has three palettes of 21" python3 -c "
import sys
n=[len(l.split('=',1)[1].split(',')) for l in open(sys.argv[1]) if '_colors=' in l]
assert n==[21,21,21], n" "$out/qt-colors.conf"
    expect "$t: sol in kitty border matches toml" bash -c "grep -qi \"^active_border_color \$(grep -m1 '^sol = ' '$REPO/theme/$t.toml' | cut -d'\"' -f2)\" '$out/kitty-colors.conf'"
    if command -v rsvg-convert >/dev/null 2>&1; then
        expect "$t: swatch.png rendered" test -s "$out/swatch.png"
        expect "$t: radiate exports" test -s "$out/radiate-5120x1440.png"
    fi
done
command -v rsvg-convert >/dev/null 2>&1 || echo "  note rsvg-convert not installed: PNG exports not tested"
# PNG exports through a stub rsvg-convert (the real one is optional)
cat > "$TMP/rsvg" <<'STUB'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done
echo png > "$out"
STUB
chmod +x "$TMP/rsvg"
expect "generate with rsvg stub" env INVICTUS_RSVG="$TMP/rsvg" "$TOOL" generate dusk "$TMP/gen-png"
for f in swatch.png radiate-3840x2160.png radiate-5120x1440.png night-3840x2160.png night-5120x1440.png; do
    expect "rsvg: $f written" test -s "$TMP/gen-png/$f"
done
# generate reads no repo path: works from another cwd with only arguments
expect "generate from another cwd" bash -c "cd / && '$TOOL' generate aegean '$TMP/cwd-out'"
expect "themes differ in sol" bash -c "! diff -q '$TMP/gen-dusk/kitty-colors.conf' '$TMP/gen-aegean/kitty-colors.conf'"

echo "4. apply (stubbed reloads)"
new_env t4
expect "apply dusk" "$TOOL" apply dusk
S="$HOME/.local/state/invictus/theme"
C="$HOME/.config/invictus/current"
expect "current is a link to dusk" test "$(readlink "$C")" = "$S/dusk"
expect "current/hyprland-colors.lua readable" test -s "$C/hyprland-colors.lua"
expect "no temp folder left" test -z "$(find "$S" -maxdepth 1 -name '.*' -not -path "$S")"
expect "list marks dusk current" bash -c "'$TOOL' list | grep -q '^\* dusk'"
for want in "hyprctl reload" "pkill -SIGUSR2 -x waybar" "swaync-client --reload-css" "pkill -SIGUSR1 -x kitty" \
    "gsettings set org.gnome.desktop.interface accent-color yellow" "pkill -SIGUSR1 -x cava"; do
    expect "ran: $want" grep -qxF "$want" "$TMP/t4/calls"
done
expect "gtk theme toggled and restored" bash -c "grep -q 'gtk-theme Adwaita-dark' '$TMP/t4/calls' && grep -q 'gtk-theme adw-gtk3-dark' '$TMP/t4/calls'"
expect "reload order: waybar after hyprland" bash -c "[ \$(grep -n '^hyprctl reload' '$TMP/t4/calls' | cut -d: -f1) -lt \$(grep -n 'x waybar' '$TMP/t4/calls' | cut -d: -f1) ]"
expect "no notification on success" bash -c "! grep -q '^notify-send' '$TMP/t4/calls'"

# wallpapers found: ultrawide gets the 5120 export, other gets 3840
: > "$TMP/t4/calls"
touch "$INVICTUS_WALLPAPERS/sol-3840x2160.png" "$INVICTUS_WALLPAPERS/sol-5120x1440.png"
"$TOOL" apply dusk >/dev/null 2>&1
expect "ultrawide gets 5120 wallpaper" grep -qF "hyprpaper reload DP-1,$INVICTUS_WALLPAPERS/sol-5120x1440.png" "$TMP/t4/calls"
expect "other output gets 3840 wallpaper" grep -qF "hyprpaper reload DP-2,$INVICTUS_WALLPAPERS/sol-3840x2160.png" "$TMP/t4/calls"
expect "hyprlock file carries the wallpaper path" grep -qF "$INVICTUS_WALLPAPERS/sol-3840x2160.png" "$C/hyprlock-colors.conf"

# switch theme, link moves, old folder kept
: > "$TMP/t4/calls"
expect "apply aegean" "$TOOL" apply aegean
expect "current now aegean" test "$(readlink "$C")" = "$S/aegean"
expect "dusk folder kept" test -d "$S/dusk"
expect "aegean accent is blue" grep -qxF "gsettings set org.gnome.desktop.interface accent-color blue" "$TMP/t4/calls"
expect "apply with no id keeps current" bash -c "'$TOOL' apply && test \"\$(readlink '$C')\" = '$S/aegean'"
expect "set is apply" bash -c "'$TOOL' set porphyry && test \"\$(readlink '$C')\" = '$S/porphyry'"

# game mode skips the Hyprland reload only
: > "$TMP/t4/calls"
touch "$INVICTUS_GAMEMODE_FILE"
"$TOOL" apply alexandria >/dev/null 2>&1
expect "game mode: no hyprctl reload" bash -c "! grep -qx 'hyprctl reload' '$TMP/t4/calls'"
expect "game mode: waybar still reloaded" grep -qF "x waybar" "$TMP/t4/calls"
expect "game mode: link still switched" test "$(readlink "$C")" = "$S/alexandria"
rm -f "$INVICTUS_GAMEMODE_FILE"

# a failing reload step: switch stands, one notification names it
: > "$TMP/t4/calls"
export STUB_FAIL="--reload-css"
"$TOOL" apply dusk >/dev/null 2>&1
expect "failed step: still switched" test "$(readlink "$C")" = "$S/dusk"
expect "failed step: later steps still ran" grep -qF "x cava" "$TMP/t4/calls"
expect "failed step: exactly one notify-send" test "$(grep -c '^notify-send' "$TMP/t4/calls")" -eq 1
expect "failed step: notification names swaync" grep -q '^notify-send.*swaync' "$TMP/t4/calls"
export STUB_FAIL="reload"
: > "$TMP/t4/calls"
"$TOOL" apply dusk >/dev/null 2>&1
expect "several failures: still one notify-send" test "$(grep -c '^notify-send' "$TMP/t4/calls")" -eq 1
unset STUB_FAIL

# hooks: run with the id; a failing hook does not undo the switch
mkdir -p "$HOME/.config/invictus/theme-hooks.d"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "$1" > "%s/hook-ran"\nexit 1\n' "$TMP/t4" > "$HOME/.config/invictus/theme-hooks.d/10-test"
chmod +x "$HOME/.config/invictus/theme-hooks.d/10-test"
"$TOOL" apply aegean >/dev/null 2>&1
expect "hook got the theme id" test "$(cat "$TMP/t4/hook-ran")" = aegean
expect "failing hook: switch stands" test "$(readlink "$C")" = "$S/aegean"
rm -rf "$HOME/.config/invictus/theme-hooks.d"

# a theme that fails check changes nothing and notifies once, critical
mkdir -p "$HOME/.config/invictus/themes"
sed -e 's/^id = .*/id = "broken"/' -e 's/^ash = .*/ash = "#3A352D"/' "$REPO/theme/dusk.toml" > "$HOME/.config/invictus/themes/broken.toml"
: > "$TMP/t4/calls"
expect_not "apply broken exits non-zero" "$TOOL" apply broken
expect "broken: current unchanged" test "$(readlink "$C")" = "$S/aegean"
expect "broken: no folder made" test ! -e "$S/broken"
expect "broken: critical notification 'Theme not changed'" grep -q '^notify-send.*-u critical.*Theme not changed' "$TMP/t4/calls"
expect "broken: no reload ran" bash -c "! grep -qE '^(hyprctl|pkill|swaync)' '$TMP/t4/calls'"
expect_not "apply unknown exits non-zero" "$TOOL" apply nosuchtheme
rm -f "$HOME/.config/invictus/themes/broken.toml"

# a fresh HOME with no current: apply with no id gives Dusk
new_env t4b
"$TOOL" apply >/dev/null 2>&1
expect "fresh install applies Dusk" test "$(readlink "$HOME/.config/invictus/current")" = "$HOME/.local/state/invictus/theme/dusk"

echo "5. pick (stub rofi)"
new_env t5
"$TOOL" apply dusk >/dev/null 2>&1
S="$HOME/.local/state/invictus/theme"; C="$HOME/.config/invictus/current"
: > "$TMP/t5/calls"
export STUB_ROFI_CHOICE=2   # third row: dusk, aegean, alexandria
"$TOOL" pick >/dev/null 2>&1
expect "pick applies the chosen row (alexandria)" test "$(readlink "$C")" = "$S/alexandria"
rofi_line="$(grep '^rofi' "$TMP/t5/calls")"
expect "rofi in dmenu mode with the picker theme" bash -c "[[ '$rofi_line' == *-dmenu* && '$rofi_line' == *rofi-picker.rasi* ]]"
expect "current row preselected" grep -q -- "-selected-row 0" "$TMP/t5/calls"
expect "rows are Dusk first, then alphabetical" python3 -c "
import re,sys
s=open('$TMP/t5/rofi-stdin').read().split('|')
names=[re.search(r'<b>(\w+)</b>', r).group(1) for r in s]
assert names==['Dusk','Aegean','Alexandria','Porphyry'], names"
expect "every row has a swatch icon that exists" python3 -c "
import os,re
for r in open('$TMP/t5/rofi-stdin').read().split('|'):
    p=r.split('\x1f')[1].strip()
    assert os.path.getsize(p)>0, p"
expect "swatch icons live outside the theme folders" test -s "$HOME/.local/state/invictus/swatches/dusk.svg"
expect "current theme has the check glyph" bash -c "grep -q 'Dusk</b>   ✓' '$TMP/t5/rofi-stdin'"
expect "concept is on the second line" bash -c "grep -q 'Lapis night' '$TMP/t5/rofi-stdin'"
# picking the current theme does nothing
: > "$TMP/t5/calls"
export STUB_ROFI_CHOICE=2
"$TOOL" pick >/dev/null 2>&1
expect "picking the current theme reloads nothing" bash -c "! grep -qE '^(hyprctl|pkill|swaync)' '$TMP/t5/calls'"
# Esc (empty output) changes nothing
export STUB_ROFI_CHOICE=
"$TOOL" pick >/dev/null 2>&1
expect "Esc changes nothing" test "$(readlink "$C")" = "$S/alexandria"
# fresh install: pick sets Dusk up first
new_env t5b
export STUB_ROFI_CHOICE=
"$TOOL" pick >/dev/null 2>&1
expect "pick on a fresh install has Dusk in place" test -s "$HOME/.config/invictus/current/rofi-picker.rasi"

echo "6. the shipped app configs (config/)"
DUSK_OUT="$TMP/dusk-out"
"$TOOL" generate dusk "$DUSK_OUT" >/dev/null 2>&1
if config_out=$(python3 "$HERE/config_checks.py" "$REPO" "$DUSK_OUT" 2>&1); then
    n=$(grep -c '^ok' <<<"$config_out")
    pass "config checks: $n passed"
else
    grep -v '^ok' <<<"$config_out" | sed 's/^/  /'
    fail "config checks (see FAIL lines above)"
fi

echo "7. shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    expect "shellcheck run.sh" shellcheck -x "${BASH_SOURCE[0]}"
    expect "shellcheck alert.sh" shellcheck -x "$REPO/scripts/waybar/alert.sh"
else
    echo "  note shellcheck not installed"
fi

echo
if (( fails )); then echo "$fails FAILED"; exit 1; fi
echo "ALL PASSED"
