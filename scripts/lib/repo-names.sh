# shellcheck shell=bash
# ------------------------------------------------------------
# File names in the [invictus] repo.
#
# The repo is served from GitHub release assets. GitHub renames an
# uploaded asset whose name has characters outside a safe set (it swaps
# them for '.'), but pacman downloads the exact %FILENAME% that
# repo-add recorded. A package with an epoch (proton-ge-custom-bin
# 1:GE_Proton11_7-1) has a ':' in its makepkg name, so the upload and
# the database would disagree and pacman would get a 404.
#
# So every package is stored under a name with only [A-Za-z0-9._-]
# before repo-add sees it. pacman reads name and version from the
# database and the package's .PKGINFO, never from the file name, so a
# renamed file installs normally (tests/pkgs/e2e-arch.sh installs an
# epoch package this way).
# ------------------------------------------------------------

# Print the repo name for a package file name (no newline).
repo_file_name() {
    local f="${1##*/}"
    printf '%s' "${f//[^A-Za-z0-9._-]/.}"
}
