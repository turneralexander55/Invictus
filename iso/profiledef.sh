#!/usr/bin/env bash
# shellcheck disable=SC2034
# ------------------------------------------------------------
# Invictus archiso profile (design 2.1), copied from archiso 91's releng
# profile and edited:
#  - names without the Arch name (trademark policy, design intro);
#  - UEFI only (D5): uefi.systemd-boot, no BIOS syslinux;
#  - the live image is the installed system (Calamares unpacks it), so
#    packages.x86_64 is the desktop plus the live-only installer bits;
#  - install_dir stays "arch" and the boot entries keep archiso's standard
#    parameters (archisobasedir, archisosearchuuid) and hooks, which is what
#    Ventoy's Arch support hooks into (docs/checklists/iso-test.md);
#  - squashfs with xz like releng; scripts/build-iso.sh --fast swaps in
#    zstd for quicker dev builds.
# scripts/build-iso.sh fills in INVICTUS_VERSION and INVICTUS_COMPRESSION.
# ------------------------------------------------------------

iso_name="invictus"
iso_version="${INVICTUS_VERSION:-$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)}"
iso_label="INVICTUS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
# The support identity from iso/support.env (checked by tests/iso/profile.sh).
iso_publisher="Sol Invictus support <solinvictus.support@gmail.com>"
iso_application="Invictus live and install medium"
install_dir="arch"
bootmodes=('uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
if [[ "${INVICTUS_COMPRESSION:-xz}" == zstd ]]; then
  airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
else
  airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
fi
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/liber"]="0:0:440"
  ["/root"]="0:0:750"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/home/liber"]="1000:100:750"
)
