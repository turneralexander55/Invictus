#!/usr/bin/env bash
# ------------------------------------------------------------
# build-iso.sh: build the Invictus live and install ISO (design 2.1).
#
#   scripts/build-iso.sh                  dev build: builds every package into
#                                         a local unsigned repo
#   scripts/build-iso.sh --release        release build from a signed repo that
#                                         is already in --repo (downloaded from
#                                         the published release, or made with
#                                         build-repo.sh and your key)
#   options:
#     --channel testing|stable   repo the installed system uses (default
#                                testing: [invictus] stable is not published
#                                yet)
#     --out DIR                  where the ISO goes (default out/iso)
#     --repo DIR                 the package repo (default out/iso-repo);
#                                dev builds reuse packages already there
#                                (delete a package file to rebuild it),
#                                except iso/own-needed ones, always rebuilt
#     --skip-repo-build          dev: do not run build-repo.sh, use --repo as is
#     --fast                     zstd level 3 instead of 19 (dev only):
#                                quicker to build, bigger, boots the same
#     --version V                ISO version (default: today, YYYY.MM.DD)
#     --keep-work                keep the staged profile (prints where)
#     --check-size FILE          only run the size check below on FILE
#
# Size: the ISO is no longer squeezed under GitHub's 2 GiB release asset
# limit (Alex, 2026-10-08: "we can keep it less compressed and find a
# different way to host it"). A build of 2 GiB or more warns that it cannot
# be a GitHub release asset (iso.yml uploads it as a workflow artifact and
# refuses to attach it to a release); every build fails at 4 GiB, a bound
# that only a runaway build reaches (it is also archiso's copy-to-RAM
# limit and FAT32's file limit). The ISO is kept for inspection.
#
# Runs mkarchiso in a privileged Arch container (podman or docker, or
# RUNTIME=docker to pick; rootless podman cannot mount /dev for the chroot; IMAGE=
# overrides archlinux:base-devel, CONTAINER_ARGS= adds runtime flags such as
# "--network host"). Inside the container it:
#  1. dev: builds the package repo with scripts/build-repo.sh from a staged
#     copy of this checkout, with iso/own-needed/* added under pkgs/own
#     when pkgs/ does not have them yet (AUR packages are pinned in pkgs/aur);
#  2. builds the ISO from a staged copy of iso/ with the @...@ values filled
#     in (repo, signature level, channel, release file);
#  3. mounts the image's squashfs and runs iso/secrets-scan.sh on it; a
#     finding fails the build and no ISO is kept;
#  4. writes <iso>.sha256, a file list and the package list.
#
# Keys. This script never handles a private key.
#  - dev: the local repo is not signed and is read with SigLevel Never.
#    While pkgs/own/invictus-keyring still holds the placeholder, a throwaway
#    key's PUBLIC half goes in the staged keyring package so invictus-base
#    installs; its private half is deleted at once and signs nothing.
#    /etc/invictus/release then says keyring=dev-throwaway: such machines
#    cannot verify real updates (dev machines only).
#  - release: needs the real public key in invictus-keyring and a signed
#    repo in --repo (<repo>.db.sig). The public key is added to the build
#    container's pacman keyring and every package is verified (SigLevel
#    Required). Signing stays where Phase 0 put it: packages.yml's publish
#    job, or build-repo.sh on Alex's machine.
#
# JAVA_TOOL_OPTIONS, when set, is passed into the container; build-repo.sh
# hands it to the package builds (see there).
# ------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
IMAGE="${IMAGE:-docker.io/library/archlinux:base-devel}"

MODE=dev
CHANNEL=testing
OUT="$ROOT/out/iso"
REPO="$ROOT/out/iso-repo"
BUILD_REPO=true
COMPRESSION=zstd
VERSION="$(date -u +%Y.%m.%d)"
KEEP_WORK=false
PREPARE_ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) MODE=release; shift ;;
        --channel) CHANNEL="${2:?}"; shift 2 ;;
        --out) OUT="${2:?}"; shift 2 ;;
        --repo) REPO="${2:?}"; shift 2 ;;
        --skip-repo-build) BUILD_REPO=false; shift ;;
        --fast) COMPRESSION=zstd-fast; shift ;;
        --version) VERSION="${2:?}"; shift 2 ;;
        --keep-work) KEEP_WORK=true; shift ;;
        # Tests: stage the checkout and the profile into DIR, then stop.
        --prepare-only) PREPARE_ONLY="${2:?}"; shift 2 ;;
        --check-size) CHECK_SIZE_ONLY="${2:?}"; shift 2 ;;
        -h|--help) sed -n '2,63p' "$0"; exit 0 ;;
        *) echo "build-iso: unknown argument $1" >&2; exit 2 ;;
    esac
done

die() { echo "build-iso: $*" >&2; exit 1; }
warn() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::warning::$*"; else echo "WARNING: $*" >&2; fi
}

# check_iso_size FILE: fail at 4 GiB (a runaway build), warn at 2 GiB
# (GitHub's release asset limit: hosted elsewhere, decision 2026-10-08).
MAX_ISO_BYTES=4294967296
GITHUB_ASSET_BYTES=2147483648
check_iso_size() {
    local f="$1" size
    [[ -f "$f" ]] || die "no ISO at $f"
    size="$(stat -c %s "$f")"
    if ((size >= MAX_ISO_BYTES)); then
        die "$(basename "$f") is $size bytes, at or over the 4 GiB bound ($MAX_ISO_BYTES): something made the image grow. Check the package list (docs/packages.md)."
    fi
    if ((size >= GITHUB_ASSET_BYTES)); then
        warn "$(basename "$f") is $size bytes, 2 GiB or more: too big for a GitHub release asset. It is hosted elsewhere (team decision 2026-10-08); iso.yml keeps it as a workflow artifact and will not attach it to a release."
    fi
    echo "==> ISO size: $size bytes ($((size * 100 / GITHUB_ASSET_BYTES))% of GitHub's 2 GiB asset limit, bound 4 GiB)"
}
if [[ -n "${CHECK_SIZE_ONLY:-}" ]]; then
    check_iso_size "$CHECK_SIZE_ONLY"
    exit 0
fi

case "$CHANNEL" in
    testing) REPO_NAME=invictus-testing ;;
    stable) REPO_NAME=invictus ;;
    *) die "--channel must be testing or stable" ;;
esac
[[ "$VERSION" =~ ^[0-9A-Za-z._-]+$ ]] || die "bad --version"
if [[ "$MODE" == release ]]; then
    [[ "$COMPRESSION" == zstd ]] || die "--fast is for dev builds only"
    BUILD_REPO=false
    BUILD_REPO_NAME="$REPO_NAME"
else
    BUILD_REPO_NAME=invictus-testing   # what build-repo.sh makes
fi

if [[ -n "$PREPARE_ONLY" ]]; then
    WORK="$PREPARE_ONLY"
    mkdir -p "$WORK"
else
    RUNTIME="${RUNTIME:-$(command -v podman || command -v docker || true)}"
    [[ -n "$RUNTIME" ]] || die "needs podman or docker"
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/invictus-iso.XXXXXX")"
    if $KEEP_WORK; then echo "==> Work folder: $WORK"; else trap 'rm -rf "$WORK"' EXIT; fi
fi
mkdir -p "$OUT" "$REPO"
OUT="$(cd "$OUT" && pwd -P)"
REPO="$(cd "$REPO" && pwd -P)"
if [[ "$MODE" == release ]]; then
    [[ -f "$REPO/$BUILD_REPO_NAME.db" && -f "$REPO/$BUILD_REPO_NAME.db.sig" ]] \
        || die "--release needs a signed $BUILD_REPO_NAME repo in $REPO ($BUILD_REPO_NAME.db and .db.sig)"
fi

# ---- 1. stage the checkout ------------------------------------------------------
echo "==> Staging the checkout"
mkdir -p "$WORK/src"
tar -C "$ROOT" --exclude=./.git --exclude=./out -cf - . | tar -C "$WORK/src" -xf -
kind=own
{
    for d in "$ROOT/iso/$kind-needed"/*/; do
        [[ -f "$d/PKGBUILD" ]] || continue
        name="$(basename "$d")"
        if [[ -e "$ROOT/pkgs/$kind/$name" ]]; then
            echo "    pkgs/$kind/$name exists: using it, not iso/$kind-needed/$name"
        else
            cp -r "$d" "$WORK/src/pkgs/$kind/$name"
            echo "    added iso/$kind-needed/$name as pkgs/$kind/$name"
            # Dev builds: our own not-yet-published packages change without
            # pkgrel bumps, so always rebuild them.
            if [[ "$kind" == own && "$MODE" == dev && -z "$PREPARE_ONLY" ]]; then
                rm -f "$REPO/$name"-[0-9]*.pkg.tar.zst "$REPO/$name"-[0-9]*.pkg.tar.zst.sig
            fi
        fi
    done
}

KEYRING_KIND=real
keyfile="$WORK/src/pkgs/own/invictus-keyring/invictus.gpg"
if grep -q INVICTUS-PLACEHOLDER "$keyfile"; then
    [[ "$MODE" == dev ]] || die "--release needs the real public key in pkgs/own/invictus-keyring/invictus.gpg"
    command -v gpg >/dev/null || die "gpg is needed to make the dev keyring"
    KEYRING_KIND=dev-throwaway
    gh="$(mktemp -d)"
    GNUPGHOME="$gh" gpg --batch --quiet --passphrase '' --quick-gen-key \
        'Invictus DEV ISO throwaway key (never signs anything)' ed25519 sign 1d
    GNUPGHOME="$gh" gpg --batch --armor --export > "$keyfile"
    GNUPGHOME="$gh" gpgconf --kill gpg-agent 2>/dev/null || true
    rm -rf "$gh"
    grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$keyfile" || die "could not make the dev keyring"
    warn "Dev ISO: invictus-keyring holds a throwaway public key (the real key is not set up yet). Installed dev machines cannot verify real [invictus] updates."
fi

# ---- 2. stage the profile ---------------------------------------------------------
echo "==> Staging the ISO profile"
P="$WORK/profile"
rm -rf "$P"
mkdir -p "$P"
tar -C "$ROOT/iso" --exclude=./own-needed --exclude=./boot-branding \
    --exclude=./secrets-scan.sh --exclude=./live-only.txt --exclude=./keep.txt -cf - . | tar -C "$P" -xf -

if [[ "$MODE" == release ]]; then siglevel="Required DatabaseRequired"; else siglevel="Never"; fi
sed -i "s|@REPO_DIR@|/repo|g; s|@SIGLEVEL@|$siglevel|g; s|@BUILD_REPO_NAME@|$BUILD_REPO_NAME|g" "$P/pacman.conf"
sed -i "s|@REPO_NAME@|$REPO_NAME|g" "$P/airootfs/etc/pacman.conf"
commit="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then commit="$commit-dirty"; fi
mkdir -p "$P/airootfs/etc/invictus"
cat > "$P/airootfs/etc/invictus/iso-release" <<EOF
version=$VERSION
channel=$CHANNEL
build=$MODE
keyring=$KEYRING_KIND
commit=$commit
EOF
if grep -rn '@[A-Z_]*@' "$P/pacman.conf" "$P/airootfs/etc" >/dev/null; then
    die "unfilled @...@ value in the staged profile: $(grep -rln '@[A-Z_]*@' "$P/pacman.conf" "$P/airootfs/etc" | tr '\n' ' ')"
fi

if [[ -n "$PREPARE_ONLY" ]]; then
    echo "==> Prepared in $WORK (--prepare-only)"
    exit 0
fi

# ---- 3. build in the container ---------------------------------------------------
cat > "$WORK/inner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "==> [container] Installing archiso"
pacman -Syu --noconfirm --needed archiso squashfs-tools >/dev/null
if [[ "$BUILD_REPO" == true ]]; then
    echo "==> [container] Building the package repo"
    bash /work/src/scripts/build-repo.sh --no-container --out /repo
fi
[[ -f "/repo/$BUILD_REPO_NAME.db" ]] || { echo "No $BUILD_REPO_NAME.db in the repo folder." >&2; exit 1; }
if [[ "$MODE" == release ]]; then
    pacman-key --init >/dev/null
    pacman-key --add /work/src/pkgs/own/invictus-keyring/invictus.gpg
    fpr="$(gpg --with-colons --show-keys /work/src/pkgs/own/invictus-keyring/invictus.gpg | awk -F: '/^fpr:/ { print $10; exit }')"
    pacman-key --lsign-key "$fpr"
fi
echo "==> [container] mkarchiso"
rm -rf /tmp/archiso-work
INVICTUS_VERSION="$VERSION" INVICTUS_COMPRESSION="$COMPRESSION" \
    mkarchiso -v -w /tmp/archiso-work -o /tmp/iso-out /work/profile
iso="$(ls /tmp/iso-out/*.iso)"

echo "==> [container] Secrets scan of the squashfs"
sfs="/tmp/archiso-work/iso/arch/x86_64/airootfs.sfs"
mkdir -p /mnt/sfs
mount -t squashfs -o loop,ro "$sfs" /mnt/sfs
rc=0
bash /work/src/iso/secrets-scan.sh /mnt/sfs || rc=$?
umount /mnt/sfs
if ((rc != 0)); then
    echo "Secrets scan failed: the ISO is not kept." >&2
    exit 1
fi
cp "$iso" /out/
(cd /out && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256")
unsquashfs -lls "$sfs" | awk '{ print $1, $2, $6 }' > "/out/$(basename "$iso" .iso).files.txt" || true
cp /tmp/archiso-work/iso/arch/pkglist.x86_64.txt "/out/$(basename "$iso" .iso).packages.txt" 2>/dev/null || true
echo "==> [container] Done: /out/$(basename "$iso")"
EOF

read -ra extra <<< "${CONTAINER_ARGS:-}"
echo "==> Building in $IMAGE via $(basename "$RUNTIME") (mode: $MODE, channel: $CHANNEL, squashfs: $COMPRESSION)"
"$RUNTIME" run --rm --privileged \
    -v "$WORK:/work" -v "$REPO:/repo" -v "$OUT:/out" \
    -e MODE="$MODE" -e VERSION="$VERSION" -e COMPRESSION="$COMPRESSION" -e BUILD_REPO="$BUILD_REPO" \
    -e BUILD_REPO_NAME="$BUILD_REPO_NAME" -e GITHUB_ACTIONS \
    -e JAVA_TOOL_OPTIONS \
    "${extra[@]}" \
    "$IMAGE" bash /work/inner.sh

iso="$(find "$OUT" -maxdepth 1 -name "invictus-*.iso" -newer "$WORK/inner.sh" | head -n 1)"
echo "==> ISO: $iso ($(du -h "$iso" | cut -f1))"
check_iso_size "$iso"
echo "==> Packages: $(grep -c . "${iso%.iso}.packages.txt" 2>/dev/null || echo "?") (${iso%.iso}.packages.txt)"
