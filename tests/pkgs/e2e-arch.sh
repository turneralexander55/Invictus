#!/usr/bin/env bash
# ------------------------------------------------------------
# End-to-end repo test. Run as root in a throwaway Arch container:
#
#   podman run --rm -v "$PWD:/src:ro" archlinux:base-devel bash /src/tests/pkgs/e2e-arch.sh
#
# Makes a throwaway signing key (passphrase-protected, deleted with the
# container), swaps its public half into a copy of invictus-keyring,
# builds the repo with scripts/build-repo.sh (build step, then the sign
# step with the key passed the way CI passes it), serves it to pacman
# over file://, and checks that:
#   1. pacman with SigLevel = Required installs invictus-keyring;
#   2. its install hook ran pacman-key --populate, and the shipped
#      trusted file alone makes the key trusted;
#   3. a tampered package is refused;
#   4. a second run reuses unchanged packages byte for byte, and a
#      pkgrel bump rebuilds that package and drops the old file;
#   5. the sign step rejects a manifest entry that is a path;
#   6. no-ai-in-base (NA3) passes on the built repo.
# Never run it on a real machine: it edits /etc/pacman.conf.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC="${1:-/src}"

fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

pacman -Syu --noconfirm --needed >/dev/null

# A copy of the repo we can edit.
WORK="$(mktemp -d)"
cp -r "$SRC/." "$WORK/src"
rm -rf "$WORK/src/out"
# shellcheck source=tests/pkgs/lib/aur-heavy.sh
. "$SRC/tests/pkgs/lib/aur-heavy.sh"
stand_in_heavy_aur "$WORK/src"

# Throwaway key, as Alex will make the real one (docs/checklists/signing-key.md).
export GNUPGHOME="$WORK/keys"
install -dm700 "$GNUPGHOME"
PASS="e2e-$(date +%s%N)"
gpg --batch --quiet --pinentry-mode loopback --passphrase "$PASS" \
    --quick-gen-key 'Invictus e2e test key (throwaway)' ed25519 sign 1d
FPR="$(gpg --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')"
gpg --armor --export "$FPR" > "$WORK/src/pkgs/own/invictus-keyring/invictus.gpg"
SECRET="$(gpg --batch --pinentry-mode loopback --passphrase "$PASS" --armor --export-secret-keys "$FPR")"
gpgconf --kill gpg-agent
unset GNUPGHOME

OUT="$WORK/repo"
mkdir -p "$OUT"
bash "$WORK/src/scripts/build-repo.sh" --no-container --build-only --out "$OUT"
INVICTUS_SIGNING_KEY="$SECRET" INVICTUS_SIGNING_PASSPHRASE="$PASS" \
    bash "$WORK/src/scripts/build-repo.sh" --no-container --repo-only --out "$OUT"

# NA3 on the built repo: no non-AI set pulls the AI set.
if bash "$SRC/tests/pkgs/no-ai-in-base.sh" "$OUT" > "$WORK/noai.log" 2>&1; then
    ok "$(grep '^ok' "$WORK/noai.log" | cut -c7-)"
else
    bad "no-ai-in-base: $(grep FAIL "$WORK/noai.log" | head -3)"
fi
for f in invictus-testing.db invictus-testing.db.sig invictus-testing.files; do
    [[ -f "$OUT/$f" && ! -L "$OUT/$f" ]] || bad "$f missing or a symlink"
done
n_pkgs=$(find "$OUT" -name '*.pkg.tar.zst' | wc -l)
n_sigs=$(find "$OUT" -name '*.pkg.tar.zst.sig' | wc -l)
[[ $n_pkgs -ge 5 && $n_pkgs == "$n_sigs" ]] || bad "$n_pkgs packages, $n_sigs signatures"

# Bootstrap trust by hand, as a new machine does before the keyring exists.
pacman-key --init >/dev/null 2>&1 || true
chmod -R a+rX "$WORK"
cat >> /etc/pacman.conf <<EOF

[invictus-testing]
SigLevel = Required DatabaseRequired
Server = file://$OUT
EOF
cp "$WORK/src/pkgs/own/invictus-keyring/invictus.gpg" "$WORK/pub.asc"
pacman-key --add "$WORK/pub.asc" >/dev/null 2>&1
pacman-key --lsign-key "$FPR" >/dev/null 2>&1
pacman -Sy >/dev/null

# 1. install with signatures required
if pacman -S --noconfirm invictus-keyring >"$WORK/install.log" 2>&1; then
    ok "invictus-keyring installs from the signed repo (SigLevel Required)"
else
    bad "install failed: $(tail -5 "$WORK/install.log")"
fi

# 2. the hook populated the key; the trusted file works on its own
grep -q "Appending keys from invictus.gpg" "$WORK/install.log" || bad "install hook did not run pacman-key --populate"
pacman-key --delete "$FPR" >/dev/null 2>&1
pacman-key --populate invictus >/dev/null 2>&1
if grep -qx "$FPR:4:" /usr/share/pacman/keyrings/invictus-trusted \
    && pacman-key --list-keys "$FPR" 2>/dev/null | grep -q '\[ *full *\]\|\[ *ultimate *\]'; then
    ok "install hook populates the key; the shipped trusted file makes it trusted"
else
    bad "key not trusted from the package alone: $(pacman-key --list-keys "$FPR" 2>&1 | head -3)"
fi

# 3. tampering is caught
victim="$(find "$OUT" -name 'invictus-dev-*.pkg.tar.zst' | head -1)"
# change one byte in place: same size, so only the checksum and the
# signature can catch it (an appended byte fails pacman's size check first)
printf 'x' | dd of="$victim" bs=1 seek=200 conv=notrunc status=none
rm -f /var/cache/pacman/pkg/invictus-dev-*
# -dd: fetch only this package, so the refusal can only be its signature
if pacman -Sw --noconfirm -dd invictus-dev >"$WORK/tamper.log" 2>&1; then
    bad "a tampered package was accepted"
elif grep -qiE 'invalid or corrupted package|signature .* is invalid' "$WORK/tamper.log"; then
    ok "a tampered package is refused (bad signature)"
else
    bad "tampered package refused for another reason: $(tail -3 "$WORK/tamper.log")"
fi

# 4. reuse and rebuild
N="$(find "$WORK/src/pkgs" -name PKGBUILD | wc -l)"
before="$(sha256sum "$OUT"/invictus-base-*.pkg.tar.zst)"
bash "$WORK/src/scripts/build-repo.sh" --no-container --build-only --out "$OUT" > "$WORK/rebuild.log" 2>&1 \
    || bad "second build failed: $(tail -5 "$WORK/rebuild.log")"
grep -q "0 built, $N reused" "$WORK/rebuild.log" || bad "second run did not reuse: $(tail -1 "$WORK/rebuild.log")"
[[ "$(sha256sum "$OUT"/invictus-base-*.pkg.tar.zst)" == "$before" ]] || bad "reused package changed"
DEV_PB="$WORK/src/pkgs/meta/invictus-dev/PKGBUILD"
DEV_VER="$(bash -c 'source "$1"; echo "$pkgver"' _ "$DEV_PB")"
DEV_REL="$(bash -c 'source "$1"; echo "$pkgrel"' _ "$DEV_PB")"
sed -i "s/^pkgrel=$DEV_REL\$/pkgrel=$((DEV_REL + 1))/" "$DEV_PB"
bash "$WORK/src/scripts/build-repo.sh" --no-container --build-only --out "$OUT" > "$WORK/rebuild.log" 2>&1 \
    || bad "build after the pkgrel bump failed: $(tail -5 "$WORK/rebuild.log")"
INVICTUS_SIGNING_KEY="$SECRET" INVICTUS_SIGNING_PASSPHRASE="$PASS" \
    bash "$WORK/src/scripts/build-repo.sh" --no-container --repo-only --out "$OUT" >> "$WORK/rebuild.log" 2>&1 \
    || bad "sign step after the pkgrel bump failed: $(tail -5 "$WORK/rebuild.log")"
if grep -q "1 built, $((N - 1)) reused" "$WORK/rebuild.log" && [[ -f "$OUT/invictus-dev-$DEV_VER-$((DEV_REL + 1))-any.pkg.tar.zst.sig" ]] \
    && ! ls "$OUT"/invictus-dev-"$DEV_VER"-"$DEV_REL"-* >/dev/null 2>&1; then
    ok "unchanged packages reused byte for byte; a pkgrel bump rebuilds, signs and drops the old file"
else
    bad "rebuild: $(grep -E 'built|Dropping' "$WORK/rebuild.log")"
fi

# 5. the sign step refuses a manifest with a path in it
cp -r "$OUT" "$WORK/evil"
find "$WORK/evil" -maxdepth 1 -name "*.pkg.tar.zst" -printf "%f\n" > "$WORK/evil/invictus-manifest.txt"
echo "../../etc/x.pkg.tar.zst" >> "$WORK/evil/invictus-manifest.txt"
if bash "$WORK/src/scripts/build-repo.sh" --no-container --repo-only --out "$WORK/evil" > "$WORK/evil.log" 2>&1; then
    bad "a manifest entry with a path was accepted"
elif grep -q "Bad package name in manifest" "$WORK/evil.log"; then
    ok "the sign step refuses manifest entries that are not plain package names"
else
    bad "evil manifest failed for another reason: $(tail -2 "$WORK/evil.log")"
fi

[[ $fail == 0 ]] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit $fail
