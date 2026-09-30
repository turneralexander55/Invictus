#!/usr/bin/env bash
# ------------------------------------------------------------
# bump-aur.sh: move an AUR pin in pkgs/aur to a newer AUR commit, with the
# diff shown for review first.
#
#   scripts/dev/bump-aur.sh --check [NAME...]
#       Compare each pin (all of pkgs/aur by default) with the AUR today.
#       Changes nothing. Exit 1 when any pin is behind.
#   scripts/dev/bump-aur.sh NAME --reviewer WHO [--commit SHA] [--yes]
#       1. clones the AUR repo, shows its log and full diff from our pinned
#          commit to SHA (default: the AUR's latest);
#       2. if the AUR only changed the version and checksums, asks (unless
#          --yes), then copies pkgver/pkgrel/epoch into our PKGBUILD;
#          anything else (a new source, a changed build step or helper
#          file) stops with exit 3: merge it by hand, keep our changes
#          listed at the top of the PKGBUILD, then rerun with --sums-only;
#       3. recomputes every checksum by downloading (updpkgsums), checks
#          that each x86_64 checksum the AUR names came out the same here
#          (two independent downloads agree), and runs makepkg
#          --verifysource so signatures are checked against keys/pgp/;
#       4. moves the "aur-commit:" and "Reviewed" header lines.
#       It never commits. Then: read `git diff`, run tests/pkgs/run.sh, and
#       commit as "NAME: AUR <commit> (<version>)".
#   scripts/dev/bump-aur.sh NAME --reviewer WHO --sums-only [--commit SHA]
#       Steps 3 and 4 only, after a hand merge.
#
# Who and when: docs/packages.md, "AUR pins" (weekly for zen-browser-bin
# and claude-code, on each GE release for proton-ge-custom-bin; the
# aur-pins workflow's weekly --check goes red when one is behind).
#
# Step 3 needs makepkg and updpkgsums (pacman-contrib): on Arch it runs
# here (not as root); elsewhere in archlinux:base-devel via podman or
# docker (IMAGE=, CONTAINER_ARGS= as for build-repo.sh).
# AUR_URL overrides https://aur.archlinux.org (tests use a local repo);
# BUMP_SUMS_CMD replaces step 3's updpkgsums/verifysource (tests only).
# ------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
AUR_URL="${AUR_URL:-https://aur.archlinux.org}"
IMAGE="${IMAGE:-docker.io/library/archlinux:base-devel}"

usage() { sed -n '2,40p' "$0"; }

MODE=bump NAME="" COMMIT="" REVIEWER="" YES=false
CHECK_NAMES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE=check; shift; while [[ $# -gt 0 && "$1" != -* ]]; do CHECK_NAMES+=("$1"); shift; done ;;
        --commit) COMMIT="${2:?}"; shift 2 ;;
        --reviewer) REVIEWER="${2:?}"; shift 2 ;;
        --yes) YES=true; shift ;;
        --sums-only) MODE=sums; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option $1" >&2; exit 2 ;;
        *) [[ -z "$NAME" ]] || { echo "One package at a time." >&2; exit 2; }; NAME="$1"; shift ;;
    esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pinned_commit() { sed -n 's/^# aur-commit: \([0-9a-f]\{40\}\).*/\1/p' "$1" | head -1; }
clone() { git clone -q "$AUR_URL/$1.git" "$2"; }

# ---- --check -----------------------------------------------------------------
if [[ "$MODE" == check ]]; then
    if [[ ${#CHECK_NAMES[@]} -eq 0 ]]; then
        for d in "$ROOT"/pkgs/aur/*/; do CHECK_NAMES+=("$(basename "$d")"); done
    fi
    behind=0
    for n in "${CHECK_NAMES[@]}"; do
        pb="$ROOT/pkgs/aur/$n/PKGBUILD"
        [[ -f "$pb" ]] || { echo "$n: no $pb" >&2; exit 2; }
        old="$(pinned_commit "$pb")"
        [[ -n "$old" ]] || { echo "$n: no '# aur-commit: <sha>' line in its PKGBUILD" >&2; exit 2; }
        clone "$n" "$TMP/$n"
        head="$(git -C "$TMP/$n" rev-parse HEAD)"
        ver="$(sed -n 's/^[[:space:]]*pkgver = //p' "$TMP/$n/.SRCINFO" 2>/dev/null | head -1)"
        if [[ "$old" == "$head" ]]; then
            echo "ok      $n at ${old:0:7} (AUR latest)"
        elif git -C "$TMP/$n" merge-base --is-ancestor "$old" "$head" 2>/dev/null; then
            count="$(git -C "$TMP/$n" rev-list --count "$old..$head")"
            since="$(git -C "$TMP/$n" log -1 --format=%cs "$old")"
            echo "BEHIND  $n: pinned ${old:0:7} ($since), AUR has $count newer commit(s), now ${head:0:7} ($ver). Run: scripts/dev/bump-aur.sh $n --reviewer <you>"
            behind=1
        else
            echo "BEHIND  $n: pinned ${old:0:7} is not in the AUR history any more (force-pushed?); AUR is at ${head:0:7} ($ver). Review by hand."
            behind=1
        fi
    done
    exit $behind
fi

# ---- bump / sums-only ------------------------------------------------------------
[[ -n "$NAME" ]] || { usage; exit 2; }
[[ -n "$REVIEWER" ]] || { echo "--reviewer WHO is required: the name goes in the PKGBUILD's Reviewed line." >&2; exit 2; }
DIR="$ROOT/pkgs/aur/$NAME"
PB="$DIR/PKGBUILD"
[[ -f "$PB" ]] || { echo "No $PB" >&2; exit 2; }
OLD="$(pinned_commit "$PB")"
[[ -n "$OLD" ]] || { echo "$PB has no '# aur-commit: <sha>' line" >&2; exit 2; }

AUR="$TMP/aur"
clone "$NAME" "$AUR"
NEW="$(git -C "$AUR" rev-parse "${COMMIT:-HEAD}^{commit}")"
git -C "$AUR" checkout -q "$NEW"

# Value of a top-level assignment in a PKGBUILD, as written (no code runs).
raw_var() { sed -n "s/^$2=//p" "$1" | head -1; }
unquote() { local v="$1"; v="${v#[\"\']}"; v="${v%[\"\']}"; printf '%s' "$v"; }

if [[ "$MODE" == bump ]]; then
    if [[ "$OLD" == "$NEW" ]]; then echo "$NAME is already at ${NEW:0:7}."; exit 0; fi
    git -C "$AUR" merge-base --is-ancestor "$OLD" "$NEW" \
        || { echo "Pinned ${OLD:0:7} is not an ancestor of ${NEW:0:7}: review the AUR history by hand." >&2; exit 3; }
    echo "==> AUR $NAME: ${OLD:0:7} -> ${NEW:0:7}"
    git -C "$AUR" log --format='    %h %cs %an: %s' "$OLD..$NEW"
    echo
    echo "==> The AUR's diff (review it; .SRCINFO left out, it mirrors the PKGBUILD)"
    git -C "$AUR" --no-pager diff "$OLD" "$NEW" -- . ':!.SRCINFO'
    echo

    # Only the version and checksums changed?
    others="$(git -C "$AUR" diff --name-only "$OLD" "$NEW" -- . ':!.SRCINFO' ':!PKGBUILD')"
    odd="$(git -C "$AUR" diff -U0 "$OLD" "$NEW" -- PKGBUILD | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' \
        | grep -vE "^[+-][[:space:]]*(_?pkgver|pkgrel|_extver|epoch)=[^;&|\`\$()]*$" \
        | grep -vE "^[+-][[:space:]]*((sha(1|224|256|384|512)|b2|md5|ck)sums(_[a-z0-9_]+)?=\\()?[[:space:]]*'([0-9a-f]{32,128}|SKIP)'[[:space:]]*\\)?[[:space:]]*$" \
        | grep -vE '^[+-][[:space:]]*$' || true)"
    if [[ -n "$others" || -n "$odd" ]]; then
        echo "The AUR changed more than the version and checksums:"
        [[ -z "$others" ]] || awk '{ print "  file " $0 }' <<< "$others"
        [[ -z "$odd" ]] || awk '{ print "  " $0 }' <<< "$odd"
        echo
        echo "Merge those by hand into pkgs/aur/$NAME (keep our changes listed at the top of the PKGBUILD), then run:"
        echo "  scripts/dev/bump-aur.sh $NAME --reviewer $REVIEWER --sums-only --commit $NEW"
        exit 3
    fi
    if ! $YES; then
        read -r -p "Only the version and checksums changed. Apply to pkgs/aur/$NAME? [y/N] " a
        [[ "$a" == [yY]* ]] || { echo "Nothing changed."; exit 1; }
    fi
    for v in pkgver pkgrel _pkgver _extver epoch; do
        new_val="$(raw_var "$AUR/PKGBUILD" "$v")"
        [[ -n "$new_val" ]] || continue
        if grep -q "^$v=" "$PB"; then
            # awk, not sed: the value may hold characters sed would read
            awk -v v="$v" -v val="$new_val" 'index($0, v "=") == 1 && !done { print v "=" val; done = 1; next } { print }' "$PB" > "$TMP/pb" \
                && cat "$TMP/pb" > "$PB"
        fi
    done
fi

# ---- checksums and signatures ------------------------------------------------------
echo "==> Recomputing checksums and checking signatures for $NAME"
if [[ -n "${BUMP_SUMS_CMD:-}" ]]; then
    bash -c "$BUMP_SUMS_CMD" _ "$DIR"
elif command -v makepkg >/dev/null && [[ $EUID -ne 0 ]]; then
    command -v updpkgsums >/dev/null || { echo "updpkgsums not found: install pacman-contrib" >&2; exit 2; }
    ( cd "$DIR"
      for key in keys/pgp/*.asc; do [[ -f "$key" ]] && gpg --batch --quiet --import "$key"; done
      export SRCDEST="$TMP/src"; mkdir -p "$SRCDEST"
      updpkgsums
      makepkg --verifysource --noconfirm
      rm -rf src )
else
    RUNTIME="$(command -v podman || command -v docker || true)"
    [[ -n "$RUNTIME" ]] || { echo "Need makepkg (Arch, not root) or podman/docker." >&2; exit 2; }
    read -ra extra <<< "${CONTAINER_ARGS:-}"
    # shellcheck disable=SC2016 # expanded in the container
    "$RUNTIME" run --rm -v "$DIR:/pkg" "${extra[@]}" "$IMAGE" bash -c '
        set -euo pipefail
        pacman -Syu --noconfirm --needed pacman-contrib git >/dev/null
        useradd -m builder
        cp -r /pkg /home/builder/pkg && chown -R builder /home/builder/pkg
        sudo -u builder -H bash -c "
            set -euo pipefail
            cd ~/pkg
            for key in keys/pgp/*.asc; do [[ -f \$key ]] && gpg --batch --quiet --import \$key; done
            updpkgsums
            makepkg --verifysource --noconfirm"
        cat /home/builder/pkg/PKGBUILD > /pkg/PKGBUILD'
fi

# Every x86_64 or arch-independent checksum the AUR names must be in ours
# too: the AUR maintainer's download and ours agree. Parsed, not sourced
# (no AUR code runs here).
aur_sums() {
    awk '
        /^[a-z0-9_]*sums(_[a-z0-9_]+)?=\(/ { name = $0; sub(/=.*/, "", name); inarr = 1 }
        inarr {
            if (name !~ /_(aarch64|i686|armv7h|riscv64)$/) {
                line = $0
                # no {m,n}: mawk has no interval expressions
                while (match(line, /\047[0-9a-f]+\047/)) {
                    if (RLENGTH - 2 >= 32 && RLENGTH - 2 <= 128) print substr(line, RSTART + 1, RLENGTH - 2)
                    line = substr(line, RSTART + RLENGTH)
                }
            }
            if ($0 ~ /\)/) inarr = 0
        }' "$1"
}
missing=0
while read -r sum; do
    grep -qF "'$sum'" "$PB" || { echo "The AUR's checksum $sum is not what we downloaded (see $PB)." >&2; missing=1; }
done < <(aur_sums "$AUR/PKGBUILD")
[[ $missing == 0 ]] || { echo "Checksums disagree with the AUR: stop and find out why before committing." >&2; exit 4; }

# ---- header lines --------------------------------------------------------------------
epoch="$(unquote "$(raw_var "$PB" epoch)")"
ver="$(sed -n 's/^[[:space:]]*pkgver = //p' "$AUR/.SRCINFO" 2>/dev/null | head -1)"
[[ -n "$ver" ]] || ver="$(unquote "$(raw_var "$PB" pkgver)")"
rel="$(unquote "$(raw_var "$PB" pkgrel)")"
label="${epoch:+$epoch:}$ver-$rel, $(git -C "$AUR" log -1 --format=%cs "$NEW")"
today="$(date -u +%Y-%m-%d)"
awk -v c="$NEW" -v label="$label" -v today="$today" -v who="$REVIEWER" '
    /^# aur-commit: / && !a { print "# aur-commit: " c " (" label ")"; a = 1; next }
    /^# Reviewed [0-9-]+ by / && !r { sub(/^# Reviewed [0-9-]+ by [A-Za-z]+( [0-9]+)?/, "# Reviewed " today " by " who); r = 1 }
    { print }' "$PB" > "$TMP/pb" && cat "$TMP/pb" > "$PB"

echo
echo "==> pkgs/aur/$NAME now pins AUR ${NEW:0:7} ($label). Nothing is committed."
git -C "$ROOT" --no-pager diff --stat -- "pkgs/aur/$NAME" 2>/dev/null || true
echo "Next: read git diff, run tests/pkgs/run.sh, then commit as \"$NAME: AUR ${NEW:0:7} ($ver)\"."
echo "Optional full build: scripts/build-repo.sh --in-container --only $NAME --out out/bump"
