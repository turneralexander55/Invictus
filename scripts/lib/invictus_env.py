"""INVICTUS_* test overrides, honoured only from a checkout (Janus, first-start
pen test L1, 2026-10-01). Installed as /usr/lib/invictus/lib/invictus_env.py
by invictus-sys.

The tests point our tools at fakes through INVICTUS_* variables. An installed
copy (anything under /usr/) ignores them, so nothing in a session's
environment (environment.d, a line in the Hyprland config) can redirect an
installed tool: which provider file the sign-in reads, which program gets a
key on stdin, which command the screens call.

    env = invictus_env.for_script(__file__)
    SHARE = env("INVICTUS_SHARE", "/usr/share/invictus")

A runtime label that is not an override (the Moneta thread id, for one) is
read with os.environ directly and marked "# not an override";
tests/pkgs/firstboot.sh fails on any other direct INVICTUS_* read in a
shipped Python script.

Load it from a script with this block, copied as is (the script must find
the helper before it knows whether it is installed). The block raises
ImportError and never exits: the caller decides (Minerva, final review
2026-10-01, ruling 5). A PreToolUse hook catches Exception and exits 2 (any
other non-zero exit lets the tool call through); a tool prints the message
and exits 1. tests/pkgs/lib/env-ast.py fails on a _invictus_env that exits.

    def _invictus_env():
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
    except ImportError as e:
        sys.exit(f"{e}")
"""
import os


def installed(script):
    """True for a copy under /usr/ (what the packages install)."""
    return os.path.realpath(script).startswith("/usr/")


def for_script(script):
    """env(NAME, default): the override from a checkout, the default when
    installed. An empty variable counts as unset."""
    inst = installed(script)

    def env(name, default=None):
        if inst:
            return default
        return os.environ.get(name) or default
    return env
