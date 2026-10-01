# shellcheck shell=bash
# Group 17 of tests/pkgs/run.sh (sourced; uses REPO, TMP, TREES, ok, bad):
# the Moneta panel and the provider layer (design 4.2; MUSTs A6 to A9, A12,
# A13; design-simple-mode SM10, SM26). The behaviour checks are in
# moneta_tests.py; this file adds the package layout, the managed profiles'
# keys (each checked against the Claude Code docs, design.md 11 "Moneta
# panel") and the static checks for A9 and A12.
# shellcheck disable=SC2153,SC2015 # REPO, TMP and TREES come from run.sh; ok || bad on purpose

if [[ "${BASH_SOURCE[0]}" == "$0" ]] || ! declare -F ok bad >/dev/null || [[ -z "${REPO:-}" || -z "${TMP:-}" || -z "${TREES:-}" ]]; then
    echo "tests/pkgs/moneta.sh is group 17 of tests/pkgs/run.sh: run that" >&2
    # shellcheck disable=SC2317 # exit is reached when run, not sourced
    return 2 2>/dev/null || exit 2
fi

set +e
echo "== Moneta panel: packages and profiles"
MT="$TREES/invictus-tribune"
GT="$TREES/invictus-guardrails"
m_fail=0
mbad() { bad "$1"; m_fail=1; }

# Layout and modes of invictus-tribune.
for f in usr/lib/invictus/moneta/moneta.py usr/lib/invictus/moneta/mcp.py; do
    [[ -f "$MT/$f" && "$(stat -c %a "$MT/$f")" == 755 ]] || mbad "invictus-tribune: $f missing or not 0755"
done
for l in tribune invictus-provider; do
    [[ -L "$MT/usr/bin/$l" && "$(readlink "$MT/usr/bin/$l")" == ../lib/invictus/moneta/moneta.py ]] \
        || mbad "invictus-tribune: /usr/bin/$l must point at ../lib/invictus/moneta/moneta.py"
done
for p in claude-code generic-cli openai-compatible none; do
    [[ -f "$MT/usr/share/invictus/providers/$p/provider.toml" && "$(stat -c %a "$MT/usr/share/invictus/providers/$p/provider.toml")" == 644 ]] \
        || mbad "invictus-tribune: provider $p missing or not 0644"
done
grep -qx 'chat = \["/usr/bin/claude", "--plugin-dir", "/usr/share/invictus/claude-plugin"\]' \
    "$MT/usr/share/invictus/providers/claude-code/provider.toml" || mbad "claude-code must run /usr/bin/claude (absolute, not PATH) with the Invictus plugin"
PL="$MT/usr/share/invictus/claude-plugin"
python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); m=json.load(open(sys.argv[2])); assert p["name"]=="invictus"; s=m["mcpServers"]["invictus"]; assert s["command"]=="/usr/bin/python3" and s["args"]==["-I","/usr/lib/invictus/moneta/mcp.py"]' \
    "$PL/.claude-plugin/plugin.json" "$PL/.mcp.json" 2>/dev/null || mbad "plugin.json / .mcp.json: name invictus and the MCP server at /usr/lib/invictus/moneta/mcp.py, run with python3 -I"
SH="$REPO/scripts/moneta/claude-plugin/skills/invictus-tools/SKILL.head.md"
if [[ "$(sed -n '1p;4p' "$SH" | paste -sd' ')" != "--- ---" ]] || ! grep -qx 'name: invictus-tools' "$SH" \
   || ! cmp -s <(cat "$SH" "$REPO/collegium/template/TOOLS.md") "$PL/skills/invictus-tools/SKILL.md"; then
    mbad "the invictus-tools skill must be the frontmatter plus collegium/template/TOOLS.md, unchanged"
fi
[[ -f "$MT/usr/share/invictus/hypr/invictus/moneta.lua" ]] || mbad "invictus-tribune must ship moneta.lua (Super+A)"
[[ ! -e "$TREES/invictus-desktop/usr/share/invictus/hypr/invictus/moneta.lua" ]] || mbad "invictus-desktop ships moneta.lua: a No AI desktop would have Super+A"
[[ "$(stat -c %a "$GT/usr/lib/invictus/claude-config-guard" 2>/dev/null)" == 755 ]] || mbad "invictus-guardrails must ship /usr/lib/invictus/claude-config-guard 0755 beside the profiles"
for p in fixed full; do
    [[ "$(stat -c %a "$GT/usr/share/invictus/guardrails/claude/$p.json" 2>/dev/null)" == 644 ]] || mbad "profile $p.json missing or not 0644"
done
# shellcheck source=scripts/lib/ai-set.sh
( . "$REPO/scripts/lib/ai-set.sh"; [[ " $AI_PKGS " == *" invictus-tribune "* ]] ) || mbad "invictus-tribune must be in the AI set (ai off removes it)"
for f in scripts/moneta/moneta.py scripts/moneta/mcp.py scripts/guardrails/claude/config-guard.py; do
    head -1 "$REPO/$f" | grep -qx '#!/usr/bin/python3 -I' || mbad "$f must run with python3 -I (no cwd or user site on sys.path)"
    python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$REPO/$f" || mbad "$f does not parse"
done
[[ $m_fail == 0 ]] && ok "invictus-tribune: panel, providers (0644), plugin with TOOLS.md as its skill, MCP server, Super+A; the guard ships with the profiles; tribune is in the AI set"

# A7, A8: the managed profiles. Only keys checked against the docs.
if python3 - "$REPO/scripts/guardrails/claude/fixed.json" "$REPO/scripts/guardrails/claude/full.json" <<'PY'
import json, sys
A7 = ["Bash(sudo *)", "Bash(rm -rf *)", "Bash(dd *)", "Bash(mkfs*)", "Bash(btrfs subvolume delete *)",
      "Bash(makepkg *)", "Bash(pacman *)", "Read(~/.claude/.credentials.json)", "Read(~/.ssh/**)",
      "Read(~/.local/share/keyrings/**)", "Read(~/.config/invictus/windows/**)", "Read(~/.config/winapps/**)",
      "Edit(//etc/**)", "Edit(//boot/**)", "Edit(//usr/**)"]
VERIFIED_TOP = {"permissions", "disableAutoMode", "env", "hooks", "allowManagedHooksOnly"}
VERIFIED_PERM = {"defaultMode", "disableBypassPermissionsMode", "deny"}
for path in sys.argv[1:]:
    kind = "fixed" if path.endswith("fixed.json") else "full"
    d = json.load(open(path))
    assert set(d) <= VERIFIED_TOP, (path, set(d) - VERIFIED_TOP)
    p = d["permissions"]
    assert set(p) <= VERIFIED_PERM, (path, set(p) - VERIFIED_PERM)
    assert p["defaultMode"] == "default" and p["disableBypassPermissionsMode"] == "disable", path
    assert d["disableAutoMode"] == "disable", path
    missing = [r for r in A7 if r not in p["deny"]]
    assert not missing, (path, missing)
    for r in p["deny"]:
        assert "(" not in r or r.endswith(")"), r
        if r.startswith(("Read(", "Edit(")):
            assert r[5:7] in ("~/", "//"), ("absolute and home rules need // or ~/", r)
    assert d["env"]["DISABLE_UPDATES"] == "1", path
    pre = d["hooks"]["PreToolUse"][0]
    assert pre["matcher"] == "Edit|Write|MultiEdit|NotebookEdit", path
    assert pre["hooks"][0]["command"] == f"/usr/lib/invictus/claude-config-guard pre {kind}", path
    assert d["hooks"]["PostToolUse"][0]["hooks"][0]["command"] == "/usr/lib/invictus/claude-config-guard post", path
    if kind == "fixed":
        assert "Bash" in p["deny"] and "NotebookEdit" in p["deny"] and d.get("allowManagedHooksOnly") is True, path
    else:
        assert "Bash" not in p["deny"], path
PY
then ok "A7/A8: both profiles carry every A7 deny rule, bypass and auto mode off, updates off and the A6 guard; only documented keys"
else bad "A7/A8: the managed profiles (see the assertion above)"; fi

# Janus L1: every print or write in the panel that interpolates a value goes
# through ext() (one line, no control bytes, no direction overrides), except
# values this file made itself or checked to be plain names and numbers.
if python3 - "$REPO/scripts/moneta/moneta.py" <<'PY'
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

# Janus L2: Claude Code lets a tool call go ahead when a hook times out, so
# the guard's hooks carry short timeouts, and the guard's own doctor run ends
# before the post hook's does (a slow check still restores).
if python3 - "$REPO/scripts/guardrails/claude/fixed.json" "$REPO/scripts/guardrails/claude/full.json" "$REPO/scripts/guardrails/claude/config-guard.py" <<'PY'
import json, re, sys
dt = int(re.search(r"^DOCTOR_TIMEOUT = (\d+)$", open(sys.argv[3]).read(), re.M).group(1))
for path in sys.argv[1:3]:
    h = json.load(open(path))["hooks"]
    pre, post = h["PreToolUse"][0]["hooks"][0], h["PostToolUse"][0]["hooks"][0]
    assert isinstance(pre.get("timeout"), int) and 1 <= pre["timeout"] <= 15, (path, pre)
    assert isinstance(post.get("timeout"), int) and dt + 5 <= post["timeout"] <= 120, (path, post, dt)
PY
then ok "L2: the guard's hooks have short timeouts (pre <= 15 s), and its doctor run ends before the post hook's"
else bad "L2: hook timeouts (see the assertion above)"; fi

# A9: no tool of ours names the Windows VM's or the work profile's files, except
# the deny rules that keep Moneta out of them.
hits="$(grep -rnE '/var/lib/invictus/vm|invictus/windows|winapps' "$REPO/scripts" "$REPO/config" \
        --include='*.sh' --include='*.py' --include='*.lua' 2>/dev/null)"
[[ -z "$hits" ]] && ok "A9: no Invictus script or the panel reads the VM, Windows or WinApps paths" \
    || bad "A9: these name VM or work paths: $hits"

# A12: the only code that sends anything over the network is the api
# provider's chat client (the person's own words to the service they chose);
# moneta_tests.py checks what that request carries.
hits="$(grep -rnE 'urlopen|requests\.post|http\.client|curl[^|]*(-d |--data|-X POST|-F )|wget[^|]*--post' \
        "$REPO/scripts" --include='*.sh' --include='*.py' 2>/dev/null \
        | grep -v '^[^:]*scripts/dev/' | grep -vE '^[^:]*scripts/moneta/moneta\.py:[0-9]+:    with urllib\.request\.urlopen\(req, timeout=180\) as resp:$')"
[[ -z "$hits" ]] && ok "A12: one network send in our tools, the chat client's request (scripts/dev excluded: never installed)" \
    || bad "A12: network sends outside the chat client: $hits"

python3 -I "$REPO/tests/pkgs/moneta_tests.py" "$REPO" "$TMP" > "$TMP/moneta.out" 2>&1
rc=$?
grep -E '^(ok|FAIL)' "$TMP/moneta.out"
if [[ $rc != 0 ]]; then
    bad "moneta_tests.py exit $rc: $(grep -vE '^(ok|==)' "$TMP/moneta.out" | tail -5)"
fi
set -e
