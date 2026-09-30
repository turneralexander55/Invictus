# Try the Invictus ISO on real hardware

For Alex. About two hours: 10 minutes to make the stick, 15 to
try the live desktop, 20 to install, the rest to check snapshots and a
second, offline install for the extras (section 8). You need a
USB stick (8 GB or more) and a **spare disk** in the PC, or a spare PC. The
install erases the disk you pick; nothing else is touched unless you pick it.

What has been checked before you: the ISO builds, its image has no secrets
in it, and the installer's jobs pass their tests on a fake disk and on a
real btrfs disk image in a container. It was booted in a virtual machine
without a graphics card (see "What was not tested" at the end). This is the
first time it meets real hardware, so expect rough edges and note them.

Before you start:
- In the firmware settings (Del or F2 at power-on), **turn Secure Boot
  off**. Invictus does not support Secure Boot yet (decision D16), and it
  saves Ventoy's key-enrolment screen.
- Know which disk is the spare one: its size and make, as the firmware or
  Windows shows it. The installer names disks by size and model.

## 1. Get the ISO

- [ ] Download `invictus-<date>-x86_64.iso` and its `.sha256` from the
  GitHub run Moneta links (Actions, "iso", the run, "Artifacts", `iso`), or
  from the `iso-<date>` release when there is one.
- [ ] Check it. In a terminal in the download folder:
  ```
  sha256sum -c invictus-*.iso.sha256
  ```
  You should see `invictus-....iso: OK`. Anything else: download again.

## 2. Put it on the stick: Ventoy (first choice)

Ventoy boots ISO files straight from the stick: copy the file, pick it from
a menu. Ventoy's tested list includes Arch Linux ISOs up to 2026.05.01 in
UEFI mode (ventoy.net/en/isolist.html), and Invictus boots the same way
they do: archiso's own start-up files and its standard `archisosearchuuid`
parameter, which Ventoy's Arch support hooks into (Ventoy source,
`IMG/cpio/ventoy/hook/arch/ventoy-hook.sh`). Nothing on the ISO names a
fixed device or partition.

- [ ] If the stick has no Ventoy yet: install Ventoy 1.1 or newer on it
  (ventoy.net, "Get started"). This erases the stick.
- [ ] Copy the `.iso` file onto the stick's big partition (named `Ventoy`),
  like any file. Eject the stick properly.
- [ ] Put the stick in the PC, power on, open the one-time boot menu (often
  F11, F12 or F8) and pick the USB stick's **UEFI** entry.
- [ ] You see Ventoy's menu with the ISO's file name. Pick it, then
  "Boot in normal mode".

If Ventoy shows an error, or the screen stays black for more than 3
minutes after the next step, use dd instead (section 3). Ventoy's "GRUB2
mode" does not apply here: the ISO starts with systemd-boot, not GRUB.

## 3. Or: write the stick with dd (fallback)

This erases the whole stick.

- [ ] Find the stick's device: `lsblk -d -o NAME,SIZE,MODEL,TRAN` (the one
  with `usb` and the stick's size, for example `sdb`).
- [ ] Write it (replace `sdX`; the wrong letter erases that disk):
  ```
  sudo dd if=invictus-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
  ```
  Etcher or Fedora Media Writer do the same with a window.
- [ ] Boot from the stick's **UEFI** entry as above.

## 4. The boot menu and the live desktop

- [ ] A text menu, white on black: `Invictus` (highlighted), `Invictus,
  Advanced install`, `Invictus, safe graphics (installer only, messages on
  screen)`, `Memory test (Memtest86+)`, `EFI Shell`, `Reboot Into Firmware
  Interface`, and `Boot in 5s.` counting down. (Seen in the virtual
  machine.) This menu cannot be coloured (build note 2); the installed
  machine's menu is in Dusk colours.
- [ ] Pick `Invictus, Advanced install` (you are the Advanced user).
- [ ] The boot splash: a dark screen with the Invictus mark in the middle,
  greyed out; its rays light up in gold one by one, left to right, then the
  disc. About 30 seconds to 2 minutes from a USB 3 port.
- [ ] Hyprland starts with the Invictus look, and the installer window
  opens by itself. The live user is `liber`; it needs no password.
- [ ] Try the desktop before installing if you like: close the installer
  (it asks to quit), use Super+Enter for a terminal. To bring the installer
  back: Super+Space (launcher), "Install Invictus (Advanced)".

If the screen stays black after the splash, or Hyprland closes at once,
the stick falls back by itself to the installer on its own (no desktop,
just the installer window). Note which happened. If nothing shows at all,
restart and pick `safe graphics`: the same installer with kernel messages
on screen; send a phone photo of the last lines.

## 5. Install to the spare disk (Advanced path)

The installer's pages, left column top to bottom:

- [ ] **Welcome**: language list. Pick yours, `Next`. (It may say the
  computer is not plugged in or not online: those are advice only.)
- [ ] **Location**: time zone on a map, preselected when online.
- [ ] **Keyboard**: layout, preselected from the language.
- [ ] **Desktop**: two pictures, `Atrium` (preselected) and `Tessera`.
  Pick `Tessera`.
- [ ] **Guard rails**: `Custodia` (preselected) and `Libertas`. Pick
  `Libertas` for your own machine, or `Custodia` to see a friend's setup.
- [ ] **Extras**: a list with tick boxes: `Office` (ticked), `Games`,
  `Programming`, `Chinese, Japanese and Korean`. The text at the top says
  they come from the internet and that the install still finishes without
  it. For this first test be online (cable, or Wi-Fi joined from the live
  desktop's network icon) and tick `Office` and `Games`.
- [ ] **Users**: your name, login name (filled in from the name), computer
  name (`<first name>-invictus`), password twice. There is no separate
  administrator password: you are the administrator, root stays locked.
- [ ] **Partitions**: pick the **spare disk** in the list at the top
  (check its size and model). Leave `Erase disk` chosen. Leave `Encrypt
  system` unticked for this first test (it works, but a first test without
  it is easier to read). Under the bars you see the new layout: a 4 GiB
  FAT32 partition and a btrfs one.
- [ ] **Summary**: what will be done. Check the disk name once more.
- [ ] **Your files**: `Invictus will replace everything on this
  computer.` and what it found on the disk. `Install` stays grey until you
  tick `I've saved the photos and files I want to keep.`
- [ ] **Install**: a quiet screen, "Copying Invictus to the disk", with a
  progress bar and the current step under it: Tidying up the live session,
  Setting up your account, Setting up start-up, Adding the extras you
  picked, Setting up safety copies. 10 to 25 minutes, plus the extras'
  download (Games is about 1.5 GB). The bar does not move during the
  extras step; that is expected.
- [ ] **Done**: "All done" with `Restart now` ticked. Click `Done`, take
  the stick out when the screen goes black.

If it stops with an error: take a photo of the error text (`Toggle log`,
right of the progress bar, shows the details). Before
restarting, copy the installer's log to another stick (the live system
forgets it on restart): in a terminal,
`sudo cp ~/.cache/calamares/session.log /run/media/liber/<stick>/`.

## 6. First start

- [ ] The start-up menu: dark background, `Invictus` in gold at the top,
  one entry, `linux-cachyos`, under `Invictus` (there is no second
  kernel any more), and a `Snapshots` group with "Fresh install" (it may
  only appear from the second start: the snapshot service adds it on
  first boot). Starts `linux-cachyos` after 3 seconds.
- [ ] In the firmware's own boot menu (F11/F12) the disk is listed as
  `Invictus`.
- [ ] The splash again, then the login screen. Log in with your password.
- [ ] You land on the Tessera desktop (or Atrium, if you picked it; the
  Atrium shell is not built yet, so it looks like Tessera for now).
- [ ] In a terminal, these should all hold:
  ```
  cat /etc/invictus/guardrails          # libertas (or custodia)
  cat ~/.config/invictus/flavor         # tessera (or atrium)
  cat /etc/os-release | head -2         # NAME="Invictus"
  sudo passwd -S root                   # "root L ..." (locked)
  findmnt -no FSTYPE,OPTIONS /          # btrfs ... subvol=/@
  sudo btrfs subvolume list /           # @ @home @home-snapshots @log @cache @pkg @snapshots @vm @swap
  sudo snapper list                     # 0 current, 1 "Fresh install"
  sudo snapper -c home get-config | grep -E 'ALLOW_GROUPS|SYNC_ACL'   # users, yes
  systemctl is-active NetworkManager bluetooth sddm cups.socket avahi-daemon
  cat /etc/invictus/release             # version, channel=testing, build, installed=
  uname -r                              # ends in -cachyos
  pacman -Q invictus-office invictus-gaming   # both installed (the extras you ticked)
  ls /var/lib/invictus/pending-extras   # "No such file": nothing left over
  ```
  A dev ISO's release file says `keyring=dev-throwaway`: that machine
  cannot install updates from the real repo until the real signing key
  exists. Fine for this test; reinstall from a release ISO later. The
  same goes for extras: on a dev ISO pacman refuses the published repo's
  signatures, so the ticked extras stay pending
  (`/var/lib/invictus/pending-extras` lists them). Test the extras lines
  above with a release ISO.

## 7. Boot a snapshot from the limine menu

- [ ] Make a change you can see, with a snapshot around it:
  ```
  sudo pacman -S cowsay       # snap-pac takes a "pre" and "post" snapshot
  cowsay hello                 # works
  sudo snapper list            # new pre/post pair with "pacman -S cowsay"
  ```
- [ ] Restart. In the limine menu open `Snapshots` (arrow keys, Enter) and
  pick the **pre** snapshot from a minute ago (or "Fresh install").
- [ ] It boots to the login screen as usual. It is a read-only snapshot
  with a temporary overlay, so changes you make now are thrown away.
- [ ] `cowsay hello` says "command not found". `findmnt -no OPTIONS /`
  shows the snapshot's path (`.snapshots/<n>/snapshot`).
- [ ] To keep the machine at that snapshot: `sudo limine-snapper-restore`,
  pick the same snapshot, confirm, restart. Afterwards, normal boot has no
  `cowsay`. To go back instead: just restart and pick `linux-cachyos`;
  `cowsay` is still there.
- [ ] Each snapshot keeps its own kernel, which is what makes one kernel
  safe: `sudo limine-snapper-info` lists the snapshots with their kernel
  versions and "verified", and `sudo ls /boot/*/limine_history/` shows
  copies of `vmlinuz` and `initramfs`. The real test is the next
  linux-cachyos update: after it, pick the snapshot from before the
  update in `Snapshots`, and `uname -r` shows the old version.

## 8. Extras without internet

A second install on the spare disk (or a friend's test machine), this
time offline.

- [ ] Unplug the network cable and do not join Wi-Fi on the live desktop.
- [ ] Install with the plain path (the normal boot entry). On **Extras**
  leave `Office` ticked and also tick `Chinese, Japanese and Korean`.
- [ ] The install finishes as usual (the extras step is quick and does
  not show an error).
- [ ] First start, log in, still offline:
  ```
  cat /var/lib/invictus/pending-extras        # invictus-office, noto-fonts-cjk
  systemctl is-enabled invictus-extras.service # enabled
  ```
- [ ] Connect to the network. Within about 10 minutes (or restart):
  ```
  pacman -Q invictus-office noto-fonts-cjk     # both installed
  ls /var/lib/invictus/pending-extras          # "No such file"
  systemctl is-enabled invictus-extras.service # disabled
  journalctl -u invictus-extras -b             # "pending-extras: done"
  ```
- [ ] While it runs, `Power off` from the desktop is held back until it
  finishes (a shutdown in the middle of an install would break things).

## What to send back

Tell Moneta, with a phone photo where a screen looked wrong:
1. Ventoy worked, or you needed dd (and what Ventoy showed).
2. Hyprland or the fallback installer window on the live stick.
3. Install time, and any error (with the log from step 5).
4. The limine menu colours and entries; whether the firmware lists
   `Invictus`.
5. The outputs of step 6 that did not match.
6. Whether the snapshot boot and `limine-snapper-restore` did what step 7
   says.
7. The extras: installed during the install (online), and after the
   first start with internet (step 8).

## What was not tested before you

- No real machine and no GPU: the virtual machine had no 3D, so the live
  session used its fallback (the installer alone in a kiosk window).
  Hyprland on the stick is untested.
- No install finished in the virtual machine (it had no KVM, so it ran at
  software speed); the jobs were tested on a disk image in a container
  instead, where the firmware boot entry could not be written.
- NVRAM (`Invictus` in the firmware menu), Plymouth on a real screen,
  suspend, Wi-Fi in the live system, Ventoy itself.
- The linux-cachyos kernel on real hardware (it replaced linux and
  linux-lts on 2026-09-30), and a snapshot boot across a kernel update.
- The Extras page and its install, online and offline: the jobs were
  tested with a fake target, not a real download. The NVIDIA firmware
  extra (added by itself on a machine with an NVIDIA card).
