#!/usr/bin/env bash
# ------------------------------------------------------------
# fetch-pinned.sh: the pinned hypr* set (design 1.5).
#
# pkgs/pinned/hypr.lock lists exact Arch package files, one per line:
#   <name> <version-pkgrel> <arch> <sha256>
# They are copied from the Arch archive as they are (no rebuild), so
# [invictus] serves the versions our Lua config was tested with and
# Arch's [extra] cannot move them (pacman takes the first repo listed).
#
#   scripts/fetch-pinned.sh --out DIR     download into DIR and verify
#   scripts/fetch-pinned.sh --list        print the repo file names, no network
#   scripts/fetch-pinned.sh --lock name=ver-rel[@arch] [...]
#                                         (maintainer) fetch those versions,
#                                         verify, and rewrite the lock file
#   scripts/fetch-pinned.sh --lock-current
#                                         same, for the versions Arch ships now
#                                         (reads a throwaway copy of the sync db)
#
# Every file must pass two checks before it is kept:
#   1. pacman-key --verify: Arch's own detached signature, made by a key
#      the local pacman keyring trusts fully (archlinux-keyring);
#   2. the sha256 in the lock file (so a pin cannot silently change).
# Needs pacman-key, so it runs on Arch or in the build container.
#
# Env: ARCH_ARCHIVE   archive base URL (default https://archive.archlinux.org)
#      PINNED_GPGDIR  pacman keyring to verify with (default pacman's own)
#      PINNED_LOCK    lock file (default pkgs/pinned/hypr.lock)
# ------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LOCK="${PINNED_LOCK:-$ROOT/pkgs/pinned/hypr.lock}"
ARCHIVE="${ARCH_ARCHIVE:-https://archive.archlinux.org}"

# shellcheck source=scripts/lib/repo-names.sh
. "$SCRIPT_DIR/lib/repo-names.sh"

die() { echo "fetch-pinned: $*" >&2; exit 1; }

# Lock entries as "name version arch sha256", comments and blanks skipped.
entries() {
    [[ -f "$LOCK" ]] || die "no lock file at $LOCK"
    grep -v '^[[:space:]]*\(#\|$\)' "$LOCK"
}

arch_file() { printf '%s-%s-%s.pkg.tar.zst' "$1" "$2" "$3"; }

url_for() {
    local name="$1" file="$2"
    printf '%s/packages/%s/%s/%s' "$ARCHIVE" "${name:0:1}" "$name" "$file"
}

verify_sig() {
    local gpgdir=()
    [[ -n "${PINNED_GPGDIR:-}" ]] && gpgdir=(--gpgdir "$PINNED_GPGDIR")
    pacman-key "${gpgdir[@]}" --verify "$1.sig" "$1" >/dev/null 2>&1
}

download() {
    local url="$1" dest="$2"
    curl -fsSL --retry 3 --retry-all-errors --retry-delay 5 -o "$dest" "$url" || return 1
}

# ---- --list ----------------------------------------------------------------
list_files() {
    local name ver arch sha
    while read -r name ver arch sha; do
        repo_file_name "$(arch_file "$name" "$ver" "$arch")"
        echo
    done < <(entries)
}

# ---- --out -----------------------------------------------------------------
fetch_all() {
    local out="$1" name ver arch sha file dest tmp got n=0 kept=0
    command -v pacman-key >/dev/null || die "pacman-key not found (run on Arch or in the build container)"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    while read -r name ver arch sha; do
        [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "$name: bad sha256 in $LOCK"
        file="$(arch_file "$name" "$ver" "$arch")"
        dest="$out/$(repo_file_name "$file")"
        n=$((n + 1))
        if [[ -f "$dest" ]] && [[ "$(sha256sum < "$dest" | cut -d' ' -f1)" == "$sha" ]]; then
            kept=$((kept + 1)); continue
        fi
        download "$(url_for "$name" "$file")" "$tmp/$file" || die "$name: download failed"
        download "$(url_for "$name" "$file").sig" "$tmp/$file.sig" || die "$name: signature download failed"
        verify_sig "$tmp/$file" || die "$name $ver: Arch signature does not verify"
        got="$(sha256sum < "$tmp/$file" | cut -d' ' -f1)"
        [[ "$got" == "$sha" ]] || die "$name $ver: sha256 $got does not match the lock ($sha)"
        mv "$tmp/$file" "$dest"
        # Our repo signs every file with its own key (scripts/build-repo.sh).
        rm -f "$dest.sig" "$tmp/$file.sig"
    done < <(entries)
    echo "==> Pinned: $n packages ($kept already present, $((n - kept)) fetched and verified)"
}

# ---- --lock ----------------------------------------------------------------
write_lock() {
    local tmp name ver arch file sha
    command -v pacman-key >/dev/null || die "pacman-key not found"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    {
        sed -n '/^#/p' "$LOCK" 2>/dev/null || true
        for spec in "$@"; do
            # name=version-pkgrel[@arch]; the version may hold an epoch ':'
            name="${spec%%=*}"; ver="${spec#*=}"; arch=x86_64
            if [[ "$ver" == *@* ]]; then arch="${ver##*@}"; ver="${ver%@*}"; fi
            file="$(arch_file "$name" "$ver" "$arch")"
            download "$(url_for "$name" "$file")" "$tmp/$file" || die "$name: no $file in the archive"
            download "$(url_for "$name" "$file").sig" "$tmp/$file.sig" || die "$name: no signature"
            verify_sig "$tmp/$file" || die "$name $ver: Arch signature does not verify"
            sha="$(sha256sum < "$tmp/$file" | cut -d' ' -f1)"
            printf '%s %s %s %s\n' "$name" "$ver" "$arch" "$sha"
        done
    } > "$tmp/lock"
    mv "$tmp/lock" "$LOCK"
    echo "==> Wrote $LOCK"
}

current_specs() {
    # A throwaway sync db, so the system's own databases are never synced
    # on their own (that would be a partial upgrade waiting to happen).
    local db names
    db="$(mktemp -d)"
    # pacman downloads as its unprivileged DownloadUser
    chmod 755 "$db"
    mkdir -p "$db/sync"
    ln -s /var/lib/pacman/local "$db/local"
    names="$(entries | cut -d' ' -f1)"
    if [[ $EUID -eq 0 ]]; then pacman -Sy --dbpath "$db" --logfile /dev/null >/dev/null
    else fakeroot -- pacman -Sy --dbpath "$db" --logfile /dev/null >/dev/null; fi || die "could not read the Arch sync databases"
    # shellcheck disable=SC2086
    pacman -Si --dbpath "$db" $names | awk '/^Name/ { n = $3 } /^Version/ { v = $3 } /^Architecture/ { print n "=" v "@" $3 }'
    rm -rf "$db"
}

case "${1:-}" in
    --list) list_files ;;
    --out)
        [[ -n "${2:-}" ]] || die "--out needs a folder"
        mkdir -p "$2"; fetch_all "$(cd "$2" && pwd)" ;;
    --lock) shift; [[ $# -gt 0 ]] || die "--lock needs name=version-pkgrel"; write_lock "$@" ;;
    --lock-current)
        specs="$(current_specs)" || exit 1
        mapfile -t specs <<< "$specs"
        [[ ${#specs[@]} -eq $(entries | wc -l) ]] || die "found ${#specs[@]} of $(entries | wc -l) packages in Arch"
        write_lock "${specs[@]}" ;;
    -h|--help|"") sed -n '2,32p' "$0" ;;
    *) die "unknown argument: $1" ;;
esac
