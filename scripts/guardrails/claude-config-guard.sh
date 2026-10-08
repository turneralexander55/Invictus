#!/bin/sh
# claude-config-guard: the managed profiles' Edit/Write hook (MUST A6).
# Installed as /usr/lib/invictus/claude-config-guard by invictus-guardrails;
# the guard itself is the Python file beside it,
# /usr/lib/invictus/claude-config-guard.py (scripts/guardrails/claude/config-guard.py).
#
# Only exit 2 blocks a PreToolUse call; any other non-zero code lets it
# through. The Python guard exits 0 or 2 by design, and env-ast.py lints the
# shapes it can see, but a library's own exit, an exception inside the
# excepthook or a signal can still end it with 1, 120 or 137 (Janus N-L1).
# So this wrapper turns every ending but 0 into 2 and has no other exit.
# What it cannot cover is a kill of the hook itself (Claude Code's timeout):
# then the deny rules in the profile are what holds.
#
# python3 -I: no PYTHON* variables, no user site, no script folder on the path.
py=/usr/lib/invictus/claude-config-guard.py
case "$0" in
    /usr/*) ;;
    *) py="${0%/*}/claude/config-guard.py" ;;  # a checkout (the tests)
esac
if /usr/bin/python3 -I "$py" "$@"; then
    exit 0
fi
exit 2
