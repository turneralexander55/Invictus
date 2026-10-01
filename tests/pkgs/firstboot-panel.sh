# shellcheck shell=bash
# Group 19 of tests/pkgs/run.sh (sourced; uses REPO, TMP, ok, bad): first
# start and the Moneta panel together. The real `invictus-first-boot
# assistant` step drives the real `invictus-provider` (scripts/moneta/moneta.py,
# as invictus-tribune links it), with only root and the keyring faked:
# invictus-sys (writes the AI state the way the root helper does), `guardrails
# status` (reads that same state) and secret-tool (records argv and stdin).
# Groups 17 and 18 each test one side against the documented contract; this
# group checks that the two sides actually meet.
# shellcheck disable=SC2153,SC2015,SC2016 # REPO and TMP come from run.sh; ok || bad on purpose; the fakes' bodies expand when they run

if [[ "${BASH_SOURCE[0]}" == "$0" ]] || ! declare -F ok bad >/dev/null || [[ -z "${REPO:-}" || -z "${TMP:-}" ]]; then
    echo "tests/pkgs/firstboot-panel.sh is group 19 of tests/pkgs/run.sh: run that" >&2
    # shellcheck disable=SC2317 # exit is reached when run, not sourced
    return 2 2>/dev/null || exit 2
fi

set +e
echo "== first start with the real provider layer"
IP="$TMP/fbpanel"
mkdir -p "$IP/bin"
# /usr/bin/invictus-provider is a link to moneta.py (invictus-tribune); the
# recorder in front of it logs the argv it is given and runs it unchanged.
ln -sf "$REPO/scripts/moneta/moneta.py" "$IP/bin/invictus-provider"
ipfake() { printf '#!/bin/bash\n%s\n' "$2" > "$IP/$1"; chmod +x "$IP/$1"; }
ipfake invictus-provider 'printf "%s\n" "$*" >> "$IP_DIR/provider-argv"
exec python3 -I "$IP_BIN/invictus-provider" "$@"'
ipfake invictus-sys 'printf "%s\n" "$*" >> "$IP_DIR/sys-argv"
if [[ "$3 $4" == "ai on" ]]; then echo on > "$IP_DIR/ai"; fi
if [[ "$3 $4" == "ai off" ]]; then echo off > "$IP_DIR/ai"; fi
echo "invictus-sys: ok snapshot=7"'
ipfake guardrails '[[ "$1" == status ]] || exit 2
printf "rails=custodia\neffective=custodia\nfull-access=off\nai=%s\n" "$(cat "$IP_DIR/ai")"'
ipfake secret-tool 'printf "%s\n" "$*" >> "$IP_DIR/secret-argv"
if [[ "$1" == store ]]; then cat >> "$IP_DIR/secret-stdin"; printf "\n--\n" >> "$IP_DIR/secret-stdin"; fi'

ip_home() {   # ip_home NAME on|off: a fresh home; sets IH
    IH="$TMP/fbph-$1"
    rm -rf "$IH"
    mkdir -p "$IH/home/.config/invictus" "$IH/run"
    echo atrium > "$IH/home/.config/invictus/flavor"
    echo "$2" > "$IH/ai"
}
# XDG_CONFIG_HOME is set: invictus-provider finds the home through the
# password database, not HOME, and must not touch the real one.
ip_env() {   # ip_env CMD...: the environment both programs see in a session
    HOME="$IH/home" XDG_CONFIG_HOME="$IH/home/.config" XDG_STATE_HOME="" XDG_RUNTIME_DIR="$IH/run" \
        IP_DIR="$IH" IP_BIN="$IP/bin" INVICTUS_STATE="" INVICTUS_AI_FILE="$IH/ai" \
        INVICTUS_SYS_CMD="$IP/invictus-sys" INVICTUS_PROVIDER_CMD="$IP/invictus-provider" \
        INVICTUS_GUARDRAILS="$IP/guardrails" INVICTUS_PROVIDERS_DIR="$REPO/scripts/moneta/providers" \
        INVICTUS_SYS="$IP/invictus-sys" INVICTUS_SECRET_TOOL="$IP/secret-tool" \
        "$@"
}
ip_wizard() { ip_env python3 "$REPO/scripts/first-boot/invictus-first-boot" assistant "$@" > "$IH/out" 2> "$IH/err"; }
ip_get() { ip_env python3 -I "$IP/bin/invictus-provider" get --json 2>> "$IH/err"; }
ip_is() {   # ip_is EXPR: a Python expression over d, the `get --json` output
    ip_get | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if eval(sys.argv[1]) else 1)' "$1" 2>/dev/null
}

# "Another AI service" (no-ai.md 2): the key goes in on the wizard's stdin.
KEY="sk-integ-$$-QX7v"
ip_home other off
printf '%s\n' "$KEY" | ip_wizard other --address api.example.com
grep -q '"result": "ok"' "$IH/out" && [[ "$(cat "$IH/ai")" == on ]] && grep -qx -- '--request first-start ai on' "$IH/sys-argv" \
    && [[ -f "$IH/home/.config/invictus/moneta.toml" ]] \
    && ok "other: the wizard turns AI on through invictus-sys and the real invictus-provider accepts its calls (result ok)" \
    || bad "other: $(cat "$IH/out" "$IH/err")"
[[ "$(grep -c '^store ' "$IH/secret-argv" 2>/dev/null)" == 1 && "$(grep -cxF -- "$KEY" "$IH/secret-stdin" 2>/dev/null)" == 1 ]] \
    && grep -q '^store --label=Moneta: .* invictus-namespace invictus/provider provider openai-compatible endpoint https://api.example.com/v1$' "$IH/secret-argv" \
    && ok "other: the key reaches the keyring once, on secret-tool's stdin, under the provider and its endpoint" \
    || bad "other: keyring calls '$(cat "$IH/secret-argv" 2>/dev/null)', $(grep -cxF -- "$KEY" "$IH/secret-stdin" 2>/dev/null || echo 0) copies of the key on its stdin"
leak="$(grep -rlF -- "$KEY" "$IH" "$IP" 2>/dev/null | grep -vx "$IH/secret-stdin")"
[[ -z "$leak" ]] && ! cat "$IH/provider-argv" "$IH/sys-argv" "$IH/secret-argv" 2>/dev/null | grep -qF -- "$KEY" \
    && ok "other: the key is in no argv (wizard to provider, provider to secret-tool, invictus-sys), file or log" \
    || bad "other: the key leaked into ${leak:-an argv}"
ip_is 'd["name"] == "openai-compatible" and d["endpoint"] == "https://api.example.com/v1" and d["permitted"]' \
    && ok "other: invictus-provider get then shows openai-compatible with the endpoint, allowed to run" \
    || bad "other: get shows $(ip_get)"

# "Home AI": an address, no key.
ip_home home off
ip_wizard home --address atlas.local < /dev/null
grep -q '"result": "ok"' "$IH/out" && [[ ! -e "$IH/secret-argv" ]] \
    && grep -qx 'set openai-compatible --endpoint http://atlas.local:11434/v1' "$IH/provider-argv" \
    && ok "home: no keyring call; the provider is set with the home endpoint the wizard built" \
    || bad "home: out $(cat "$IH/out") keyring $(cat "$IH/secret-argv" 2>/dev/null) provider $(cat "$IH/provider-argv" 2>/dev/null) $(cat "$IH/err")"
ip_is 'd["name"] == "openai-compatible" and d["endpoint"] == "http://atlas.local:11434/v1" and d["permitted"]' \
    && ok "home: invictus-provider get then shows openai-compatible with http://atlas.local:11434/v1" \
    || bad "home: get shows $(ip_get)"

# "No AI", on a machine where AI was on: ai off, no provider call, no key.
ip_home none on
ip_wizard none < /dev/null
grep -q '"ai": "off"' "$IH/out" && grep -qx -- '--request first-start ai off' "$IH/sys-argv" \
    && [[ ! -e "$IH/secret-argv" && ! -e "$IH/provider-argv" && ! -e "$IH/home/.config/invictus/moneta.toml" ]] \
    && ok "No AI: invictus-sys ai off, and neither invictus-provider nor the keyring is called" \
    || bad "No AI: out $(cat "$IH/out") sys $(cat "$IH/sys-argv" 2>/dev/null) provider $(cat "$IH/provider-argv" 2>/dev/null) keyring $(cat "$IH/secret-argv" 2>/dev/null)"
ip_is 'not d["permitted"] and d["why"].startswith("AI is off")' \
    && ok "No AI: invictus-provider get then says nothing may run (AI is off)" \
    || bad "No AI: get shows $(ip_get)"
echo
unset IH
set -e
