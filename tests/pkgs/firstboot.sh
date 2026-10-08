# shellcheck shell=bash
# Group 18 of tests/pkgs/run.sh (sourced; uses REPO, TMP, ALL, LUA, STUBS,
# ok, bad): invictus-first-boot, the first-start wizard's logic (design.md
# 2.3, no-ai.md 2, simple-mode.md 3.2), with every command it calls faked at
# the seam: hyprctl, invictus-sys, invictus-provider (Vulcan's provider
# layer, docs/moneta-panel.md), the terminal, invictus-theme, invictus-motion, gsettings,
# nmcli, invictus-doctor and quickshell. The screens themselves are tested
# in the real toolkit by tests/firstboot/qml.sh (container).
# shellcheck disable=SC2153,SC2015,SC2016 # REPO, TMP, ALL, STUBS come from run.sh; ok || bad on purpose; the fakes' bodies expand when they run

if [[ "${BASH_SOURCE[0]}" == "$0" ]] || ! declare -F ok bad >/dev/null || [[ -z "${REPO:-}" || -z "${TMP:-}" ]]; then
    echo "tests/pkgs/firstboot.sh is group 18 of tests/pkgs/run.sh: run that" >&2
    # shellcheck disable=SC2317 # exit is reached when run, not sourced
    return 2 2>/dev/null || exit 2
fi

set +e
echo "== first start"
FB="$REPO/scripts/first-boot/invictus-first-boot"
QMLDIR="$REPO/quickshell/first-boot"
FF="$TMP/fbfake"
mkdir -p "$FF"

# ---- fakes ----------------------------------------------------------------------
fake() { printf '#!/bin/bash\n%s\n' "$2" > "$FF/$1"; chmod +x "$FF/$1"; }
fake hyprctl 'echo "hyprctl $*" >> "$FAKE_DIR/log"
case "$1" in monitors) cat "$FAKE_DIR/monitors.json" ;; reload) exit 0 ;; esac'
# invictus-sys: logs its argv; FAKE_SYS_RC and FAKE_SYS_RESULT choose the
# outcome; ai on|off write the state file the way the root helper does.
fake invictus-sys 'echo "invictus-sys $*" >> "$FAKE_DIR/log"
rc="${FAKE_SYS_RC:-0}"; res="${FAKE_SYS_RESULT:-ok}"
if [[ "$3 $4" == "ai on" && $rc == 0 ]]; then echo on > "$FAKE_DIR/ai"; fi
if [[ "$3 $4" == "ai off" && $rc == 0 ]]; then echo off > "$FAKE_DIR/ai"; fi
[[ "$3" == snapshot ]] && snap=42 || snap=7
(( rc == 0 )) && echo "invictus-sys: $res snapshot=$snap"
exit "$rc"'
# invictus-provider: logs argv; whatever comes on stdin goes to its own file
# invictus-provider as docs/moneta-panel.md documents it: set NAME [--endpoint
# URL], key set NAME (one line on stdin). Logs argv; the key to its own file.
fake invictus-provider 'echo "invictus-provider $*" >> "$FAKE_DIR/log"
case "$1 $2" in
    "key set") IFS= read -r k; printf "%s" "$k" > "$FAKE_DIR/provider-stdin"; exit "${FAKE_KEY_RC:-0}" ;;
    "set "*) exit "${FAKE_PROVIDER_RC:-0}" ;;
    *) exit 2 ;;
esac'
# the terminal the Claude sign-in runs in; "signs in" when FAKE_LOGIN_OK=1
fake terminal 'echo "terminal $*" >> "$FAKE_DIR/log"
if [[ "${FAKE_LOGIN_OK:-0}" == 1 ]]; then mkdir -p "$HOME/.claude"; echo "{\"t\":\"SECRET-TOKEN-MARK\"}" > "$HOME/.claude/.credentials.json"; chmod 000 "$HOME/.claude/.credentials.json"; fi
exit 0'
fake invictus-theme 'echo "invictus-theme $*" >> "$FAKE_DIR/log"
[[ "$1" == list ]] && printf "* dusk Dusk\n  porphyry Porphyry\n  aegean Aegean\n  alexandria Alexandria\n"
[[ "$1" == swatches ]] && printf "dusk /sw/dusk.png\nporphyry /sw/porphyry.png\naegean /sw/aegean.svg\n"
exit 0'
fake invictus-motion 'echo "invictus-motion $*" >> "$FAKE_DIR/log"; [[ "$1" == get ]] && echo showcase; exit 0'
fake gsettings 'echo "gsettings $*" >> "$FAKE_DIR/log"; [[ "$1" == get ]] && echo "prefer-dark"; exit 0'
fake nmcli 'echo "${FAKE_NET:-full}"'
fake invictus-doctor 'echo "invictus-doctor $*" >> "$FAKE_DIR/log"; exit "${FAKE_DOCTOR_RC:-0}"'
fake quickshell 'echo "quickshell $* cmd=$INVICTUS_FIRSTBOOT_CMD" >> "$FAKE_DIR/log"; exit 0'

new_home() {   # new_home NAME [flavor]: a fresh home and fake state; sets H
    H="$TMP/fbh-$1"
    rm -rf "$H"
    mkdir -p "$H/.config/invictus" "$H/.config/hypr" "$H/run"
    [[ -n "${2:-}" ]] && echo "$2" > "$H/.config/invictus/flavor"
    export FAKE_DIR="$H"
    : > "$H/log"
    echo off > "$H/ai"
    cat > "$H/monitors.json" <<'EOF'
[{"name": "DP-1", "description": "Dell Inc. DELL U2720Q 7XQ1", "make": "Dell Inc.", "model": "DELL U2720Q", "width": 2560, "height": 1440,
  "refreshRate": 164.998, "x": 0, "y": 0, "scale": 1.0, "transform": 0, "disabled": false},
 {"name": "eDP-1", "description": "BOE 0x0BCA \"13\" panel", "width": 1920, "height": 1200,
  "refreshRate": 60.0, "x": 2560, "y": 0, "scale": 1.25, "transform": 0, "disabled": false}]
EOF
}

fb() {   # fb ARGS...: run the wizard command in $H; stdout to $H/out
    HOME="$H" XDG_CONFIG_HOME="" XDG_STATE_HOME="" INVICTUS_STATE="" XDG_RUNTIME_DIR="$H/run" \
        INVICTUS_SHARE="$TMP/fbshare" INVICTUS_AI_FILE="$H/ai" \
        INVICTUS_HYPRCTL="$FF/hyprctl" INVICTUS_SYS_CMD="$FF/invictus-sys" INVICTUS_PROVIDER_CMD="$FF/invictus-provider" \
        INVICTUS_THEME_CMD="$FF/invictus-theme" INVICTUS_MOTION_CMD="$FF/invictus-motion" INVICTUS_GSETTINGS="$FF/gsettings" \
        INVICTUS_NMCLI="$FF/nmcli" INVICTUS_DOCTOR_CMD="$FF/invictus-doctor" INVICTUS_QUICKSHELL="$FF/quickshell" \
        INVICTUS_TERMINAL="$FF/terminal" \
        python3 "$FB" "$@" > "$H/out" 2> "$H/err"
}
jq_() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {'d': d}))" "$H/out" "$1" 2>/dev/null; }

# the installed screens, as invictus-tools puts them
mkdir -p "$TMP/fbshare"
cp -r "$QMLDIR" "$TMP/fbshare/first-boot"

# ---- run once per person, re-runnable -------------------------------------------
new_home once tessera
fb start --if-pending
[[ ! -s "$H/log" ]] && grep -q '"started": false' "$H/out" \
    && ok "start --if-pending does nothing on a home first-login did not mark" \
    || bad "start --if-pending opened the screens unasked: $(cat "$H/log")"
fb mark-pending
fb start --if-pending
grep -q "^quickshell -p $TMP/fbshare/first-boot cmd=.*invictus-first-boot$" "$H/log" \
    && ok "a marked home: start --if-pending opens the screens (quickshell -p, INVICTUS_FIRSTBOOT_CMD set)" \
    || bad "marked home did not open: $(cat "$H/log" "$H/err")"
fb finish
: > "$H/log"
fb start --if-pending; fb start
[[ ! -s "$H/log" && ! -e "$H/.local/state/invictus/first-boot.pending" ]] \
    && ok "once per person: after finish, neither --if-pending nor a plain start opens it again" \
    || bad "it ran again after finish: $(cat "$H/log")"
fb start --again
grep -q "^quickshell -p" "$H/log" && ok "re-runnable: start --again (Settings) opens it on a finished home" \
    || bad "start --again did not open it"
fb mark-pending
[[ ! -e "$H/.local/state/invictus/first-boot.pending" ]] && ok "mark-pending on a finished home marks nothing" \
    || bad "mark-pending re-marked a finished home"
exec 9> "$H/run/invictus-first-boot.lock"; flock -n 9
: > "$H/log"; fb start --again
[[ ! -s "$H/log" ]] && grep -q "already open" "$H/out" && ok "a second start while one is open does nothing (lock)" \
    || bad "two wizards could open at once"
exec 9>&-

# first-login marks new homes only
FL="$REPO/scripts/first-login.sh"
fl_run() {   # fl_run HOME args...
    local h="$1"; shift
    HOME="$h" XDG_CONFIG_HOME="" XDG_STATE_HOME="" INVICTUS_STATE="" INVICTUS_SHARE="$ALL/usr/share/invictus" \
        INVICTUS_DEFAULTS_SH="$REPO/scripts/lib/defaults.sh" PATH="$TMP/nobin:$PATH" INVICTUS_THEME_CMD=/nonexistent \
        INVICTUS_FIRST_BOOT_CMD="$FF/fb-wrap" bash "$FL" "$@" >/dev/null 2>&1
}
printf '#!/bin/bash\necho "fb $*" >> "$HOME/fb.log"\n' > "$FF/fb-wrap"; chmod +x "$FF/fb-wrap"
mkdir -p "$TMP/nobin"
for c in systemctl xdg-user-dirs-update fc-cache; do printf '#!/bin/sh\nexit 0\n' > "$TMP/nobin/$c"; chmod +x "$TMP/nobin/$c"; done
h1="$TMP/fbl-new"; h2="$TMP/fbl-adopt"; h3="$TMP/fbl-old"
rm -rf "$h1" "$h2" "$h3"; mkdir -p "$h1" "$h2" "$h3/.local/state"
touch "$h3/.local/state/hyprdots-initialized"
fl_run "$h1"; fl_run "$h2" --adopt "$TMP/fbl-adopt-bak"; fl_run "$h3"
if grep -qx "fb mark-pending" "$h1/fb.log" 2>/dev/null && [[ ! -e "$h2/fb.log" && ! -e "$h3/fb.log" ]]; then
    ok "first-login marks a new home for first start; not an adopted home, not one the old scripts set up"
else
    bad "first-login marking: new=$(cat "$h1/fb.log" 2>/dev/null) adopt=$(cat "$h2/fb.log" 2>/dev/null) old=$(cat "$h3/fb.log" 2>/dev/null)"
fi
grep -q 'hl.exec_cmd("invictus-first-boot start --if-pending")' "$REPO/config/hypr/invictus/autostart.lua" \
    && ok "Hyprland's autostart opens first start on a marked home" || bad "autostart does not run invictus-first-boot"
[[ -x "$ALL/usr/bin/invictus-first-boot" && -f "$ALL/usr/share/invictus/first-boot/shell.qml" \
   && "$(find "$ALL/usr/share/invictus/first-boot" -name '*.qml' | wc -l)" == "$(find "$QMLDIR" -name '*.qml' | wc -l)" ]] \
    && ok "invictus-tools installs /usr/bin/invictus-first-boot and every screen file" \
    || bad "the package does not install the wizard"

# ---- monitors.lua from hyprctl monitors -j ----------------------------------------
stub_check() {   # stub_check MONITORS.LUA: load it with the shipped modules
    local d="$TMP/fbcheck"
    rm -rf "$d"; mkdir -p "$d"
    sed "s#/usr/share/invictus/hypr/?.lua#$REPO/config/hypr/?.lua#" "$REPO/config/hypr/hyprland.lua" > "$d/hyprland.lua"
    cp "$1" "$d/monitors.lua"
    (cd "$TMP" && "$LUA" "$REPO/scripts/doctor/hypr-check.lua" "$d/hyprland.lua" "$STUBS") > "$TMP/fbcheck.log" 2>&1
}
new_home mon atrium
M="$H/.config/hypr/monitors.lua"
echo "-- old file" > "$M"
fb monitors-write auto
if grep -q 'output   = "desc:BOE 0x0BCA \\"13\\" panel", -- eDP-1' "$M" \
   && grep -q 'mode     = "2560x1440@165.00"' "$M" && grep -q 'mode     = "1920x1200@60.00"' "$M" \
   && grep -q 'scale    = 1.25,' "$M" && grep -q 'position = "2560x0"' "$M" \
   && grep -q 'hl.workspace_rule({ workspace = "1", monitor = "desc:BOE 0x0BCA \\"13\\" panel", default = true })' "$M" \
   && grep -q 'hl.monitor({ output = "", mode = "preferred"' "$M"; then
    ok "monitors-write auto: one rule per screen from hyprctl (desc: selector, mode, position, scale), the laptop is main, a catch-all"
else
    bad "monitors.lua from auto: $(cat "$M" "$H/err")"
fi
bk="$(find "$H/.local/state/invictus/backups" -name monitors.lua 2>/dev/null | head -1)"
[[ -n "$bk" && "$(cat "$bk")" == "-- old file" ]] && ok "A6: the old monitors.lua is backed up under ~/.local/state/invictus/backups first" \
    || bad "no backup of the old monitors.lua"
grep -q "^invictus-doctor --hypr$" "$H/log" && grep -q "^hyprctl reload$" "$H/log" \
    && ok "A6: the config check runs after the write, then Hyprland reloads" || bad "no doctor --hypr or reload: $(cat "$H/log")"
if [[ -n "$LUA" ]]; then
    stub_check "$M" && ok "the written monitors.lua loads with the shipped modules (stub check)" \
        || bad "monitors.lua fails the stub check: $(grep -E 'error' "$TMP/fbcheck.log" | head -3)"
else
    bad "no lua: the stub check of monitors.lua cannot run (set LUA)"
fi
fb monitors-write DP-1
grep -q 'hl.workspace_rule({ workspace = "1", monitor = "desc:Dell Inc. DELL U2720Q 7XQ1"' "$M" \
    && [[ "$(grep -A3 '\-\- eDP-1' "$M" | grep position)" == *'"2560x0"'* && "$(grep -A3 '\-\- DP-1' "$M" | grep position)" == *'"0x0"'* ]] \
    && ok "Atrium \"This one\": that screen is main at 0x0, the others to its right" \
    || bad "This one layout: $(cat "$M")"
fb monitors-write eDP-1 DP-1=0,0 eDP-1=2560,240
[[ "$(grep -A3 '\-\- eDP-1' "$M" | grep position)" == *'"2560x240"'* ]] && grep -q 'monitor = "desc:BOE' "$M" \
    && ok "Tessera drag layout: the positions given are written, the main one chosen" || bad "drag layout: $(cat "$M")"
cp "$M" "$H/before"
FAKE_DOCTOR_RC=1 fb monitors-write DP-1; rc=$?
cmp -s "$M" "$H/before" && [[ $rc == 1 ]] && grep -q '"ok": false' "$H/out" \
    && ok "A6: a failed config check puts the old monitors.lua back (exit 1)" || bad "failed check left the new file (rc $rc)"
: > "$H/log"
bad_args=0
refused() { fb monitors-write "$@"; local rc=$?; [[ $rc == 2 ]] || { bad "monitors-write $*: exit $rc, expected 2"; bad_args=1; }; }
refused HDMI-9
refused DP-1 DP-1=0,0
refused DP-1 DP-1=0,0 'eDP-1=1;rm'
refused auto DP-1=0,0
refused DP-1 "'DP-1=0,0'" x=1,1
cmp -s "$M" "$H/before" && [[ $bad_args == 0 ]] && ok "monitors-write refuses unknown screens, partial or malformed positions (exit 2, file untouched)" \
    || bad "a refused call changed monitors.lua"
# a screen name that tries to end the Lua comment
python3 - "$H/monitors.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d[0]["name"] = "DP-1\nos.exit(1)--"; d[0]["description"] = ""
json.dump(d, open(sys.argv[1], "w"))
EOF
fb monitors-write auto
if [[ -n "$LUA" ]] && stub_check "$M" && ! grep -q '^os.exit' "$M"; then
    ok "a screen name with a newline cannot add Lua to monitors.lua"
else
    bad "hostile screen name: $(cat "$M")"
fi

# ---- look ----------------------------------------------------------------------------
new_home look tessera
fb look porphyry calm light
grep -qx "invictus-theme apply porphyry" "$H/log" && grep -qx "invictus-motion set calm" "$H/log" \
    && grep -qx "gsettings set org.gnome.desktop.interface color-scheme prefer-light" "$H/log" \
    && ok "look: invictus-theme apply, invictus-motion set, the GTK colour scheme" || bad "look: $(cat "$H/log")"
: > "$H/log"
fb look nero calm light; rc=$?
[[ $rc == 2 ]] && ! grep -q "apply\|set" "$H/log" && ok "look refuses a theme invictus-theme does not list; nothing applied" \
    || bad "look with an unknown theme: rc $rc $(cat "$H/log")"

# ---- step 3: the assistant (no-ai.md 2), against docs/moneta-panel.md ----------------
new_home none atrium
fb assistant none
[[ ! -s "$H/log" ]] && grep -q '"result": "ok"' "$H/out" \
    && ok "No AI on a machine with AI off: nothing to run, no password" || bad "No AI ran: $(cat "$H/log")"
echo on > "$H/ai"
fb assistant none
grep -qx "invictus-sys --request first-start ai off" "$H/log" && [[ "$(cat "$H/ai")" == off ]] \
    && ok "No AI after a sign-in given up (AI on): invictus-sys ai off" || bad "No AI with AI on: $(cat "$H/log")"

new_home claude atrium
fb assistant claude
if [[ "$(head -1 "$H/log")" == "invictus-sys --request first-start ai on" \
      && "$(sed -n 2p "$H/log")" == "invictus-provider set claude-code" && "$(wc -l < "$H/log")" == 2 ]] \
   && grep -q '"result": "ok"' "$H/out"; then
    ok "NA6/N1 at first start: Claude asks the password through invictus-sys ai on (org.invictus.sys.ai-on), then invictus-provider set claude-code"
else
    bad "claude flow: $(cat "$H/log" "$H/out")"
fi
new_home cancel atrium
FAKE_SYS_RC=126 fb assistant claude
grep -q '"result": "cancelled"' "$H/out" && ! grep -q invictus-provider "$H/log" && [[ "$(cat "$H/ai")" == off ]] \
    && [[ ! -e "$H/.local/state/invictus/first-boot.json" ]] \
    && ok "a cancelled password changes nothing: no provider, AI still off, nothing recorded" || bad "cancel: $(cat "$H/log" "$H/out")"

new_home other atrium
KEY="sk-test-$RANDOM-not-a-real-key"
printf '%s\n' "$KEY" | fb assistant other --address https://api.example.org/v1
if [[ "$(cat "$H/provider-stdin" 2>/dev/null)" == "$KEY" ]] && ! grep -q -- "$KEY" "$H/log" \
   && ! grep -rq -- "$KEY" "$H/.local" "$H/.config" "$H/out" "$H/err" \
   && [[ "$(sed -n 2p "$H/log")" == "invictus-provider set openai-compatible --endpoint https://api.example.org/v1" \
      && "$(sed -n 3p "$H/log")" == "invictus-provider key set openai-compatible" ]]; then
    ok "S2: another service: set --endpoint, then the key on key set's stdin only: not on any command line, not in any file we write"
else
    bad "key handling: $(cat "$H/log")"
fi
new_home home atrium
fb assistant home --address atlas.local
grep -qx "invictus-provider set openai-compatible --endpoint http://atlas.local:11434/v1" "$H/log" && ! grep -q "key set" "$H/log" \
    && ok "a home AI system: atlas.local becomes http://atlas.local:11434/v1 for set --endpoint; no key" || bad "home: $(cat "$H/log")"
new_home home2 atrium
fb assistant home --address http://192.168.1.20:8080/v1
grep -qx "invictus-provider set openai-compatible --endpoint http://192.168.1.20:8080/v1" "$H/log" \
    && ok "a full address is passed as typed" || bad "home URL: $(cat "$H/log")"
new_home refused atrium
FAKE_PROVIDER_RC=3 fb assistant home --address atlas.local
grep -q '"result": "provider-refused"' "$H/out" && ok "invictus-provider exit 3 (or 2): provider-refused, so the screen says the address can't be used" \
    || bad "refused provider: $(cat "$H/out")"
new_home keyfail atrium
printf 'k\n' | FAKE_KEY_RC=1 fb assistant other --address https://api.example.org/v1
grep -q '"result": "provider-failed"' "$H/out" && ok "the keyring refusing the key (exit 1): provider-failed" || bad "key fail: $(cat "$H/out")"
: > "$H/log"; echo off > "$H/ai"
all2=0
for a in "home" "other" "home --address atlas.local;id" "home --address -x" "claude --address atlas.local" "home --this-computer" "generic-cli"; do
    # shellcheck disable=SC2086 # split on purpose
    fb assistant $a < /dev/null; rc=$?
    [[ $rc == 2 ]] || { bad "assistant $a: exit $rc, expected 2"; all2=1; }
done
[[ $all2 == 0 && ! -s "$H/log" ]] && ok "SM10: bad choices are refused before any password (no generic-cli, no odd address); nothing called" \
    || bad "refused choices still called: $(cat "$H/log")"

# Offline: ai on is pending, invictus-provider is not installed yet.
new_home pending atrium
printf 'k-%s\n' "$RANDOM" > "$H/key"
FAKE_SYS_RESULT=pending fb assistant other --address https://api.example.org/v1 < "$H/key"
grep -q '"result": "pending"' "$H/out" && ! grep -q invictus-provider "$H/log" \
    && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['provider_pending'] and d['provider']=={'choice':'other','endpoint':'https://api.example.org/v1'}" "$H/.local/state/invictus/first-boot.json" \
    && ! grep -rq -- "$(cat "$H/key")" "$H/.local" \
    && ok "offline (ai on pending): the choice and endpoint are kept, never the key; the provider is not called yet" || bad "pending: $(cat "$H/log" "$H/out")"
: > "$H/log"
HOME="$H" INVICTUS_STATE="" XDG_STATE_HOME="" XDG_CONFIG_HOME="" INVICTUS_AI_FILE="$H/ai" INVICTUS_PROVIDER_CMD=/nonexistent \
    python3 "$FB" apply-pending > "$H/out" 2>/dev/null
grep -q "waiting for the packages" "$H/out" && ! grep -q invictus-provider "$H/log" \
    && ok "apply-pending before the packages arrive: waits, calls nothing" || bad "apply-pending early: $(cat "$H/out")"
fb start --if-pending
if grep -qx "invictus-provider set openai-compatible --endpoint https://api.example.org/v1" "$H/log" && ! grep -q "key set" "$H/log" \
   && python3 -c "import json,sys; assert not json.load(open(sys.argv[1]))['provider_pending']" "$H/.local/state/invictus/first-boot.json"; then
    ok "the next session start (Hyprland autostart, start) sets the kept choice up once invictus-provider is in; the key is left for Settings"
else
    bad "pending pickup: $(cat "$H/log")"
fi
: > "$H/log"; fb start --if-pending
! grep -q invictus-provider "$H/log" && ok "a picked-up choice is set up once, not at every session" || bad "pending applied twice"
new_home pending2 atrium
FAKE_SYS_RESULT=pending fb assistant claude
echo off > "$H/ai"; : > "$H/log"
fb apply-pending
grep -q '"result": "dropped: AI is off"' "$H/out" && ! grep -q invictus-provider "$H/log" \
    && ok "a kept choice is dropped if AI was turned off meanwhile" || bad "pending after ai off: $(cat "$H/out" "$H/log")"

# ---- sign-in: never sees the token -----------------------------------------------------
new_home signin atrium
fb signin
grep -q '"signed_in": false' "$H/out" && [[ ! -s "$H/log" ]] \
    && ok "sign-in with no shipped claude-code provider (AI pending): no terminal, not signed in" || bad "signin none: $(cat "$H/out" "$H/log")"
mkdir -p "$TMP/fbshare/providers/claude-code" "$H/.config/invictus/providers/claude-code"
echo 'login = ["/usr/bin/claude", "auth", "login"]' > "$TMP/fbshare/providers/claude-code/provider.toml"
echo 'login = ["/usr/bin/env", "HOME-FILE-LOGIN"]' > "$H/.config/invictus/providers/claude-code/provider.toml"
FAKE_LOGIN_OK=1 fb signin
if grep -qx "terminal --class invictus-signin --title Sign in to Claude /usr/bin/claude auth login" "$H/log" \
   && grep -q '"signed_in": true' "$H/out" && ! grep -rq SECRET-TOKEN-MARK "$H/out" "$H/err" "$H/.local"; then
    ok "never sees the token: the shipped provider's login runs in a terminal (a home provider file is ignored); a mode 000 credentials file counts as signed in"
else
    bad "signin with a credentials file: $(cat "$H/log" "$H/out" "$H/err")"
fi
fb state
grep -q SECRET-TOKEN-MARK "$H/out" && bad "state printed the token" || ok "state says signed in without the token"
chmod 600 "$H/.claude/.credentials.json"
echo 'login = ["sh", "-c", "x"]' > "$TMP/fbshare/providers/claude-code/provider.toml"
: > "$H/log"; fb signin
[[ ! -s "$H/log" ]] && ok "a login command outside /usr/bin is not run" || bad "odd login ran: $(cat "$H/log")"
rm -rf "$TMP/fbshare/providers"

# ---- finish: the "First boot done" snapshot ----------------------------------------------
new_home finish atrium
fb mark-pending
fb finish
if grep -qx 'invictus-sys --request first-start snapshot First boot done' "$H/log" \
   && grep -q '"snapshot": "42"' "$H/.local/state/invictus/first-boot.done" && [[ ! -e "$H/.local/state/invictus/first-boot.pending" ]]; then
    ok "step 7: \"First boot done\" snapshot through invictus-sys; its id recorded; the home marked done"
else
    bad "finish: $(cat "$H/log" "$H/out")"
fi
grep -qx "invictus-theme apply dusk" "$H/log" && grep -qx "invictus-motion set calm" "$H/log" \
    && grep -qx "gsettings set org.gnome.desktop.interface color-scheme prefer-light" "$H/log" \
    && ok "Atrium asks no look question: finish sets the theme in use, Calm and light apps (simple-mode.md 3.2)" \
    || bad "Atrium look defaults: $(cat "$H/log")"
new_home finish3 tessera
fb finish
grep -q "invictus-motion set" "$H/log" && bad "finish changed a Tessera look" || ok "Tessera keeps the look its step chose (finish sets none)"
new_home finish2 atrium
FAKE_SYS_RC=1 fb finish
grep -q '"snapshot_result": "failed"' "$H/out" && [[ -e "$H/.local/state/invictus/first-boot.done" ]] \
    && ok "a failed snapshot is recorded, and the person is not stuck in the wizard" || bad "finish with failed snapshot: $(cat "$H/out")"

# ---- state: which steps, the hooks ------------------------------------------------------
steps() { python3 -c "import json,sys; print(' '.join(s['id'] for s in json.load(open(sys.argv[1]))['steps']))" "$H/out"; }
later() { python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['later']))" "$H/out"; }
new_home st1 atrium
echo '[{"name":"eDP-1","width":1920,"height":1080,"x":0,"y":0,"scale":1}]' > "$H/monitors.json"
fb state
[[ "$(steps)" == "assistant ready" ]] && ok "Atrium, one screen, online: How should Help work?, then Three things to know" || bad "atrium steps: $(steps)"
new_home st2 atrium
fb state
[[ "$(steps)" == "screens assistant ready" ]] && ok "Atrium, two screens: Which screen is in front of you? first" || bad "atrium 2 screens: $(steps)"
new_home st3 tessera
fb state
if [[ "$(steps)" == "monitors look assistant ready" && "$(later)" == "collegium windows voice" ]]; then
    ok "Tessera: monitors, look, assistant, tour; Collegium, Windows and voice are hooks for later releases"
else
    bad "tessera steps: $(steps) / later: $(later)"
fi
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
sw = {t['id']: t['swatch'] for t in d['themes']}
assert sw == {'dusk': '/sw/dusk.png', 'porphyry': '/sw/porphyry.png', 'aegean': '/sw/aegean.svg', 'alexandria': ''}, sw
m = {x['name']: (x['make'], x['model']) for x in d['monitors']}
assert m['DP-1'] == ('Dell Inc.', 'DELL U2720Q') and m['eDP-1'] == ('', ''), m" "$H/out" \
    && ok "state: each theme's swatch from invictus-theme swatches (none when it has none), each screen's make and model" \
    || bad "state swatches/models: $(cat "$H/out")"
new_home st4
fb state
grep -q '"flavor": "tessera"' "$H/out" && ok "no flavor file (an adopted home): Tessera" || bad "no flavor: $(cat "$H/out")"
new_home st5 atrium
FAKE_NET=none fb state
[[ "$(steps)" == "screens assistant ready" && "$(later)" == wifi ]] \
    && ok "Atrium offline: the Wi-Fi screen is a hook (no file yet), the rest still runs" || bad "offline: $(steps) / $(later)"
cp "$QMLDIR/StepReady.qml" "$TMP/fbshare/first-boot/StepCollegium.qml"
new_home st6 tessera
fb state
python3 -c "import json,sys; s=json.load(open(sys.argv[1]))['steps']; assert [x['id'] for x in s]==['monitors','look','assistant','collegium','ready'] and s[3]['needs_ai']" "$H/out" \
    && ok "a hook: dropping in StepCollegium.qml adds step 4 (needs AI, so No AI skips it)" || bad "hook: $(steps)"
rm "$TMP/fbshare/first-boot/StepCollegium.qml"

# ---- Janus's first-start pen test (2026-10-01), one check per finding ----------------------
# L1: the login argv must be a normalised path straight in /usr/bin
mkdir -p "$TMP/fbshare/providers/claude-code"
new_home l1 atrium
for argv in '["/usr/bin/../../home/p/payload"]' '["/usr/bin/sub/claude", "auth"]' '["/usr/bin//claude"]' '["/usr/bin/./claude"]'; do
    echo "login = $argv" > "$TMP/fbshare/providers/claude-code/provider.toml"
    fb signin
done
[[ ! -s "$H/log" ]] && ok "L1: a login program that is not a plain /usr/bin/NAME (.., a subfolder, // or .) is not run" \
    || bad "L1: odd login argv ran: $(cat "$H/log")"
rm -rf "$TMP/fbshare/providers"
# L1: the override rule lives in one helper; installed copies ignore INVICTUS_*
if python3 - "$REPO/scripts/lib/invictus_env.py" <<'EOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("invictus_env", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
os.environ["INVICTUS_SHARE"] = "/home/p/x"
assert m.for_script("/usr/bin/invictus-first-boot")("INVICTUS_SHARE", "/usr/share/invictus") == "/usr/share/invictus"
assert m.for_script("/usr/lib/invictus/x")("INVICTUS_SHARE", "d") == "d"
assert m.for_script("/home/p/checkout/scripts/x")("INVICTUS_SHARE", "d") == "/home/p/x"
os.environ["INVICTUS_SHARE"] = ""
assert m.for_script("/home/p/checkout/scripts/x")("INVICTUS_SHARE", "d") == "d"
EOF
then ok "L1: invictus_env.for_script: an installed script (under /usr/) gets the default whatever INVICTUS_* says; a checkout gets the override"
else bad "L1: scripts/lib/invictus_env.py missing or wrong"; fi
# L1, N2, N3: the override rule on the syntax tree (tests/pkgs/lib/env-ast.py):
# no INVICTUS_* read but through the helper, no environment read with a
# computed name, every tool() default an absolute path.
py=()
while IFS= read -r f; do
    [[ -f "$REPO/$f" ]] || continue
    head -1 "$REPO/$f" | grep -q python || [[ "$f" == *.py ]] || continue
    [[ "$f" == scripts/lib/invictus_env.py ]] && continue
    py+=("$REPO/$f")
done < <(cd "$REPO" && { git ls-files 'scripts/**' 'theme/*' 2>/dev/null || find scripts theme -type f; } | grep -v '^scripts/dev/')
if (( ${#py[@]} >= 2 )) && python3 "$HERE/lib/env-ast.py" "${py[@]}" > "$TMP/envast.out"; then
    ok "N3: every shipped Python script (${#py[@]}) reads INVICTUS_* only through invictus_env, no computed names, absolute tool() defaults"
else
    bad "N3: $(head -5 "$TMP/envast.out")"
fi
# the checker itself: Janus's two shapes, a direct read, a bare default
cat > "$TMP/envast-bad.py" <<'EOF'
import os
def _invictus_env(): pass
a = os.environ.get(
    "INVICTUS_STATE")
def tool(env, d):
    return os.environ.get(env) or d
b = os.environ["INVICTUS_SHARE"]
c = tool("INVICTUS_X", "invictus-provider")
d = os.environ.get("INVICTUS_THREAD", "")  # not an override
EOF
n_bad="$(python3 "$HERE/lib/env-ast.py" "$TMP/envast-bad.py" | wc -l)"
[[ "$n_bad" == 4 ]] && ok "N3: the check catches a split call, a computed name, a subscript and a bare tool() default (4 of 4; the marked label passes)" \
    || bad "N3: the checker found $n_bad of 4 planted reads"
# Minerva ruling 5: the loader raises, and a hook exits only with the literal 2.
mkdir -p "$TMP/envast-hook/scripts/guardrails/claude" "$TMP/envast-hook/scripts/tool"
cat > "$TMP/envast-hook/scripts/guardrails/claude/hook.py" <<'EOF'
import os, sys
def main(): return 2
if main():
    sys.exit(2)
sys.exit(main())
sys.exit(1)
sys.exit()
raise SystemExit
raise SystemExit(0)
os._exit(3)
exit(1)
EOF
cat > "$TMP/envast-hook/scripts/tool/loader.py" <<'EOF'
import os, sys
def _invictus_env():
    path = None
    if path is None:
        sys.exit(1)
    return path
env = _invictus_env()
sys.exit(1)
EOF
python3 "$HERE/lib/env-ast.py" "$TMP/envast-hook/scripts/guardrails/claude/hook.py" "$TMP/envast-hook/scripts/tool/loader.py" > "$TMP/envast-hook.out"
n_hook="$(grep -c 'hook.py:.*without the literal 2' "$TMP/envast-hook.out")"
n_exit="$(grep -c 'hook.py:.*exit (forbidden in a hook' "$TMP/envast-hook.out")"
n_eh="$(grep -c 'hook.py: a hook must set an exit-2 sys.excepthook' "$TMP/envast-hook.out")"
n_load="$(grep -c 'loader.py:.*_invictus_env exits' "$TMP/envast-hook.out")"
n_all="$(wc -l < "$TMP/envast-hook.out")"
[[ "$n_hook" == 6 && "$n_exit" == 1 && "$n_eh" == 1 && "$n_load" == 1 && "$n_all" == 9 ]] \
    && ok "ruling 5: the check catches a hook exit that is not the literal 2 (6 of 6: main(), 1, none, bare and 0 SystemExit, os._exit), the builtin exit, a hook with no excepthook, and a loader that exits; sys.exit(2) and a tool's own exit 1 pass" \
    || bad "ruling 5: env-ast found $n_hook of 6 hook exits, $n_exit of 1 builtin exit, $n_eh of 1 missing excepthook, $n_load of 1 loader exits, $n_all lines: $(head -10 "$TMP/envast-hook.out")"
# Janus J-L2: the rule is a shape, not a list of exits. Each planted hook
# below exits non-2 (or could) and must be named by the lint; the good one
# must pass. The first eight carry a correct excepthook, so only the shape
# itself can be what the lint catches.
JL2="$TMP/envast-jl2/scripts/guardrails/claude"
rm -rf "$TMP/envast-jl2"; mkdir -p "$JL2"
hdr='import os
import sys


def _block(*_):
    try:
        sys.stderr.write("blocked\n")
    finally:
        os._exit(2)


sys.excepthook = _block
'
plant_hook() {  # plant_hook NAME HEADER(yes|no) BODY
    { [[ "$2" == yes ]] && printf '%s' "$hdr"; printf '%s\n' "$3"; } >"$JL2/$1.py"
}
plant_hook alias-sys yes 'import sys as s
s.exit(1)'
plant_hook from-exit yes 'from sys import exit as bye
bye(1)'
plant_hook abort yes 'os.abort()'
plant_hook kill yes 'os.kill(os.getpid(), 9)'
plant_hook getattr yes 'getattr(sys, "exit")(1)'
plant_hook alias-systemexit yes 'E = SystemExit
raise E(1)'
plant_hook subclass yes 'class Out(SystemExit):
    pass


raise Out(1)'
plant_hook builtins-exit yes 'import builtins
builtins.exit(1)'
plant_hook loader-no-try no 'import os, sys
def _invictus_env():
    raise ImportError("helper missing")
env = _invictus_env()'
plant_hook module-raise no 'import os
import pwd
HOME = pwd.getpwuid(os.getuid()).pw_dir'
plant_hook hook-late no 'import os, sys
import json
sys.excepthook = lambda *a: os._exit(2)'
plant_hook hook-exits-1 no 'import os, sys
sys.excepthook = lambda *a: os._exit(1)'
plant_hook hook-undone yes 'sys.excepthook = sys.__excepthook__'
plant_hook good yes 'def main():
    return 2


if main() != 0:
    sys.exit(2)
raise SystemExit(2) from None'
printf '#!/bin/sh\nexit 1\n' >"$JL2/shell-hook.sh"
ln -s good.py "$JL2/link.py"
python3 "$HERE/lib/env-ast.py" --hook-dir "$JL2" >"$TMP/envast-jl2.out"; jl2_rc=$?
jl2_missed=()
for f in alias-sys from-exit abort kill getattr alias-systemexit subclass builtins-exit \
         loader-no-try module-raise hook-late hook-exits-1 hook-undone; do
    grep -q "^$JL2/$f.py" "$TMP/envast-jl2.out" || jl2_missed+=("$f")
done
grep -q "^$JL2/shell-hook.sh: not a .py or .json file" "$TMP/envast-jl2.out" || jl2_missed+=(shell-hook.sh)
grep -q "^$JL2/link.py: not a .py or .json file" "$TMP/envast-jl2.out" || jl2_missed+=(link.py)
grep -q "^$JL2/good.py" "$TMP/envast-jl2.out" && jl2_missed+=("good.py was flagged")
if [[ $jl2_rc == 1 && ${#jl2_missed[@]} == 0 ]]; then
    ok "J-L2: the hook lint catches all 15 planted shapes (sys and exit aliases, os.abort, os.kill, getattr, a SystemExit alias and subclass, builtins.exit, an unwrapped loader, a module-level raise, a late, exit-1 or undone excepthook, a shell hook, a symlink) and passes the good hook"
else
    bad "J-L2: env-ast rc $jl2_rc, missed: ${jl2_missed[*]}"
fi
# ... and the real hook folder: Python hooks and JSON profiles only, every hook in the good shape
if python3 "$HERE/lib/env-ast.py" --hook-dir "$REPO/scripts/guardrails/claude" >"$TMP/envast-dir.out"; then
    ok "J-L2: scripts/guardrails/claude holds only .py and .json files and every hook sets the exit-2 excepthook first"
else
    bad "J-L2: the hook folder: $(head -5 "$TMP/envast-dir.out")"
fi
# ... and the block the helper's docstring tells every script to copy passes the same check
if python3 - "$REPO/scripts/lib/invictus_env.py" "$TMP/envast-doc.py" <<'EOF'
import ast, sys, textwrap
doc = ast.get_docstring(ast.parse(open(sys.argv[1]).read()), clean=False)
block = doc.split("def _invictus_env():", 1)[1]
code = textwrap.dedent("    def _invictus_env():" + block)
assert "raise ImportError" in code, "the copied loader must raise ImportError"
open(sys.argv[2], "w").write("import os, sys\n" + code)
EOF
then
    python3 "$HERE/lib/env-ast.py" "$TMP/envast-doc.py" > "$TMP/envast-doc.out" \
        && ok "ruling 5: the loader block in invictus_env.py's docstring raises ImportError and never exits" \
        || bad "ruling 5: the docstring's loader block: $(head -3 "$TMP/envast-doc.out")"
else
    bad "ruling 5: the docstring's loader block does not raise ImportError"
fi
grep -q "invictus_env.py" "$REPO/pkgs/own/invictus-sys/PKGBUILD" && [[ -f "$ALL/usr/lib/invictus/lib/invictus_env.py" ]] \
    && ok "L1: invictus-sys installs the helper as /usr/lib/invictus/lib/invictus_env.py" || bad "L1: the helper is not packaged"

# L2: an unchanged monitors.lua is left alone, even when the check would fail
new_home l2 atrium
M="$H/.config/hypr/monitors.lua"
fb monitors-write auto
cp "$M" "$H/first"
: > "$H/log"
FAKE_DOCTOR_RC=1 fb monitors-write auto; rc=$?
[[ -f "$M" ]] && cmp -s "$M" "$H/first" && [[ $rc == 0 ]] && ! grep -q "invictus-doctor" "$H/log" \
    && ok "L2: writing the same monitors.lua again changes nothing, checks nothing, deletes nothing" \
    || bad "L2: same text, failed check: rc $rc, file $( [[ -f "$M" ]] && echo kept || echo DELETED ), $(cat "$H/out")"
new_home l2b atrium
FAKE_DOCTOR_RC=1 fb monitors-write auto
[[ ! -e "$H/.config/hypr/monitors.lua" ]] && grep -q '"ok": false' "$H/out" \
    && ok "L2: a new monitors.lua that fails the check is removed (there was none before)" || bad "L2 new file: $(cat "$H/out")"

# L3: two writes in the same second keep two backups
new_home l3 atrium
echo "-- hand-tuned" > "$H/.config/hypr/monitors.lua"
fb monitors-write DP-1; fb monitors-write auto
n_bk="$(find "$H/.local/state/invictus/backups" -name monitors.lua | wc -l)"
grep -rq "hand-tuned" "$H/.local/state/invictus/backups" && [[ "$n_bk" == 2 ]] \
    && ok "L3: back-to-back writes keep every old monitors.lua (unique backup folders)" \
    || bad "L3: $n_bk backups, hand-tuned file $(grep -rlq hand-tuned "$H/.local/state/invictus/backups" && echo kept || echo LOST)"

# L4: a refused kept endpoint is dropped after one try; a bad record never stops start
new_home l4 atrium
FAKE_SYS_RESULT=pending fb assistant home --address atlas.local
: > "$H/log"
FAKE_PROVIDER_RC=3 fb start --if-pending; FAKE_PROVIDER_RC=3 fb start --if-pending
n_set="$(grep -c "invictus-provider set" "$H/log")"
[[ "$n_set" == 1 ]] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert not d['provider_pending'] and d['provider_result']=='provider-refused'" "$H/.local/state/invictus/first-boot.json" \
    && ok "L4: a kept endpoint invictus-provider refuses is tried once, then dropped (provider_result recorded)" \
    || bad "L4: $n_set set calls; $(cat "$H/.local/state/invictus/first-boot.json")"
new_home l4b atrium
echo on > "$H/ai"; fb mark-pending
mkdir -p "$H/.local/state/invictus"
for rec in '{"provider": {"choice": "home"}, "provider_pending": true}' '{"provider": {"choice": "home", "endpoint": 7}, "provider_pending": true}' \
           '{"provider": {"choice": "rm -rf", "endpoint": "atlas.local"}, "provider_pending": true}' '{"provider": "x", "provider_pending": true}' 'not json'; do
    echo "$rec" > "$H/.local/state/invictus/first-boot.json"
    : > "$H/log"
    fb start --if-pending; rc=$?
    if [[ $rc != 0 ]] || ! grep -q "^quickshell" "$H/log" || grep -q "invictus-provider" "$H/log" || grep -q Traceback "$H/err"; then
        bad "L4: record $rec: rc $rc, $(cat "$H/log" "$H/err" | head -3)"; l4bad=1
    fi
done
[[ -z "${l4bad:-}" ]] && ok "L4: a kept choice with no endpoint, a wrong type, an unknown choice or a broken file is dropped; the wizard still opens"
unset l4bad
# I2: a trailing newline is not an address
new_home i2 atrium
fb assistant home --address "$(printf 'atlas.local\n ')"; rc1=$?
fb assistant home --address $'atlas.local\n'; rc2=$?
[[ $rc1 == 2 && $rc2 == 2 && ! -s "$H/log" ]] && ok "I2: an address with a trailing newline is refused" || bad "I2: rc $rc1/$rc2 $(cat "$H/log")"
# I1: a non-ASCII control character in a description still gives a monitors.lua
new_home i1 atrium
python3 - "$H/monitors.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d[1]["description"] = "BOE ‮ panel é"
json.dump(d, open(sys.argv[1], "w"))
EOF
fb monitors-write auto
if [[ -n "$LUA" ]] && stub_check "$H/.config/hypr/monitors.lua" && MON_LUA="$H/.config/hypr/monitors.lua" "$LUA" -e '
  local seen; hl = { monitor = function(t) if t.output:find("BOE") then seen = t.output end end, workspace_rule = function() end }
  dofile(os.getenv("MON_LUA")); assert(seen == "desc:BOE \226\128\174 panel \195\169", seen)' < /dev/null; then
    ok "I1: a description with U+202E is written as UTF-8 byte escapes Lua reads back unchanged"
else
    bad "I1: monitors.lua with U+202E: $(cat "$H/err" "$TMP/fbcheck.log" 2>/dev/null | head -3)"
fi

# ---- Janus's re-check (2026-10-01) ----------------------------------------------------
# N4: invictus-tools needs the invictus-sys that ships the helper
sysv="$(bash -c 'source "$1"; echo "$pkgver-$pkgrel"' _ "$REPO/pkgs/own/invictus-sys/PKGBUILD")"
toolsdeps="$(bash -c 'source "$1"; printf "%s\n" "${depends[@]}"' _ "$REPO/pkgs/own/invictus-tools/PKGBUILD")"
toolsrel="$(bash -c 'source "$1"; echo "$pkgrel"' _ "$REPO/pkgs/own/invictus-tools/PKGBUILD")"
# The floor is 0.2.0-4 (the first invictus-sys with the helper), and no
# higher than the invictus-sys in this tree; a later invictus-sys bump does
# not force a new invictus-tools.
toolsmin="$(sed -n 's/^invictus-sys>=//p' <<< "$toolsdeps")"
vle() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }
[[ -n "$toolsmin" ]] && vle 0.2.0-4 "$toolsmin" && vle "$toolsmin" "$sysv" && (( toolsrel >= 7 )) \
    && ok "N4: invictus-tools (pkgrel $toolsrel) depends on invictus-sys>=$toolsmin (the helper came in 0.2.0-4; this tree has $sysv)" \
    || bad "N4: invictus-tools depends: $(grep invictus-sys <<< "$toolsdeps"), pkgrel $toolsrel"
# N4: without the helper the scripts say so, no traceback
mkdir -p "$TMP/nohelper/bin"
cp "$FB" "$TMP/nohelper/bin/invictus-first-boot"
cp "$REPO/theme/invictus-theme" "$TMP/nohelper/bin/invictus-theme"
cp "$REPO/scripts/moneta/moneta.py" "$TMP/nohelper/bin/moneta.py"
cp "$REPO/scripts/moneta/mcp.py" "$TMP/nohelper/bin/mcp.py"
n4=""
for s in invictus-first-boot invictus-theme moneta.py mcp.py; do
    python3 "$TMP/nohelper/bin/$s" state > /dev/null 2> "$TMP/nohelper/$s.err" < /dev/null; rc=$?
    if [[ $rc == 0 ]] || grep -q Traceback "$TMP/nohelper/$s.err" || ! grep -q "invictus_env.py" "$TMP/nohelper/$s.err"; then
        n4+=" $s(rc $rc: $(tail -1 "$TMP/nohelper/$s.err"))"
    fi
done
[[ -z "$n4" ]] && ok "N4, ruling 5: with the helper missing, the wizard, invictus-theme, the panel and the MCP server stop with a line naming invictus_env.py, no traceback" || bad "N4:$n4"
# Info: a provider-failed kept choice stops after five tries
new_home cap atrium
FAKE_SYS_RESULT=pending fb assistant claude
for _ in 1 2 3 4 5 6 7; do FAKE_PROVIDER_RC=1 fb start --if-pending; done
n_set="$(grep -c "invictus-provider set" "$H/log")"
[[ "$n_set" == 5 ]] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert not d['provider_pending'] and d['provider_result'].startswith('dropped')" "$H/.local/state/invictus/first-boot.json" \
    && ok "a kept choice that keeps failing (exit 1) is tried five times, then dropped" || bad "provider-failed cap: $n_set set calls"
# Info: HOST_RE keeps its anchors, so a later .match() cannot take a prefix
python3 - "$FB" <<'EOF' && ok "HOST_RE is anchored (\A...\Z) as well as fullmatched" || bad "HOST_RE has no anchors"
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'HOST_RE = re\.compile\(r"(.*)"\)', src)
assert m and m.group(1).startswith(r"\A") and m.group(1).endswith(r"\Z"), m and m.group(1)
EOF

# ---- static rules ---------------------------------------------------------------------------
# Every step the command lists either has its screen or is a later release.
missing=""
for id in screens monitors look assistant ready; do
    cap="$(tr '[:lower:]' '[:upper:]' <<< "${id:0:1}")${id:1}"
    [[ -f "$QMLDIR/Step$cap.qml" ]] || missing+=" $id"
done
[[ -z "$missing" ]] && ok "every step of this release has its screen file" || bad "screen files missing:$missing"
grep -q '^    property string picked: ""' "$QMLDIR/StepAssistant.qml" \
    && grep -q 'property string provider: "claude"' "$QMLDIR/StepAssistant.qml" \
    && ok "no-ai.md 2.1: neither card preselected; Claude preselected inside the AI card (drawn: tests/firstboot/qml.sh)" \
    || bad "the assistant screen preselects a card, or not Claude"
hits="$(grep -rnE 'pkexec|sudo |secret-tool|generic-cli|\.credentials\.json.*(open|read)' "$FB" "$QMLDIR" | grep -v '^\S*:[0-9]*:\s*#' || true)"
[[ -z "$hits" ]] && ok "no root path but invictus-sys, no keyring writes of our own, no generic-cli" \
    || bad "forbidden in the wizard: $hits"
# The credentials file is only ever asked whether it exists (design.md 2.3).
uses="$(grep -c 'credentials_file()' "$FB")"
exists="$(grep -c 'credentials_file()\.is_file()' "$FB")"
[[ "$uses" -ge 2 && $((uses - 1)) == "$exists" ]] \
    && ok "never sees the token: every use of the Claude credentials path is an existence check" \
    || bad "the credentials path is used for more than is_file() ($exists of $((uses - 1)))"
echo
unset FAKE_DIR H
set -e
