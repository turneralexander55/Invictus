# shellcheck shell=bash
# stand_in_heavy_aur COPY: in a copy of the repo, replace each AUR pin
# listed in tests/pkgs/fixtures/aur-heavy.txt with an empty stand-in
# package of the same name (version 0, same provides and conflicts), so the e2e tests do not spend 20
# minutes and 1.5 GB on them but every set still resolves. CI's aur-pins
# workflow builds the real ones. E2E_FULL_AUR=1 keeps the real ones.
stand_in_heavy_aur() {
    local copy="$1" n rel done_=()
    if [[ "${E2E_FULL_AUR:-}" == 1 ]]; then echo "E2E_FULL_AUR=1: building every AUR pin"; return 0; fi
    while read -r n _; do
        [[ -n "$n" && "$n" != \#* ]] || continue
        [[ -d "$copy/pkgs/aur/$n" ]] || continue
        # keep what pacman resolves with: provides and conflicts
        rel="$(bash -c 'source "$1" >/dev/null; for v in provides conflicts; do declare -n a=$v; printf "%s=(" "$v"; printf "\047%s\047 " "${a[@]}"; echo ")"; done' _ "$copy/pkgs/aur/$n/PKGBUILD")"
        rm -rf "${copy:?}/pkgs/aur/$n"
        mkdir -p "$copy/pkgs/aur/$n"
        printf "pkgname=%s\npkgver=0\npkgrel=1\npkgdesc='e2e stand-in'\narch=('any')\nlicense=('custom')\n%s\npackage() { :; }\n" "$n" "$rel" \
            > "$copy/pkgs/aur/$n/PKGBUILD"
        done_+=("$n")
    done < "$copy/tests/pkgs/fixtures/aur-heavy.txt"
    if [[ ${#done_[@]} -gt 0 ]]; then echo "Empty stand-ins for (E2E_FULL_AUR=1 builds the real ones): ${done_[*]}"; fi
}
