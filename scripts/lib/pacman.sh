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
