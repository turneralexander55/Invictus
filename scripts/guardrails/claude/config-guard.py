#!/usr/bin/python3 -I
# ------------------------------------------------------------
# claude-config-guard: MUST A6 for Claude Code (design 4.8). Installed as
# /usr/lib/invictus/claude-config-guard by invictus-guardrails, next to the
# managed profiles that call it as hooks. Root-owned, so the agent cannot
# change it, and hooks in managed settings cannot be turned off from a home.
#
#   claude-config-guard pre fixed|full    PreToolUse on Edit, Write, NotebookEdit
#   claude-config-guard post              PostToolUse on the same tools
#
# pre: the file must be on the A6 allowlist in the home:
#        ~/.config/hypr/user.lua, ~/.config/hypr/monitors.lua,
#        ~/.config/invictus/** (not moneta.toml or providers/: who answers is
#        the person's choice, T7; not theme-hooks.d/: invictus-theme apply
#        runs what is there, Janus I5), ~/.config/waybar/**
#      fixed (Custodia, or Libertas without Full access): nothing else.
#      full (Full access): also any path in the home whose first part does
#        not start with a dot (projects, documents); no other dotfile, and
#        nothing outside the home (the deny rules guard /etc, /usr, /boot).
#      Both the path as given and where it really leads must pass. Before an
#      allowed edit of an existing file, a copy goes to
#      ~/.local/state/invictus/backups/<time>/<path in home>.
# post: after an edit under ~/.config/hypr, `invictus-doctor --hypr`; if it
#      fails, the backup goes back (or the new file is removed) and Moneta is
#      told why.
# Any error in pre blocks the edit (exit 2): a broken guard fails closed.
# A hook that times out does not: Claude Code lets the tool call go ahead
# (hooks docs, PreToolUse timeouts), so the profiles give pre 10 s and post
# 60 s, and on a timeout what still holds is the managed deny rules
# (/etc, /usr, /boot, the who-answers files, ~/.claude settings) and, under
# the fixed profile, no shell. post's doctor gets DOCTOR_TIMEOUT, under the
# hook's 60 s, so a slow check still ends in a restore, not a kill.
# Env (tests, honoured only from a checkout): INVICTUS_DOCTOR, HOME_OVERRIDE.
# ------------------------------------------------------------
import hashlib
import json
import os
import pwd
import shutil
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
    path = next(p for p in paths if os.path.isfile(p))
    spec = importlib.util.spec_from_file_location("invictus_env", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.for_script(here)


try:
    env = _invictus_env()
except Exception as e:  # fail closed: exit 1 would let the edit through
    print(f"claude-config-guard cannot load invictus_env ({type(e).__name__}); not allowed.", file=sys.stderr)
    sys.exit(2)


DOCTOR = env("INVICTUS_DOCTOR", "/usr/bin/invictus-doctor")
DOCTOR_TIMEOUT = 45
HOME = os.path.realpath(env("HOME_OVERRIDE", "") or pwd.getpwuid(os.getuid()).pw_dir)
STATE = os.path.join(HOME, ".local/state/invictus/backups")

ALLOW_FILES = (".config/hypr/user.lua", ".config/hypr/monitors.lua")
ALLOW_TREES = (".config/invictus", ".config/waybar")
NEVER = (".config/invictus/moneta.toml", ".config/invictus/providers",
         ".config/invictus/theme-hooks.d")  # programs invictus-theme apply runs (Janus I5)


def rel_in_home(path):
    if not path.startswith(HOME + "/"):
        return None
    return path[len(HOME) + 1:]


def under(rel, tree):
    return rel == tree or rel.startswith(tree + "/")


def on_allowlist(rel):
    if any(under(rel, n) for n in NEVER):
        return False
    return rel in ALLOW_FILES or any(under(rel, t) and rel != t for t in ALLOW_TREES)


def decide(path, profile):
    """None if allowed, else the reason."""
    if not path or not os.path.isabs(path) or "\0" in path:
        return "Moneta edits files by their full path only."
    given = os.path.normpath(path)
    real = os.path.realpath(path)
    for p in (given, real):
        rel = rel_in_home(p)
        if rel is None:
            return f"{path} is outside your home folder; Moneta does not edit it."
        if on_allowlist(rel):
            continue
        if profile == "full" and not rel.split("/", 1)[0].startswith("."):
            continue
        if profile == "full":
            return (f"{path} is a settings file Moneta may not change. It may change ~/.config/hypr/user.lua, "
                    "monitors.lua, ~/.config/waybar and ~/.config/invictus.")
        return (f"{path} is not one Moneta may change here. It may change ~/.config/hypr/user.lua, monitors.lua, "
                "~/.config/waybar and ~/.config/invictus; anything else is yours to do.")
    return None


def pending_file(path):
    return os.path.join(STATE, "pending", hashlib.sha256(path.encode()).hexdigest() + ".json")


def backup(path):
    real = os.path.realpath(path)
    record = {"path": real, "backup": None}
    if os.path.isfile(real):
        stamp = time.strftime("%Y%m%d-%H%M%S-") + f"{time.time_ns() % 10**9:09d}"
        dest = os.path.join(STATE, stamp, rel_in_home(real))
        os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
        shutil.copy2(real, dest)
        record["backup"] = dest
    os.makedirs(os.path.join(STATE, "pending"), mode=0o700, exist_ok=True)
    with open(pending_file(real), "w") as f:
        json.dump(record, f)
    return record["backup"]


def tool_path(data):
    ti = data.get("tool_input") or {}
    return ti.get("file_path") or ti.get("notebook_path") or ""


def pre(profile):
    data = json.load(sys.stdin)
    path = tool_path(data)
    why = decide(path, profile)
    if why:
        print(why, file=sys.stderr)
        return 2
    where = backup(path)
    if where:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                 "additionalContext": f"Backup of {path}: {where}"}}))
    return 0


def post():
    data = json.load(sys.stdin)
    path = tool_path(data)
    if not path:
        return 0
    real = os.path.realpath(path)
    rel = rel_in_home(real)
    try:
        with open(pending_file(real)) as f:
            record = json.load(f)
        os.unlink(pending_file(real))
    except (OSError, ValueError):
        record = {"path": real, "backup": None}
    if rel is None or not under(rel, ".config/hypr"):
        return 0
    try:
        r = subprocess.run([DOCTOR, "--hypr"], capture_output=True, text=True, timeout=DOCTOR_TIMEOUT, stdin=subprocess.DEVNULL)
        ok, out = r.returncode == 0, (r.stdout + r.stderr)[-1500:]
    except (OSError, subprocess.TimeoutExpired) as e:
        ok, out = False, str(e)
    if ok:
        return 0
    if record.get("backup") and os.path.isfile(record["backup"]):
        shutil.copy2(record["backup"], real)
        undo = f"put back from {record['backup']}"
    else:
        try:
            os.unlink(real)
        except OSError:
            pass
        undo = "removed (it did not exist before)"
    print(f"The change to {path} broke the Hyprland config check, so it was {undo}. "
          f"invictus-doctor --hypr said:\n{out}", file=sys.stderr)
    return 2


def main():
    args = sys.argv[1:]
    if args[:1] == ["pre"] and len(args) == 2 and args[1] in ("fixed", "full"):
        try:
            return pre(args[1])
        except Exception as e:  # fail closed
            print(f"claude-config-guard could not check this edit ({e}); not allowed.", file=sys.stderr)
            return 2
    if args == ["post"]:
        try:
            return post()
        except Exception as e:
            print(f"claude-config-guard could not check the result ({e}); run invictus-doctor --hypr.", file=sys.stderr)
            return 2
    print("claude-config-guard pre fixed|full | post", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
