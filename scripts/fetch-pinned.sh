#!/usr/bin/env bash
# ------------------------------------------------------------
# fetch-pinned.sh: pinned binary packages (design 1.5), copied into
# [invictus] as they are (no rebuild).
#
# Every pkgs/pinned/*.lock lists exact package files, one per line:
#   <name> <version-pkgrel> <arch> <sha256>
#  - hypr.lock: the hypr* set from the Arch archive, so [invictus] serves
#    the versions our Lua config was tested with and Arch's [extra]
#    cannot move them (pacman takes the first repo listed);
#  - cachyos.lock: the linux-cachyos kernel and headers from CachyOS's
#    [cachyos] repo (Alex, 2026-09-30). The CachyOS repos are never added
#    to an installed pacman.conf: these files are re-signed into ours.
#
# A lock's header may name another source (default: the Arch archive and
# pacman's own keyring) with "#@" lines:
#   #@ source URL            files are at URL/<file> and URL/<file>.sig
#   #@ key FILE FINGERPRINT  the only key allowed to sign them (FILE is a
#                            public key in this checkout; FINGERPRINT is its
#                            primary key, checked on every signature)
#   #@ fallback URL          where to get a file the source no longer has
#                            (CachyOS keeps only the current build): our
#                            own published repo. Such a file is checked by
#                            its sha256 only; the lock's sha256 was written
#                            after the upstream signature verified.
#
#   scripts/fetch-pinned.sh --out DIR     download into DIR and verify (every lock)
#   scripts/fetch-pinned.sh --list        print the repo file names, no network
#   scripts/fetch-pinned.sh --lock name=ver-rel[@arch] [...]
#                                         (maintainer) fetch those versions,
#                                         verify, and rewrite the lock file
#   scripts/fetch-pinned.sh --lock-current
#                                         same, for the versions Arch ships now
#                                         (reads a throwaway copy of the sync
#                                         db; Arch-sourced locks only)
#
# Every file must pass two checks before it is kept:
#   1. its detached signature: for Arch, pacman-key --verify with a key the
#      local pacman keyring trusts fully (archlinux-keyring); for a "#@ key"
#      lock, gpg with only that key in a throwaway keyring, and the
#      signature must be made by that primary key;
#   2. the sha256 in the lock file (so a pin cannot silently change).
# Needs pacman-key (Arch locks) and gpg, so it runs on Arch or in the build
# container.
#
# Env: ARCH_ARCHIVE   archive base URL (default https://archive.archlinux.org)
#      PINNED_GPGDIR  pacman keyring to verify with (default pacman's own)
#      PINNED_LOCK    one lock file (default: every pkgs/pinned/*.lock for
#                     --out and --list; hypr.lock for --lock, --lock-current)
# ------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
if [[ -n "${PINNED_LOCK:-}" ]]; then LOCKS=("$PINNED_LOCK")
else LOCKS=("$ROOT"/pkgs/pinned/*.lock); fi
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

# directive NAME: the value of the lock's "#@ NAME value" line (empty if none).
directive() {
    awk -v d="$1" '$1 == "#@" && $2 == d { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }' "$LOCK"
}

# use_lock FILE: make FILE the current lock and read its source, key and
# fallback.
SOURCE="" KEY_FILE="" KEY_FPR="" FALLBACK=""
use_lock() {
    LOCK="$1"
    [[ -f "$LOCK" ]] || die "no lock file at $LOCK"
    SOURCE="$(directive source)"
    FALLBACK="$(directive fallback)"
    KEY_FILE="" KEY_FPR=""
    read -r KEY_FILE KEY_FPR _ <<< "$(directive key)" || true
    if [[ -n "$SOURCE" || -n "$KEY_FILE" ]]; then
        [[ "$SOURCE" =~ ^https://[A-Za-z0-9./_-]+$ ]] || die "$LOCK: '#@ source' must be an https URL"
        [[ -n "$KEY_FILE" && "$KEY_FPR" =~ ^[0-9A-F]{40}$ ]] \
            || die "$LOCK: a '#@ source' lock needs '#@ key FILE FINGERPRINT' (40 upper-case hex)"
        [[ "$KEY_FILE" != /* && "$KEY_FILE" != *..* ]] || die "$LOCK: the key file must be a path inside the checkout"
        KEY_FILE="$ROOT/$KEY_FILE"
        [[ -f "$KEY_FILE" ]] || die "$LOCK: no key file $KEY_FILE"
    fi
    if [[ -n "$FALLBACK" && ! "$FALLBACK" =~ ^https://[A-Za-z0-9./_-]+$ ]]; then
        die "$LOCK: '#@ fallback' must be an https URL"
    fi
}

arch_file() { printf '%s-%s-%s.pkg.tar.zst' "$1" "$2" "$3"; }

url_for() {
    local name="$1" file="$2"
    if [[ -n "$SOURCE" ]]; then printf '%s/%s' "$SOURCE" "$file"
    else printf '%s/packages/%s/%s/%s' "$ARCHIVE" "${name:0:1}" "$name" "$file"; fi
}

verify_sig() {
    if [[ -n "$KEY_FILE" ]]; then verify_sig_key "$1"; return; fi
    local gpgdir=()
    [[ -n "${PINNED_GPGDIR:-}" ]] && gpgdir=(--gpgdir "$PINNED_GPGDIR")
    pacman-key "${gpgdir[@]}" --verify "$1.sig" "$1" >/dev/null 2>&1
}

# A throwaway keyring holding only the lock's key; the signature must be
# good and made by that primary key (or a subkey of it).
verify_sig_key() {
    local gh status rc=0 fpr
    command -v gpg >/dev/null || die "gpg not found"
    gh="$(mktemp -d)"
    if ! GNUPGHOME="$gh" gpg --batch --quiet --import "$KEY_FILE" 2>/dev/null; then
        rm -rf "$gh"; return 1
    fi
    fpr="$(GNUPGHOME="$gh" gpg --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
    if [[ "$fpr" != "$KEY_FPR" ]]; then
        echo "fetch-pinned: $KEY_FILE holds key $fpr, the lock names $KEY_FPR" >&2
        rm -rf "$gh"; return 1
    fi
    status="$(GNUPGHOME="$gh" gpg --batch --status-fd 1 --verify "$1.sig" "$1" 2>/dev/null)" || rc=$?
    GNUPGHOME="$gh" gpgconf --kill gpg-agent 2>/dev/null || true
    rm -rf "$gh"
    ((rc == 0)) || return 1
    # [GNUPG:] VALIDSIG <signing fpr> <date> ... <primary fpr> (field 12)
    awk -v want="$KEY_FPR" '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && ($3 == want || $12 == want) { found = 1 }
        END { exit !found }' <<< "$status"
}

download() {
    local url="$1" dest="$2"
    curl -fsSL --retry 3 --retry-all-errors --retry-delay 5 -o "$dest" "$url" || return 1
}

# ---- --list ----------------------------------------------------------------
list_files() {
    local name ver arch sha lock
    for lock in "${LOCKS[@]}"; do
        use_lock "$lock"
        while read -r name ver arch sha; do
            repo_file_name "$(arch_file "$name" "$ver" "$arch")"
            echo
        done < <(entries)
    done
}

# ---- --out -----------------------------------------------------------------
fetch_all() {
    local lock
    for lock in "${LOCKS[@]}"; do
        use_lock "$lock"
        fetch_lock "$1"
    done
}

fetch_lock() {
    local out="$1" name ver arch sha file dest tmp got n=0 kept=0 fell=0
    if [[ -z "$KEY_FILE" ]]; then
        command -v pacman-key >/dev/null || die "pacman-key not found (run on Arch or in the build container)"
    fi
    tmp="$(mktemp -d)"
    # One-shot: a RETURN trap set in a function stays set for its callers.
    trap 'rm -rf "$tmp"; trap - RETURN' RETURN
    while read -r name ver arch sha; do
        [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "$name: bad sha256 in $LOCK"
        file="$(arch_file "$name" "$ver" "$arch")"
        dest="$out/$(repo_file_name "$file")"
        n=$((n + 1))
        if [[ -f "$dest" ]] && [[ "$(sha256sum < "$dest" | cut -d' ' -f1)" == "$sha" ]]; then
            kept=$((kept + 1)); continue
        fi
        if download "$(url_for "$name" "$file")" "$tmp/$file"; then
            download "$(url_for "$name" "$file").sig" "$tmp/$file.sig" || die "$name: signature download failed"
            verify_sig "$tmp/$file" || die "$name $ver: the upstream signature does not verify"
        elif [[ -n "$FALLBACK" ]]; then
            # Upstream moved on: our published copy, checked by sha256 below.
            download "$FALLBACK/$(repo_file_name "$file")" "$tmp/$file" \
                || die "$name: download failed (source and fallback)"
            fell=$((fell + 1))
        else
            die "$name: download failed"
        fi
        got="$(sha256sum < "$tmp/$file" | cut -d' ' -f1)"
        [[ "$got" == "$sha" ]] || die "$name $ver: sha256 $got does not match the lock ($sha)"
        mv "$tmp/$file" "$dest"
        # Our repo signs every file with its own key (scripts/build-repo.sh).
        rm -f "$dest.sig" "$tmp/$file.sig"
    done < <(entries)
    echo "==> Pinned ($(basename "$LOCK")): $n packages ($kept already present, $((n - kept)) fetched and verified; $fell from the fallback by sha256)"
}

# ---- --lock ----------------------------------------------------------------
write_lock() {
    local tmp name ver arch file sha
    use_lock "$LOCK"
    [[ -n "$KEY_FILE" ]] || command -v pacman-key >/dev/null || die "pacman-key not found"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"; trap - RETURN' RETURN
    {
        sed -n '/^#/p' "$LOCK" 2>/dev/null || true
        for spec in "$@"; do
            # name=version-pkgrel[@arch]; the version may hold an epoch ':'
            name="${spec%%=*}"; ver="${spec#*=}"; arch=x86_64
            if [[ "$ver" == *@* ]]; then arch="${ver##*@}"; ver="${ver%@*}"; fi
            file="$(arch_file "$name" "$ver" "$arch")"
            download "$(url_for "$name" "$file")" "$tmp/$file" || die "$name: no $file at the source"
            download "$(url_for "$name" "$file").sig" "$tmp/$file.sig" || die "$name: no signature"
            verify_sig "$tmp/$file" || die "$name $ver: the upstream signature does not verify"
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
        use_lock "$LOCK"
        [[ -z "$SOURCE" ]] || die "--lock-current reads Arch's databases; for $(basename "$LOCK") use --lock name=version-pkgrel"
        specs="$(current_specs)" || exit 1
        mapfile -t specs <<< "$specs"
        [[ ${#specs[@]} -eq $(entries | wc -l) ]] || die "found ${#specs[@]} of $(entries | wc -l) packages in Arch"
        write_lock "${specs[@]}" ;;
    -h|--help|"") sed -n '2,49p' "$0" ;;
    *) die "unknown argument: $1" ;;
esac
