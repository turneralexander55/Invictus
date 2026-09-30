#!/usr/bin/env bash
# ------------------------------------------------------------
# iso/render-art.sh: render the installer and boot-splash PNGs from their
# SVG sources. The PNGs are committed, so package builds need no SVG tools
# (build-repo.sh builds our own packages without installing makedepends).
# Run it after changing any of the SVGs; needs rsvg-convert (librsvg).
#
#   iso/render-art.sh            render into the checkout
#   iso/render-art.sh --check    exit 1 if a PNG is missing or older than
#                                its SVG
# ------------------------------------------------------------
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BRAND="$ROOT/installer/branding/invictus"
PLY="$ROOT/iso/boot-branding/plymouth"
CHECK=false
[[ "${1:-}" == --check ]] && CHECK=true

# target|source|width|height ("-" keeps the SVG's own size)
jobs=(
    "$BRAND/logo.png|$ROOT/docs/brand/invictus-mark.svg|256|256"
    "$BRAND/icon.png|$ROOT/docs/brand/invictus-mark.svg|64|64"
    "$BRAND/welcome.png|$ROOT/assets/wallpapers/sol.svg|960|540"
)
for f in "$BRAND"/art/*.svg; do
    jobs+=("$BRAND/$(basename "${f%.svg}").png|$f|480|300")
done
for f in "$PLY"/*.svg; do
    if [[ "$(basename "$f")" == field.svg ]]; then
        jobs+=("$PLY/field.png|$f|-|-")
    else
        # 192 px; the Plymouth script scales to 96 (sharp on HiDPI too).
        jobs+=("$PLY/$(basename "${f%.svg}").png|$f|192|192")
    fi
done

stale=0
for j in "${jobs[@]}"; do
    IFS='|' read -r out src w h <<<"$j"
    if $CHECK; then
        # Compare commit times, not file mtimes: a fresh checkout (CI, a
        # merge) writes files in any order, so mtimes say nothing.
        if [[ ! -f "$out" ]]; then echo "missing: ${out#"$ROOT"/}"; stale=1; continue; fi
        st=$(git -C "$ROOT" log -1 --format=%ct -- "$src" 2>/dev/null || true)
        ot=$(git -C "$ROOT" log -1 --format=%ct -- "$out" 2>/dev/null || true)
        if [[ -n "$st" && -n "$ot" ]]; then
            if (( st > ot )); then echo "stale: ${out#"$ROOT"/}"; stale=1; fi
        elif [[ "$src" -nt "$out" ]]; then echo "stale: ${out#"$ROOT"/}"; stale=1; fi
        continue
    fi
    size=()
    [[ "$w" == - ]] || size=(-w "$w" -h "$h")
    if [[ "$src" == */invictus-mark.svg ]]; then
        # The mark is drawn in currentColor; the installer shows it in sol.
        sed 's/currentColor/#E0A64B/g' "$src" | rsvg-convert "${size[@]}" -o "$out"
    else
        rsvg-convert "${size[@]}" -o "$out" "$src"
    fi
    echo "rendered ${out#"$ROOT"/}"
done
exit "$stale"
