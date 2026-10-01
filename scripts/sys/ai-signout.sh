#!/usr/bin/bash
# ------------------------------------------------------------
# ai-signout: one person's part of No AI (design-no-ai.md N3 steps 2 and 3).
# Installed as /usr/lib/invictus/ai-signout by invictus-sys. Run by
# `invictus-sys ai off` (root) AS THAT PERSON (setpriv, no extra groups,
# a clean environment with HOME set), once per home folder, so root never
# reads or writes a file inside anyone's home (Janus H1, L1).
#
#   ai-signout [--logout]
#
#   --logout   first `claude auth logout` (revokes the credential when
#              online; 10 s at most). Given for the person who turned AI off.
#
# Then, in $HOME: deletes ~/.claude/.credentials.json, removes the
# oauthAccount block from ~/.claude.json (everything else in it stays), and
# signs gh out only if invictus-collegium signed it in (its record in
# ~/.local/state/invictus/collegium/gh-login). Kept: ~/.claude/projects,
# ~/Collegium and every other memory (N6). Provider keys in the keyring
# need the person's own session: invictus-session clears them at the next
# login (/var/lib/invictus/ai-off-pending/<uid>, written by root).
# Env: HOME; CLAUDE, GH (the commands, default claude and gh).
# Exit: 0 always (best effort); one line per thing done.
# ------------------------------------------------------------
set -uo pipefail
LOGOUT=0
[[ "${1:-}" == --logout ]] && LOGOUT=1
CLAUDE="${CLAUDE:-claude}"
GH="${GH:-gh}"
cd "${HOME:?}" 2>/dev/null || { echo "ai-signout: no home folder"; exit 0; }

if ((LOGOUT)) && command -v "$CLAUDE" >/dev/null 2>&1; then
    if timeout 10 "$CLAUDE" auth logout </dev/null >/dev/null 2>&1; then echo "ai-signout: signed out of Claude"
    else echo "ai-signout: claude auth logout did not finish (offline?); the credential file is deleted anyway"; fi
fi

if [[ -e .claude/.credentials.json || -L .claude/.credentials.json ]]; then
    rm -f -- .claude/.credentials.json && echo "ai-signout: deleted ~/.claude/.credentials.json"
fi

# A regular file only: a link is not followed, and nothing else is touched.
if [[ -f .claude.json && ! -L .claude.json ]] && grep -q '"oauthAccount"' .claude.json 2>/dev/null; then
    # -I: no user site-packages, no PYTHON* variables and not the home
    # folder on sys.path (python3 - would import ~/json.py) (Janus N-L1).
    if python3 -I - .claude.json <<'PY' 2>/dev/null
import json, os, sys, tempfile
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
if not isinstance(d, dict) or "oauthAccount" not in d:
    sys.exit(1)
del d["oauthAccount"]
mode = os.stat(p).st_mode & 0o7777
fd, tmp = tempfile.mkstemp(dir=".", prefix=".claude.json.")
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2)
os.chmod(tmp, mode)
os.replace(tmp, p)
PY
    then echo "ai-signout: removed the account block from ~/.claude.json"
    else echo "ai-signout: could not read ~/.claude.json; left as it is"; fi
fi

rec=.local/state/invictus/collegium/gh-login
if [[ -f "$rec" ]]; then
    if command -v "$GH" >/dev/null 2>&1; then
        timeout 10 "$GH" auth logout --hostname github.com </dev/null >/dev/null 2>&1 \
            && echo "ai-signout: signed gh out (Collegium had signed it in)"
    fi
    rm -f -- "$rec"
fi
exit 0
