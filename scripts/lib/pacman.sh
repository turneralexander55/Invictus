# shellcheck shell=bash
# ------------------------------------------------------------
# Shared pacman helpers (installed as /usr/lib/invictus/lib/pacman.sh by
# invictus-tools). Used by pending-extras and invictus-sys, so both accept
# the same package names and install the same way: the whole system at
# once (pacman -Syu --needed), never -Sy alone (design 1.4, MUST A4), with
# the system's own pacman.conf, so only packages from the configured repos
# can come in (MUST A3).
#
#   valid_package_name NAME     a plain repo package name or repo/name;
#                               never an option, a path, a URL or a file
#   pacman_install_needed CMD... runs CMD... -Syu --needed --noconfirm -- names
#                               under the INHIBIT array (shutdown and sleep
#                               held off while pacman runs)
#   pacman_install_classified NAME... the same, and sets PACMAN_FAILURE:
#                               "" (it worked), "download" (no connection
#                               or no mirror answered: worth trying again
#                               later) or "other" (a conflict, a bad
#                               signature, a full disk...: trying again
#                               will not help)
# Callers set PACMAN and INHIBIT (an array) before calling.
# ------------------------------------------------------------

# Lowercase letters, digits and @._+- as Arch names allow, starting with a
# letter or digit; optionally one "repo/" prefix of the same characters.
valid_package_name() {
    [[ "$1" =~ ^([a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9@._+-]*$ && ${#1} -le 128 ]]
}

# pacman_install_needed NAME...: install (or keep) NAME... and update
# everything else in the same transaction.
pacman_install_needed() {
    "${INHIBIT[@]}" "$PACMAN" -Syu --needed --noconfirm -- "$@"
}

# pacman's own summary lines (LC_ALL=C) when the databases or the packages
# could not be downloaded. Checked against pacman 7 in Arch with no network
# (tests/pkgs/e2e-sys.sh). Nothing else counts as a download failure, and
# there is no separate `pacman -Sy` probe (MUST A4).
PACMAN_DOWNLOAD_FAILED='failed to synchronize all databases|failed to retrieve some files|download library error'
pacman_install_classified() {
    local err rc=0
    PACMAN_FAILURE=""
    err="$(mktemp)"
    pacman_install_needed "$@" 2>"$err" || rc=$?
    cat -- "$err" >&2
    if ((rc != 0)); then
        if grep -qE -- "$PACMAN_DOWNLOAD_FAILED" "$err"; then PACMAN_FAILURE=download; else PACMAN_FAILURE=other; fi
    fi
    rm -f -- "$err"
    return "$rc"
}
