#!/usr/bin/env bash
# upstream-check.sh PKGBUILD: the .deb sha256 pinned in PKGBUILD must be
# listed for that version in Microsoft's signed apt index. Run by
# scripts/dev/bump-aur.sh after it recomputes checksums; needs curl and gpg.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PB="${1:-$HERE/PKGBUILD}"
REPO=https://packages.microsoft.com/repos/code
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GNUPGHOME="$T/gnupg"
install -dm700 "$GNUPGHOME"
gpg --batch --quiet --import "$HERE"/upstream/*.asc
ver="$(sed -n 's/^pkgver=//p' "$PB")"
sum="$(sed -n "s/^sha256sums_x86_64=('\([0-9a-f]\{64\}\)')$/\1/p" "$PB")"
[[ -n "$ver" && -n "$sum" ]] || { echo "upstream-check: no pkgver or sha256sums_x86_64 in $PB" >&2; exit 1; }
curl -sSfL -o "$T/InRelease" "$REPO/dists/stable/InRelease"
gpg --batch --status-fd 1 --output "$T/Release" --decrypt "$T/InRelease" 2>/dev/null | grep -q '^\[GNUPG:\] VALIDSIG' \
    || { echo "upstream-check: InRelease is not signed by the key in upstream/" >&2; exit 1; }
want="$(awk '$3 == "main/binary-amd64/Packages" && length($1) == 64 { print $1; exit }' "$T/Release")"
curl -sSfL -o "$T/Packages" "$REPO/dists/stable/main/binary-amd64/Packages"
[[ "$(sha256sum < "$T/Packages" | cut -d' ' -f1)" == "$want" ]] || { echo "upstream-check: Packages does not match the signed Release" >&2; exit 1; }
if awk -v v="$ver" -v s="$sum" '
    /^Package: / { pkg = $2 } /^Version: / { ver = $2 } /^SHA256: / { if (pkg == "code" && index(ver, v "-") == 1 && $2 == s) found = 1 }
    END { exit !found }' "$T/Packages"; then
    echo "upstream-check: code $ver sha256 $sum is in Microsoft's signed apt index"
else
    echo "upstream-check: code $ver with sha256 $sum is NOT in Microsoft's signed apt index" >&2
    exit 1
fi
