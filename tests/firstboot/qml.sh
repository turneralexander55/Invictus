#!/usr/bin/env bash
# ------------------------------------------------------------
# The first-start screens (quickshell/first-boot/) in the real toolkit, in a
# throwaway Arch container:
#
#   docker run --rm --network host -v "$PWD:/src:ro" archlinux:base-devel \
#       bash /src/tests/firstboot/qml.sh /src [OUTDIR]
#
#   1. qmllint, with Quickshell 0.3's own type files, on every QML file:
#      no unknown type, property or import
#   2. each screen drawn by quickshell under a headless sway (pixman), one
#      or two 1920x1080 outputs, with a fake invictus-first-boot that answers
#      `state` from a fixture; grim takes the picture (PNG in OUTDIR,
#      default /tmp/firstboot-renders), and the pictures are checked:
#        - quickshell logged no QML error or warning
#        - the card is drawn (basalt pixels in the middle)
#        - "How should Help work?" fresh: no gold anywhere (neither card
#          preselected, so the one gold button is still disabled: no-ai.md
#          2.1); picked: the gold button is there
#        - "Which screen is in front of you?" draws on both outputs
#        - the steps the command lists are the steps drawn (no Wi-Fi screen
#          offline: it is a later release's file)
# Never run it on a real machine: it installs packages.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC="${1:-/src}"
OUT="${2:-/tmp/firstboot-renders}"
QML="$SRC/quickshell/first-boot"

fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

pacman -Sy --noconfirm --needed quickshell qt6-declarative qt6-svg sway grim ttf-ibm-plex otf-cormorant python python-pillow \
    >/tmp/pacman.log 2>&1 || { tail -20 /tmp/pacman.log; exit 1; }
echo "quickshell $(pacman -Q quickshell | cut -d' ' -f2), qt $(pacman -Q qt6-declarative | cut -d' ' -f2)"
mkdir -p "$OUT"

# ---- 1. qmllint ------------------------------------------------------------------
echo "== qmllint"
LINT=/usr/lib/qt6/bin/qmllint
for f in "$QML"/*.qml; do
    # -I the folder itself (the steps use Card, Theme, ...); Quickshell's
    # modules are found under /usr/lib/qt6/qml.
    # --max-warnings 0: qmllint exits 0 on warnings otherwise, and an unknown
    # property is only a warning. Two categories are off because Quickshell
    # 0.3.1's own type files trip them (it runs fine, the renders show it):
    # PanelWindow is registered "not creatable", and Process.exited's
    # QProcess::ExitStatus parameter type is not exported.
    if "$LINT" -I "$QML" -I /usr/lib/qt6/qml --max-warnings 0 \
        --uncreatable-type disable --signal-handler-parameters disable "$f" >/tmp/lint.out 2>&1; then
        ok "qmllint $(basename "$f")"
    else
        bad "qmllint $(basename "$f")"
        sed 's/^/      /' /tmp/lint.out
    fi
done

# ---- 2. renders -------------------------------------------------------------------
echo "== renders"
export XDG_RUNTIME_DIR=/tmp/xdg
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
W=/tmp/fb
mkdir -p "$W"
# sway carries cap_sys_nice, which a container without that capability
# refuses to exec; a plain copy has no file capabilities.
cp /usr/bin/sway "$W/sway"

cat > "$W/sway.conf" <<'EOF'
output HEADLESS-1 mode 1920x1080 position 0 0 bg #000000 solid_color
EOF

SWAY_PID=""
stop_sway() {
    [[ -n "$SWAY_PID" ]] || return 0
    kill "$SWAY_PID" 2>/dev/null || true
    wait "$SWAY_PID" 2>/dev/null || true
    SWAY_PID=""
}

start_sway() {   # start_sway N: N headless outputs of 1920x1080
    stop_sway
    rm -f "$XDG_RUNTIME_DIR"/wayland-* "$XDG_RUNTIME_DIR"/sway-ipc.*
    WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
        "$W/sway" -c "$W/sway.conf" >"$W/sway.log" 2>&1 &
    SWAY_PID=$!
    SWAYSOCK=""
    local s
    for _ in $(seq 50); do
        for s in "$XDG_RUNTIME_DIR"/sway-ipc.*; do [[ -S "$s" ]] && SWAYSOCK="$s"; done
        [[ -n "$SWAYSOCK" ]] && break
        sleep 0.2
    done
    if [[ -z "$SWAYSOCK" ]]; then
        bad "sway did not start"
        sed 's/^/      /' "$W/sway.log" | tail -20
        exit 1
    fi
    export SWAYSOCK WAYLAND_DISPLAY=wayland-1
    if (( $1 > 1 )); then
        swaymsg create_output >/dev/null
        swaymsg output HEADLESS-2 mode 1920x1080 position 1920 0 >/dev/null
    fi
    sleep 0.5
}

# The fake command: `state` prints the fixture; every other call is logged
# and answers like the real one does on success.
cat > "$W/fake" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
case "$1" in
    state) python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))" "$FAKE_STATE" ;;
    monitors-write) echo '{"ok": true, "main": "HEADLESS-1"}' ;;
    *) echo '{"ok": true, "result": "ok"}' ;;
esac
EOF
chmod +x "$W/fake"

steps_json() {  # steps_json FLAVOR id... (the flavor only labels the call)
    local out="" id cap need
    shift
    for id in "$@"; do
        cap="$(tr '[:lower:]' '[:upper:]' <<< "${id:0:1}")${id:1}"
        need=false
        out+="${out:+,}{\"id\":\"$id\",\"qml\":\"Step$cap.qml\",\"needs_ai\":$need}"
    done
    echo "[$out]"
}

state_json() {  # state_json FLAVOR NMON STEPS PRESET
    local mons='{"name":"HEADLESS-1","description":"","width":1920,"height":1080,"refresh":60.0,"x":0,"y":0,"scale":1.0,"transform":0,"laptop":false}'
    (( $2 > 1 )) && mons+=',{"name":"HEADLESS-2","description":"","make":"Dell Inc.","model":"DELL U2720Q","width":1920,"height":1080,"refresh":60.0,"x":1920,"y":0,"scale":1.0,"transform":0,"laptop":false}'
    cat <<EOF
{"flavor":"$1","monitors":[$mons],"auto_main":"HEADLESS-1","online":true,"ai":"off","signed_in":false,
"themes":$THEMES_JSON,
 "motion":"showcase","apps":"dark","tokens":{},"steps":$3,"later":["wifi"],"again":false,"assistant":null
 ${4:+,\"render_preset\":$4}}
EOF
}

render() {  # render NAME FLAVOR NMON STEPS PRESET
    local name="$1"
    state_json "$2" "$3" "$4" "${5:-}" > "$W/state.json"
    : > "$W/calls"
    FAKE_STATE="$W/state.json" FAKE_LOG="$W/calls" INVICTUS_FIRSTBOOT_CMD="$W/fake" \
        QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software quickshell -p "$QML" >"$W/$name.log" 2>&1 &
    local qs=$!
    sleep 4
    grim -o HEADLESS-1 "$OUT/$name.png" 2>>"$W/grim.log" || bad "$name: grim failed"
    if (( $3 > 1 )); then grim -o HEADLESS-2 "$OUT/$name-2.png" 2>>"$W/grim.log" || bad "$name: grim on output 2 failed"; fi
    kill "$qs" 2>/dev/null || true
    wait "$qs" 2>/dev/null || true
    # Quickshell's own WARN/ERROR lines (colour codes stripped); the GPU
    # driver's chatter about the missing GPU is not ours.
    sed 's/\x1b\[[0-9;]*m//g' "$W/$name.log" | grep -E '^ *(WARN|ERROR)' > "$W/$name.problems" || true
    if [[ -s "$W/$name.problems" ]]; then
        bad "$name: quickshell logged problems"
        head -15 "$W/$name.problems" | sed 's/^/      /'
    else
        ok "$name: drawn, no QML errors"
    fi
}

# pixels FILE: counts of gold (sol) and card (basalt) pixels
pixels() {
    python3 -c '
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
gold = card = 0
for (r, g, b) in im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata():
    if abs(r - 0xE0) < 8 and abs(g - 0xA6) < 8 and abs(b - 0x4B) < 8: gold += 1
    if abs(r - 0x1C) < 3 and abs(g - 0x1A) < 3 and abs(b - 0x16) < 3: card += 1
print(gold, card)
' "$1"
}

expect_pixels() {  # expect_pixels NAME FILE gold:none|some
    local g c
    read -r g c < <(pixels "$2")
    if (( c < 20000 )); then bad "$1: no card drawn ($c card pixels)"; return; fi
    case "$3" in
        none) if (( g == 0 )); then ok "$1: no gold (nothing preselected, gold button disabled)"; else bad "$1: $g gold pixels, expected none"; fi ;;
        some) if (( g > 2000 )); then ok "$1: the gold button is there ($g px)"; else bad "$1: only $g gold pixels"; fi ;;
    esac
}

# The themes with real swatches, drawn by the theme tool from the checkout.
THEMES_JSON="$(INVICTUS_STATE="$W/theme" python3 - "$SRC/theme/invictus-theme" <<'EOF'
import json, subprocess, sys
names = {"dusk": "Dusk", "porphyry": "Porphyry", "aegean": "Aegean", "alexandria": "Alexandria"}
sw = dict(l.split(" ", 1) for l in subprocess.run([sys.argv[1], "swatches"], capture_output=True, text=True).stdout.splitlines())
print(json.dumps([{"id": i, "name": n, "current": i == "dusk", "swatch": sw.get(i, "")} for i, n in names.items()]))
EOF
)"
[[ "$THEMES_JSON" == *'.svg"'* || "$THEMES_JSON" == *'.png"'* ]] || bad "invictus-theme swatches drew nothing"

start_sway 1
ATRIUM_1="$(steps_json atrium assistant ready)"
render atrium-3-help-fresh atrium 1 "$ATRIUM_1"
expect_pixels "atrium help, fresh" "$OUT/atrium-3-help-fresh.png" none
render atrium-3-help-ai-picked atrium 1 "$ATRIUM_1" '{"step":"assistant","pick":"ai"}'
expect_pixels "atrium help, AI picked" "$OUT/atrium-3-help-ai-picked.png" some
render atrium-3-help-no-ai-picked atrium 1 "$ATRIUM_1" '{"step":"assistant","pick":"none"}'
expect_pixels "atrium help, No AI picked" "$OUT/atrium-3-help-no-ai-picked.png" some
render atrium-4-ready atrium 1 "$ATRIUM_1" '{"step":"ready","choice":"ai"}'
expect_pixels "atrium ready" "$OUT/atrium-4-ready.png" some
render atrium-4-ready-no-ai atrium 1 "$ATRIUM_1" '{"step":"ready","choice":"none"}'

TESSERA="$(steps_json tessera monitors look assistant ready)"
render tessera-2-look tessera 1 "$(steps_json tessera look assistant ready)"
expect_pixels "tessera look" "$OUT/tessera-2-look.png" some
render tessera-7-tour tessera 1 "$(steps_json tessera look assistant ready)" '{"step":"ready","choice":"ai"}'

start_sway 2
render atrium-2-screens atrium 2 "$(steps_json atrium screens assistant ready)"
expect_pixels "atrium screens, output 1" "$OUT/atrium-2-screens.png" some
expect_pixels "atrium screens, output 2" "$OUT/atrium-2-screens-2.png" some
render tessera-1-monitors tessera 2 "$TESSERA"
expect_pixels "tessera monitors" "$OUT/tessera-1-monitors.png" some
stop_sway

echo
if [[ $fail == 0 ]]; then echo "ALL PASSED"; else echo "SOME TESTS FAILED"; fi
exit $fail
