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
    { print }' /etc/pacman.conf > "$CONF"
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

# All of them in one transaction, as a machine with every non-AI set gets.
# AUR names our repo does not carry (paru) cannot resolve; leave them out.
if "${P[@]}" -Sp --print-format '%n' "${checked[@]}" > "$TMP/all" 2> "$TMP/all.err"; then
    for ai in $AI_PKGS; do
        grep -qx "$ai" "$TMP/all" && bad "installing every non-AI set pulls $ai"
    done
else
    bad "the non-AI sets do not resolve together: $(head -3 "$TMP/all.err")"
fi

if [[ $fail == 0 ]]; then
    ok "no-ai-in-base: ${#checked[@]} non-AI packages (${checked[*]}) pull none of: $AI_PKGS"
fi
exit $fail
