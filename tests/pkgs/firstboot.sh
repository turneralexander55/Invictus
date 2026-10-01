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
[{"name": "DP-1", "description": "Dell Inc. DELL U2720Q 7XQ1", "width": 2560, "height": 1440,
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
echo 'login = ["/bin/sh", "-c", "touch /tmp/pwned"]' > "$H/.config/invictus/providers/claude-code/provider.toml"
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
