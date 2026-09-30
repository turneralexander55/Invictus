# Move your current machine onto the Invictus packages

For Alex, on the desktop that runs the old hyprdots setup. About 45 minutes,
most of it waiting for downloads. Your desktop and packages change at step 6.
Before that: steps 1, 2, 3 and 5 change nothing on the system (step 5 only
prints), and step 4 installs build tools with `sudo` unless you build in a
container (docker or podman). Step 9 puts everything back if you want.

What changes: your desktop runs from the Invictus packages and the new Lua
config (the look Venus designed), and updates come from `invictus-update`
instead of `git pull`. Your own binds (the dashboard-tmux one, anything you
added, and your workspace-to-monitor lines) come along in
`~/.config/hypr/user.lua`. Anything the tool cannot convert is listed as
"not ported" with its file and line, and kept there as a comment. Your old files are kept in a
backup folder.

Before you start: the package signing key exists
(`docs/checklists/signing-key.md`, steps 1 to 3) and you know its
fingerprint (`FPR` below).

## 1. Tell us about the disk (decision D1)

- [ ] Run `findmnt / -o FSTYPE,OPTIONS` and send the output to the team.
  Snapshots before updates only exist on btrfs; either answer is fine for
  this checklist.
  You should see two lines: a header (`FSTYPE OPTIONS`) and one line that
  starts with the filesystem, for example `btrfs rw,noatime,...` or
  `ext4 rw,relatime`.

## 2. Get a separate copy of the repo

Leave `~/hyprdots` alone: your current desktop runs from it until step 7.

- [ ] ```
  git clone -b ccr-e2dd4715-j4vnyk https://github.com/turneralexander55/invictus ~/src/invictus
  cd ~/src/invictus
  git branch --show-current
  ```
  (The repo was renamed from hyprdots; GitHub shows it as "Invictus".
  Moneta tells you the branch name if it has moved on.)
  You should see `Cloning into '/home/<you>/src/invictus'...` ending in
  `done.`, then `ccr-e2dd4715-j4vnyk` from the last command.

## 3. Put your public key in the copy

- [ ] ```
  gpg --armor --export FPR > pkgs/own/invictus-keyring/invictus.gpg
  ```
  Only the public half. The build refuses a private key. Check it:
  ```
  head -1 pkgs/own/invictus-keyring/invictus.gpg
  ```
  You should see `-----BEGIN PGP PUBLIC KEY BLOCK-----`. If it says PRIVATE
  KEY, or the file is empty, stop and tell the team.

## 4. Build the package repo on your machine, signed with your key

Until the team merges this to `main`, GitHub does not publish the packages,
so you build them once here.

- [ ] Bring the system fully up to date first:
  ```
  sudo pacman -Syu
  ```
  The build installs build tools with `pacman -S` (makepkg `--syncdeps`), and
  on a system that is not fully up to date that is a partial upgrade, which
  can break things. Reboot if it upgrades the kernel.
- [ ] If `docker` or `podman` is installed (recommended: no build tools go
  on your system, and no package code runs where your key is):
  ```
  INVICTUS_SIGN_KEY=FPR scripts/build-repo.sh --in-container
  ```
  Without either, the same command without `--in-container` builds on your
  system and may ask for `sudo` to install build tools.
  The container builds everything (about 20 minutes the first time: it
  compiles Calamares and two limine tools and downloads Proton GE, Zen, VS
  Code and Claude Code, about 1.5 GB), then the files come back to you and
  it signs them here: it asks for your key's passphrase once. It also
  downloads the pinned Hyprland set from the Arch archive and checks Arch's
  signatures.
  You should see `==> Building in ... (no signing key in there)`, later
  `==> Signing and indexing on this machine` and `==> Signing with key
  FPR`, and at the end a list of files in `out/repo`, among them
  `invictus-testing.db` and a `.sig` next to every `.pkg.tar.zst`.

## 5. Look at the plan

- [ ] ```
  scripts/dev/adopt.sh --server "file://$PWD/out/repo"
  ```
  Nothing changes. Read it:
  - the key fingerprint matches yours;
  - the packages marked `invictus-testing` (Invictus packages and the pinned
    Hyprland set);
  - "user.lua would end with": your own binds and workspace lines, as Lua;
  - any `not ported: FILE:LINE: ...` line: something in your old config the
    tool could not convert (a `monitorv2` block, a workspace option with no
    Lua form, a file it could not read). Note them; you can add them to
    `~/.config/hypr/user.lua` or `monitors.lua` by hand later;
  - any **PROBLEM** line. The usual ones:
    - an AUR package our repo does not carry: every one the sets use is in
      it now, so tell the team;
    - `[multilib]` is off: turn it on in `/etc/pacman.conf`, or add
      `--skip gaming`.
  You should see numbered steps `[1]` to `[6]`, the `+[invictus-testing]`
  block that would go into `/etc/pacman.conf`, and at the end
  `Dry run finished. Nothing was changed.`

## 6. Adopt

- [ ] ```
  scripts/dev/adopt.sh --server "file://$PWD/out/repo" --apply
  ```
  pacman asks before it installs (this is also a full system update). At the
  end it says "Adopted" and prints the backup folder and the undo command.
  Copy both somewhere.

If it says "The new config did not load", your old config is already back;
send the team the lines above that message. If it stops with "adopt.sh
stopped at step N", something failed part way (a download, pacman); run the
undo command it prints, then send the team the lines above.

## 7. Log out and back in

- [ ] Save your work and close your programs first. The old session's
  Super+Delete logs out at once, without asking. Then log out (Super+Delete)
  and log in again.
  You should see the login screen, then the desktop with the Sol wallpaper
  and the bar. If you do not, go to "If the desktop does not start" below.

## 8. Check on your hardware

Tick each one, or note what is wrong:

- [ ] The desktop starts; the wallpaper is Sol (the sun).
- [ ] All three monitors are placed as before, and the workspaces sit on the
  monitors your old config set.
- [ ] The bar is on your main monitor, with workspaces 1-3, 4-6 and 7-9 on
  the right monitors.
- [ ] Super+/ shows the key list; Super+Shift+T opens the theme picker and a
  theme applies without logging out.
- [ ] Your dashboard bind (Super+minus) opens the tmux dashboard.
- [ ] Super+Delete and Super+Alt+Ctrl+Escape ask first; No does nothing.
- [ ] Screenshots (Print, Shift+Print), volume and media keys.
- [ ] Share a window in Discord (xwaylandvideobridge) and your screen in a
  browser call.
- [ ] Steam starts a game; gamescope and MangoHud behave as before.
- [ ] Click the updates number on the bar: a terminal runs `invictus-update`
  and ends with "Update complete".
- [ ] `invictus-doctor` in a terminal: no FAIL lines. Send the team the
  output either way.

## If the desktop does not start

A black screen, or straight back to the login screen:

1. Press Ctrl+Alt+F3 and log in with your user name and password.
2. ```
   cd ~/src/invictus
   scripts/dev/adopt.sh --undo --apply
   ```
3. `reboot`.

You are back on the old desktop. Tell the team what you saw on the screen
before it failed.

## 9. If you want your old desktop back

- [ ] ```
  cd ~/src/invictus
  scripts/dev/adopt.sh --undo            # prints what it will do
  scripts/dev/adopt.sh --undo --apply
  ```
  Then log out and back in. Your config folders, `/etc/pacman.conf` and the
  package list are as they were before step 6. Packages the system update
  upgraded stay upgraded; the GTK accent colour the theme set stays until you
  change it.

## After this

Keep using `invictus-update` (or the bar button) for updates, not
`~/hyprdots/scripts/update.sh`. AUR packages you installed yourself (with
paru) now update with `invictus-update --aur`; without it the command only
tells you how many have updates. When the team merges to `main`, adopted
machines switch from the local `out/repo` to the published repo; the team
sends the one-line change for `/etc/pacman.conf`.
