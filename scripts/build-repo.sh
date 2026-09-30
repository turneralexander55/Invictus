#!/usr/bin/env bash
# ------------------------------------------------------------
# build-repo.sh: build pkgs/ into the [invictus-testing] pacman repo.
#
#   scripts/build-repo.sh                 build + index into out/repo
#   scripts/build-repo.sh --build-only    build packages, no repo db
#   scripts/build-repo.sh --repo-only     sign (if a key is given) + repo-add
#   scripts/build-repo.sh --out DIR       output folder (default out/repo)
#   scripts/build-repo.sh --no-pinned     leave out the pinned hypr* set
#                                         (offline builds; not for publishing)
#   scripts/build-repo.sh --only NAME     build just this PKGBUILD (repeat for
#                                         more); implies --build-only, writes
#                                         no manifest (CI's aur-pins job)
#   scripts/build-repo.sh --in-container  build in archlinux:base-devel via
#                                         podman or docker (the default when
#                                         makepkg is not installed), then
#                                         sign and index on this machine
#
# Build and index are separate steps so package code (PKGBUILDs) never runs
# where the signing key is: CI builds in one job and signs in another that
# runs no package code (.github/workflows/packages.yml). With
# --in-container, one command does both: the container builds with no key
# and no signing variables, its files are handed back to you (not root),
# then the repo step runs here with your key (repo-add comes with pacman,
# so this machine must be Arch). Where this machine has no repo-add (CI's
# Ubuntu runners) the repo step runs in a second container, which only
# gets the CI key variables. Without a container both steps run here; the
# signing variables are kept out of the build step's environment.
#
# The build step also writes invictus-manifest.txt (the package files the
# PKGBUILDs produce). The repo step reads it when present instead of
# sourcing PKGBUILDs, so no package code runs while the key is loaded.
#
# Reuse: packages already in the output folder at the version a PKGBUILD
# would produce are kept, not rebuilt. CI downloads the published set first,
# so an unchanged package keeps its bytes and signature (a rebuild under the
# same file name would clash with copies in pacman caches). Bump pkgrel to
# publish a change.
#
# PKGBUILDs in pkgs/own and pkgs/meta package files from elsewhere in
# the repo (scripts/, config/, theme/, assets/): the whole checkout is
# staged, and each PKGBUILD finds the root at $startdir/../../..
# Bump pkgrel whenever one of those files changes, or the old package
# is reused.
#
# The pinned hypr* set (pkgs/pinned/hypr.lock) is fetched from the Arch
# archive and verified by scripts/fetch-pinned.sh in the build step.
#
# Repo file names only use [A-Za-z0-9._-] (scripts/lib/repo-names.sh):
# GitHub renames release assets with other characters, such as the ':'
# of an epoch.
#
# Size: GitHub refuses release assets of 2 GiB or more, so the build step
# fails on any package that big (proton-ge-custom-bin is about 600 MB).
#
# JAVA_TOOL_OPTIONS, when set, reaches the package builds (the limine AUR
# packages build with a bundled JDK that ignores the system CA store; behind
# a TLS-inspecting proxy point it at /etc/ssl/certs/java/cacerts).
#
# Signing (repo step): set INVICTUS_SIGN_KEY to a key id in your own gpg
# keyring (local), or INVICTUS_SIGNING_KEY to an ASCII-armoured private key
# plus INVICTUS_SIGNING_PASSPHRASE (CI secrets; imported into a temp
# keyring that is deleted on exit). With neither, the repo is built
# unsigned and a warning says so.
# ------------------------------------------------------------
set -euo pipefail

REPO_NAME="invictus-testing"
IMAGE="${IMAGE:-docker.io/library/archlinux:base-devel}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OUT="$ROOT/out/repo"
DO_BUILD=true
DO_REPO=true
CONTAINER=auto
PINNED=true
ONLY=()
# GitHub's limit is "under 2 GiB" per release asset.
MAX_ASSET_BYTES=$((2 * 1024 * 1024 * 1024 - 1))

# The CI signing key must never be visible to package code: keep it in this
# shell only, not in the environment of anything it starts (makepkg,
# PKGBUILDs). The repo step passes it to gpg explicitly.
SIGNING_KEY_MATERIAL="${INVICTUS_SIGNING_KEY:-}"
SIGNING_PASSPHRASE="${INVICTUS_SIGNING_PASSPHRASE:-}"
unset INVICTUS_SIGNING_KEY INVICTUS_SIGNING_PASSPHRASE

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2 ;;
        --build-only) DO_REPO=false; shift ;;
        --repo-only) DO_BUILD=false; shift ;;
        --in-container) CONTAINER=yes; shift ;;
        --no-container) CONTAINER=no; shift ;;
        --no-pinned) PINNED=false; shift ;;
        --only) ONLY+=("${2:?--only needs a package name}"); DO_REPO=false; shift 2 ;;
        -h|--help) sed -n '2,70p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
if [[ ${#ONLY[@]} -gt 0 ]] && ! $DO_BUILD; then echo "--only builds; it cannot go with --repo-only." >&2; exit 2; fi
for n in "${ONLY[@]}"; do
    compgen -G "$ROOT/pkgs/*/$n/PKGBUILD" >/dev/null || { echo "--only $n: no pkgs/*/$n/PKGBUILD" >&2; exit 2; }
done
mkdir -p "$OUT"

warn() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::warning::$*"; else echo "WARNING: $*" >&2; fi
}

# ---- build in an Arch container, sign and index here ---------------------------
if [[ "$CONTAINER" == yes || ( "$CONTAINER" == auto && ! -x /usr/bin/makepkg ) ]]; then
    RUNTIME="$(command -v podman || command -v docker || true)"
    [[ -n "$RUNTIME" ]] || { echo "Need makepkg (Arch) or podman/docker." >&2; exit 2; }
    # Where the repo step runs: here when repo-add is here, else in a second
    # container. A key in your own keyring (INVICTUS_SIGN_KEY) can only sign
    # here, so check before a long build.
    REPO_HERE=false
    command -v repo-add >/dev/null && REPO_HERE=true
    if $DO_REPO && ! $REPO_HERE && [[ -n "${INVICTUS_SIGN_KEY:-}" ]]; then
        echo "INVICTUS_SIGN_KEY signs with your own gpg keyring, so the repo step runs on this machine, and it has no repo-add (pacman). Run this on Arch, or build with --build-only and sign where pacman is." >&2
        exit 2
    fi
    # CONTAINER_ARGS: extra runtime flags, split on spaces (e.g. "--network host").
    read -ra extra <<< "${CONTAINER_ARGS:-}"
    # Runs build-repo.sh in a fresh container with the checkout read-only
    # and $OUT as /out, then gives /out's files to whoever owns /out (you,
    # as the container sees it: docker's root would otherwise leave
    # root-owned files; rootless podman maps its root to you already).
    in_container() {
        "$RUNTIME" run --rm \
            -v "$ROOT:/src:ro" -v "$OUT:/out" \
            "${extra[@]}" "$@"
    }
    # shellcheck disable=SC2016 # expanded by the container's bash
    INNER='pacman -Syu --noconfirm --needed >/dev/null && bash /src/scripts/build-repo.sh "$@"; rc=$?; chown -R "$(stat -c %u:%g /out)" /out; exit $rc'
    if $DO_BUILD; then
        args=(--no-container --build-only --out /out)
        $PINNED || args+=(--no-pinned)
        for n in "${ONLY[@]}"; do args+=(--only "$n"); done
        env_args=(-e GITHUB_ACTIONS)
        if [[ -n "${JAVA_TOOL_OPTIONS:-}" ]]; then env_args+=(-e JAVA_TOOL_OPTIONS); fi
        echo "==> Building in $IMAGE via $(basename "$RUNTIME") (no signing key in there)"
        in_container "${env_args[@]}" "$IMAGE" bash -c "$INNER" _ "${args[@]}"
    fi
    if $DO_REPO; then
        if $REPO_HERE; then
            echo "==> Signing and indexing on this machine"
            INVICTUS_SIGNING_KEY="$SIGNING_KEY_MATERIAL" INVICTUS_SIGNING_PASSPHRASE="$SIGNING_PASSPHRASE" \
                exec bash "$SCRIPT_DIR/build-repo.sh" --no-container --repo-only --out "$OUT"
        fi
        echo "==> Signing and indexing in a second $IMAGE container (no repo-add here)"
        INVICTUS_SIGNING_KEY="$SIGNING_KEY_MATERIAL" INVICTUS_SIGNING_PASSPHRASE="$SIGNING_PASSPHRASE" \
            in_container -e INVICTUS_SIGNING_KEY -e INVICTUS_SIGNING_PASSPHRASE -e GITHUB_ACTIONS \
            "$IMAGE" bash -c "$INNER" _ --no-container --repo-only --out /out
    fi
    exit 0
fi

command -v makepkg >/dev/null || { echo "makepkg not found" >&2; exit 2; }

# shellcheck source=scripts/lib/repo-names.sh
. "$SCRIPT_DIR/lib/repo-names.sh"

# makepkg refuses to run as root; containers start as root.
BUILD_USER=""
if [[ $EUID -eq 0 ]]; then
    id builder >/dev/null 2>&1 || useradd -m builder
    echo "builder ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/builder
    if [[ -n "${JAVA_TOOL_OPTIONS:-}" ]]; then
        echo 'Defaults env_keep += "JAVA_TOOL_OPTIONS"' >> /etc/sudoers.d/builder
    fi
    BUILD_USER=builder
fi
as_builder() {
    if [[ -n "$BUILD_USER" ]]; then sudo -u "$BUILD_USER" -H "$@"; else "$@"; fi
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
# Stage the whole checkout (not .git, not build output): own packages
# install files from scripts/, config/, theme/ and assets/.
mkdir -p "$WORK/src"
tar -C "$ROOT" --exclude=./.git --exclude=./out -cf - . | tar -C "$WORK/src" -xf -
PKGS="$WORK/src/pkgs"
# makepkg writes packages here (as the build user); we copy them to $OUT.
STAGE="$WORK/stage"
mkdir -p "$STAGE"
[[ -z "$BUILD_USER" ]] || chown -R "$BUILD_USER" "$WORK"
chmod 755 "$WORK"

is_placeholder_keyring() {
    [[ "$(basename "$1")" == invictus-keyring ]] && grep -q INVICTUS-PLACEHOLDER "$1/invictus.gpg"
}

# Package file names (no path) one PKGBUILD produces, as makepkg names
# them; fails if there are none.
package_files() {
    local list
    list="$(cd "$1" && as_builder env PKGDEST="$STAGE" makepkg --packagelist)" || return 1
    [[ -n "$list" ]] || return 1
    # Debug packages are listed whenever makepkg.conf enables debug, but only
    # exist for binaries with symbols. We do not publish them.
    printf '%s\n' "$list" | xargs -n1 basename | grep -v -- '-debug-[^-]*-[^-]*-[^-]*\.pkg\.tar'
}

# Repo file names for every PKGBUILD that is not skipped, plus the
# pinned set.
expected_files() {
    local dir f files
    for dir in "$PKGS"/*/*/; do
        dir="${dir%/}"
        [[ -f "$dir/PKGBUILD" ]] || continue
        is_placeholder_keyring "$dir" && continue
        files="$(package_files "$dir")" || { echo "makepkg --packagelist failed in $dir" >&2; return 1; }
        for f in $files; do repo_file_name "$f"; echo; done
    done
    if $PINNED; then bash "$SCRIPT_DIR/fetch-pinned.sh" --list; fi
}

# ---- build ----------------------------------------------------------------
if $DO_BUILD; then
    built=0 reused=0 skipped=0
    for dir in "$PKGS"/*/*/; do
        dir="${dir%/}"
        [[ -f "$dir/PKGBUILD" ]] || continue
        name="$(basename "$dir")"
        if [[ ${#ONLY[@]} -gt 0 && " ${ONLY[*]} " != *" $name "* ]]; then continue; fi
        if is_placeholder_keyring "$dir"; then
            warn "Skipping invictus-keyring: invictus.gpg is still the placeholder (docs/checklists/signing-key.md)."
            skipped=$((skipped + 1)); continue
        fi
        files="$(package_files "$dir")" || { echo "makepkg --packagelist failed for $name" >&2; exit 1; }
        have=true
        for f in $files; do [[ -f "$OUT/$(repo_file_name "$f")" ]] || have=false; done
        if $have; then
            echo "==> $name: $(head -1 <<< "$files") already built, reusing (bump pkgrel to rebuild)"
            reused=$((reused + 1)); continue
        fi
        echo "==> Building $name"
        # Our own and meta packages build nothing and depend on each other and
        # on AUR packages, so skip dependency checks for them; AUR packages
        # compile, so they install their build and runtime deps.
        if [[ "$dir" == */pkgs/aur/* ]]; then deps=(--syncdeps); else deps=(--nodeps); fi
        # Upstream signing keys kept with the PKGBUILD (AUR convention
        # keys/pgp/<fingerprint>.asc), so makepkg can check source signatures.
        for key in "$dir"/keys/pgp/*.asc; do
            [[ -f "$key" ]] && as_builder gpg --batch --quiet --import "$key"
        done
        (cd "$dir" && as_builder env PKGDEST="$STAGE" makepkg --clean --cleanbuild --noconfirm "${deps[@]}")
        for f in $files; do
            [[ -f "$STAGE/$f" ]] || { echo "$name did not produce $f" >&2; exit 1; }
            size="$(stat -c %s "$STAGE/$f")"
            if [[ "$size" -gt "$MAX_ASSET_BYTES" ]]; then
                echo "$f is $size bytes; GitHub release assets must be under 2 GiB. Split the package or host it elsewhere." >&2
                exit 1
            fi
            safe="$(repo_file_name "$f")"
            cp "$STAGE/$f" "$OUT/$safe"
            rm -f "$OUT/$safe.sig"
        done
        built=$((built + 1))
    done
    echo "==> Build: $built built, $reused reused, $skipped skipped"
    if [[ ${#ONLY[@]} -gt 0 ]]; then
        echo "==> --only: no manifest written (not a whole repo)"
    else
        if $PINNED; then bash "$SCRIPT_DIR/fetch-pinned.sh" --out "$OUT"; fi
        expected_files > "$OUT/invictus-manifest.txt"
    fi
fi

# ---- sign + index -----------------------------------------------------------
if $DO_REPO; then
    command -v repo-add >/dev/null || { echo "repo-add not found" >&2; exit 2; }
    cd "$OUT"

    # Keep only what the current PKGBUILDs produce; drop older versions.
    if [[ -f invictus-manifest.txt ]]; then
        list="$(cat invictus-manifest.txt)"
        rm -f invictus-manifest.txt
    else
        list="$(expected_files)" || exit 1
    fi
    mapfile -t current <<< "$list"
    [[ -n "$list" && ${#current[@]} -gt 0 ]] || { echo "No packages to index." >&2; exit 1; }
    # The manifest came from the build step, where package code ran: accept
    # plain package file names only (no paths, no leading dash).
    for c in "${current[@]}"; do
        [[ "$c" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*\.pkg\.tar\.zst$ ]] || { echo "Bad package name in manifest: $c" >&2; exit 1; }
    done
    for f in *.pkg.tar.zst; do
        [[ -e "$f" ]] || continue
        keep=false
        for c in "${current[@]}"; do [[ "$f" == "$c" ]] && keep=true; done
        $keep || { echo "==> Dropping stale $f"; rm -f "$f" "$f.sig"; }
    done
    for c in "${current[@]}"; do
        [[ -f "$c" ]] || { echo "Missing $c: run the build step first." >&2; exit 1; }
    done

    KEY=""
    # CI hands the passphrase over; locally gpg-agent asks for it (pinentry)
    # once and caches it for the rest of the run.
    SIGN_OPTS=()
    if [[ -n "$SIGNING_KEY_MATERIAL" ]]; then
        SIGN_OPTS=(--batch --pinentry-mode loopback --passphrase "$SIGNING_PASSPHRASE")
        export GNUPGHOME="$WORK/gnupg"
        install -dm700 "$GNUPGHOME"
        echo "allow-loopback-pinentry" > "$GNUPGHOME/gpg-agent.conf"
        echo "default-cache-ttl 7200" >> "$GNUPGHOME/gpg-agent.conf"
        printf '%s\n' "$SIGNING_KEY_MATERIAL" | gpg --batch --quiet --import
        KEY="$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr:/ { print $10; exit }')"
        [[ -n "$KEY" ]] || { echo "INVICTUS_SIGNING_KEY holds no private key." >&2; exit 1; }
        # Unlock once through loopback; repo-add's own gpg calls then use the
        # agent's cached passphrase.
        echo unlock | gpg --batch --pinentry-mode loopback --passphrase "$SIGNING_PASSPHRASE" \
            --local-user "$KEY" --detach-sign --output /dev/null
        trap 'gpgconf --kill gpg-agent 2>/dev/null || true; cleanup' EXIT
    elif [[ -n "${INVICTUS_SIGN_KEY:-}" ]]; then
        KEY="$INVICTUS_SIGN_KEY"
    fi

    rm -f "$REPO_NAME".db* "$REPO_NAME".files*
    if [[ -n "$KEY" ]]; then
        echo "==> Signing with key $KEY"
        for c in "${current[@]}"; do
            if [[ -f "$c.sig" ]] && gpg --batch --verify "$c.sig" "$c" 2>/dev/null; then continue; fi
            rm -f "$c.sig"
            gpg "${SIGN_OPTS[@]}" --local-user "$KEY" --detach-sign --no-armor --output "$c.sig" "$c"
        done
        repo-add --sign --key "$KEY" "$REPO_NAME.db.tar.gz" "${current[@]}"
    else
        warn "No signing key: the repo and packages are UNSIGNED. pacman will refuse them with the default SigLevel. Set up the key: docs/checklists/signing-key.md"
        rm -f -- *.pkg.tar.zst.sig
        repo-add "$REPO_NAME.db.tar.gz" "${current[@]}"
    fi

    # GitHub release assets cannot be symlinks: store real copies.
    for link in "$REPO_NAME".db "$REPO_NAME".files "$REPO_NAME".db.sig "$REPO_NAME".files.sig; do
        if [[ -L "$link" ]]; then cp --remove-destination "$(readlink -f "$link")" "$link"; fi
    done
    echo "==> Repo $REPO_NAME in $OUT:"
    ls -1 "$OUT"
fi
