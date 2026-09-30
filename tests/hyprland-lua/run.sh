#!/usr/bin/env bash
# ------------------------------------------------------------
# Tests for the Lua Hyprland config. Needs no running Hyprland.
#
#   tests/hyprland-lua/run.sh
#
# 1. Compiles every Lua file (luac -p, or load() if luac is missing).
# 2. Loads config/hypr/hyprland.lua against a mock `hl` that checks
#    each call against the Hyprland Lua API, and compares the result
#    with the old hyprlang config in fixtures/.
# 3. Feeds fake `hyprctl binds` output to scripts/show-keybindings.sh.
# 4. Runs scripts/confirm.sh against a fake rofi.
#
# API source: /usr/share/hypr/stubs/hl.meta.lua when Hyprland is
# installed (so it tracks the installed version), else the vendored
# 0.56.2 copy in stubs/. Override with HL_STUBS=/path.
# Key names are checked against XKB_KEYSYMS_H, default
# /usr/include/xkbcommon/xkbcommon-keysyms.h (package libxkbcommon).
#
# Env: LUA=/path/to/lua (default: first of lua5.5, lua5.4, lua)
# ------------------------------------------------------------
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"

pick() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return 0; }; done; return 1; }

LUA="${LUA:-$(pick lua5.5 lua5.4 lua || true)}"
[[ -n "$LUA" ]] || { echo "No Lua interpreter found (install lua or lua54)"; exit 2; }
# luac must match the interpreter: a Debian/Ubuntu `luac` can point at 5.1
# (luacheck pulls it in), which rejects 5.3+ syntax such as `&` and `//`.
LUA_VER="$("$LUA" -e 'io.write((_VERSION:match("%d+%.%d+")))')"
case "$LUA_VER" in 5.[34]|5.[5-9]) ;; *) echo "Lua $LUA_VER is too old: the config and tests need 5.3+ (Hyprland embeds 5.5)"; exit 2 ;; esac
luac_ok() { [[ -x "$1" ]] && "$1" -v 2>&1 | grep -q "^Lua $LUA_VER"; }
if [[ -z "${LUAC:-}" ]]; then
    for c in "$(dirname "$LUA")/luac$LUA_VER" "$(command -v "luac$LUA_VER" || true)" "$(dirname "$LUA")/luac" "$(command -v luac || true)"; do
        if [[ -n "$c" ]] && luac_ok "$c"; then LUAC="$c"; break; fi
    done
fi
LUAC="${LUAC:-}"

if [[ -z "${HL_STUBS:-}" ]]; then
    if [[ -f /usr/share/hypr/stubs/hl.meta.lua ]]; then
        HL_STUBS=/usr/share/hypr/stubs/hl.meta.lua
    else
        HL_STUBS="$HERE/stubs/hl.meta.lua"
    fi
fi
XKB_KEYSYMS_H="${XKB_KEYSYMS_H:-/usr/include/xkbcommon/xkbcommon-keysyms.h}"

echo "lua:     $("$LUA" -v 2>&1 | head -1)"
echo "luac:    ${LUAC:-none, using load()}"
echo "stubs:   $HL_STUBS"
echo "keysyms: $([[ -f "$XKB_KEYSYMS_H" ]] && echo "$XKB_KEYSYMS_H" || echo "not found")"
echo

fail=0

# ---- 1. syntax -------------------------------------------------------------
echo "== syntax"
mapfile -t LUA_FILES < <(find "$REPO/config/hypr" "$HERE" -name '*.lua' -not -path "$HERE/stubs/*" | sort)
n=0
for f in "${LUA_FILES[@]}"; do
    if [[ -n "$LUAC" ]]; then
        out=$("$LUAC" -p "$f" 2>&1) || { echo "FAIL  $f"; echo "$out"; fail=1; continue; }
    else
        out=$("$LUA" -e "assert(loadfile(arg[1]))" "$f" 2>&1) || { echo "FAIL  $f"; echo "$out"; fail=1; continue; }
    fi
    n=$((n + 1))
done
echo "ok    $n/${#LUA_FILES[@]} Lua files compile"
echo

# ---- 2. config against the API --------------------------------------------
echo "== config"
FAKE_BINDS="$(mktemp)"
trap 'rm -f "$FAKE_BINDS" "$FAKE_BINDS.hyprctl"' EXIT
( cd "$HERE" && "$LUA" run.lua "$REPO" "$HL_STUBS" "$([[ -f "$XKB_KEYSYMS_H" ]] && echo "$XKB_KEYSYMS_H")" "$FAKE_BINDS" ) || fail=1
echo

# ---- 3. show-keybindings.sh -----------------------------------------------
echo "== show-keybindings.sh"
cat > "$FAKE_BINDS.hyprctl" <<EOF
#!/usr/bin/env bash
[[ "\$1" == "binds" ]] && cat "$FAKE_BINDS"
EOF
chmod +x "$FAKE_BINDS.hyprctl"

sk_fail=0
out=$(HYPRCTL="$FAKE_BINDS.hyprctl" bash "$REPO/scripts/show-keybindings.sh" --stdout) || { echo "FAIL  script exited non-zero"; sk_fail=1; }

expect() {
    if grep -qF -- "$1" <<< "$out"; then :; else echo "FAIL  missing line: $1"; sk_fail=1; fi
}
expect "=== HYPRLAND KEYBINDINGS ==="
expect "─── Apps & windows ───"
expect "─── Screenshots ───"
expect "Super + Return"
expect "terminal"
expect "Super + Alt + SPACE"
expect "Super + Shift + 0"
expect "to workspace 10"
expect "Shift + Print"
expect "XF86AudioRaiseVolume"
expect "Super + mouse:272"
expect "power off with confirm"

total=$(grep -c "→" <<< "$out" || true)
binds=$(grep -c "^bind" "$FAKE_BINDS" || true)
if [[ "$total" != "$binds" ]]; then echo "FAIL  $total rows shown for $binds binds"; sk_fail=1; fi
if grep -q "(no description)" <<< "$out"; then echo "FAIL  a bind has no description"; sk_fail=1; fi

if [[ $sk_fail == 0 ]]; then echo "ok    $total binds listed, grouped by section"; else fail=1; fi
echo

# ---- 4. confirm.sh ------------------------------------------------
echo "== confirm.sh"
cp_fail=0
FAKE_DIR="$(mktemp -d)"
export FAKE_DIR
trap 'rm -rf "$FAKE_DIR"; rm -f "$FAKE_BINDS" "$FAKE_BINDS.hyprctl"' EXIT
# Fake rofi: records its arguments and menu, answers with $FAKE_ANSWER (exit 1 = Escape).
cat > "$FAKE_DIR/rofi" <<'EOF'
#!/usr/bin/env bash
echo "$*" > "$FAKE_DIR/args"
cat > "$FAKE_DIR/menu"
[[ -n "${FAKE_ANSWER:-}" ]] || exit 1
echo "$FAKE_ANSWER"
EOF
chmod +x "$FAKE_DIR/rofi"
run_confirm() {
    rm -f "$FAKE_DIR/powered"
    FAKE_ANSWER="$1" ROFI="$FAKE_DIR/rofi" \
        bash "$REPO/scripts/confirm.sh" "Log out?" -- touch "$FAKE_DIR/powered" || true
}
run_confirm "Yes"; [[ -e "$FAKE_DIR/powered" ]] || { echo "FAIL  Yes did not run the command"; cp_fail=1; }
run_confirm "No";  [[ ! -e "$FAKE_DIR/powered" ]] || { echo "FAIL  No ran the command"; cp_fail=1; }
run_confirm "";    [[ ! -e "$FAKE_DIR/powered" ]] || { echo "FAIL  Escape ran the command"; cp_fail=1; }
run_confirm "yes please"; [[ ! -e "$FAKE_DIR/powered" ]] || { echo "FAIL  free text ran the command"; cp_fail=1; }
[[ "$(head -1 "$FAKE_DIR/menu")" == "No" ]] || { echo "FAIL  first row is not No"; cp_fail=1; }
grep -q -- "-selected-row 0" "$FAKE_DIR/args" || { echo "FAIL  default row is not No"; cp_fail=1; }
grep -q -- "-no-custom" "$FAKE_DIR/args" || { echo "FAIL  free text is allowed"; cp_fail=1; }
grep -q -- "-p Log out?" "$FAKE_DIR/args" || { echo "FAIL  prompt not passed to rofi"; cp_fail=1; }
run_confirm "Yes" >/dev/null; rm -f "$FAKE_DIR/powered"
bash "$REPO/scripts/confirm.sh" "Log out?" touch "$FAKE_DIR/powered" 2>/dev/null && { echo "FAIL  missing -- accepted"; cp_fail=1; } || true
[[ ! -e "$FAKE_DIR/powered" ]] || { echo "FAIL  missing -- ran the command"; cp_fail=1; }
if [[ $cp_fail == 0 ]]; then echo "ok    only Yes runs the command; No, Escape and other text do nothing; default is No"; else fail=1; fi
echo

if [[ $fail == 0 ]]; then echo "ALL PASSED"; else echo "SOME TESTS FAILED"; fi
exit $fail
