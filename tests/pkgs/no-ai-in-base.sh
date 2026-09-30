#!/usr/bin/env bash
# ------------------------------------------------------------
# no-ai-in-base (design-no-ai.md N5, NA3): no package outside the AI set
# depends on it, directly or transitively, in the BUILT repo, resolved by
# pacman against Arch's repos (tests/pkgs/run.sh checks the PKGBUILDs;
# this checks what machines actually get). Run as root in a throwaway Arch
# container with network:
#
#   docker run --rm --network host -v "$PWD:/src:ro" archlinux:base-devel \
#       bash /src/tests/pkgs/no-ai-in-base.sh /src/out/repo
#
# For every invictus-* package in the repo that is not an AI meta
# (tests/pkgs/lib/ai-set.sh), `pactree -s` must contain none of the AI set,
# and a full install of all of them together must pull none of it
# (pacman -Sp with every one as a target). CI runs it on every repo build,
# before publishing (.github/workflows/packages.yml), and e2e-arch.sh runs
# it on its repo.
# Arch's sync databases go into a throwaway --dbpath; the container's own
# are not touched.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
REPO_DIR="$(cd -- "${1:?usage: no-ai-in-base.sh REPO_DIR}" && pwd)"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/pkgs/lib/ai-set.sh
. "$HERE/lib/ai-set.sh"
[[ -f "$REPO_DIR/invictus-testing.db" ]] || { echo "No invictus-testing.db in $REPO_DIR: build the repo first." >&2; exit 2; }

fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

command -v pactree >/dev/null || pacman -Sy --noconfirm --needed pacman-contrib >/dev/null

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CONF="$TMP/pacman.conf"
# Our repo first, as on a real machine; unsigned here (only resolution is
# checked, nothing is installed).
awk -v repo="$REPO_DIR" '
    /^\[options\]/ { print; next }
    /^\[core\]/ && !done { printf "[invictus-testing]\nSigLevel = Never\nServer = file://%s\n\n", repo; done = 1 }
    { print }' /etc/pacman.conf | sed '/^DownloadUser/d' > "$CONF"
# (no DownloadUser: pacman's download user could not read a repo in a
# private temp folder or write this throwaway dbpath)
grep -qx '\[multilib\]' "$CONF" || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "$CONF"
DB="$TMP/db"
mkdir -p "$DB/sync" "$DB/local"
P=(pacman --config "$CONF" --dbpath "$DB" --logfile /dev/null)
"${P[@]}" -Sy >/dev/null

mapfile -t metas < <("${P[@]}" -Sl invictus-testing | awk '$2 ~ /^invictus-/ { print $2 }' | sort)
checked=()
for m in "${metas[@]}"; do
    [[ " $AI_METAS " == *" $m "* ]] && continue
    checked+=("$m")
    tree="$(pactree --config "$CONF" --dbpath "$DB" -s -u "$m" 2>/dev/null || true)"
    [[ -n "$tree" ]] || { bad "$m: pactree found nothing"; continue; }
    for ai in $AI_PKGS; do
        grep -qx "$ai" <<< "$tree" && bad "$m pulls $ai (AI set; design-no-ai.md N5)"
    done
done
[[ ${#checked[@]} -ge 8 ]] || bad "only ${#checked[@]} non-AI invictus packages in the repo: ${checked[*]}"

# All of them in one transaction, as a machine with every non-AI set gets
# (pacman picks providers here, which pactree does not). Names no repo has
# (the placeholder keyring is not built until the real key is in) are
# assumed installed and reported; an AI name is never assumed.
assume=() assumed=()
for try in 1 2; do
    if "${P[@]}" -Sp --print-format '%n' "${assume[@]}" "${checked[@]}" > "$TMP/all" 2> "$TMP/all.err"; then
        for ai in $AI_PKGS; do
            grep -qx "$ai" "$TMP/all" && bad "installing every non-AI set pulls $ai"
        done
        [[ ${#assumed[@]} -eq 0 ]] || echo "note  not in any repo, assumed installed: ${assumed[*]}"
        break
    fi
    # pacman prints the reasons (":: unable to satisfy ...") on stdout
    mapfile -t missing < <(cat "$TMP/all" "$TMP/all.err" | sed -n "s/.*unable to satisfy dependency '\([^'<>=]*\).*/\1/p" | sort -u)
    if [[ $try == 2 || ${#missing[@]} -eq 0 ]]; then
        bad "the non-AI sets do not resolve together: $(cat "$TMP/all" "$TMP/all.err" | grep -v '^$' | head -6 | tr '\n' ' ')"
        break
    fi
    for n in "${missing[@]}"; do
        if [[ " $AI_PKGS " == *" $n "* ]]; then bad "a non-AI set needs $n, which is in the AI set"; fi
        assume+=(--assume-installed "$n"); assumed+=("$n")
    done
done

if [[ $fail == 0 ]]; then
    ok "no-ai-in-base: ${#checked[@]} non-AI packages (${checked[*]}) pull none of: $AI_PKGS"
fi
exit $fail
