#!/usr/bin/env bash
# ------------------------------------------------------------
# End-to-end test of the one-command local build:
#
#   INVICTUS_SIGN_KEY=FPR scripts/build-repo.sh --in-container
#
# builds in a container with no key in it, hands the files back to the
# user, then signs and indexes on the host with the user's own key
# (docs/checklists/adopt.md step 4). Run as root in a throwaway Arch
# container:
#
#   podman run --rm -v "$PWD:/src:ro" archlinux:base-devel bash /src/tests/pkgs/e2e-container-sign.sh
#
# The container runtime is a stand-in `docker` on PATH: it runs the command
# as root on this machine with only the variables passed with -e (as docker
# does) and /src, /out mapped to the mounted folders. That tests
# build-repo.sh's side of the contract; the real runtime was run by hand
# (build notes). A probe package records the environment its PKGBUILD
# sees. Checks:
#   1. user alex, key in his own keyring: one command builds as "root",
#      every file ends up alex's, every package and the database are signed
#      with his key, and pacman (SigLevel Required) takes them;
#   2. the build step saw no signing variable, in all three flows (local
#      key; CI key with --in-container; CI key without a container);
#   3. with INVICTUS_SIGN_KEY and no repo-add on the host it stops before
#      building, and says why.
# Never run it on a real machine: it edits /etc/pacman.conf.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC="${1:-/src}"

fail=0 passed=0
ok()  { echo "ok    $1"; passed=$((passed + 1)); }
bad() { echo "FAIL  $1"; fail=1; }

pacman -Syu --noconfirm --needed sudo >/dev/null

WORK="$(mktemp -d)"
chmod 755 "$WORK"
cp -r "$SRC/." "$WORK/src"
rm -rf "$WORK/src/out" "$WORK/src/.git"
# Orchestration is under test, not the AUR builds: leave pkgs/aur out.
rm -rf "$WORK/src/pkgs/aur"
# The probe: its package() writes the environment the PKGBUILD sees.
PROBE_DIR="$WORK/probe"
install -dm1777 "$PROBE_DIR"
mkdir -p "$WORK/src/pkgs/own/zz-envprobe"
cat > "$WORK/src/pkgs/own/zz-envprobe/PKGBUILD" <<EOF
pkgname=zz-envprobe
pkgver=1
pkgrel=1
arch=('any')
license=('custom')
package() { env > "$PROBE_DIR/env-\$(date +%s%N)"; install -Dm644 /dev/null "\$pkgdir/usr/share/doc/zz-envprobe/probe"; }
EOF
chmod -R a+rX "$WORK/src"
probe_clean() { rm -f "$PROBE_DIR"/env-*; }
probe_saw_key() { cat "$PROBE_DIR"/env-* 2>/dev/null | grep -E 'INVICTUS_SIGNING|PRIVATE KEY|INVICTUS_SIGN_KEY' | cut -c1-40 || true; }
probe_ran() { compgen -G "$PROBE_DIR/env-*" >/dev/null; }

# ---- the stand-in runtime ------------------------------------------------------
SHIM="$WORK/shim"
mkdir -p "$SHIM"
RUNLOG="$WORK/runtime.log"
: > "$RUNLOG"; chmod 666 "$RUNLOG"
cat > "$SHIM/docker" <<'EOF'
#!/usr/bin/env bash
# docker run --rm -v A:/src:ro -v B:/out [-e VAR]... [flags] IMAGE bash -c CMD _ ARGS...
set -euo pipefail
[[ "$1" == run ]] || { echo "shim: only 'run'" >&2; exit 2; }
shift
src="" out="" envs=() image=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rm) shift ;;
        -v) case "$2" in *:/src:ro) src="${2%:/src:ro}" ;; *:/out) out="${2%:/out}" ;; *) echo "shim: mount $2" >&2; exit 2 ;; esac; shift 2 ;;
        -e) envs+=("$2"); shift 2 ;;
        --network) shift 2 ;;
        -*) echo "shim: flag $1" >&2; exit 2 ;;
        *) image="$1"; shift; break ;;
    esac
done
[[ "$1 $2" == "bash -c" ]] || { echo "shim: want bash -c" >&2; exit 2; }
cmd="$3"; shift 3
echo "run image=$image env=${envs[*]:-} args=$*" >> "$RUNLOG"
# Only the -e variables that are set reach the "container", as with docker.
pass=(PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=/root)
for v in "${envs[@]}"; do [[ -n "${!v+x}" ]] && pass+=("$v=${!v}"); done
cmd="${cmd//\/src/$src}"; cmd="${cmd//\/out/$out}"
args=()
for a in "$@"; do a="${a//\/src/$src}"; args+=("${a//\/out/$out}"); done
exec sudo -n env -i "${pass[@]}" bash -c "$cmd" "${args[@]}"
EOF
sed -i "s|\$RUNLOG|$RUNLOG|" "$SHIM/docker"
chmod 755 "$SHIM/docker"
BUILD_REPO="$WORK/src/scripts/build-repo.sh"

# ---- 1. alex: his key, one command ------------------------------------------------
useradd -m alex
echo 'alex ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/alex    # the stand-in runtime runs as root, like docker
as_alex() { sudo -u alex -H env PATH="$SHIM:/usr/local/bin:/usr/bin" "$@"; }
as_alex gpg --batch --quiet --passphrase '' --quick-gen-key 'Alex test key (throwaway)' ed25519 sign 1d
FPR="$(as_alex gpg --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')"
as_alex gpg --armor --export "$FPR" > "$WORK/src/pkgs/own/invictus-keyring/invictus.gpg"
OUT=/home/alex/repo
probe_clean
if as_alex env INVICTUS_SIGN_KEY="$FPR" bash "$BUILD_REPO" --in-container --no-pinned --out "$OUT" > "$WORK/a.log" 2>&1; then
    ok "one command as alex: exit 0"
else
    bad "one command as alex failed: $(tail -8 "$WORK/a.log")"
fi
if ! { grep -q "Building in .* (no signing key in there)" "$WORK/a.log" && grep -q "Signing and indexing on this machine" "$WORK/a.log"; }; then
    bad "a.log does not show build-in-container then sign-here: $(grep '==>' "$WORK/a.log" | head -5)"
fi
[[ "$(grep -c '^run ' "$RUNLOG")" == 1 ]] || bad "expected one container run, got: $(cat "$RUNLOG")"
grep -q 'args=--no-container --build-only --out /out --no-pinned' "$RUNLOG" || bad "container args: $(cat "$RUNLOG")"
not_alex="$(find "$OUT" ! -user alex | head -3)"
if [[ -z "$not_alex" && -n "$(ls "$OUT")" ]]; then ok "every file in the repo belongs to alex (the container's root handed them back)"
else bad "files not alex's: $not_alex"; fi
nsig=0 nbad=0
for p in "$OUT"/*.pkg.tar.zst; do
    nsig=$((nsig + 1))
    as_alex gpg --batch --verify "$p.sig" "$p" 2>/dev/null || { nbad=$((nbad + 1)); echo "  bad signature: $p"; }
done
as_alex gpg --batch --verify "$OUT/invictus-testing.db.sig" "$OUT/invictus-testing.db" 2>/dev/null || nbad=$((nbad + 1))
if [[ $nsig -ge 5 && $nbad == 0 ]]; then ok "$nsig packages and the database signed with alex's key"
else bad "$nsig packages, $nbad bad or missing signatures"; fi
if probe_ran && [[ -z "$(probe_saw_key)" ]]; then ok "local key: the build step saw no signing variable"
else bad "local key: probe did not run, or saw: $(probe_saw_key)"; fi

# pacman takes the repo with signatures required
pacman-key --init >/dev/null 2>&1 || true
as_alex gpg --armor --export "$FPR" > "$WORK/alex.asc"
pacman-key --add "$WORK/alex.asc" >/dev/null 2>&1
pacman-key --lsign-key "$FPR" >/dev/null 2>&1
cat >> /etc/pacman.conf <<EOF

[invictus-testing]
SigLevel = Required DatabaseRequired
Server = file://$OUT
EOF
chmod 755 /home/alex
if pacman -Sy >/dev/null 2>&1 && pacman -S --noconfirm invictus-keyring > "$WORK/install.log" 2>&1; then
    ok "pacman installs invictus-keyring from alex's repo (SigLevel Required)"
else
    bad "install from alex's repo: $(tail -4 "$WORK/install.log")"
fi

# ---- 2. CI key, with and without a container --------------------------------------
PASS="e2e-$(date +%s%N)"
export GNUPGHOME="$WORK/cikeys"
install -dm700 "$GNUPGHOME"
gpg --batch --quiet --pinentry-mode loopback --passphrase "$PASS" --quick-gen-key 'CI test key (throwaway)' ed25519 sign 1d
CIFPR="$(gpg --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')"
SECRET="$(gpg --batch --pinentry-mode loopback --passphrase "$PASS" --armor --export-secret-keys "$CIFPR")"
gpgconf --kill gpg-agent
for mode in --in-container --no-container; do
    out="$WORK/ci-repo$mode"
    mkdir -p "$out"
    probe_clean
    : > "$RUNLOG"
    if INVICTUS_SIGNING_KEY="$SECRET" INVICTUS_SIGNING_PASSPHRASE="$PASS" PATH="$SHIM:$PATH" \
        bash "$BUILD_REPO" "$mode" --no-pinned --out "$out" > "$WORK/ci$mode.log" 2>&1; then
        good=true
        for p in "$out"/*.pkg.tar.zst; do gpg --batch --verify "$p.sig" "$p" 2>/dev/null || good=false; done
        if $good; then ok "CI key $mode: built and signed"; else bad "CI key $mode: a signature does not verify"; fi
    else
        bad "CI key $mode failed: $(tail -5 "$WORK/ci$mode.log")"
    fi
    if probe_ran && [[ -z "$(probe_saw_key)" ]]; then ok "CI key $mode: the build step saw no signing variable"
    else bad "CI key $mode: probe did not run, or saw: $(probe_saw_key)"; fi
    if [[ "$mode" == --in-container ]] && grep -q 'INVICTUS_SIGNING' "$RUNLOG"; then
        bad "CI key: a container was handed the signing variables: $(cat "$RUNLOG")"
    fi
done
unset GNUPGHOME

# ---- 3. own key, no repo-add here: stop before building ------------------------------
NOREPO="$WORK/norepoadd"
mkdir -p "$NOREPO"
for f in /usr/bin/*; do [[ "$(basename "$f")" == repo-add ]] || ln -s "$f" "$NOREPO/"; done
: > "$RUNLOG"
rc=0
as_alex env PATH="$SHIM:$NOREPO" INVICTUS_SIGN_KEY="$FPR" bash "$BUILD_REPO" --in-container --no-pinned --out /home/alex/repo2 > "$WORK/c.log" 2>&1 || rc=$?
if [[ $rc == 2 ]] && grep -q "no repo-add" "$WORK/c.log" && [[ ! -s "$RUNLOG" ]]; then
    ok "own key and no repo-add here: stops before building, says why"
else
    bad "no repo-add: rc $rc, runs: $(wc -l < "$RUNLOG"), $(tail -2 "$WORK/c.log")"
fi

echo
if [[ $fail == 0 ]]; then echo "ALL PASSED ($passed checks)"; else echo "SOME TESTS FAILED ($passed passed)"; fi
exit $fail
