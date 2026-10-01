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
    picks the program (Janus N2).
"""
import ast
import sys


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
