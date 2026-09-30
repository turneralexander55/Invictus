# Move your current machine onto the Invictus packages

For Alex, on the desktop that runs the old hyprdots setup. About 45 minutes,
most of it waiting for downloads. Nothing changes until step 6, every step
before it only prints, and step 9 puts everything back if you want.

What changes: your desktop runs from the Invictus packages and the new Lua
config (the look Venus designed), and updates come from `invictus-update`
instead of `git pull`. Your own binds (the dashboard-tmux one, anything you
added) come along in `~/.config/hypr/user.lua`. Your old files are kept in a
backup folder.

Before you start: the package signing key exists
(`docs/checklists/signing-key.md`, steps 1 to 3) and you know its
fingerprint (`FPR` below).

## 1. Tell us about the disk (decision D1)

- [ ] Run `findmnt / -o FSTYPE,OPTIONS` and send the output to the team.
  Snapshots before updates only exist on btrfs; either answer is fine for
  this checklist.

## 2. Get a separate copy of the repo

Leave `~/hyprdots` alone: your current desktop runs from it until step 7.

- [ ] ```
  git clone -b invictus-p1 https://github.com/turneralexander55/invictus ~/src/invictus
  cd ~/src/invictus
  ```
  (Moneta tells you the branch name if it has moved on.)

## 3. Put your public key in the copy

- [ ] ```
  gpg --armor --export FPR > pkgs/own/invictus-keyring/invictus.gpg
  ```
  Only the public half. The build refuses a private key.

## 4. Build the package repo on your machine, signed with your key

Until the team merges this to `main`, GitHub does not publish the packages,
so you build them once here.

- [ ] ```
  INVICTUS_SIGN_KEY=FPR scripts/build-repo.sh
  ```
  It asks for your key's passphrase, may ask for `sudo` to install build
  tools (cmake for xwaylandvideobridge), downloads the pinned Hyprland set
  from the Arch archive and checks Arch's signatures. It ends with a list of
  files in `out/repo`.

## 5. Look at the plan

- [ ] ```
  scripts/dev/adopt.sh --server "file://$PWD/out/repo"
  ```
  Nothing changes. Read it:
  - the key fingerprint matches yours;
  - the packages marked `invictus-testing` (Invictus packages and the pinned
    Hyprland set);
  - "user.lua would end with": your own binds, as Lua;
  - any **PROBLEM** line. The usual ones:
    - an AUR package our repo does not carry yet (for example
      `zen-browser-bin`): install it the old way first, `paru -S <name>`;
    - `[multilib]` is off: turn it on in `/etc/pacman.conf`, or add
      `--skip gaming`.

## 6. Adopt

- [ ] ```
  scripts/dev/adopt.sh --server "file://$PWD/out/repo" --apply
  ```
  pacman asks before it installs (this is also a full system update). At the
  end it says "Adopted" and prints the backup folder and the undo command.
  Copy both somewhere.

If it says "The new config did not load", your old config is already back;
send the team the lines above that message.

## 7. Log out and back in

- [ ] Log out (Super+Delete, then Yes) and log in again.

## 8. Check on your hardware

Tick each one, or note what is wrong:

- [ ] The desktop starts; the wallpaper is Sol (the sun).
- [ ] All three monitors are placed as before.
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
`~/hyprdots/scripts/update.sh`. When the team merges to `main`, adopted
machines switch from the local `out/repo` to the published repo; the team
sends the one-line change for `/etc/pacman.conf`.
