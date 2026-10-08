#!/usr/bin/env python3
"""Each own or meta package's inputs, hashed, against pkgs/inputs.lock.

A package built from this repo takes files from it (`"$root/..."` in
package()). If those files change and pkgver-pkgrel does not, the repo
publishes a package with new contents under an old version, and pacman never
installs it on a machine that has the old one (Janus, pre-release confirm
2026-10-08: invictus-sys, -guardrails and -tools changed after 7a6cc3f with no
bump). Works on a plain copy of the tree (no git), so the gate and CI run it
the same way.

Inputs of a package: every file in its own folder (the PKGBUILD without its
pkgver/pkgrel lines, .install files, keys), plus every repo path its PKGBUILD
names after `$root` or after a local set from `$root` (`local src="$root/x"`).
A plain path is that file, or that folder with everything under it; a path
with a glob or a variable in it is matched like the shell glob in that one
folder. That can take in a little more than package() installs, never less
of what it names.

usage: pkg-inputs.py [--repo DIR] --check    exit 1 if a package changed without a bump
       pkg-inputs.py [--repo DIR] --update   rewrite the lock; refuses the same
                                             version with a new hash
       pkg-inputs.py [--repo DIR] --inputs NAME   print one package's input files
"""
import fnmatch
import hashlib
import os
import re
import sys

LOCK = "pkgs/inputs.lock"
GLOB = re.compile(r"[*?\[]")
SKIP_DIRS = {"__pycache__", "src", "pkg", ".git"}


def files_under(repo, rel):
    out = []
    for d, dirs, names in os.walk(os.path.join(repo, rel)):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for n in names:
            if not n.endswith((".pyc", ".pkg.tar.zst", ".pkg.tar.xz")):
                out.append(os.path.relpath(os.path.join(d, n), repo))
    return out


def named_paths(text):
    """Repo-relative paths (or globs) a PKGBUILD names after $root or a $root-based local."""
    roots = {"root": ""}
    for var, sub in re.findall(r'local\s+(\w+)="\$root/([^"$]*)"', text):
        roots[var] = sub.rstrip("/") + "/"
    out = []
    for var, prefix in roots.items():
        for m in re.finditer(r'\$(?:\{' + var + r'\}|' + var + r'\b)"?/([^"\s;)|}]*)', text):
            p = prefix + m.group(1)
            if "$" in p:
                p = p[:p.index("$")] + "*"
            if p.strip("/"):
                out.append(p)
    return out


def inputs(repo, pkgdir):
    pb = os.path.join(pkgdir, "PKGBUILD")
    with open(pb, encoding="utf-8") as f:
        text = f.read()
    got = set(files_under(repo, os.path.relpath(pkgdir, repo)))
    for p in named_paths(text):
        if GLOB.search(p):
            d, pat = os.path.split(p)
            full = os.path.join(repo, d)
            if os.path.isdir(full):
                got.update(os.path.join(d, n) for n in os.listdir(full)
                           if fnmatch.fnmatch(n, pat) and not n.startswith(".")
                           and os.path.isfile(os.path.join(full, n)))
        elif os.path.isfile(os.path.join(repo, p)):
            got.add(os.path.normpath(p))
        elif os.path.isdir(os.path.join(repo, p)):
            got.update(files_under(repo, p.rstrip("/")))
        else:
            raise SystemExit(f"{os.path.relpath(pb, repo)}: names {p}, which is not in the repo")
    return sorted(got), text


def version(text):
    v = dict(re.findall(r"^(pkgver|pkgrel|epoch)=['\"]?([^'\"\s]+)", text, re.M))
    return (v["epoch"] + ":" if "epoch" in v else "") + f"{v['pkgver']}-{v['pkgrel']}"


def digest(repo, files, pkgdir):
    h = hashlib.sha256()
    pb = os.path.relpath(os.path.join(pkgdir, "PKGBUILD"), repo)
    for rel in files:
        with open(os.path.join(repo, rel), "rb") as f:
            data = f.read()
        if rel == pb:  # the version lines are what a bump changes, not an input
            data = re.sub(rb"(?m)^(pkgver|pkgrel|epoch)=.*\n", b"", data)
        h.update(rel.encode() + b"\0" + hashlib.sha256(data).digest())
    return h.hexdigest()


def packages(repo):
    out = {}
    for kind in ("own", "meta"):
        base = os.path.join(repo, "pkgs", kind)
        for name in sorted(os.listdir(base)):
            d = os.path.join(base, name)
            if os.path.isfile(os.path.join(d, "PKGBUILD")):
                files, text = inputs(repo, d)
                out[name] = (version(text), digest(repo, files, d), files)
    return out


def read_lock(repo):
    lock = {}
    try:
        with open(os.path.join(repo, LOCK)) as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    name, ver, h = line.split()
                    lock[name] = (ver, h)
    except FileNotFoundError:
        pass
    return lock


def main(argv):
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    if len(argv) >= 2 and argv[0] == "--repo":
        repo, argv = argv[1], argv[2:]
    if argv[:1] == ["--inputs"] and len(argv) == 2:
        for kind in ("own", "meta"):
            d = os.path.join(repo, "pkgs", kind, argv[1])
            if os.path.isdir(d):
                print("\n".join(inputs(repo, d)[0]))
                return 0
        return 1
    if argv not in (["--check"], ["--update"]):
        print(__doc__, file=sys.stderr)
        return 2
    now, lock, bad = packages(repo), read_lock(repo), []
    for name, (ver, h, _) in now.items():
        if name not in lock:
            bad.append(f"{name}: not in {LOCK}")
        elif lock[name][1] != h and lock[name][0] == ver:
            bad.append(f"{name}: its files changed but its version is still {ver}: bump pkgrel")
        elif lock[name] != (ver, h):
            bad.append(f"{name}: {LOCK} has {lock[name][0]}, the PKGBUILD has {ver}: run {sys.argv[0]} --update")
    bad += [f"{name}: in {LOCK} but has no PKGBUILD" for name in lock if name not in now]
    if argv == ["--check"]:
        for b in bad:
            print(b)
        return 1 if bad else 0
    refused = [b for b in bad if "bump pkgrel" in b]
    if refused:
        print("\n".join(refused) + "\nnothing written", file=sys.stderr)
        return 1
    with open(os.path.join(repo, LOCK), "w") as f:
        f.write("# name version sha256-of-inputs: scripts/dev/pkg-inputs.py --update after a bump;\n"
                "# tests/pkgs/run.sh group 1b fails when a package's inputs change and its version does not.\n")
        for name, (ver, h, _) in now.items():
            f.write(f"{name} {ver} {h}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
