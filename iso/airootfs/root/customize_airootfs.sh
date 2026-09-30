#!/usr/bin/env bash
# Runs inside the image once packages are in (mkarchiso, then deleted).
# archiso marks this hook deprecated; it is used for three things that have
# no other hook in archiso 91 (build note):
set -euo pipefail

# 1. The live initramfs. limine-mkinitcpio-hook replaces mkinitcpio's
#    kernel pacman hook with its own, which needs an ESP and does nothing in
#    the build chroot, so build archiso's initramfs here with the stock
#    mkinitcpio and /etc/mkinitcpio.conf.d/archiso.conf.
kver="$(basename "$(dirname "$(grep -lx linux-cachyos /usr/lib/modules/*/pkgbase)")")"
install -Dm644 "/usr/lib/modules/$kver/vmlinuz" /boot/vmlinuz-linux-cachyos
/usr/bin/mkinitcpio -k "$kver" -g /boot/initramfs-linux-cachyos.img

# 2. The live user's Hyprland loader (user.lua is already in the image).
install -d -o 1000 -g 100 /home/liber/.config/hypr
install -m 644 -o 1000 -g 100 /usr/share/invictus/config/hypr/hyprland.lua /home/liber/.config/hypr/hyprland.lua

# 3. Services on the live system. NetworkManager and sddm are enabled on the
#    installed system by Calamares; the live system logs in on tty1 instead.
systemctl enable NetworkManager.service
