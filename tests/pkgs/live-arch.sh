#!/usr/bin/env bash
# ------------------------------------------------------------
# Live check of the package sets against Arch and the AUR. Run as root in
# a throwaway Arch container with network:
#
#   docker run --rm --network host -v "$PWD:/src:ro" archlinux:base-devel \
#       bash /src/tests/pkgs/live-arch.sh
#   ... bash /src/tests/pkgs/live-arch.sh /src --write
#       (rewrite pkgs/meta/sources.txt; needs /src writable)
#
# 1. Every package a PKGBUILD in pkgs/meta or pkgs/own names (depends and
#    optdepends) comes from where pkgs/meta/sources.txt says: core, extra
#    or multilib (pacman -Si), aur (AUR RPC, and pkgs/aur builds it),
#    aur-paru (AUR RPC; not in pkgs/aur yet, a machine gets it with paru),
#    invictus (our own PKGBUILD), or pinned (not in Arch; a binary pinned in
#    pkgs/pinned/*.lock, like linux-cachyos). tests/pkgs/run.sh checks the same
#    file offline; this is what keeps it true.
# 2. Every command in tests/pkgs/fixtures/commands.txt is a file of the
#    Arch package it is mapped to (pacman -F), and
#    tests/pkgs/fixtures/arch-base.txt is still what Arch's base depends on.
# 3. Every Arch package of every set, plus what the ISO adds as targets
#    (pipewire-jack), resolves in one transaction, no two of them
#    conflict, Steam's Vulkan drivers resolve to the AMD ones, and "jack"
#    to pipewire-jack, not jack2.
# Arch's sync and file databases are read into a throwaway --dbpath; the
# container's own are never synced alone.
# ------------------------------------------------------------
set -euo pipefail

[[ -f /.dockerenv || -f /run/.containerenv ]] || { echo "Run this only in a container." >&2; exit 2; }
SRC="${1:-/src}"
WRITE=false
[[ "${2:-}" == --write ]] && WRITE=true
MANIFEST="$SRC/pkgs/meta/sources.txt"
COMMANDS="$SRC/tests/pkgs/fixtures/commands.txt"
ARCH_BASE="$SRC/tests/pkgs/fixtures/arch-base.txt"

fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

pacman -Syu --noconfirm --needed jq curl >/dev/null

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CONF="$TMP/pacman.conf"
cp /etc/pacman.conf "$CONF"
grep -qx '\[multilib\]' "$CONF" || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "$CONF"
DB="$TMP/db"
mkdir -p "$DB/sync"
chmod 755 "$TMP" "$DB" "$DB/sync"
ln -s /var/lib/pacman/local "$DB/local"
P=(pacman --config "$CONF" --dbpath "$DB" --logfile /dev/null)
"${P[@]}" -Sy >/dev/null
"${P[@]}" -Fy >/dev/null

field() {
    bash -c 'source "$1" >/dev/null; declare -n v="$2"; printf "%s\n" "${v[@]}"' _ "$1" "$2"
}
# Package name of a depends/optdepends entry: drop ": why" and version bounds.
bare() { sed -e 's/:.*//' -e 's/[<>=].*//' -e '/^$/d'; }

# ---- 1. where every named package comes from ----------------------------------
echo "== sources"
for pb in "$SRC"/pkgs/meta/*/PKGBUILD "$SRC"/pkgs/own/*/PKGBUILD; do
    { field "$pb" depends; field "$pb" optdepends; } | bare
done | sort -u > "$TMP/names"

ours() { [[ -f "$SRC/pkgs/own/$1/PKGBUILD" || -f "$SRC/pkgs/meta/$1/PKGBUILD" ]]; }

# pacman -Si exits 1 when any name is missing (ours, the AUR ones)
mapfile -t names < "$TMP/names"
{ "${P[@]}" -Si "${names[@]}" 2>/dev/null || true; } \
    | awk -F' *: ' '/^Repository/ { r = $2 } /^Name/ { print $2, r }' | sort -u > "$TMP/arch"
args="$(sed 's/^/arg[]=/' "$TMP/names" | paste -sd'&')"
curl -sSf "https://aur.archlinux.org/rpc/v5/info?$args" | jq -r '.results[].Name' | sort -u > "$TMP/aur"

: > "$TMP/found"
while IFS= read -r n; do
    if ours "$n"; then src=invictus
    elif src="$(awk -v n="$n" '$1 == n { print $2; exit }' "$TMP/arch")" && [[ -n "$src" ]]; then :
    elif grep -hv '^#' "$SRC"/pkgs/pinned/*.lock | cut -d' ' -f1 | grep -x "$n" >/dev/null; then src=pinned
    elif grep -qx "$n" "$TMP/aur"; then
        if [[ -f "$SRC/pkgs/aur/$n/PKGBUILD" ]]; then src=aur; else src=aur-paru; fi
    else
        bad "$n: not in Arch (core, extra, multilib), not in the AUR, not ours"; continue
    fi
    echo "$n $src" >> "$TMP/found"
done < "$TMP/names"

if $WRITE; then
    {
        echo "# Where every package named by pkgs/meta/*/PKGBUILD and pkgs/own/*/PKGBUILD"
        echo "# comes from. Written by tests/pkgs/live-arch.sh --write in an Arch"
        echo "# container on $(date -u +%Y-%m-%d); checked offline by tests/pkgs/run.sh and"
        echo "# live by tests/pkgs/live-arch.sh. Sources: core, extra, multilib (Arch),"
        echo "# aur (built from pkgs/aur), aur-paru (AUR, not in pkgs/aur yet: install it"
        echo "# with paru), invictus (our own PKGBUILD), pinned (pkgs/pinned/*.lock, not in Arch)."
        cat "$TMP/found"
    } > "$MANIFEST"
    ok "wrote $MANIFEST ($(wc -l < "$TMP/found") packages)"
elif diff <(grep -v '^#' "$MANIFEST") "$TMP/found" > "$TMP/diff"; then
    ok "$(wc -l < "$TMP/found") packages come from where sources.txt says"
else
    bad "sources.txt differs from Arch and the AUR today (< file, > live):"
    sed 's/^/      /' "$TMP/diff"
fi
echo

# ---- 2. commands -> packages ---------------------------------------------------
echo "== commands"
c_fail=0; n=0
"${P[@]}" -Si base | awk -F' *: ' '/^Depends/ { print $2 }' | tr -s ' ' '\n' | sed '/^$/d' | sort > "$TMP/base"
if diff <(grep -v '^#' "$ARCH_BASE" | sort) "$TMP/base" > "$TMP/base.diff"; then :; else
    bad "arch-base.txt is not what base depends on today: $(paste -sd' ' "$TMP/base.diff")"; c_fail=1
fi
while read -r cmd pkg _; do
    src="$(awk -v n="$pkg" '$1 == n { print $2; exit }' "$TMP/found")"
    [[ -n "$src" ]] || ! grep -qx "$pkg" "$TMP/base" || src=core
    case "$src" in
        core|extra|multilib) ;;
        "") bad "$cmd: $pkg is named by no set"; c_fail=1; continue ;;
        *) continue ;;
    esac
    n=$((n + 1))
    path="${cmd#/}"; [[ "$cmd" == /* ]] || path="usr/bin/$cmd"
    owners="$("${P[@]}" -Fq "$path" 2>/dev/null | sed 's|.*/||' || true)"
    grep -qx "$pkg" <<< "$owners" || { bad "$cmd is not in $pkg (owned by: ${owners:-nothing})"; c_fail=1; }
done < <(grep -v '^[[:space:]]*\(#\|$\)' "$COMMANDS")
[[ $c_fail == 0 ]] && ok "$n commands are files of the Arch packages they are mapped to"
echo

# ---- 3. every set together ---------------------------------------------------------
echo "== one transaction"
for pb in "$SRC"/pkgs/meta/*/PKGBUILD; do field "$pb" depends | bare; done | sort -u > "$TMP/deps"
mapfile -t targets < <(awk 'NR == FNR { d[$1] = 1; next } ($1 in d) && $2 ~ /^(core|extra|multilib)$/ { print $1 }' "$TMP/deps" "$TMP/found")
targets+=(pipewire-jack)   # the ISO installs it by name (docs/packages.md)
if "${P[@]}" -Sp --noconfirm --print-format '%n' "${targets[@]}" > "$TMP/plan" 2>"$TMP/plan.err"; then
    # Conflicts among the planned packages (pacman -Sp does not check them).
    mapfile -t plan < "$TMP/plan"
    { "${P[@]}" -Si "${plan[@]}" 2>/dev/null || true; } | awk -F' *: ' '
        /^Name/ { n = $2 }
        /^Provides/ || /^Conflicts With/ {
            k = ($1 == "Provides") ? "p" : "c"
            m = split($2, a, /  +/)
            for (i = 1; i <= m; i++) {
                x = a[i]
                if (k == "c" && x ~ /[<>=]/) continue  # versioned conflicts: an older release only
                sub(/[<>=].*/, "", x); if (x != "None") print k, n, x
            }
        }' > "$TMP/pc"
    # prov[x] = the planned packages that are or provide x; a package that
    # conflicts with a name only it provides (the usual provides+conflicts
    # pair) is not a conflict.
    awk 'FNR == 1 { pass++ }
         pass == 1 { prov[$1] = prov[$1] " " $1; next }
         pass == 2 { if ($1 == "p") prov[$3] = prov[$3] " " $2; next }
         $1 == "c" { m = split(prov[$3], a, " "); for (i = 1; i <= m; i++) if (a[i] != $2) print $2 " conflicts with " $3 " (" a[i] ")" }' \
        "$TMP/plan" "$TMP/pc" "$TMP/pc" | sort -u > "$TMP/conflicts"
    if [[ -s "$TMP/conflicts" ]]; then bad "conflicts: $(paste -sd';' "$TMP/conflicts")"
    else ok "${#targets[@]} Arch packages of all sets resolve to $(wc -l < "$TMP/plan") with no conflict"; fi
    wrong="$(grep -xE '(lib32-)?(nvidia-utils|vulkan-intel|vulkan-swrast|vulkan-nouveau|vulkan-asahi|amdvlk)' "$TMP/plan" | paste -sd' ' || true)"
    if grep -qx vulkan-radeon "$TMP/plan" && grep -qx lib32-vulkan-radeon "$TMP/plan" && [[ -z "$wrong" ]]; then
        ok "Vulkan drivers: vulkan-radeon and lib32-vulkan-radeon, no other"
    else
        bad "Vulkan drivers wrong: other drivers '${wrong}'"
    fi
    if grep -qx pipewire-jack "$TMP/plan" && ! grep -qx jack2 "$TMP/plan"; then ok "jack: pipewire-jack, not jack2"
    else bad "jack resolves to jack2 on a fresh install"; fi
else
    bad "the sets do not resolve: $(head -5 "$TMP/plan.err" | paste -sd' ')"
fi

echo
if [[ $fail == 0 ]]; then echo "ALL PASSED"; else echo "SOME TESTS FAILED"; fi
exit $fail
