# Group 17 of tests/pkgs/run.sh (through cicero.sh): the Cicero panel
# (tribune), the provider layer, the chat client and the MCP server. Prints "ok    ..." or "FAIL  ..." lines; exit 1 on any FAIL.
#
# usage: python3 -I cicero_tests.py REPO TMPDIR
#
# Faked at the seam: /etc/invictus/ai (a state file), secret-tool, invictus-sys, invictus-doctor and journalctl (recorders), the
# agent (a script that leaves a grandchild in its own session) and an
# OpenAI-compatible endpoint (http.server on 127.0.0.1).
import http.server
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time

REPO, TMP = sys.argv[1], sys.argv[2]
MON = os.path.join(REPO, "scripts/cicero/cicero.py")
MCP = os.path.join(REPO, "scripts/cicero/mcp.py")
PY = sys.executable
FAILED = 0


def ok(msg):
    print(f"ok    {msg}", flush=True)


def bad(msg):
    global FAILED
    FAILED = 1
    print(f"FAIL  {msg}", flush=True)


def check(cond, good, failmsg):
    ok(good) if cond else bad(failmsg)
    return cond


W = os.path.join(TMP, "cicero")
shutil.rmtree(W, ignore_errors=True)
FAKE = os.path.join(W, "fake")
os.makedirs(FAKE)
STATE = os.path.join(W, "state")
LOG = os.path.join(W, "log")


def script(name, body):
    p = os.path.join(FAKE, name)
    with open(p, "w") as f:
        f.write("#!/bin/bash\n" + body)
    os.chmod(p, 0o755)
    return p


script("invictus-sys", 'printf "%s\\n" "$(printf "%q " "$@")" >> "$FAKE_LOG.sys"\necho "invictus-sys: ok snapshot=7"\nexit "${FAKE_SYS_RC:-0}"\n')
script("secret-tool", 'printf "%s\\n" "$*" >> "$FAKE_LOG.secret"\n'
       'if [[ "$1" == store ]]; then cat > "$FAKE_LOG.secret-stdin"; fi\n'
       'if [[ "$1" == lookup && -f "$FAKE_KEY" ]]; then cat "$FAKE_KEY"; fi\n')
script("doctor", 'echo "doctor $*" >> "$FAKE_LOG.doctor"\necho "FAIL  hypr: user.lua line 3"\nexit "${FAKE_DOCTOR_RC:-0}"\n')
script("journalctl", 'echo \'{"__REALTIME_TIMESTAMP":"1759320000000000","INVICTUS_VERB":"install","INVICTUS_ARGS":"firefox","INVICTUS_RESULT":"ok","INVICTUS_SNAPSHOT":"12","INVICTUS_REQUEST":"t-1","INVICTUS_USER":"alex"}\'\n')
# The agent: records its pid, leaves a grandchild in its own session (a
# process group kill alone would miss it), and optionally ignores SIGTERM.
AGENT = script("agent", 'echo "$$" >> "$FAKE_LOG.agent"\n'
               'setsid sleep 300 & echo "$!" >> "$FAKE_LOG.grandchild"\n'
               '[[ -n "${AGENT_IGNORE_TERM:-}" ]] && trap "" TERM\n'
               'echo "agent env thread=$INVICTUS_THREAD provider=$INVICTUS_PROVIDER" >> "$FAKE_LOG.agent-env"\n'
               'while :; do sleep 0.2; done\n')
SHELL_AGENT = script("shell-agent", 'echo ran >> "$FAKE_LOG.shell"\nsleep 300\n')

SYSPROV = os.path.join(W, "providers")
shutil.copytree(os.path.join(REPO, "scripts/cicero/providers"), SYSPROV)
# The shipped claude-code provider runs /usr/bin/claude; here, the fake agent.
with open(os.path.join(SYSPROV, "claude-code/provider.toml")) as f:
    shipped_claude = f.read()
with open(os.path.join(SYSPROV, "claude-code/provider.toml"), "w") as f:
    f.write(shipped_claude.replace('chat = ["/usr/bin/claude", "--plugin-dir", "/usr/share/invictus/claude-plugin"]',
                                   f'chat = ["{AGENT}"]'))

HOME = os.path.join(W, "home")
CONF = os.path.join(HOME, ".config")
# A socket path must fit in 108 bytes: the runtime folder goes in /tmp.
RUN = tempfile.mkdtemp(prefix="mon.", dir="/tmp")
os.makedirs(CONF)


def state(ai="on"):
    with open(STATE, "w") as f:
        f.write(f"{ai}\n")


def envmap(**extra):
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": HOME, "XDG_CONFIG_HOME": CONF,
         "XDG_RUNTIME_DIR": RUN, "INVICTUS_AI_FILE": STATE,
         "INVICTUS_PROVIDERS_DIR": SYSPROV, "INVICTUS_SYS": os.path.join(FAKE, "invictus-sys"),
         "INVICTUS_SECRET_TOOL": os.path.join(FAKE, "secret-tool"), "INVICTUS_JOURNALCTL": os.path.join(FAKE, "journalctl"),
         "INVICTUS_DOCTOR": os.path.join(FAKE, "doctor"), "FAKE_LOG": LOG,
         "TRIBUNE_GRACE": "2", "LC_ALL": "C.UTF-8"}
    e.update({k: v for k, v in extra.items() if v is not None})
    return e


def provider(*args, stdin="", **extra):
    return subprocess.run([PY, "-I", MON, "provider", *args], input=stdin, capture_output=True, text=True,
                          env=envmap(**extra), timeout=30)


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default


def reset_logs():
    for n in os.listdir(W):
        if n.startswith("log"):
            os.unlink(os.path.join(W, n))


def settings(text):
    os.makedirs(os.path.join(CONF, "invictus"), exist_ok=True)
    with open(os.path.join(CONF, "invictus/cicero.toml"), "w") as f:
        f.write(text)


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError:
        return False


def pids(name):
    return [int(x) for x in read(f"{LOG}.{name}").split()]


# ---- provider layer -------------------------------------------------------------------
print("== Cicero: provider layer", flush=True)
state()
r = provider("list", "--json")
rows = {x["name"]: x for x in json.loads(r.stdout or "[]")} if r.returncode == 0 else {}
check(set(rows) == {"claude-code", "generic-cli", "openai-compatible", "none"} and rows["claude-code"]["selected"],
      "4.2: four shipped providers (claude-code, generic-cli, openai-compatible, none); claude-code is the default",
      f"provider list: rc {r.returncode} {r.stdout} {r.stderr}")

# A home provider never replaces a shipped one (A8: the agent cannot change
# its own command by writing ~/.config/invictus/providers/claude-code).
os.makedirs(os.path.join(CONF, "invictus/providers/claude-code"))
with open(os.path.join(CONF, "invictus/providers/claude-code/provider.toml"), "w") as f:
    f.write(f'name = "claude-code"\nkind = "cli"\nchat = ["{SHELL_AGENT}"]\n')
os.makedirs(os.path.join(CONF, "invictus/providers/mine"))
with open(os.path.join(CONF, "invictus/providers/mine/provider.toml"), "w") as f:
    f.write(f'name = "mine"\nkind = "cli"\nchat = ["{SHELL_AGENT}"]\n')
r = provider("list", "--json")
rows = {x["name"]: x for x in json.loads(r.stdout or "[]")}
check(rows.get("claude-code", {}).get("source") == "system" and rows.get("mine", {}).get("command_agent") is True,
      "A8: a home provider named claude-code is ignored; a home cli provider counts as a command-line agent",
      f"shadowing: {rows}")

# Who may run, from root-owned state only: with AI on every provider, with
# No AI (or no /etc/invictus/ai) only none.
matrix = {}
for ai in ("on", "off"):
    state(ai)
    r = provider("list", "--json")
    matrix[ai] = sorted(x["name"] for x in json.loads(r.stdout or "[]") if x["offered"])
os.unlink(STATE)
r = provider("list", "--json")
matrix["missing"] = sorted(x["name"] for x in json.loads(r.stdout or "[]") if x["offered"])
check(matrix == {"on": ["claude-code", "generic-cli", "mine", "none", "openai-compatible"], "off": ["none"], "missing": ["none"]},
      "every provider is offered with AI on; No AI, or no /etc/invictus/ai, offers only none", f"offered {matrix}")

state()
r = provider("set", "generic-cli", "--command", "--", SHELL_AGENT, "-x")
mode = stat.S_IMODE(os.stat(os.path.join(CONF, "invictus/cicero.toml")).st_mode) if r.returncode == 0 else 0
got = json.loads(provider("get", "--json").stdout or "{}")
check(r.returncode == 0 and mode == 0o600 and got.get("name") == "generic-cli" and got.get("permitted"),
      "generic-cli set with its command; cicero.toml is 0600",
      f"set generic-cli: rc {r.returncode} {r.stderr} mode {oct(mode)} get {got}")

# Endpoints: plain http only at home, no credentials in the URL.
results = {}
for url in ("http://example.com/v1", "http://8.8.8.8/v1", "http://192.168.1.5:11434/v1", "http://localhost:8080/v1",
            "http://box.lan/v1", "https://api.example.com/v1", "http://u:p@192.168.1.5/v1", "file:///etc/passwd"):
    results[url] = provider("set", "openai-compatible", "--endpoint", url, "--model", "m1").returncode
check(results == {"http://example.com/v1": 2, "http://8.8.8.8/v1": 2, "http://192.168.1.5:11434/v1": 0,
                  "http://localhost:8080/v1": 0, "http://box.lan/v1": 0, "https://api.example.com/v1": 0,
                  "http://u:p@192.168.1.5/v1": 2, "file:///etc/passwd": 2},
      "keys never cross the internet in clear text: http only to this computer or the home network",
      f"endpoints: {results}")

# Keys: stdin to secret-tool, never argv; the namespace ai off clears.
reset_logs()
provider("set", "openai-compatible", "--endpoint", "http://127.0.0.1:9/v1", "--model", "m1")
r = provider("key", "set", "openai-compatible", stdin="sk-test-secret-123\n")
argv_log = read(f"{LOG}.secret")
check(r.returncode == 0 and "sk-test-secret-123" not in argv_log and read(f"{LOG}.secret-stdin") == "sk-test-secret-123"
      and "invictus-namespace invictus/provider provider openai-compatible endpoint http://127.0.0.1:9/v1" in argv_log,
      "S2: the API key goes to the keyring on secret-tool's stdin, under invictus/provider and its endpoint",
      f"key set: rc {r.returncode} argv {argv_log!r} stdin {read(f'{LOG}.secret-stdin')!r}")
reset_logs()
provider("key", "clear")
check(read(f"{LOG}.secret").strip() == "clear invictus-namespace invictus/provider",
      "NA2: `key clear` removes every Cicero key by the namespace", f"key clear: {read(f'{LOG}.secret')!r}")

# Janus L1: a home provider's label and model reach the terminal through
# `list`, `get` and `set`; escape sequences and direction overrides must not.
os.makedirs(os.path.join(CONF, "invictus/providers/evil"))
with open(os.path.join(CONF, "invictus/providers/evil/provider.toml"), "w") as f:
    f.write('name = "evil"\nkind = "api"\nendpoint = "http://127.0.0.1:9/v1"\nmodel = "m\\u001b]52;c;eA==\\u0007"\n'
            'label = "Home \\u001b[2J\\u001b]0;pwned\\u0007 AI \\u202eIA"\n')
state()
outs = [provider("set", "evil"), provider("list"), provider("get")]
raw = "".join(r.stdout + r.stderr for r in outs)
check(all(r.returncode == 0 for r in outs) and "Home" in raw and "\x1b" not in raw and "\x07" not in raw
      and "\u202e" not in raw,
      "L1: a provider's label and model print with no escape sequences or direction overrides (list, get, set)",
      f"hostile label: {[r.returncode for r in outs]} {raw!r}")
shutil.rmtree(os.path.join(CONF, "invictus/providers/evil"))

# ---- the panel ---------------------------------------------------------------------------
print("== Cicero: the panel (tribune)", flush=True)
SOCK = os.path.join(RUN, "invictus/tribune.sock")


class Panel:
    def __init__(self, **extra):
        self.out = os.path.join(W, f"panel.{time.time_ns()}")
        self.f = open(self.out, "w")
        self.p = subprocess.Popen([PY, "-I", MON, "run"], stdin=subprocess.PIPE, stdout=self.f, stderr=subprocess.STDOUT,
                                  env=envmap(**extra), text=True)

    def text(self):
        return read(self.out)

    def wait_for(self, what, timeout=10, count=1):
        end = time.time() + timeout
        while time.time() < end:
            if self.text().count(what) >= count:
                return True
            if self.p.poll() is not None:
                return self.text().count(what) >= count
            time.sleep(0.05)
        return False

    def finish(self):
        if self.p.poll() is None:
            self.p.terminate()
            try:
                self.p.wait(10)
            except subprocess.TimeoutExpired:
                self.p.kill()
        for pid in pids("agent") + pids("grandchild"):
            try:
                os.kill(pid, 9)
            except OSError:
                pass


state()
settings('provider = "claude-code"\n')
reset_logs()
P = Panel()
started = P.wait_for("[tribune] started claude-code")
time.sleep(0.3)
st = os.stat(SOCK) if os.path.exists(SOCK) else None
check(started and st and stat.S_ISSOCK(st.st_mode) and stat.S_IMODE(st.st_mode) == 0o600
      and stat.S_IMODE(os.stat(os.path.dirname(SOCK)).st_mode) == 0o700,
      "panel: starts claude-code and holds $XDG_RUNTIME_DIR/invictus/tribune.sock (0600, folder 0700) so only one panel runs",
      f"panel start: {P.text()!r} sock {st}")
env_line = read(f"{LOG}.agent-env")
check("provider=claude-code" in env_line and "thread=t-" in env_line,
      "panel: the agent gets its thread id (INVICTUS_THREAD) for invictus-sys --request", f"agent env {env_line!r}")

second = subprocess.run([PY, "-I", MON, "run"], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                        env=envmap(), timeout=20)
check(second.returncode == 3 and "already open" in second.stdout and os.path.exists(SOCK),
      "panel: a second panel refuses (exit 3) and leaves the first one's socket alone",
      f"second panel: {second.returncode} {second.stdout!r}")

P.finish()

# The panel refuses every provider with No AI.
reset_logs()
state("off")
settings('provider = "claude-code"\n')
P = Panel()
r2 = P.wait_for("AI is off")
P.finish()
check(r2 and not read(f"{LOG}.agent"), "NA: with No AI nothing starts", f"refusal: {r2} {P.text()!r}")

# Acta in the panel's header.
state()
settings('provider = "none"\n')
P = Panel()
P.wait_for("No assistant is set up")
check("install  firefox  ok  snapshot=12" in P.text(), "Acta: the panel shows the last invictus-sys calls",
      f"acta header: {P.text()!r}")
P.finish()
r = subprocess.run([PY, "-I", MON, "acta", "-n", "5"], capture_output=True, text=True, env=envmap(), timeout=20)
check(r.returncode == 0 and "thread t-1" in r.stdout, "Acta: `tribune acta` lists them with the thread that asked",
      f"tribune acta: {r.stdout!r}")

# ---- the chat client (api providers, A13) ---------------------------------------------
print("== Cicero: chat client", flush=True)
REQUESTS = []
REPLY = {"text": ""}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        REQUESTS.append({"path": self.path, "auth": self.headers.get("Authorization"),
                         "body": json.loads(self.rfile.read(n))})
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for part in (REPLY["text"][:20], REPLY["text"][20:]):
            self.wfile.write(b"data: " + json.dumps({"choices": [{"delta": {"content": part}}]}).encode() + b"\n\n")
        self.wfile.write(b"data: [DONE]\n\n")


srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
endpoint = f"http://127.0.0.1:{srv.server_port}/v1"
settings(f'provider = "openai-compatible"\n\n["openai-compatible"]\nendpoint = "{endpoint}"\nmodel = "m1"\n')
KEYFILE = os.path.join(W, "key")
with open(KEYFILE, "w") as f:
    f.write("sk-home-key\n")
REPLY["text"] = ("Sure.\x1b]52;c;ZXZpbA==\x07\x1b[2J Here:\n```invictus-sys\ninstall firefox\n"
                 "guardrails set libertas\nset-config assistant.full-access on\ninstall foo; rm -rf ~\n"
                 "ai on\ninstall --request=x foo\ninstall fire\u202efox\nremove \u0430pp\n```\n"
                 "Mirrored: \u202eabc\n")


def chat(lines, **extra):
    return subprocess.run([PY, "-I", MON, "chat"], input=lines, capture_output=True, text=True,
                          env=envmap(FAKE_KEY=KEYFILE, INVICTUS_THREAD="t-chat-1", **extra), timeout=30)


reset_logs()
r = chat("hello\n/quit\n")
buttons = [ln.strip() for ln in r.stdout.splitlines() if ln.strip().startswith("[")]
check(r.returncode == 0 and buttons == ["[1] invictus-sys install firefox   (type 1 and Enter to run it)"]
      and not read(f"{LOG}.sys"),
      "A13: a proposal shows as a numbered button and nothing runs; old guard-rails calls, ai, options and "
      "shell tricks are never offered", f"chat buttons {buttons} sys log {read(f'{LOG}.sys')!r} out {r.stdout!r}")
check("\x1b" not in r.stdout and "\x07" not in r.stdout and "\u202e" not in r.stdout,
      "the reply reaches the terminal with no escape sequences or direction overrides (no clipboard or screen tricks, "
      "no button that reads differently from what it runs)", f"escapes in {r.stdout!r}")
req = REQUESTS[-1] if REQUESTS else {}
msgs = req.get("body", {}).get("messages", [])
check(req.get("auth") == "Bearer sk-home-key" and req.get("path") == "/v1/chat/completions"
      and [m["role"] for m in msgs] == ["system", "user"] and msgs[1]["content"] == "hello",
      "A12: the request carries the person's words and the fixed system prompt, nothing else; the key comes from the keyring",
      f"request {req}")

reset_logs()
r = chat("hello\n2\n1\n/quit\n")
check(read(f"{LOG}.sys").strip() == "--request t-chat-1 install firefox" and "Done." in r.stdout,
      "A13: pressing 1 runs exactly `invictus-sys --request <thread> install firefox`; a number with no button runs nothing",
      f"press: {read(f'{LOG}.sys')!r} {r.stdout[-300:]!r}")
reset_logs()
r = chat("hello\n1\n", FAKE_SYS_RC="126")
check("You said no" in r.stdout, "exit 126 from invictus-sys reads as 'You said no; nothing changed.'", f"126: {r.stdout[-200:]!r}")

settings('provider = "openai-compatible"\n\n["openai-compatible"]\nendpoint = "http://example.com/v1"\nmodel = "m1"\n')
n_before = len(REQUESTS)
reset_logs()
r = chat("hello\n/quit\n")
check(r.returncode == 3 and len(REQUESTS) == n_before and not read(f"{LOG}.secret").count("lookup"),
      "an endpoint edited to plain http on the internet is refused before any key is read or sent",
      f"edited endpoint: rc {r.returncode} {r.stdout!r}")
srv.shutdown()

# ---- MCP server ------------------------------------------------------------------------
print("== Cicero: MCP server", flush=True)


def mcp(calls, **extra):
    lines = [json.dumps({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}}),
             json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"})]
    for i, (method, params) in enumerate(calls, 1):
        lines.append(json.dumps({"jsonrpc": "2.0", "id": i, "method": method, "params": params}))
    r = subprocess.run([PY, "-I", MCP], input="\n".join(lines) + "\n", capture_output=True, text=True,
                       env=envmap(**{"INVICTUS_THREAD": "t-mcp-1", **extra}), timeout=30)
    return {m["id"]: m for m in (json.loads(x) for x in r.stdout.splitlines())}


reset_logs()
out = mcp([("tools/list", {})])
names = sorted(t["name"] for t in out.get(1, {}).get("result", {}).get("tools", []))
check(out.get(0, {}).get("result", {}).get("serverInfo", {}).get("name") == "invictus"
      and names == ["acta", "doctor", "package_install", "package_remove", "report_collect", "rollback", "service_set",
                    "snapshot", "update_now"],
      "MCP: initialize, then exactly nine tools; none for AI on/off (SM26)", f"tools {names}")


# Janus P-L1: a server entry with our exact (allowlisted) command can still
# carry `env`. BASH_ENV pointing at a theme file (the one kind of file Cicero
# may write under fixed) made the bash doctor source it. The tools' children
# now get an environment the server builds itself.
PL1 = os.path.join(W, "pl1")
os.makedirs(PL1, exist_ok=True)
marker = os.path.join(PL1, "marker")
payload = os.path.join(PL1, "x.toml")
with open(payload, "w") as f:
    f.write(f"touch {marker}\n")
reset_logs()
mcp([("tools/call", {"name": "doctor", "arguments": {}})], BASH_ENV=payload, ENV=payload)
check(not os.path.exists(marker) and "doctor" in read(f"{LOG}.doctor"),
      "P-L1: the doctor tool runs, and a BASH_ENV/ENV in the server's environment is not sourced (no marker)",
      f"P-L1 BASH_ENV marker: exists={os.path.exists(marker)} doctor log {read(f'{LOG}.doctor')!r}")
subprocess.run([os.path.join(FAKE, "doctor")], env={"BASH_ENV": payload, "PATH": "/usr/bin:/bin", "FAKE_LOG": LOG},
               capture_output=True, timeout=30)
check(os.path.exists(marker), "P-L1 control: the same doctor started with that BASH_ENV does source the file (the proof is real)",
      "P-L1 control: BASH_ENV did not create the marker, so the check above proves nothing")
dump = script("envdump", f'env > "{PL1}/child.env"\n')
planted = {"BASH_ENV": payload, "ENV": payload, "LD_PRELOAD": "/nonexistent-pl1.so", "LD_LIBRARY_PATH": PL1,
           "PYTHONPATH": PL1, "PYTHONSTARTUP": payload, "SHELLOPTS": "xtrace", "BASHOPTS": "extdebug",
           "PERL5OPT": "-d", "NODE_OPTIONS": "--require /x", "GIT_CONFIG_GLOBAL": payload, "XDG_DATA_DIRS": PL1,
           "LANG": "en_US.UTF-8; touch /x", "WAYLAND_DISPLAY": "../../tmp/evil"}
mcp([("tools/call", {"name": "doctor", "arguments": {}})], INVICTUS_DOCTOR=dump, **planted)
child = {}
for line in read(os.path.join(PL1, "child.env")).splitlines():
    if "=" in line:
        k, v = line.split("=", 1)
        child[k] = v
ALLOWED = {"PATH", "LANG", "HOME", "USER", "LOGNAME", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY",
           "HYPRLAND_INSTANCE_SIGNATURE", "INVICTUS_THREAD", "XDG_CONFIG_HOME", "PWD", "SHLVL", "_", "OLDPWD"}
extra = sorted(k for k in child if k not in ALLOWED and not k.startswith(("INVICTUS_", "FAKE_")))
check(child and not extra and child.get("PATH") == "/usr/bin:/bin" and child.get("LANG") == "C.UTF-8"
      and "WAYLAND_DISPLAY" not in child and child.get("INVICTUS_THREAD") == "t-mcp-1",
      "P-L1: a tool's child gets only PATH=/usr/bin:/bin, HOME, USER, LANG (checked), the runtime folder and thread id; "
      "none of BASH_ENV, ENV, LD_*, PYTHON*, SHELLOPTS, BASHOPTS, PERL5OPT, NODE_OPTIONS, GIT_CONFIG_*, XDG_DATA_DIRS",
      f"P-L1 child env: extra {extra}, PATH {child.get('PATH')!r}, LANG {child.get('LANG')!r}, "
      f"WAYLAND_DISPLAY {child.get('WAYLAND_DISPLAY')!r}")
# Janus's P-L1 confirm nit: `.` and `..` are plain names too, but name the
# runtime folder itself or step out of hypr/. Refused like any other path.
os.unlink(os.path.join(PL1, "child.env"))
mcp([("tools/call", {"name": "doctor", "arguments": {}})], INVICTUS_DOCTOR=dump, WAYLAND_DISPLAY="..",
    HYPRLAND_INSTANCE_SIGNATURE=".")
child = dict(ln.split("=", 1) for ln in read(os.path.join(PL1, "child.env")).splitlines() if "=" in ln)
check(child and "WAYLAND_DISPLAY" not in child and "HYPRLAND_INSTANCE_SIGNATURE" not in child,
      "child_env: WAYLAND_DISPLAY='..' and HYPRLAND_INSTANCE_SIGNATURE='.' are not passed to a tool's child",
      f"child_env dot names: WAYLAND_DISPLAY {child.get('WAYLAND_DISPLAY')!r} "
      f"HYPRLAND_INSTANCE_SIGNATURE {child.get('HYPRLAND_INSTANCE_SIGNATURE')!r}")
os.unlink(os.path.join(PL1, "child.env"))
mcp([("tools/call", {"name": "doctor", "arguments": {}})], INVICTUS_DOCTOR=dump, WAYLAND_DISPLAY="wayland-1",
    HYPRLAND_INSTANCE_SIGNATURE="abc_123.x")
child = dict(ln.split("=", 1) for ln in read(os.path.join(PL1, "child.env")).splitlines() if "=" in ln)
check(child.get("WAYLAND_DISPLAY") == "wayland-1" and child.get("HYPRLAND_INSTANCE_SIGNATURE") == "abc_123.x",
      "child_env control: plain socket names are still passed (the doctor's hyprctl checks need them)",
      f"child_env plain names dropped: {child.get('WAYLAND_DISPLAY')!r} {child.get('HYPRLAND_INSTANCE_SIGNATURE')!r}")
# Janus Info: re.match with `$` took "t1\n" as a thread id and passed it to
# invictus-sys --request (which then refused every call). fullmatch refuses
# it and the server makes its own id.
reset_logs()
mcp([("tools/call", {"name": "package_install", "arguments": {"names": ["firefox"]}})], INVICTUS_THREAD="t1\n")
sys_line = read(f"{LOG}.sys").strip()
check(re.fullmatch(r"--request mcp-\d{8}-\d{6}-[0-9a-f]{4} install firefox", sys_line) is not None,
      "INVICTUS_THREAD with a trailing newline is refused; the server makes its own thread id",
      f"INVICTUS_THREAD 't1\\n' reached invictus-sys: {sys_line!r}")
reset_logs()


def text_of(m):
    return "".join(c.get("text", "") for c in m.get("result", {}).get("content", []))


out = mcp([("tools/call", {"name": "package_install", "arguments": {"names": ["firefox", "git"]}}),
           ("tools/call", {"name": "service_set", "arguments": {"unit": "bluetooth.service", "action": "restart"}}),
           ("tools/call", {"name": "snapshot", "arguments": {"description": "before the new theme"}})])
check([ln.strip() for ln in read(f"{LOG}.sys").splitlines()] == ["--request t-mcp-1 install firefox git",
                                          "--request t-mcp-1 service restart bluetooth.service",
                                          "--request t-mcp-1 snapshot before the new theme"]
      and not out[1]["result"]["isError"],
      "MCP: tools call invictus-sys with argv only and the thread id", f"mcp sys log {read(f'{LOG}.sys')!r}")
reset_logs()
out = mcp([("tools/call", {"name": "package_install", "arguments": {"names": ["-Syu"]}}),
           ("tools/call", {"name": "package_install", "arguments": {"names": "firefox; rm -rf ~"}}),
           ("tools/call", {"name": "service_set", "arguments": {"unit": "x", "action": "mask"}}),
           ("tools/call", {"name": "update_now", "arguments": {"command": "rm -rf ~"}}),
           ("tools/call", {"name": "snapshot", "arguments": {"description": "a --for 7d"}}),
           ("tools/call", {"name": "guardrails_set", "arguments": {}}),
           ("tools/call", {"name": "rollback", "arguments": {"id": "1; reboot"}})])
check(not read(f"{LOG}.sys") and all(out[i]["result"]["isError"] for i in range(1, 8)),
      "MCP: options, strings for lists, unknown actions, extra arguments, unknown tools: refused, nothing run",
      f"mcp refusals ran {read(f'{LOG}.sys')!r}")
HS = os.path.join(W, "help-session")
open(HS, "w").close()
out = mcp([("tools/call", {"name": "update_now", "arguments": {}})], INVICTUS_HELP_SESSION=HS)
check(not read(f"{LOG}.sys") and "Support is helping" in text_of(out[1]),
      "SM13: during a help session the action tools wait", f"help session: {text_of(out[1])!r}")
out = mcp([("tools/call", {"name": "acta", "arguments": {"limit": 3}})])
check("install" in text_of(out[1]) and '"INVICTUS_SNAPSHOT": "12"' in text_of(out[1]),
      "MCP: the acta tool returns the Acta entries", f"acta tool {text_of(out[1])!r}")

shutil.rmtree(RUN, ignore_errors=True)
sys.exit(FAILED)
