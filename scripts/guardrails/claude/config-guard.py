#!/usr/bin/python3 -I
# ------------------------------------------------------------
# claude-config-guard: MUST A6 for Claude Code (design 4.8). Installed as
# /usr/lib/invictus/claude-config-guard.py by invictus-guardrails and run by
# /usr/lib/invictus/claude-config-guard (scripts/guardrails/claude-config-guard.sh),
# the /bin/sh wrapper the managed profiles call as hooks: it runs this file
# with python3 -I and turns any exit code but 0 into 2, a signal death too
# (Janus N-L1). Root-owned, so the agent cannot change it, and hooks in
# managed settings cannot be turned off from a home.
#
#   claude-config-guard pre fixed|full    PreToolUse on Edit, Write, NotebookEdit
#   claude-config-guard post              PostToolUse on the same tools
#
# pre: the file must be on the A6 allowlist for the profile, in the home.
#      fixed (Custodia, or Libertas without Full access): data files only,
#        each listed by name next to the reader that validates every field
#        it uses (Minerva, final review 2026-10-01, rulings 1 and 4):
#          ~/.config/invictus/themes/*.toml   invictus-theme, schema on load
#          ~/.config/invictus/motion          invictus-motion, three-word enum
#          ~/.config/waybar/*.css             waybar style, no commands
#        Anything else under ~/.config/invictus is refused until it is added
#        here with its reader. Files a program executes (user.lua,
#        monitors.lua, waybar's config) are the person's or a tool's: any of
#        them can start a program (hl.exec_cmd, waybar exec/on-click).
#      full (Full access): ~/.config/hypr/user.lua, ~/.config/hypr/monitors.lua,
#        ~/.config/invictus/** (not moneta.toml or providers/: who answers is
#        the person's choice, T7; not theme-hooks.d/: invictus-theme apply
#        runs what is there, Janus I5), ~/.config/waybar/**, and any path in
#        the home whose first part does not start with a dot (projects,
#        documents); no other dotfile, and nothing outside the home (the
#        deny rules guard /etc, /usr, /boot).
#      Both the path as given and where it really leads must pass. Before an
#      allowed edit of an existing file, a copy goes to
#      ~/.local/state/invictus/backups/<time>/<path in home>.
# post: after an edit under ~/.config/hypr, `invictus-doctor --hypr`; if it
#      fails, the backup goes back (or the new file is removed) and Moneta is
#      told why.
# Any error in pre blocks the edit (exit 2): a broken guard fails closed.
# Python exits 1 on an uncaught exception, and exit 1 lets a PreToolUse call
# through, so the first thing this file does is install an excepthook that
# exits 2 (Janus J-L1); everything that can raise runs after it, and the
# lookups that used to run at import (HOME) run inside main()'s try.
# tests/pkgs/lib/env-ast.py requires that shape in every hook file. The
# wrapper is what makes the rule hold for ways out the lint cannot see (a
# library's own exit, a rebound os inside the excepthook, a kill).
# A hook that times out does not: Claude Code lets the tool call go ahead
# (hooks docs, PreToolUse timeouts), so the profiles give pre 10 s and post
# 60 s, and on a timeout what still holds is the managed deny rules
# (/etc, /usr, /boot, the who-answers files, ~/.claude settings) and, under
# the fixed profile, no shell. post's doctor gets DOCTOR_TIMEOUT, under the
# hook's 60 s, so a slow check still ends in a restore, not a kill.
# Env (tests, honoured only from a checkout): INVICTUS_DOCTOR, HOME_OVERRIDE.
# ------------------------------------------------------------
import os
import sys


def _block(*_):
    # Any exception nothing caught: block the edit (exit 2), never exit 1.
    try:
        sys.stderr.write("claude-config-guard failed; not allowed.\n")
        sys.stderr.flush()
    finally:
        os._exit(2)


sys.excepthook = _block

import fnmatch  # noqa: E402  (after the excepthook on purpose)
import hashlib  # noqa: E402
import json  # noqa: E402
import pwd  # noqa: E402
import shutil  # noqa: E402
import stat  # noqa: E402
import subprocess  # noqa: E402
import time  # noqa: E402

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
except BaseException as e:  # fail closed: exit 1 would let the edit through. BaseException, not
    # Exception: the helper runs through exec_module, so a SystemExit or KeyboardInterrupt it
    # raises lands here too (Janus N-L1)
    print(f"claude-config-guard cannot load invictus_env ({type(e).__name__}); not allowed.", file=sys.stderr)
    sys.exit(2)


DOCTOR = env("INVICTUS_DOCTOR", "/usr/bin/invictus-doctor")
DOCTOR_TIMEOUT = 45
HOME = STATE = None  # set by setup(), inside main()'s try (Janus J-L1)


def setup():
    global HOME, STATE
    HOME = os.path.realpath(env("HOME_OVERRIDE", "") or pwd.getpwuid(os.getuid()).pw_dir)
    STATE = os.path.join(HOME, ".local/state/invictus/backups")

# fixed: (folder in the home, file-name pattern, the reader that validates it).
# A file is on the list only in that folder itself, not below it.
FIXED_ALLOW = (
    (".config/invictus/themes", "*.toml", "invictus-theme: theme schema on load (note 48)"),
    (".config/invictus", "motion", "invictus-motion: showcase, calm or off"),
    (".config/waybar", "*.css", "waybar: style only, no commands"),
)
# full
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


def on_allowlist(rel, profile):
    if profile != "full":
        folder, name = os.path.split(rel)
        return any(folder == d and fnmatch.fnmatchcase(name, pat) for d, pat, _ in FIXED_ALLOW)
    if any(under(rel, n) for n in NEVER):
        return False
    return rel in ALLOW_FILES or any(under(rel, t) and rel != t for t in ALLOW_TREES)


def decide(path, profile):
    """None if allowed, else the reason."""
    if not path or not os.path.isabs(path) or "\0" in path:
        return "Moneta edits files by their full path only."
    given = os.path.normpath(path)
    real = os.path.realpath(path)
    if profile != "full":
        # A hard link looks like any file to realpath and to the deny rules
        # (Janus J-L3): under fixed, an existing target must be a regular
        # file with one link.
        try:
            st = os.lstat(real)
        except FileNotFoundError:
            st = None
        if st is not None and (not stat.S_ISREG(st.st_mode) or st.st_nlink > 1):
            return (f"{path} is a link to another file or not a plain file; "
                    "Moneta does not edit it here.")
    for p in (given, real):
        rel = rel_in_home(p)
        if rel is None:
            return f"{path} is outside your home folder; Moneta does not edit it."
        if on_allowlist(rel, profile):
            continue
        if profile == "full" and not rel.split("/", 1)[0].startswith("."):
            continue
        if profile == "full":
            return (f"{path} is a settings file Moneta may not change. It may change ~/.config/hypr/user.lua, "
                    "monitors.lua, ~/.config/waybar and ~/.config/invictus.")
        return (f"{path} is not one Moneta may change here. It may change themes in ~/.config/invictus/themes, "
                "the motion level and waybar's style sheets; anything else is yours to do.")
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
            setup()
            return pre(args[1])
        except BaseException as e:  # fail closed (BaseException: a library's SystemExit too, N-L1)
            print(f"claude-config-guard could not check this edit ({e}); not allowed.", file=sys.stderr)
            return 2
    if args == ["post"]:
        try:
            setup()
            return post()
        except BaseException as e:
            print(f"claude-config-guard could not check the result ({e}); run invictus-doctor --hypr.", file=sys.stderr)
            return 2
    print("claude-config-guard pre fixed|full | post", file=sys.stderr)
    return 2


if __name__ == "__main__":
    # Only exit 2 blocks a PreToolUse call; any other non-zero lets it through.
    # So the guard exits 2 or 0 (falling off the end), nothing else.
    rc = main()
    # The flush only matters for rc != 0: os._exit(2) skips the interpreter's
    # own flush, so a message still in a buffer would be lost (today every
    # such path writes whole lines to stderr, which Python flushes per line,
    # so this is belt and braces). It does not decide the exit code (Janus
    # I-5): with rc 0 a failed flush at interpreter exit gives 120, which
    # lets the call through just as 0 does, and with rc != 0 the finally
    # below exits 2 whether or not the flush raised.
    try:
        sys.stdout.flush()
        sys.stderr.flush()
    finally:
        if rc != 0:
            os._exit(2)
