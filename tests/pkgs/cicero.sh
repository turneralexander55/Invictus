# shellcheck shell=bash
# Group 17 of tests/pkgs/run.sh (sourced; uses REPO, TMP, TREES, ok, bad):
# the Cicero panel and the provider layer (design 4.2; MUSTs A9, A12, A13).
# The behaviour checks are in cicero_tests.py; this file adds the package
# layout and the static checks for A9 and A12.
# shellcheck disable=SC2153,SC2015 # REPO, TMP and TREES come from run.sh; ok || bad on purpose

if [[ "${BASH_SOURCE[0]}" == "$0" ]] || ! declare -F ok bad >/dev/null || [[ -z "${REPO:-}" || -z "${TMP:-}" || -z "${TREES:-}" ]]; then
    echo "tests/pkgs/cicero.sh is group 17 of tests/pkgs/run.sh: run that" >&2
    # shellcheck disable=SC2317 # exit is reached when run, not sourced
    return 2 2>/dev/null || exit 2
fi

set +e
echo "== Cicero panel: packages"
MT="$TREES/invictus-tribune"
m_fail=0
mbad() { bad "$1"; m_fail=1; }

# Layout and modes of invictus-tribune.
for f in usr/lib/invictus/cicero/cicero.py usr/lib/invictus/cicero/mcp.py; do
    [[ -f "$MT/$f" && "$(stat -c %a "$MT/$f")" == 755 ]] || mbad "invictus-tribune: $f missing or not 0755"
done
for l in tribune invictus-provider; do
    [[ -L "$MT/usr/bin/$l" && "$(readlink "$MT/usr/bin/$l")" == ../lib/invictus/cicero/cicero.py ]] \
        || mbad "invictus-tribune: /usr/bin/$l must point at ../lib/invictus/cicero/cicero.py"
done
for p in claude-code generic-cli openai-compatible none; do
    [[ -f "$MT/usr/share/invictus/providers/$p/provider.toml" && "$(stat -c %a "$MT/usr/share/invictus/providers/$p/provider.toml")" == 644 ]] \
        || mbad "invictus-tribune: provider $p missing or not 0644"
done
grep -qx 'chat = \["/usr/bin/claude", "--plugin-dir", "/usr/share/invictus/claude-plugin"\]' \
    "$MT/usr/share/invictus/providers/claude-code/provider.toml" || mbad "claude-code must run /usr/bin/claude (absolute, not PATH) with the Invictus plugin"
PL="$MT/usr/share/invictus/claude-plugin"
python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); m=json.load(open(sys.argv[2])); assert p["name"]=="invictus"; s=m["mcpServers"]["invictus"]; assert s["command"]=="/usr/bin/python3" and s["args"]==["-I","/usr/lib/invictus/cicero/mcp.py"]' \
    "$PL/.claude-plugin/plugin.json" "$PL/.mcp.json" 2>/dev/null || mbad "plugin.json / .mcp.json: name invictus and the MCP server at /usr/lib/invictus/cicero/mcp.py, run with python3 -I"
SH="$REPO/scripts/cicero/claude-plugin/skills/invictus-tools/SKILL.head.md"
if [[ "$(sed -n '1p;4p' "$SH" | paste -sd' ')" != "--- ---" ]] || ! grep -qx 'name: invictus-tools' "$SH" \
   || ! cmp -s <(cat "$SH" "$REPO/collegium/template/TOOLS.md") "$PL/skills/invictus-tools/SKILL.md"; then
    mbad "the invictus-tools skill must be the frontmatter plus collegium/template/TOOLS.md, unchanged"
fi
[[ -f "$MT/usr/share/invictus/hypr/invictus/cicero.lua" ]] || mbad "invictus-tribune must ship cicero.lua (Super+A)"
[[ ! -e "$TREES/invictus-desktop/usr/share/invictus/hypr/invictus/cicero.lua" ]] || mbad "invictus-desktop ships cicero.lua: a No AI desktop would have Super+A"
# shellcheck source=scripts/lib/ai-set.sh
( . "$REPO/scripts/lib/ai-set.sh"; [[ " $AI_PKGS " == *" invictus-tribune "* ]] ) || mbad "invictus-tribune must be in the AI set (ai off removes it)"
for f in scripts/cicero/cicero.py scripts/cicero/mcp.py; do
    head -1 "$REPO/$f" | grep -qx '#!/usr/bin/python3 -I' || mbad "$f must run with python3 -I (no cwd or user site on sys.path)"
    python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$REPO/$f" || mbad "$f does not parse"
done
[[ $m_fail == 0 ]] && ok "invictus-tribune: panel, providers (0644), plugin with TOOLS.md as its skill, MCP server, Super+A; tribune is in the AI set"

# Janus L1: every print or write in the panel that interpolates a value goes
# through ext() (one line, no control bytes, no direction overrides), except
# values this file made itself or checked to be plain names and numbers.
if python3 - "$REPO/scripts/cicero/cicero.py" <<'PY'
import re, sys
SAFE = {"'*' if r['selected'] else ' '", "r['name']:<20", "r['kind']:<4", "p['name']", "self.child.pid", "thread",
        "rc", "n", "k", "' '.join(shlex.quote(a) for a in argv)"}
SAFE_ARGS = re.compile(r"^(\"[^\"{}]*\"|PROVIDER_HELP|why|why or \"[^\"]*\"|json\.dumps\(\w+\)|clean\(\w+\)|"
                       r"meaning\.get\(rc, f\"Finished with code \{rc\}\.\"\)|"
                       r"(\"[^\"{}]*\" \+ )?\"[^\"{}]*\"\.join\(ext\(\w+\) for \w+ in \w+\)( if \w+ else \"[^\"{}]*\")?|)$")
bad = []
for no, line in enumerate(open(sys.argv[1]), 1):
    m = re.search(r"(?:\bprint|sys\.std(?:out|err)\.write)\((.*)\)", line)
    if not m:
        continue
    arg = re.sub(r",\s*(file|flush)=[^,)]*", "", m.group(1)).strip()
    arg = re.sub(r"\)\s*;\s*sys\.stdout\.flush\(.*$", "", arg)
    if "f\"" in arg or "f'" in arg:
        for field in re.findall(r"\{([^{}]+)\}", arg):
            if not field.startswith("ext(") and field not in SAFE:
                bad.append(f"{no}: {{{field}}}")
    elif not SAFE_ARGS.match(arg):
        bad.append(f"{no}: {arg}")
if bad:
    print("prints of outside text not through ext(): " + "; ".join(bad))
    sys.exit(1)
PY
then ok "L1: every print in the panel and provider tools that carries outside text goes through ext()"
else bad "L1: a print bypasses ext() (see the line above)"; fi

# Minerva's final review: the S2
# row carries the Wi-Fi exception and its 802.1X exclusion, note 45 and
# first-boot.md point to it; note 37b no longer says byte-identical.
if python3 - "$REPO" <<'PY'
import ast, re, sys
repo = sys.argv[1]
design = open(f"{repo}/docs/design.md").read()
s2 = next(l for l in design.splitlines() if l.startswith("| S2 |"))
assert "Wi-Fi passwords of shared networks" in s2 and "802.1X" in s2 and "auth_admin_keep" in s2, "S2 row"
n45 = next(l for l in design.splitlines() if l.startswith("45. "))
assert "design.md S2" in n45, "note 45"
fb = " ".join(open(f"{repo}/docs/first-boot.md").read().split())
assert "802.1X exclusion: design.md S2" in fb, "first-boot.md"
n37b = next(l for l in design.splitlines() if l.startswith("37b. "))
assert "byte-identical" not in n37b, "note 37b"
# Janus I-2: SM2 holds on adopted installs too, because invictus-sys owns the generator mask
sm2 = next(l for l in open(f"{repo}/docs/design-simple-mode.md").read().splitlines() if l.startswith("| SM2 |"))
assert "owned by `invictus-sys` (`pacman -Qo`), on ISO and adopted installs alike" in sm2, "SM2"
PY
then ok "S2 docs: S2 has the Wi-Fi exception, note 45 and first-boot.md point to it; note 37b fixed; SM2 names invictus-sys as the mask's owner (I-2)"
else bad "S2 docs out of step with Minerva's text (see the assertion above)"; fi

# A9: no tool of ours names the Windows VM's or the work profile's files, except
# the deny rules that keep Cicero out of them.
hits="$(grep -rnE '/var/lib/invictus/vm|invictus/windows|winapps' "$REPO/scripts" "$REPO/config" \
        --include='*.sh' --include='*.py' --include='*.lua' 2>/dev/null)"
[[ -z "$hits" ]] && ok "A9: no Invictus script or the panel reads the VM, Windows or WinApps paths" \
    || bad "A9: these name VM or work paths: $hits"

# A12: the only code that sends anything over the network is the api
# provider's chat client (the person's own words to the service they chose);
# cicero_tests.py checks what that request carries.
hits="$(grep -rnE 'urlopen|requests\.post|http\.client|curl[^|]*(-d |--data|-X POST|-F )|wget[^|]*--post' \
        "$REPO/scripts" --include='*.sh' --include='*.py' 2>/dev/null \
        | grep -v '^[^:]*scripts/dev/' | grep -vE '^[^:]*scripts/cicero/cicero\.py:[0-9]+:    with urllib\.request\.urlopen\(req, timeout=180\) as resp:$')"
[[ -z "$hits" ]] && ok "A12: one network send in our tools, the chat client's request (scripts/dev excluded: never installed)" \
    || bad "A12: network sends outside the chat client: $hits"

python3 -I "$REPO/tests/pkgs/cicero_tests.py" "$REPO" "$TMP" > "$TMP/cicero.out" 2>&1
rc=$?
grep -E '^(ok|FAIL)' "$TMP/cicero.out"
if [[ $rc != 0 ]]; then
    bad "cicero_tests.py exit $rc: $(grep -vE '^(ok|==)' "$TMP/cicero.out" | tail -5)"
fi
set -e
