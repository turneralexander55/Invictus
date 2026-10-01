#!/usr/bin/python3 -I
# ------------------------------------------------------------
# The Moneta panel (code name tribune) and its provider layer (design 4.2).
# Installed as /usr/lib/invictus/moneta/moneta.py by invictus-tribune, with
# two names in /usr/bin pointing at it:
#
#   invictus-provider ...   choose and set up who answers (Settings, the
#                           first-start wizard); contract: docs/moneta-panel.md
#   tribune [run]           the panel itself, inside the dropdown kitty that
#                           Super+A opens (config/hypr/invictus/moneta.lua)
#   tribune chat            the chat client for api providers (the panel
#                           starts it; chat only, it proposes and you press)
#   tribune acta [-n N]     the last invictus-sys calls (Acta)
#
# Security (design 4.1, 4.7 T7 and T11, design-simple-mode 12.3):
#   * Whether a provider may run is decided from root-owned state only
#     (`guardrails status`: rails, full access, AI), never from the person's
#     own config, which an agent can edit. Unreadable state means nothing runs.
#   * Only the shipped claude-code provider runs a command without Full
#     access. generic-cli and every provider defined in a home directory
#     (kind cli) are "a command-line agent": Libertas and Full access on.
#   * A provider in a home directory never replaces a shipped one.
#   * api providers run nothing: proposed invictus-sys calls become numbered
#     buttons, and only the person's key press runs one (no shell).
#   * Keys live in the keyring (secret-tool), under the namespace
#     invictus/provider, tied to the endpoint they were typed for.
#
# Env (tests): INVICTUS_GUARDRAILS, INVICTUS_PROVIDERS_DIR, INVICTUS_SYS,
#   INVICTUS_SECRET_TOOL, INVICTUS_JOURNALCTL, TRIBUNE_GRACE. Honoured only
#   when run from a checkout; the installed copy (/usr/...) ignores them.
# ------------------------------------------------------------
import ipaddress
import json
import os
import re
import secrets
import select
import shlex
import signal
import socket
import stat
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request

INSTALLED = os.path.realpath(__file__).startswith("/usr/")


def env(name, default):
    if INSTALLED:
        return default
    return os.environ.get(name, default)


GUARDRAILS = env("INVICTUS_GUARDRAILS", "/usr/lib/invictus/guardrails")
SYSTEM_PROVIDERS = env("INVICTUS_PROVIDERS_DIR", "/usr/share/invictus/providers")
INVICTUS_SYS = env("INVICTUS_SYS", "/usr/bin/invictus-sys")
SECRET_TOOL = env("INVICTUS_SECRET_TOOL", "/usr/bin/secret-tool")
JOURNALCTL = env("INVICTUS_JOURNALCTL", "/usr/bin/journalctl")
GRACE = float(env("TRIBUNE_GRACE", "5"))

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
KEY_NAMESPACE = "invictus/provider"   # design-no-ai.md N4: ai off clears it
CLI_OFF = "Moneta's command-line agent is off. Pick who answers in Settings > Moneta."
AI_OFF = "AI is off on this computer. Settings > AI turns it on."
NO_STATE = "Moneta cannot read the guard-rails state, so it does not start. Run invictus-doctor."

EXIT_OK, EXIT_FAILED, EXIT_BAD, EXIT_REFUSED = 0, 1, 2, 3


class Refused(Exception):
    pass


class BadArgs(Exception):
    pass


def home():
    import pwd
    return pwd.getpwuid(os.getuid()).pw_dir


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home(), ".config")
    return os.path.join(base, "invictus")


def runtime_dir():
    d = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(d, "invictus")


def clean(text, keep_newlines=True):
    """Text from a model, a log or a command, made safe for a terminal: no
    escape sequences or other control bytes (a reply could otherwise set the
    window title, write the clipboard or talk to the terminal)."""
    allowed = "\n\t" if keep_newlines else "\t"
    return "".join(c if (c >= " " and c != "\x7f" and not 0x80 <= ord(c) < 0xa0 and c not in BIDI) or c in allowed
                   else "?" for c in text)


def ext(value):
    """Every piece of text from outside this file that goes to a terminal
    (a provider's label or model, an error naming a path or argument, a
    model's reply) goes through here: one line, no control bytes, no
    direction overrides. Group 17 greps the prints for it (Janus L1)."""
    return clean(str(value), keep_newlines=False)


# Direction overrides and isolates: they can make a line read differently
# from what it holds (a button that shows one command and runs another).
BIDI = set("\u061c\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069")


# ---- root-owned state -------------------------------------------------------------

def machine_state():
    """rails, full access and AI from `guardrails status` (root-owned files).
    Any failure returns None: callers refuse to start anything but none."""
    try:
        out = subprocess.run([GUARDRAILS, "status"], capture_output=True, text=True,
                             timeout=10, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    kv = {}
    for line in out.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            kv[k.strip()] = v.strip()
    rails = kv.get("effective") or kv.get("rails")
    if rails not in ("custodia", "libertas"):
        return None
    return {"rails": rails, "full_access": kv.get("full-access") == "on", "ai": kv.get("ai") == "on"}


# ---- providers -------------------------------------------------------------------

def _load_toml(path):
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_size > 64 * 1024:
        raise ValueError("not a small regular file")
    with open(path, "rb") as f:
        return tomllib.load(f)


def _str_list(v):
    return isinstance(v, list) and all(isinstance(x, str) and x and "\0" not in x for x in v)


def _provider_from(data, name, source):
    kind = data.get("kind")
    if data.get("name", name) != name or kind not in ("cli", "api", "none"):
        return None
    p = {"name": name, "kind": kind, "source": source,
         "label": str(data.get("label", name))[:80],
         "user_command": bool(data.get("user_command", False)) if source == "system" else False}
    if kind == "cli":
        chat = data.get("chat", [])
        if not _str_list(chat):
            return None
        p["chat"] = chat
        p["harness"] = str(data.get("harness", "agents-md"))
    if kind == "api":
        for k in ("endpoint", "model"):
            if isinstance(data.get(k), str):
                p[k] = data[k]
    return p


def providers():
    """Shipped providers first; a home provider with a shipped name is ignored."""
    found = {}
    for source, base in (("system", SYSTEM_PROVIDERS), ("user", os.path.join(config_dir(), "providers"))):
        try:
            names = sorted(os.listdir(base))
        except OSError:
            continue
        for name in names:
            if not NAME_RE.match(name) or name in found:
                continue
            try:
                data = _load_toml(os.path.join(base, name, "provider.toml"))
            except (OSError, ValueError, tomllib.TOMLDecodeError):
                continue
            p = _provider_from(data, name, source)
            if p:
                found[name] = p
    return found


def settings_path():
    return os.path.join(config_dir(), "moneta.toml")


def read_settings():
    try:
        return _load_toml(settings_path())
    except (OSError, ValueError, tomllib.TOMLDecodeError):
        return {}


def _toml_str(s):
    return json.dumps(s, ensure_ascii=True)


def write_settings(data):
    lines = ["# Written by invictus-provider (Settings > Moneta). Who answers in the Moneta panel."]
    if "provider" in data:
        lines.append(f"provider = {_toml_str(data['provider'])}")
    for section in sorted(k for k, v in data.items() if isinstance(v, dict)):
        lines.append("")
        lines.append(f"[{_toml_str(section)}]")
        for k, v in sorted(data[section].items()):
            if isinstance(v, list):
                lines.append(f"{k} = [{', '.join(_toml_str(x) for x in v)}]")
            else:
                lines.append(f"{k} = {_toml_str(str(v))}")
    d = config_dir()
    os.makedirs(d, mode=0o700, exist_ok=True)
    tmp = os.path.join(d, f".moneta.toml.{secrets.token_hex(4)}")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, settings_path())


def resolved(p, settings=None):
    """The provider with the person's own values filled in (generic-cli's
    command, an api provider's endpoint and model)."""
    p = dict(p)
    own = (settings if settings is not None else read_settings()).get(p["name"], {})
    if not isinstance(own, dict):
        own = {}
    if p["kind"] == "cli" and p["user_command"]:
        p["chat"] = own.get("chat", []) if _str_list(own.get("chat", [])) else []
    if p["kind"] == "api":
        for k in ("endpoint", "model"):
            if isinstance(own.get(k), str):
                p[k] = own[k]
    return p


def is_command_agent(p):
    """A cli provider whose command is not fixed by a shipped file: generic-cli
    and anything defined in a home (design-simple-mode 12.3, SM10, SM26)."""
    return p["kind"] == "cli" and (p["source"] != "system" or p["user_command"])


def permitted(p, state):
    """(True, "") or (False, why). Root-owned state only."""
    if p["kind"] == "none":
        return True, ""
    if state is None:
        return False, NO_STATE
    if not state["ai"]:
        return False, AI_OFF
    if is_command_agent(p) and not (state["rails"] == "libertas" and state["full_access"]):
        return False, CLI_OFF
    return True, ""


def offered(p, state):
    """What Settings and the wizard may list (SM10: no command-line agent
    under Custodia; none is No AI, which Settings shows as its own card)."""
    return permitted(p, state)[0]


def selected():
    s = read_settings()
    name = s.get("provider", "claude-code")
    all_p = providers()
    p = all_p.get(name) if isinstance(name, str) else None
    if p is None:
        p = all_p.get("none", {"name": "none", "kind": "none", "source": "system", "label": "No assistant", "user_command": False})
    return resolved(p, s)


# ---- endpoints and keys ---------------------------------------------------------------

LOCAL_SUFFIXES = (".local", ".lan", ".home.arpa", ".internal")


def check_endpoint(url):
    """https anywhere; plain http only to this computer or the home network
    (a home AI system), so a key never crosses the internet in clear text."""
    u = urllib.parse.urlsplit(url)
    if u.scheme not in ("http", "https") or not u.hostname or u.username or u.password:
        raise BadArgs("the endpoint must be an http(s) URL with no user name in it")
    if u.scheme == "https":
        return url.rstrip("/")
    host = u.hostname
    if host == "localhost" or host.endswith(LOCAL_SUFFIXES):
        return url.rstrip("/")
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        raise BadArgs("plain http is only for this computer or your home network; use https") from None
    if ip.is_loopback or ip.is_private or ip.is_link_local:
        return url.rstrip("/")
    raise BadArgs("plain http is only for this computer or your home network; use https")


def key_attrs(name, endpoint):
    return ["invictus-namespace", KEY_NAMESPACE, "provider", name, "endpoint", endpoint]


def key_lookup(name, endpoint):
    try:
        out = subprocess.run([SECRET_TOOL, "lookup", *key_attrs(name, endpoint)],
                             capture_output=True, text=True, timeout=15, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout.rstrip("\n") if out.returncode == 0 and out.stdout else None


# ---- invictus-provider ------------------------------------------------------------------

def provider_cli(argv):
    try:
        return _provider_cli(argv)
    except BadArgs as e:
        print(f"invictus-provider: {ext(e)}", file=sys.stderr)
        return EXIT_BAD
    except Refused as e:
        print(f"invictus-provider: {ext(e)}", file=sys.stderr)
        return EXIT_REFUSED


def _provider_cli(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(PROVIDER_HELP)
        return EXIT_OK
    cmd, rest = argv[0], argv[1:]
    state = machine_state()
    if cmd == "list":
        cur = read_settings().get("provider", "claude-code")
        rows = []
        for p in providers().values():
            rows.append({"name": p["name"], "kind": p["kind"], "label": p["label"], "source": p["source"],
                         "command_agent": is_command_agent(p), "offered": offered(p, state),
                         "selected": p["name"] == cur})
        if rest == ["--json"]:
            print(json.dumps(rows))
        elif rest:
            raise BadArgs("list takes only --json")
        else:
            for r in rows:
                if r["offered"]:
                    print(f"{'*' if r['selected'] else ' '} {r['name']:<20} {r['kind']:<4} {ext(r['label'])}")
        return EXIT_OK
    if cmd in ("get", "check"):
        p = selected()
        ok, why = permitted(p, state)
        if cmd == "get":
            info = {"name": p["name"], "kind": p["kind"], "label": p["label"], "permitted": ok, "why": why}
            if p["kind"] == "api":
                info.update({"endpoint": p.get("endpoint", ""), "model": p.get("model", "")})
            print(json.dumps(info) if rest == ["--json"] else "\n".join(f"{k}={ext(v)}" for k, v in info.items()))
            return EXIT_OK
        if not ok:
            print(why)
            return EXIT_REFUSED
        return EXIT_OK
    if cmd == "set":
        return _provider_set(rest, state)
    if cmd == "key":
        return _provider_key(rest)
    raise BadArgs(f"unknown command '{cmd}' (list, get, check, set, key)")


def _provider_set(rest, state):
    if not rest:
        raise BadArgs("set NAME [--endpoint URL] [--model M] [--command -- ARG...]")
    name, rest = rest[0], rest[1:]
    all_p = providers()
    if name not in all_p:
        raise BadArgs(f"no provider called '{name}' (invictus-provider list)")
    p = all_p[name]
    if not offered(p, state):
        raise Refused(permitted(p, state)[1])
    s = read_settings()
    own = dict(s.get(name, {})) if isinstance(s.get(name), dict) else {}
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--endpoint" and i + 1 < len(rest) and p["kind"] == "api":
            own["endpoint"] = check_endpoint(rest[i + 1]); i += 2
        elif a == "--model" and i + 1 < len(rest) and p["kind"] == "api":
            m = rest[i + 1]
            if not re.match(r"^[A-Za-z0-9._:/@+-]{1,128}$", m):
                raise BadArgs("model names are letters, digits and ._:/@+-")
            own["model"] = m; i += 2
        elif a == "--command" and p["kind"] == "cli" and p["user_command"]:
            cmdv = rest[i + 1:]
            if cmdv[:1] == ["--"]:
                cmdv = cmdv[1:]
            if not _str_list(cmdv) or not cmdv or len(cmdv) > 64:
                raise BadArgs("--command needs the program and its arguments")
            own["chat"] = cmdv; i = len(rest)
        else:
            raise BadArgs(f"'{a}' does not apply to {name}")
    if p["kind"] == "api" and "endpoint" not in own and "endpoint" not in p:
        raise BadArgs(f"{name} needs --endpoint URL")
    if p["kind"] == "cli" and p["user_command"] and not own.get("chat"):
        raise BadArgs(f"{name} needs --command -- PROGRAM ARGS")
    s["provider"] = name
    if own:
        s[name] = own
    write_settings(s)
    print(f"Moneta now answers with {ext(p['label'])}.")
    return EXIT_OK


def _provider_key(rest):
    if len(rest) >= 1 and rest[0] == "clear":
        names = rest[1:2]
        attrs = ["invictus-namespace", KEY_NAMESPACE] + (["provider", names[0]] if names else [])
        subprocess.run([SECRET_TOOL, "clear", *attrs], stdin=subprocess.DEVNULL, check=False)
        return EXIT_OK
    if len(rest) != 2 or rest[0] != "set":
        raise BadArgs("key set NAME (the key on stdin) | key clear [NAME]")
    name = rest[1]
    all_p = providers()
    if name not in all_p or all_p[name]["kind"] != "api":
        raise BadArgs(f"'{name}' is not an api provider")
    p = resolved(all_p[name])
    endpoint = p.get("endpoint")
    if not endpoint:
        raise BadArgs(f"set the endpoint first: invictus-provider set {name} --endpoint URL")
    key = sys.stdin.readline().strip()
    if not key or len(key) > 4096 or any(c < " " for c in key):
        raise BadArgs("the key goes on stdin, one line")
    # The key travels on secret-tool's stdin, never on a command line.
    r = subprocess.run([SECRET_TOOL, "store", f"--label=Moneta: {p['label']} key", *key_attrs(name, endpoint)],
                       input=key, text=True, check=False)
    if r.returncode != 0:
        print("invictus-provider: the keyring did not take the key (is it unlocked?)", file=sys.stderr)
        return EXIT_FAILED
    return EXIT_OK


PROVIDER_HELP = """invictus-provider: who answers in the Moneta panel (docs/moneta-panel.md)
  list [--json]                         the providers you may pick now
  get [--json]                          the one picked, and whether it may run
  check                                 exit 0 if it may run, 3 and why if not
  set NAME [--endpoint URL] [--model M] [--command -- PROGRAM ARGS...]
  key set NAME                          the API key, one line on stdin, to the keyring
  key clear [NAME]                      forget the keys (all Moneta keys without NAME)
Exit: 0 done, 1 failed, 2 bad arguments, 3 refused (guard rails, Full access, No AI)."""


# ---- Acta --------------------------------------------------------------------------------

def acta_lines(n=20):
    try:
        out = subprocess.run([JOURNALCTL, "-t", "invictus-sys", "-o", "json", "-n", str(int(n)), "--no-pager"],
                             capture_output=True, text=True, timeout=15, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    rows = []
    for line in out.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if not isinstance(e, dict) or "INVICTUS_VERB" not in e:
            continue
        try:
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(int(e.get("__REALTIME_TIMESTAMP", "0")) / 1e6))
        except (TypeError, ValueError):
            when = "?"
        parts = [when, e.get("INVICTUS_VERB", ""), e.get("INVICTUS_ARGS", ""), e.get("INVICTUS_RESULT", ""),
                 f"snapshot={e.get('INVICTUS_SNAPSHOT', 'none') or 'none'}"]
        if e.get("INVICTUS_USER"):
            parts.append(f"by {e['INVICTUS_USER']}")
        if e.get("INVICTUS_REQUEST"):
            parts.append(f"thread {e['INVICTUS_REQUEST']}")
        rows.append(clean("  ".join(str(x) for x in parts if x), keep_newlines=False))
    return rows


def acta_cli(argv):
    n = 20
    if argv[:1] == ["-n"] and len(argv) == 2 and argv[1].isdigit():
        n = min(int(argv[1]), 500)
    elif argv:
        print("tribune acta [-n N]", file=sys.stderr)
        return EXIT_BAD
    rows = acta_lines(n)
    if rows is None:
        print("Acta is in the system log, which only an administrator account can read.")
        return EXIT_FAILED
    print("Acta: what invictus-sys changed, newest last")
    print("\n".join(ext(r) for r in rows) if rows else "(nothing yet)")
    return EXIT_OK


# ---- the chat client (api providers) -----------------------------------------------------

# What a model may propose. The person presses a number to run one through
# invictus-sys and its password prompt; nothing runs on its own (MUST A13).
# Guard rails, Full access and AI on/off are the person's choices in Settings.
PROPOSABLE = {"update", "install", "remove", "snapshot", "rollback", "service", "set-config", "report-collect"}
SETTABLE = re.compile(r"^(nets\.[a-z-]+|flavor\.lock)$")

SYSTEM_PROMPT = """You are Moneta, the assistant on this Invictus computer. You cannot run anything yourself.
When a change to the system would help, propose it as invictus-sys calls in a fenced block, one per line:
```invictus-sys
install firefox
```
Verbs: update; install PKG...; remove PKG...; snapshot DESCRIPTION; rollback ID;
service enable|disable|restart UNIT; set-config nets.KEY on|off; report-collect.
Say in one plain sentence what each call changes and how to undo it. The person presses a button to run it,
and the system asks for their password. Never suggest sudo, pacman, makepkg or editing files under /etc or /usr."""

FENCE = re.compile(r"```invictus-sys[ \t]*\n(.*?)```", re.S)


def proposals(reply):
    """argv lists (without the invictus-sys word) for each acceptable line."""
    out = []
    for block in FENCE.findall(reply):
        for line in block.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                argv = shlex.split(line, comments=False, posix=True)
            except ValueError:
                continue
            if argv[:1] == ["invictus-sys"]:
                argv = argv[1:]
            if valid_proposal(argv):
                out.append(argv)
    return out[:9]


def valid_proposal(argv):
    if not argv or argv[0] not in PROPOSABLE or len(argv) > 65:
        return False
    for a in argv:
        # ASCII only: what the button shows is exactly what runs.
        if not a or len(a) > 200 or a.startswith("-") or not a.isascii() or not a.isprintable():
            return False
    if argv[0] == "set-config" and (len(argv) != 3 or not SETTABLE.match(argv[1]) or argv[2] not in ("on", "off")):
        return False
    return True


def stream_reply(p, key, messages):
    body = json.dumps({"model": p.get("model", ""), "messages": messages, "stream": True}).encode()
    req = urllib.request.Request(p["endpoint"] + "/chat/completions", data=body, method="POST",
                                 headers={"Content-Type": "application/json", "Accept": "text/event-stream"})
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    text = []
    with urllib.request.urlopen(req, timeout=180) as resp:
        ctype = resp.headers.get("Content-Type", "")
        if "text/event-stream" not in ctype:
            data = json.loads(resp.read(4 * 1024 * 1024))
            piece = data["choices"][0]["message"]["content"] or ""
            sys.stdout.write(clean(piece)); sys.stdout.flush()
            return piece
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                delta = json.loads(payload)["choices"][0].get("delta", {}).get("content") or ""
            except (ValueError, KeyError, IndexError, TypeError):
                continue
            text.append(delta)
            sys.stdout.write(clean(delta)); sys.stdout.flush()
    return "".join(text)


def run_proposal(argv, thread):
    print(f"\nRunning: invictus-sys {' '.join(shlex.quote(a) for a in argv)}")
    try:
        rc = subprocess.run([INVICTUS_SYS, "--request", thread, *argv], check=False).returncode
    except OSError as e:
        print(f"Could not run invictus-sys: {ext(e)}")
        return 127
    meaning = {0: "Done.", 1: "It did not work; the message above says why.", 2: "invictus-sys did not accept that.",
               3: "Refused by the guard rails or because it protects the system.", 4: "Another change is running; try again shortly.",
               126: "You said no; nothing changed.", 127: "This account is not allowed to do that."}
    print(meaning.get(rc, f"Finished with code {rc}."))
    return rc


def chat_cli(argv):
    p = selected()
    ok, why = permitted(p, machine_state())
    if p["kind"] != "api" or not ok:
        print(why or "The chosen provider is not a chat service.")
        return EXIT_REFUSED
    if not p.get("endpoint"):
        print("No endpoint is set. Settings > Moneta, or: invictus-provider set NAME --endpoint URL")
        return EXIT_REFUSED
    try:
        check_endpoint(p["endpoint"])
    except BadArgs as e:
        print(f"Moneta will not use this endpoint: {ext(e)}")
        return EXIT_REFUSED
    key = key_lookup(p["name"], p["endpoint"])
    thread = os.environ.get("INVICTUS_THREAD", "")
    if not re.match(r"^[A-Za-z0-9._:-]{1,64}$", thread):
        thread = new_thread_id()
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    buttons = []
    print(f"Moneta, through {ext(p['label'])} ({ext(p.get('model', ''))}). Chat only: it can propose, you decide.")
    print("Type and press Enter. A number runs a proposed action. /quit ends.\n")
    while True:
        try:
            line = input("You: ")
        except EOFError:
            return EXIT_OK
        line = line.strip()
        if not line:
            continue
        if line in ("/quit", "/exit"):
            return EXIT_OK
        if line.isdigit() and buttons:
            i = int(line) - 1
            if 0 <= i < len(buttons):
                argv = buttons[i]
                rc = run_proposal(argv, thread)
                messages.append({"role": "user", "content": f"[I ran: invictus-sys {' '.join(argv)}; exit {rc}]"})
                buttons = []
                continue
        messages.append({"role": "user", "content": line})
        sys.stdout.write("Moneta: "); sys.stdout.flush()
        try:
            reply = stream_reply(p, key, messages)
        except (urllib.error.URLError, OSError, ValueError, KeyError, IndexError, TypeError) as e:
            print(f"\n(no answer: {ext(e)[:200]})")
            messages.pop()
            continue
        print()
        messages.append({"role": "assistant", "content": reply})
        buttons = proposals(reply)
        for n, argv in enumerate(buttons, 1):
            print(f"  [{n}] invictus-sys {' '.join(shlex.quote(a) for a in argv)}   (type {n} and Enter to run it)")


# ---- the panel ---------------------------------------------------------------------------

def new_thread_id():
    return time.strftime("t-%Y%m%d-%H%M%S-") + secrets.token_hex(2)


def _prctl_subreaper():
    try:
        import ctypes
        ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0)  # PR_SET_CHILD_SUBREAPER
    except (OSError, AttributeError):
        pass


def descendants(root_pid):
    kids = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open(f"/proc/{d}/stat") as f:
                ppid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        kids.setdefault(ppid, []).append(int(d))
    out, todo = [], [root_pid]
    while todo:
        for c in kids.get(todo.pop(), []):
            out.append(c)
            todo.append(c)
    return out


class Panel:
    def __init__(self):
        self.child = None
        self.sock = None
        self.sock_ino = None
        self.tty = sys.stdin.isatty()

    # The socket invictus-sys and the guard rails talk to (docs/invictus-sys.md).
    def listen(self):
        d = runtime_dir()
        os.makedirs(d, mode=0o700, exist_ok=True)
        st = os.lstat(d)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
            raise SystemExit(f"tribune: {d} is not a folder of yours; not listening there")
        os.chmod(d, 0o700)
        path = os.path.join(d, "tribune.sock")
        if os.path.lexists(path):
            probe = socket.socket(socket.AF_UNIX)
            try:
                probe.settimeout(1)
                probe.connect(path)
                probe.close()
                print("Moneta is already open in another window.")
                raise SystemExit(EXIT_REFUSED)
            except OSError:
                os.unlink(path)
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        old = os.umask(0o177)
        try:
            s.bind(path)
        finally:
            os.umask(old)
        s.listen(4)
        self.sock, self.sock_path, self.sock_ino = s, path, os.stat(path).st_ino

    def close(self):
        if self.sock:
            self.sock.close()
            try:
                if os.stat(self.sock_path).st_ino == self.sock_ino:
                    os.unlink(self.sock_path)
            except OSError:
                pass

    def read_message(self):
        conn, _ = self.sock.accept()
        try:
            uid = None
            try:
                import struct
                cred = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
                uid = struct.unpack("3i", cred)[1]
            except OSError:
                pass
            if uid not in (0, os.getuid()):
                return None
            conn.settimeout(1)
            data = b""
            while b"\n" not in data and len(data) < 64:
                chunk = conn.recv(64)
                if not chunk:
                    break
                data += chunk
        except OSError:
            return None
        finally:
            conn.close()
        msg = data.split(b"\n", 1)[0].decode("ascii", "replace")
        return msg if msg in ("stop", "restart-profile") else None

    # ---- the agent process ----
    def start(self):
        p = selected()
        ok, why = permitted(p, machine_state())
        if not ok:
            print(why)
            return False
        if p["kind"] == "none":
            print("No assistant is set up. Pick one in Settings > Moneta.")
            return False
        if p["kind"] == "cli":
            argv = p.get("chat") or []
            if not argv:
                print("No command is set for this agent. Settings > Moneta.")
                return False
        else:
            argv = [sys.executable, "-I", os.path.realpath(__file__), "chat"]
        thread = new_thread_id()
        child_env = dict(os.environ, INVICTUS_THREAD=thread, INVICTUS_PROVIDER=p["name"])
        tty = self.tty

        def pre():
            os.setpgid(0, 0)
            if tty:
                signal.signal(signal.SIGTTOU, signal.SIG_IGN)
                try:
                    os.tcsetpgrp(0, os.getpgrp())
                except OSError:
                    pass
                signal.signal(signal.SIGTTOU, signal.SIG_DFL)
        try:
            self.child = subprocess.Popen(argv, env=child_env, preexec_fn=pre, close_fds=True)
        except OSError as e:
            print(f"Could not start {ext(p['label'])}: {ext(e)}")
            self.child = None
            return False
        print(f"[tribune] started {p['name']} pid={self.child.pid} thread={thread}", flush=True)
        return True

    def take_terminal(self):
        if self.tty:
            try:
                os.tcsetpgrp(0, os.getpgrp())
            except OSError:
                pass

    def stop_agent(self):
        """SIGTERM to the agent's process group and every process it left
        behind, SIGKILL after the grace time (design-simple-mode G7)."""
        me = os.getpid()
        pgid = None
        if self.child and self.child.poll() is None:
            try:
                pgid = os.getpgid(self.child.pid)
            except OSError:
                pgid = None

        def hit(sig):
            if pgid:
                try:
                    os.killpg(pgid, sig)
                except OSError:
                    pass
            for pid in descendants(me):
                try:
                    os.kill(pid, sig)
                except OSError:
                    pass
        hit(signal.SIGTERM)
        end = time.monotonic() + GRACE
        while time.monotonic() < end:
            self.reap()
            if not descendants(me):
                break
            time.sleep(0.05)
        if descendants(me):
            hit(signal.SIGKILL)
            time.sleep(0.1)
        self.reap()
        self.child = None
        self.take_terminal()

    def reap(self):
        while True:
            try:
                pid, _ = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                return
            if pid == 0:
                return

    def run(self):
        _prctl_subreaper()
        signal.signal(signal.SIGTTOU, signal.SIG_IGN)
        def bye(*_):
            raise SystemExit(0)
        for s in (signal.SIGHUP, signal.SIGTERM):
            signal.signal(s, bye)
        self.listen()
        try:
            self.loop()
        finally:
            if self.child:
                self.stop_agent()
            self.close()
        return EXIT_OK

    def header(self):
        print("Moneta. Super+A shows and hides this panel. What invictus-sys changed: tribune acta")
        rows = acta_lines(3)
        if rows:
            print("Last changes:\n  " + "\n  ".join(ext(r) for r in rows))

    def loop(self):
        self.header()
        running = self.start()
        while True:
            watch = [self.sock]
            if not running:
                watch.append(sys.stdin)
                if running is False:
                    print("Press Enter to start Moneta again, or close this window.", flush=True)
                    running = None
            r, _, _ = select.select(watch, [], [], 0.5)
            if self.sock in r:
                msg = self.read_message()
                if msg == "stop":
                    if self.child:
                        self.stop_agent()
                    print("Moneta stopped: AI was turned off on this computer.", flush=True)
                    return
                if msg == "restart-profile":
                    if self.child:
                        self.stop_agent()
                    print("Moneta is starting again with the new rules.", flush=True)
                    running = self.start()
                    continue
            if sys.stdin in r:
                line = sys.stdin.readline()
                if line == "":
                    return
                running = self.start()
                continue
            if running and self.child and self.child.poll() is not None:
                self.reap()
                self.child = None
                self.take_terminal()
                print("\nMoneta ended.", flush=True)
                running = False


def main():
    prog = os.path.basename(sys.argv[0])
    args = sys.argv[1:]
    if prog == "invictus-provider" or args[:1] == ["provider"]:
        return provider_cli(args[1:] if args[:1] == ["provider"] else args)
    cmd = args[0] if args else "run"
    if cmd == "run":
        return Panel().run()
    if cmd == "chat":
        return chat_cli(args[1:])
    if cmd == "acta":
        return acta_cli(args[1:])
    print("tribune [run] | tribune chat | tribune acta [-n N] | invictus-provider ...", file=sys.stderr)
    return EXIT_BAD


if __name__ == "__main__":
    sys.exit(main())
