# shellcheck shell=bash
# drop_heavy_aur COPY: remove the AUR pins listed in
# tests/pkgs/fixtures/aur-heavy.txt from a copy of the repo, so the e2e
# tests do not spend 20 minutes and 1.5 GB on them (CI's aur-pins workflow
# builds each one). E2E_FULL_AUR=1 keeps them. Prints what it dropped.
drop_heavy_aur() {
    local copy="$1" n dropped=()
    [[ "${E2E_FULL_AUR:-}" == 1 ]] && { echo "E2E_FULL_AUR=1: building every AUR pin"; return 0; }
    while read -r n _; do
        [[ -n "$n" && "$n" != \#* ]] || continue
        if [[ -d "$copy/pkgs/aur/$n" ]]; then rm -rf "${copy:?}/pkgs/aur/$n"; dropped+=("$n"); fi
    done < "$copy/tests/pkgs/fixtures/aur-heavy.txt"
    [[ ${#dropped[@]} -eq 0 ]] || echo "Left out of this test (E2E_FULL_AUR=1 keeps them): ${dropped[*]}"
}
