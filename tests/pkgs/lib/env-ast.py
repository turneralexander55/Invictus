#!/usr/bin/env python3
"""The INVICTUS_* override rule, checked on the syntax tree (Janus N3).

    env-ast.py FILE...      exit 1 and one line per problem

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
  - in a Claude Code hook (scripts/guardrails/claude/), every sys.exit,
    SystemExit and os._exit has the literal argument 2: a PreToolUse hook
    that exits with anything else but 0 lets the tool call through, and 0
    comes from falling off the end.
"""
import ast
import os
import sys

HOOK_DIR = "/scripts/guardrails/claude/"


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
    hook = HOOK_DIR in os.path.abspath(path)
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "_invictus_env":
            for sub in ast.walk(node):
                ex = exit_call(sub)
                if ex:
                    bad.append(f"{path}:{sub.lineno}: _invictus_env exits ({ex[0]}); it must raise ImportError")
        if hook:
            ex = exit_call(node)
            if ex and not (isinstance(ex[1], ast.Constant) and ex[1].value == 2 and type(ex[1].value) is int):
                bad.append(f"{path}:{node.lineno}: {ex[0]} in a hook without the literal 2 (only exit 2 blocks)")
    if "INVICTUS_" in src and "_invictus_env()" not in src:
        bad.append(f"{path}: names INVICTUS_* but does not load invictus_env")
    return bad


def main(paths):
    bad = []
    for p in paths:
        bad += check(p)
    for b in bad:
        print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
