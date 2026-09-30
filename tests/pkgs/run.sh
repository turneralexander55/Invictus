#!/usr/bin/env bash
# ------------------------------------------------------------
# Tests for pkgs/. Needs bash and gpg; runs without makepkg.
#
#   tests/pkgs/run.sh
#
# 1. Every PKGBUILD parses and names itself after its folder.
# 2. The meta packages carry the design 1.2 fixes.
# 3. invictus-keyring: build() derives the trusted fingerprint from
#    the public key; check() refuses the placeholder and any private
#    key. Uses a throwaway key made in a temp dir and deleted after.
# ------------------------------------------------------------
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
ok()   { echo "ok    $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

# Print one field of a PKGBUILD (arrays one item per line).
field() {
    bash -c 'source "$1" >/dev/null; declare -n v="$2"; printf "%s\n" "${v[@]}"' _ "$1" "$2"
}

# ---- 1. every PKGBUILD -----------------------------------------------------
echo "== PKGBUILDs"
n=0
while IFS= read -r pb; do
    dir="$(basename "$(dirname "$pb")")"
    n=$((n + 1))
    if ! bash -n "$pb" 2>"$TMP/err"; then bad "$pb: $(cat "$TMP/err")"; continue; fi
    name="$(field "$pb" pkgname)"
    [[ "$name" == "$dir" ]] || bad "$pb: pkgname '$name' is not the folder name '$dir'"
    [[ -n "$(field "$pb" pkgver)" && -n "$(field "$pb" pkgrel)" ]] || bad "$pb: no pkgver/pkgrel"
    [[ "$(field "$pb" arch)" == "any" ]] || bad "$pb: arch is not 'any'"
    bash -c 'source "$1"; declare -F package >/dev/null' _ "$pb" || bad "$pb: no package()"
done < <(find "$REPO/pkgs" -name PKGBUILD | sort)
[[ $n -ge 5 ]] || bad "found only $n PKGBUILDs"
[[ $fail == 0 ]] && ok "$n PKGBUILDs parse, named after their folders"
echo

# ---- 2. meta fixes (design 1.2) --------------------------------------------
echo "== meta packages"
m_fail=0
all_deps="$TMP/deps"
for pb in "$REPO"/pkgs/meta/*/PKGBUILD; do field "$pb" depends; done > "$all_deps"
grep -qx vscode "$all_deps" && { bad "vscode is not an Arch package (use code)"; m_fail=1; }
grep -qx mako "$all_deps"   && { bad "mako is listed; swaync is the notification daemon"; m_fail=1; }
for p in code xwaylandvideobridge discord steam brightnessctl playerctl jq invictus-keyring; do
    grep -qx "$p" "$all_deps" || { bad "$p missing from the metas"; m_fail=1; }
done
dupes="$(for pb in "$REPO"/pkgs/meta/*/PKGBUILD; do field "$pb" depends | sort | uniq -d; done)"
[[ -z "$dupes" ]] || { bad "listed twice in one meta: $dupes"; m_fail=1; }
[[ $m_fail == 0 ]] && ok "code not vscode, no mako, the missing deps added, no duplicates"
echo

# ---- 3. invictus-keyring -----------------------------------------------------
echo "== invictus-keyring"
KR="$REPO/pkgs/own/invictus-keyring"

# Run prepare, build and check the way makepkg would, in a copy.
run_keyring() {
    local asc="$1" src="$TMP/src"
    rm -rf "$src"; mkdir -p "$src"
    cp "$asc" "$src/invictus.gpg"
    cp "$KR/invictus-revoked" "$src/"
    ( cd "$src" && srcdir="$src" bash -c 'set -e; source "$1"; prepare; build; check' _ "$KR/PKGBUILD" ) >"$TMP/out" 2>&1
}

export GNUPGHOME="$TMP/keys"
install -dm700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key 'Invictus test key (throwaway)' ed25519 sign never
fpr="$(gpg --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')"
gpg --armor --export "$fpr" > "$TMP/public.asc"
gpg --batch --pinentry-mode loopback --passphrase '' --armor --export-secret-keys "$fpr" > "$TMP/secret.asc"
cat "$TMP/public.asc" "$TMP/secret.asc" > "$TMP/both.asc"
unset GNUPGHOME

k_fail=0
if run_keyring "$TMP/public.asc"; then
    if [[ "$(cat "$TMP/src/invictus-trusted")" == "$fpr:4:" ]]; then :; else
        bad "trusted file is '$(cat "$TMP/src/invictus-trusted")', want '$fpr:4:'"; k_fail=1
    fi
else
    bad "a real public key did not build: $(cat "$TMP/out")"; k_fail=1
fi
cp "$REPO/pkgs/own/invictus-keyring/invictus.gpg" "$TMP/placeholder.asc"
if grep -q INVICTUS-PLACEHOLDER "$TMP/placeholder.asc"; then
    if run_keyring "$TMP/placeholder.asc"; then bad "the placeholder built"; k_fail=1
    elif ! grep -q "still the placeholder" "$TMP/out"; then bad "placeholder refused without saying why: $(cat "$TMP/out")"; k_fail=1; fi
fi
if run_keyring "$TMP/secret.asc"; then bad "a private key built"; k_fail=1
elif ! grep -q "private key material" "$TMP/out"; then bad "private key refused without saying why: $(cat "$TMP/out")"; k_fail=1; fi
if run_keyring "$TMP/both.asc"; then bad "public + private key built"; k_fail=1; fi
echo "not a key" > "$TMP/junk.asc"
if run_keyring "$TMP/junk.asc"; then bad "a file with no key built"; k_fail=1; fi
if grep -q 'PRIVATE KEY' "$KR/invictus.gpg"; then bad "the committed invictus.gpg holds a private key"; k_fail=1; fi
[[ $k_fail == 0 ]] && ok "trusted fingerprint derived from the key; placeholder and private keys refused"
echo

if [[ $fail == 0 ]]; then echo "ALL PASSED"; else echo "SOME TESTS FAILED"; fi
exit $fail
