#!/usr/bin/env bash
# ------------------------------------------------------------
# iso/secrets-scan.sh ROOT: fail if the image's file system (the mounted or
# extracted airootfs.sfs) holds anything secret (design S1, test T8: "The
# ISO and the repo contain no credential, key, token or password").
#
# Checks:
#  1. pacman's keyring folder is empty. A keyring built into the image
#     would give every install the same local master key; the live system
#     makes its own on a tmpfs and the installer runs pacman-key --init.
#  2. No GnuPG private keys anywhere: private-keys-v1.d contents, secring.gpg,
#     or an armoured "PGP PRIVATE KEY BLOCK" (the repo signing key must
#     never reach the ISO).
#  3. No SSH host or user private keys, no OpenSSH/RSA/EC private key blocks
#     outside known upstream test data.
#  4. No credentials: Claude Code's .credentials.json, .git-credentials,
#     .netrc, GitHub tokens (ghp_, gho_, ghs_, github_pat_), AWS access keys,
#     Anthropic API keys.
#  5. Every home folder in the image belongs to the live user.
# Prints each finding; exit 1 if any, 0 if clean.
# ------------------------------------------------------------
set -euo pipefail

ROOT="${1:?usage: secrets-scan.sh ROOT}"
[[ -d "$ROOT" ]] || { echo "secrets-scan: $ROOT is not a folder" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"
found=0
hit() { echo "SECRET: $*"; found=1; }

# Upstream test fixtures that ship sample keys on purpose.
ALLOW='^(usr/lib/python3[^/]*/test/|usr/lib/python3[^/]*/site-packages/[^/]+/tests?/|usr/share/doc/|usr/lib/go/src/|usr/share/gnupg/)'

rel() { local p="${1#"$ROOT"/}"; printf '%s' "$p"; }

# ---- 1. pacman keyring -----------------------------------------------------------
if [[ -d "$ROOT/etc/pacman.d/gnupg" ]] && [[ -n "$(ls -A "$ROOT/etc/pacman.d/gnupg" 2>/dev/null)" ]]; then
    hit "etc/pacman.d/gnupg is not empty (a shared pacman master key)"
fi

# ---- 2 and 3, 4 by file name -------------------------------------------------------
while IFS= read -r -d '' f; do
    r="$(rel "$f")"
    [[ "$r" =~ $ALLOW ]] && continue
    case "$r" in
        */private-keys-v1.d/*|*/secring.gpg|*/secring.kbx) hit "$r (GnuPG private key store)" ;;
        etc/ssh/ssh_host_*_key) hit "$r (SSH host private key)" ;;
        */.ssh/id_*) [[ "$r" == *.pub ]] || hit "$r (SSH private key)" ;;
        */.credentials.json|*/.git-credentials|*/.netrc) hit "$r (credentials file)" ;;
    esac
done < <(find "$ROOT" -xdev \( -type f -o -type l \) \( -path '*/private-keys-v1.d/*' -o -name 'secring.*' \
    -o -name 'ssh_host_*_key' -o -path '*/.ssh/id_*' -o -name '.credentials.json' -o -name '.git-credentials' \
    -o -name '.netrc' \) -print0)

# ---- 2, 3 and 4 by content (text files only) ------------------------------------
# A key counts only with a key body after its header (base64 on the next
# lines, after any armour headers): MIME tables and docs quote the header
# lines on their own (shared-mime-info, ImageMagick, gcr: all seen in the
# first full build).
header='-----BEGIN (PGP PRIVATE KEY BLOCK|OPENSSH PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|DSA PRIVATE KEY|PRIVATE KEY|ENCRYPTED PRIVATE KEY)-----'
tokens='gh[pos]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{60,}|AKIA[0-9A-Z]{16}|sk-ant-[A-Za-z0-9_-]{20,}'
has_key_body() {
    # Header, optional "Name: value" armour lines, optional blank line,
    # then a base64 line of 40+ characters.
    awk -v h="$header" '
        $0 ~ h { state = 1; next }
        state == 1 && /^[A-Za-z-]+: / { next }
        state == 1 && /^[[:space:]]*\r?$/ { next }
        # (no {40,}: mawk has no interval expressions)
        state == 1 && /^[A-Za-z0-9+\/=]+\r?$/ && length($0) >= 40 { found = 1; exit }
        { state = 0 }
        END { exit !found }' "$1"
}
while IFS= read -r f; do
    r="$(rel "$f")"
    if grep -qE -e "$tokens" "$f"; then
        [[ "$r" =~ $ALLOW ]] || hit "$r ($(grep -oE -e "$tokens" "$f" | head -n 1 | cut -c1-12)...)"
    fi
    if has_key_body "$f"; then
        if [[ "$r" =~ $ALLOW ]]; then
            # Even in test data, a PGP private key is never expected.
            grep -q 'BEGIN PGP PRIVATE KEY BLOCK' "$f" && hit "$r (PGP private key block)"
        else
            hit "$r ($(grep -oE -e "$header" "$f" | head -n 1))"
        fi
    fi
done < <(grep -rIlE --exclude-dir=proc --exclude-dir=sys --exclude-dir=dev -e "$header|$tokens" "$ROOT" 2>/dev/null || true)

# ---- 5. homes ----------------------------------------------------------------------
if [[ -d "$ROOT/home" ]]; then
    for h in "$ROOT"/home/*; do
        [[ -e "$h" ]] || continue
        [[ "$(basename "$h")" == liber ]] || hit "home/$(basename "$h") (a home folder other than the live user's)"
    done
fi

if ((found)); then
    echo "secrets-scan: FAILED"
    exit 1
fi
echo "secrets-scan: clean ($ROOT)"
