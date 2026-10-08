#!/usr/bin/env python3
"""The INVICTUS_* override rule, checked on the syntax tree (Janus N3).

    env-ast.py FILE...                exit 1 and one line per problem
    env-ast.py --hook-dir DIR FILE... also: DIR holds only .py and .json
                                      files, and every .py in it is checked

For each shipped Python script:
  - os.environ.get / os.environ[...] / os.getenv / environ.get with a name
    that is not a string constant (it could be anything, INVICTUS_* too),
    or with a string constant that starts with INVICTUS_, is an offence,
    unless the line is marked "# not an override" (a runtime label);
  - a file that names INVICTUS_* at all must load the helper
    (scripts/lib/invictus_env.py, the _invictus_env() loader);
  - every tool(NAME, DEFAULT) default is an absolute path, so PATH never
    picks the program (Janus N2);
  - the _invictus_env() loader never exits (sys.exit, SystemExit, os._exit):
    it raises ImportError and the caller decides (Minerva, ruling 5);
  - a Claude Code hook (scripts/guardrails/claude/) may exit only 0 or 2:
    a PreToolUse hook that exits with anything else lets the tool call
    through. Listing the ways out does not prove that (Janus J-L2: any
    uncaught exception exits 1), so the rule is a shape:
      * the hook installs sys.excepthook first: before it, only a
        docstring, `import os`, `import sys` and plain function
        definitions; the hook is a lambda calling os._exit(2), or a
        function whose body is os._exit(2) or a try whose finally is
        exactly os._exit(2); nothing assigns or deletes it again;
      * every sys.exit, os._exit and SystemExit is a direct call with the
        literal 2 (0 comes from falling off the end);
      * none of the other ways out: an exit/_exit/abort/kill/killpg/
        raise_signal/pthread_kill attribute on anything (aliased modules,
        builtins.exit, os.abort, os.kill), the names exit, quit,
        SystemExit (aliases, subclasses, bare raise), __import__ or
        __builtins__ outside such a call, an aliased import of sys or os,
        `from sys|os|posix import ...` of an exit name, importing builtins,
        signal, ctypes, posix, _thread, _signal or faulthandler, or getattr
        on sys, os, builtins, signal or posix or with a computed name;
      * nothing binds or deletes the names os or sys except a plain
        `import os` / `import sys` (Janus N-L1): the excepthook looks up
        the global os when it runs, so `os = None`, `del os` or
        `import posixpath as os` make the hook itself raise, and Python
        then exits 1. The /bin/sh wrapper (claude-config-guard.sh) turns
        that 1 into 2 as well; the lint names the edit that caused it.
"""
import ast
import os
import stat
import sys

HOOK_DIR = "/scripts/guardrails/claude/"
EXIT_ATTRS = {"exit", "_exit", "abort", "kill", "killpg", "raise_signal", "pthread_kill"}
EXIT_NAMES = {"exit", "quit", "SystemExit", "_exit", "abort", "__import__", "__builtins__"}
BANNED_MODULES = {"builtins", "signal", "ctypes", "posix", "nt", "_thread", "_signal", "faulthandler"}
GETATTR_MODULES = {"sys", "os", "builtins", "signal", "posix"}


def is_two(node):
    return isinstance(node, ast.Constant) and type(node.value) is int and node.value == 2


def exit2_call(node):
    """True for sys.exit(2), os._exit(2) and SystemExit(2), one argument, no keywords."""
    if not (isinstance(node, ast.Call) and len(node.args) == 1 and not node.keywords and is_two(node.args[0])):
        return False
    f = node.func
    if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name):
        return (f.value.id, f.attr) in (("sys", "exit"), ("os", "_exit"))
    return isinstance(f, ast.Name) and f.id == "SystemExit"


def is_excepthook_target(t):
    return isinstance(t, ast.Attribute) and t.attr == "excepthook" and isinstance(t.value, ast.Name) and t.value.id == "sys"


def blocks(fn_body):
    """A hook body that always ends in os._exit(2)."""
    body = [b for b in fn_body if not (isinstance(b, ast.Expr) and isinstance(b.value, ast.Constant))]
    if len(body) != 1:
        return False
    b = body[0]
    if isinstance(b, ast.Expr):
        return exit2_call(b.value) and b.value.func.attr == "_exit"
    return (isinstance(b, ast.Try) and len(b.finalbody) == 1 and isinstance(b.finalbody[0], ast.Expr)
            and exit2_call(b.finalbody[0].value) and isinstance(b.finalbody[0].value.func, ast.Attribute)
            and b.finalbody[0].value.func.attr == "_exit")


def excepthook_first(tree):
    """None if the module installs the exit-2 excepthook before anything that can raise, else why not."""
    funcs = {}
    for i, st in enumerate(tree.body):
        if i == 0 and isinstance(st, ast.Expr) and isinstance(st.value, ast.Constant):
            continue
        if isinstance(st, ast.Import) and all(a.name in ("os", "sys") and a.asname is None for a in st.names):
            continue
        if isinstance(st, ast.FunctionDef) and not st.decorator_list and not st.args.defaults \
                and not any(st.args.kw_defaults) and not st.returns \
                and not any(a.annotation for a in st.args.args + st.args.kwonlyargs):
            funcs[st.name] = st
            continue
        if isinstance(st, ast.Assign) and len(st.targets) == 1 and is_excepthook_target(st.targets[0]):
            v = st.value
            if isinstance(v, ast.Lambda) and not v.args.defaults and exit2_call(v.body) \
                    and isinstance(v.body.func, ast.Attribute) and v.body.func.attr == "_exit":
                return None
            if isinstance(v, ast.Name) and v.id in funcs and blocks(funcs[v.id].body):
                return None
            return f"line {st.lineno}: the excepthook does not always end in os._exit(2)"
        return f"line {st.lineno}: something that can raise runs before sys.excepthook is set"
    return "no sys.excepthook"


def hook_problems(path, tree):
    bad = []
    why = excepthook_first(tree)
    if why:
        bad.append(f"{path}: a hook must set an exit-2 sys.excepthook before anything else ({why}); "
                   "an uncaught exception exits 1, which lets the call through")
    hooks = 0
    allowed = set()  # the func of each allowed exit call
    for node in ast.walk(tree):
        if exit2_call(node):
            allowed.add(id(node.func))
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AugAssign, ast.AnnAssign, ast.Delete)):
            targets = node.targets if isinstance(node, (ast.Assign, ast.Delete)) else [node.target]
            if any(is_excepthook_target(t) for t in targets):
                hooks += 1
                if hooks > 1 or isinstance(node, ast.Delete):
                    bad.append(f"{path}:{node.lineno}: sys.excepthook changed again (forbidden in a hook)")
        if isinstance(node, ast.Call):
            f = node.func
            what = None
            if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and (f.value.id, f.attr) in (("sys", "exit"), ("os", "_exit")):
                what = f"{f.value.id}.{f.attr}"
            elif isinstance(f, ast.Name) and f.id == "SystemExit":
                what = "SystemExit"
            if what and id(f) not in allowed:
                bad.append(f"{path}:{node.lineno}: {what} in a hook without the literal 2 (only exit 2 blocks)")
                allowed.add(id(f))  # one line per call
            if isinstance(f, ast.Name) and f.id == "getattr" and node.args:
                obj = node.args[0]
                name = node.args[1] if len(node.args) > 1 else None
                if (isinstance(obj, ast.Name) and obj.id in GETATTR_MODULES) or not isinstance(name, ast.Constant):
                    bad.append(f"{path}:{node.lineno}: getattr on a module or with a computed name (forbidden in a hook)")
        elif isinstance(node, ast.Raise) and isinstance(node.exc, ast.Name) and node.exc.id == "SystemExit":
            bad.append(f"{path}:{node.lineno}: raise SystemExit in a hook without the literal 2 (only exit 2 blocks)")
            allowed.add(id(node.exc))
    for node in ast.walk(tree):
        name = rebinds_os_sys(node)
        if name:
            bad.append(f"{path}:{getattr(node, 'lineno', '?')}: rebinds or deletes {name} (forbidden in a hook: "
                       "the excepthook needs the real os and sys; Janus N-L1)")
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and node.attr in EXIT_ATTRS and id(node) not in allowed:
            bad.append(f"{path}:{node.lineno}: .{node.attr} (forbidden in a hook: only sys.exit(2) or os._exit(2))")
        elif isinstance(node, ast.Name) and node.id in EXIT_NAMES and id(node) not in allowed:
            bad.append(f"{path}:{node.lineno}: {node.id} (forbidden in a hook: only sys.exit(2), os._exit(2), SystemExit(2))")
        elif isinstance(node, ast.Import):
            for a in node.names:
                top = a.name.split(".")[0]
                if top in BANNED_MODULES or (top in ("sys", "os") and a.asname):
                    bad.append(f"{path}:{node.lineno}: import {a.name}{' as ' + a.asname if a.asname else ''} (forbidden in a hook)")
        elif isinstance(node, ast.ImportFrom):
            mod = (node.module or "").split(".")[0]
            if mod in BANNED_MODULES or (mod in ("sys", "os", "posix") and any(
                    a.name == "*" or a.name in EXIT_ATTRS or a.asname for a in node.names)):
                bad.append(f"{path}:{node.lineno}: from {node.module} import ... (forbidden in a hook)")
    return bad


def rebinds_os_sys(node):
    """The line of a binding or deletion of os or sys other than a plain import, else None."""
    names = ("os", "sys")
    if isinstance(node, ast.Name) and node.id in names and isinstance(node.ctx, (ast.Store, ast.Del)):
        return node.id
    if isinstance(node, ast.Import):
        hit = [a.asname for a in node.names if a.asname in names]
        return hit[0] if hit else None
    if isinstance(node, ast.ImportFrom):
        hit = [a.asname or a.name for a in node.names if (a.asname or a.name) in names]
        return hit[0] if hit else None
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.ExceptHandler)) and node.name in names:
        return node.name
    if isinstance(node, ast.arg) and node.arg in names:
        return node.arg
    if isinstance(node, (ast.MatchAs, ast.MatchStar)) and node.name in names:
        return node.name
    if isinstance(node, (ast.Global, ast.Nonlocal)) and set(node.names) & set(names):
        return sorted(set(node.names) & set(names))[0]
    return None


def hook_dir_problems(d):
    """The hook folder holds Python hooks and JSON profiles only."""
    bad, py = [], []
    for root, dirs, files in os.walk(d):
        for name in sorted(dirs + files):
            p = os.path.join(root, name)
            st = os.lstat(p)
            if stat.S_ISDIR(st.st_mode) and not os.path.islink(p):
                continue
            if not stat.S_ISREG(st.st_mode) or not name.endswith((".py", ".json")):
                bad.append(f"{p}: not a .py or .json file; the hook folder holds Python hooks and profiles only")
            elif name.endswith(".py"):
                py.append(p)
    return bad, py


def exit_call(node):
    """(what, first argument or None) for sys.exit(...), os._exit(...),
    SystemExit(...) and a bare raise SystemExit; else None."""
    if isinstance(node, ast.Raise) and isinstance(node.exc, ast.Name) and node.exc.id == "SystemExit":
        return "raise SystemExit", None
    if isinstance(node, ast.Call):
        f = node.func
        arg = node.args[0] if node.args else None
        if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and (
                (f.value.id == "sys" and f.attr == "exit") or (f.value.id == "os" and f.attr == "_exit")):
            return f"{f.value.id}.{f.attr}", arg
        if isinstance(f, ast.Name) and f.id in ("SystemExit", "exit", "quit"):
            return f.id, arg
    return None


def env_call_name(node):
    """The name argument of an environment read, or False if node is none."""
    if isinstance(node, ast.Call):
        f = node.func
        is_get = isinstance(f, ast.Attribute) and f.attr in ("get", "getenv") and (
            (f.attr == "getenv" and isinstance(f.value, ast.Name) and f.value.id == "os")
            or (f.attr == "get" and (
                (isinstance(f.value, ast.Attribute) and f.value.attr == "environ")
                or (isinstance(f.value, ast.Name) and f.value.id == "environ"))))
        if is_get:
            return node.args[0] if node.args else None
    if isinstance(node, ast.Subscript):
        v = node.value
        if (isinstance(v, ast.Attribute) and v.attr == "environ") or (isinstance(v, ast.Name) and v.id == "environ"):
            return node.slice
    return False


def check(path):
    src = open(path).read()
    lines = src.splitlines()
    tree = ast.parse(src, path)
    bad = []
    for node in ast.walk(tree):
        arg = env_call_name(node)
        if arg is not False:
            marked = any("# not an override" in lines[i - 1]
                         for i in range(node.lineno, (node.end_lineno or node.lineno) + 1))
            if marked:
                continue
            if not (isinstance(arg, ast.Constant) and isinstance(arg.value, str)):
                bad.append(f"{path}:{node.lineno}: environment read with a computed name")
            elif arg.value.startswith("INVICTUS_"):
                bad.append(f"{path}:{node.lineno}: {arg.value} read directly, not through invictus_env")
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "tool"
                and len(node.args) >= 2):
            d = node.args[1]
            if not (isinstance(d, ast.Constant) and isinstance(d.value, str) and d.value.startswith("/")):
                bad.append(f"{path}:{node.lineno}: tool() default is not an absolute path")
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "_invictus_env":
            for sub in ast.walk(node):
                ex = exit_call(sub)
                if ex:
                    bad.append(f"{path}:{sub.lineno}: _invictus_env exits ({ex[0]}); it must raise ImportError")
    if HOOK_DIR in os.path.abspath(path):
        bad += hook_problems(path, tree)
    if "INVICTUS_" in src and "_invictus_env()" not in src:
        bad.append(f"{path}: names INVICTUS_* but does not load invictus_env")
    return bad


def main(paths):
    bad = []
    if paths[:1] == ["--hook-dir"] and len(paths) >= 2:
        dbad, py = hook_dir_problems(paths[1])
        bad += dbad
        paths = sorted(set(paths[2:]) | set(py))
    for p in paths:
        bad += check(p)
    for b in bad:
        print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
