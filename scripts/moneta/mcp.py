#!/usr/bin/python3 -I
# ------------------------------------------------------------
# The Invictus MCP server (design 4.2, design-simple-mode 4.2): structured
# calls for Claude Code, so Moneta can act with no shell at all (the fixed
# profile denies Bash). Installed as /usr/lib/invictus/moneta/mcp.py by
# invictus-tribune; the Invictus plugin's .mcp.json starts it.
#
# Each tool is a thin client of a command the person could type: invictus-sys
# (its own checks, its polkit prompt, its Acta line), invictus-doctor and
# Acta. No tool takes a command string, a path or a URL; argv lists only, no
# shell. There is no tool for the guard rails, Full access or AI on/off:
# those are the person's choices in Settings (SM26).
#
# Protocol: MCP over stdio, newline-delimited JSON-RPC 2.0.
# Env (tests, honoured only from a checkout): INVICTUS_SYS, INVICTUS_DOCTOR,
#   INVICTUS_HELP_SESSION, INVICTUS_JOURNALCTL.
# ------------------------------------------------------------
import json
import os
import re
import secrets
import subprocess
import sys
import time

def _invictus_env():
    # INVICTUS_* overrides work only from a checkout: scripts/lib/invictus_env.py
    import importlib.util
    here = os.path.realpath(__file__)
    if here.startswith("/usr/"):
        paths = ["/usr/lib/invictus/lib/invictus_env.py"]
    else:  # a checkout, or a test's install tree
        d = os.path.dirname(here)
        paths = [os.path.join(d, *p, "invictus_env.py") for p in
                 (("lib",), ("..", "lib"), ("..", "scripts", "lib"), ("..", "..", "lib"),
                  ("..", "lib", "invictus", "lib"))]
    path = next((p for p in paths if os.path.isfile(p)), None)
    if path is None:
        raise ImportError(f"{os.path.basename(here)}: {paths[0] if here.startswith('/usr/') else 'invictus_env.py'} "
                          "is missing (invictus-sys 0.2.0-4 or later installs it as "
                          "/usr/lib/invictus/lib/invictus_env.py)")
    spec = importlib.util.spec_from_file_location("invictus_env", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.for_script(here)


try:
    env = _invictus_env()
except ImportError as e:  # not a gate: say what is missing and stop
    sys.exit(f"{e}")


INVICTUS_SYS = env("INVICTUS_SYS", "/usr/bin/invictus-sys")
DOCTOR = env("INVICTUS_DOCTOR", "/usr/bin/invictus-doctor")
HELP_SESSION = env("INVICTUS_HELP_SESSION", "/run/invictus/help-session")
JOURNALCTL = env("INVICTUS_JOURNALCTL", "/usr/bin/journalctl")
THREAD = os.environ.get("INVICTUS_THREAD", "")  # not an override
if not re.fullmatch(r"[A-Za-z0-9._:-]{1,64}", THREAD):  # fullmatch: `$` would take "t1\n" (Janus)
    THREAD = time.strftime("mcp-%Y%m%d-%H%M%S-") + secrets.token_hex(2)

OUT_LIMIT = 8192
WORD = re.compile(r"^[A-Za-z0-9@._+:][A-Za-z0-9@._+:/=-]{0,199}$")


def clean(text):
    text = "".join(c if c in "\n\t" or (c >= " " and c != "\x7f") else "?" for c in text)
    return text[-OUT_LIMIT:]


def strings(v, lo=1, hi=64):
    if not isinstance(v, list) or not lo <= len(v) <= hi:
        raise ValueError(f"a list of {lo} to {hi} names")
    for x in v:
        if not isinstance(x, str) or not WORD.match(x):
            raise ValueError(f"'{x}' is not a name")
    return v


def one(v, what):
    if not isinstance(v, str) or not WORD.match(v):
        raise ValueError(f"{what}: letters, digits and @._+:/=-, not starting with -")
    return v


MEANING = {0: "done", 1: "the change failed", 2: "invictus-sys did not accept the arguments",
           3: "refused (guard rails, a protected package, or No AI)", 4: "another change is running",
           126: "the person said no at the password prompt; stop and say so",
           127: "this account is not allowed to do that; stop and say so"}


INSTALLED = os.path.realpath(__file__).startswith("/usr/")
LANG_RE = re.compile(r"[A-Za-z]{1,8}(_[A-Za-z]{2,3})?(\.[A-Za-z0-9-]{1,16})?(@[A-Za-z]{1,16})?")
SOCKET_RE = re.compile(r"[A-Za-z0-9._-]{1,128}")


def socket_name(name):
    """A plain file name in the runtime folder: no slash, and not `.` or `..` (Janus)."""
    return name if SOCKET_RE.fullmatch(name) and name not in (".", "..") else ""


def child_env():
    """The whole environment of every program a tool runs (Janus P-L1).

    Built here, never inherited: this server's own environment comes from
    whatever server entry started it, and an entry with our exact command can
    still carry `env` (the managed allowlist does not compare it). BASH_ENV
    would make the bash doctor source any file; ENV, LD_*, PYTHON*, SHELLOPTS
    and the rest are left out the same way. Names below are fixed; values are
    computed (HOME, USER and the runtime folder from the uid) or checked
    against a narrow pattern. A checkout (the tests) also passes INVICTUS_*
    and FAKE_* for the fakes, and the test HOME and runtime folder.
    """
    uid = os.getuid()
    e = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}
    try:
        import pwd
        pw = pwd.getpwuid(uid)
        e.update(HOME=pw.pw_dir, USER=pw.pw_name, LOGNAME=pw.pw_name)
    except (ImportError, KeyError):
        e["HOME"] = "/"
    lang = os.environ.get("LANG", "")
    if LANG_RE.fullmatch(lang):
        e["LANG"] = lang
    rundir = f"/run/user/{uid}"
    if os.path.isdir(rundir):
        e["XDG_RUNTIME_DIR"] = rundir
        e["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={rundir}/bus"
    wl = socket_name(os.environ.get("WAYLAND_DISPLAY", ""))
    if wl:
        e["WAYLAND_DISPLAY"] = wl
    his = socket_name(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""))
    if his:
        e["HYPRLAND_INSTANCE_SIGNATURE"] = his
    e["INVICTUS_THREAD"] = THREAD  # checked above
    if not INSTALLED:  # a checkout: the tests' fakes and overrides; never an installed copy
        e.update({k: v for k, v in os.environ.items()  # not an override (checkout only)
                  if k.startswith(("INVICTUS_", "FAKE_")) or k in ("HOME", "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME")})
    return e


def run(argv, timeout):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL,
                           env=child_env())
    except subprocess.TimeoutExpired:
        return "timed out", True
    except OSError as e:
        return f"could not run {argv[0]}: {e}", True
    out = clean((p.stdout or "") + (p.stderr or ""))
    return f"exit {p.returncode}: {MEANING.get(p.returncode, '')}\n{out}".rstrip(), p.returncode != 0


def sys_verb(*args):
    if os.path.exists(HELP_SESSION):
        return "Support is helping on this computer right now; I'll wait until they are done.", True
    return run([INVICTUS_SYS, "--request", THREAD, *args], 3600)


def acta(limit=10):
    n = limit if isinstance(limit, int) and 1 <= limit <= 200 else 10
    text, err = run([JOURNALCTL, "-t", "invictus-sys", "-o", "json", "-n", str(n), "--no-pager"], 30)
    if err:
        return "Acta is in the system log, which only an administrator account can read.", True
    rows = []
    for line in text.splitlines()[1:]:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        rows.append({k: e.get(k, "") for k in ("__REALTIME_TIMESTAMP", "INVICTUS_VERB", "INVICTUS_ARGS",
                                               "INVICTUS_RESULT", "INVICTUS_SNAPSHOT", "INVICTUS_REQUEST")})
    return json.dumps(rows), False


SERVICE_ACTIONS = ("enable", "disable", "restart")

TOOLS = {
    "doctor": ("Read-only health checks of this computer (ok/note/warn/FAIL lines). Run it before you guess.",
               {}, lambda a: run([DOCTOR], 120)),
    "acta": ("The last invictus-sys calls: what changed, when, the snapshot to undo it.",
             {"limit": {"type": "integer", "minimum": 1, "maximum": 200}}, lambda a: acta(a.get("limit", 10))),
    "update_now": ("Update everything (pacman -Syu through invictus-sys). The person may be asked for their password.",
                   {}, lambda a: sys_verb("update")),
    "snapshot": ("Make a safety copy of the system now.",
                 {"description": {"type": "string", "maxLength": 200}},
                 lambda a: sys_verb("snapshot", *_description(a))),
    "package_install": ("Install packages from the configured repositories (never the AUR). Password prompt.",
                        {"names": {"type": "array", "items": {"type": "string"}, "minItems": 1, "maxItems": 64}},
                        lambda a: sys_verb("install", *strings(a.get("names")))),
    "package_remove": ("Remove packages; refuses the ones that keep the computer working. Password prompt.",
                       {"names": {"type": "array", "items": {"type": "string"}, "minItems": 1, "maxItems": 64}},
                       lambda a: sys_verb("remove", *strings(a.get("names")))),
    "service_set": ("Enable, disable or restart a service from the short allowed list. Password prompt.",
                    {"unit": {"type": "string"}, "action": {"type": "string", "enum": list(SERVICE_ACTIONS)}},
                    lambda a: sys_verb("service", _service_action(a), one(a.get("unit"), "unit"))),
    "rollback": ("Put the system back to safety copy ID (it says how to finish in the boot menu). Password prompt.",
                 {"id": {"type": "string", "pattern": "^[0-9]{1,9}$"}},
                 lambda a: sys_verb("rollback", _snap_id(a))),
    "report_collect": ("Collect this boot's error log for a problem report (nothing is sent).",
                       {}, lambda a: sys_verb("report-collect")),
}
REQUIRED = {"package_install": ["names"], "package_remove": ["names"], "service_set": ["unit", "action"],
            "rollback": ["id"], "snapshot": ["description"]}


def _description(a):
    d = a.get("description")
    if not isinstance(d, str) or not d.strip() or len(d) > 200 or d.startswith("-"):
        raise ValueError("a short description, not starting with -")
    if any(c < " " for c in d) or any(w.startswith("-") for w in d.split()):
        raise ValueError("one line of plain text, no word starting with -")
    return d.split()


def _service_action(a):
    if a.get("action") not in SERVICE_ACTIONS:
        raise ValueError("action is enable, disable or restart")
    return a["action"]


def _snap_id(a):
    v = a.get("id")
    if not isinstance(v, str) or not re.match(r"^[0-9]{1,9}$", v):
        raise ValueError("a snapshot number")
    return v


def tool_list():
    return [{"name": n, "description": d,
             "inputSchema": {"type": "object", "properties": props, "required": REQUIRED.get(n, []),
                             "additionalProperties": False}}
            for n, (d, props, _) in TOOLS.items()]


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if method == "initialize":
        ver = (msg.get("params") or {}).get("protocolVersion") or "2025-06-18"
        return {"protocolVersion": ver, "capabilities": {"tools": {}},
                "serverInfo": {"name": "invictus", "version": "0.2.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": tool_list()}
    if method == "tools/call":
        params = msg.get("params") or {}
        name, args = params.get("name"), params.get("arguments") or {}
        if name not in TOOLS or not isinstance(args, dict):
            return {"content": [{"type": "text", "text": f"no tool called {name}"}], "isError": True}
        props = TOOLS[name][1]
        extra = set(args) - set(props)
        if extra:
            return {"content": [{"type": "text", "text": f"unknown arguments: {sorted(extra)}"}], "isError": True}
        try:
            text, err = TOOLS[name][2](args)
        except ValueError as e:
            text, err = f"not run: {e}", True
        return {"content": [{"type": "text", "text": text}], "isError": err}
    if mid is None:
        return None  # a notification
    raise LookupError(method)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
            if not isinstance(msg, dict):
                raise ValueError
        except ValueError:
            reply = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}
        else:
            mid = msg.get("id")
            try:
                result = handle(msg)
                if mid is None:
                    continue
                reply = {"jsonrpc": "2.0", "id": mid, "result": result}
            except LookupError:
                reply = {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "method not found"}}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
