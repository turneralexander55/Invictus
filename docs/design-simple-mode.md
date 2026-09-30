# Invictus: Simple mode, the admin, update and safety model

Author: Minerva (consultant). Date: 2026-09-30, revised the same day after DS1. Status: draft for Alex's owner decisions (section 9), then build. Addendum to `design.md`; the experience side is Venus's `simple-mode.md`.

The ask (Alex, 2026-09-30): an "ultra dumb mode" for friends who do not know what "run as administrator" means. This document decides who holds the keys on such a machine, how it stays updated and bootable with no human decision, how apps get installed without a terminal, what the assistant may do, and how Alex helps from afar. Everything in `design.md` still holds unless a line here says otherwise; section 7 lists the exact changes to the existing MUSTs.

**Revised after DS1 (Alex, 2026-09-30).** The first draft made the person a non-administrator with a second account, `custos`, for Alex. Alex denied it: "They have to be responsible for themselves. I can SA their systems for free. We should just childproof stuff without restricting their ability to ever act with it." This revision follows that: the person is the administrator of their own machine, nothing they could do before is taken away, and the machine childproofs instead. Every changed part carries a "Revised after DS1" note; parts without one are unchanged from the first draft (automatic updates, boot guard, Flatpak apps, RustDesk on request, the assistant never showing a command).

Read section 0 for the decisions and section 9 for what only Alex can decide.

Names (Clio, 2026-09-30): **Simple** is the machine-wide safety model in this document (`/etc/invictus/mode = simple`; its opposite is Standard). It is a team word and never appears on screen. The desktop the person sees is **Classic** (Venus's `simple-mode.md`); Alex's is **Tiling**. The **helper** is the person who helps remotely (Alex, or whoever `helper_person` names); a **helper request** is what the person sees as **Ask Alex**. The assistant is **Moneta**; the dashboard is the **Desk**.

---

## 0. Decisions in one screen

Revised after DS1 (Alex, 2026-09-30): the Admin, Assistant, Remote help and Break glass rows changed; Updates and Apps did not.

| Area | Decision | Why (short) |
|---|---|---|
| Admin | The person is the administrator: in `wheel`, sudo with their own password, polkit prompts answered with their own password. No second account by default. The machine childproofs: every prompt says in plain words what will change, a snapshot is taken before any admin authentication so it can be undone, and the few truly destructive actions get a pause and a scam cue. Nothing is locked away. | Alex's call (DS1): responsible for themselves, childproofed, never restricted. The prompt is not the safeguard; the snapshot and the plain words are. |
| Updates | Automatic, stable channel only, daily when the machine is idle, on mains power, not in a game, not in a help session. Snapshot before, doctor after, undo from the package cache if the doctor fails, and a boot guard that boots the pre-update snapshot by itself if two boots in a row do not reach the desktop. The person can pause updates for up to 14 days in Settings, with a warning; turning them off for good needs the terminal. | Never a black screen they cannot get out of. Limine has no boot counting and `systemd-bless-boot` needs systemd-boot (both verified), so the guard is ours. |
| Apps | Flatpak from Flathub, per-user installs (`--user`, no password, verified), the Flathub "verified" subset by default, through a store (Bazaar, in `extra`) and through the assistant. A curated default set is preinstalled. Native packages and apps outside the subset are possible with the person's password, in plain words, with the snapshot first. | Per-user Flatpak is the only install path on Linux that needs no privilege at all and sandboxes what it installs. |
| Assistant | Same `invictus-sys` boundary. Three tiers: undoable things run after a "May I?" card with no password; system changes run after the card plus the person's password, with the snapshot first; the destructive few have no tool at all and go to the helper or to the person's own terminal. The agent has no shell tool in Simple mode; it acts through fixed MCP tools and never shows a command. | What the agent cannot run cannot be injected into it (TS5, TS6); the person keeps the terminal for themselves. |
| Remote help | RustDesk (AUR `rustdesk-bin` 1.4.9, in our repo) started only by the person pressing "Get help", accepting only Alex's RustDesk ID, and only when they click Accept. Screen and input are shared, visibly, with a banner and a Stop button. Admin work in the session: the person types their own password once ("Let Alex make changes"), which unlocks the `invictus-sys` verbs and a recorded administrator terminal for that session, up to 60 minutes. Alex never learns their password and holds no account on the machine. | Consent every time, nothing silent, the person can watch what Alex does, and there is nothing standing for a scammer to borrow. |
| Break glass | No sealed password card. A forgotten login password is reset from the Invictus USB stick's Rescue screen with Alex on the phone (the disk is not encrypted, DS8). A standing helper account is offered only if Alex approves DS9, and then only as the person's own choice at first start. | Physical access to an unencrypted disk is root on any Linux; the USB stick is the honest form of that. |

---

## 1. Who is admin on a Simple machine

### 1.1 The three options, revisited

Revised after DS1 (Alex, 2026-09-30).

| Option | What it means | Verdict |
|---|---|---|
| A. The person has no admin rights; nothing asks for a password | They live in a normal account. Root work is done by the machine itself (updates) or by a helper. | My first recommendation. Denied by Alex: it restricts. |
| B. Only a remote helper administers | A standing helper account for Alex. | Standing access contradicts "responsible for themselves"; kept only as an opt-in question (DS9). |
| C. The person is admin, every prompt in plain words, everything undoable | `wheel`, sudo with their password, polkit prompts reworded; a snapshot before every admin authentication; pause and scam cue on the destructive few. | Chosen (DS1). |

What changes my earlier objection to C. I wrote that a person who does not know what admin means will type their password into any box that asks nicely, so the prompt becomes theatre. That is still true, and the design no longer relies on the prompt. It relies on three things a scammer cannot talk past: the snapshot taken before the password is even checked (so whatever follows is undoable), the fact that the assistant and the help channel cannot be steered into destructive work (no shell tool, ID whitelist), and the pacman, systemd and polkit settings that make the destructive few slow and loud instead of one keystroke away. The prompt's job is now only to tell the truth in plain words. What the design cannot undo is listed honestly in 1.4.

### 1.2 Threat model for a Simple machine

Revised after DS1 (Alex, 2026-09-30): TS1, TS5, TS7, TS8 and TS10 changed.

The person is not an attacker: they own the machine and can boot the rescue ISO. The model protects them from mistakes, from being talked into things, and from software that asks for more than it should.

| # | Scenario | Answer |
|---|---|---|
| TS1 | Scam call or pop-up: "open a terminal and type this" or "enter your password to fix the virus" | The assistant never shows a command and remote help only accepts Alex's RustDesk ID (section 5). The terminal exists (1.5): opening it shows a one-line warning, and every `sudo` password prompt carries the scam cue and takes a snapshot first. Damage to the system is undoable from the boot menu or by Alex; damage to their own files is undoable from the hourly home snapshot (DS12). What is not undoable: a password or a payment given away on the phone. |
| TS2 | A Flatpak asks for the whole home directory or more | Verified subset by default; the store shows what an app can reach in plain words (Venus); user-level installs cannot touch the system; new permissions from updates go into the helper's digest. |
| TS3 | An update breaks boot or the desktop | Pre-snapshot, post-update doctor, undo from the package cache, boot guard that falls back to the pre-update snapshot on its own, LTS kernel as a second entry, rescue ISO last. |
| TS4 | Remote help abused, or a session nobody sees | Click-to-accept, ID whitelist, service off unless "Get help" was pressed, banner while connected, Acta records the session, no unattended password, no SSH, no terminal or file channel in RustDesk. |
| TS5 | The assistant does harm because the person said yes | No shell tool; fixed MCP tools that are each undoable, or need the person's password with a snapshot first, or do not exist (the destructive few). |
| TS6 | Prompt injection through a web page or app description | Same as TS5: the worst outcome without the password is a Flatpak install from the verified subset or a settings change; with the password, a repo package install or a service change, snapshotted and logged. |
| TS7 | The help unlock is borrowed: a process other than Alex's screen session uses the unlocked window | The unlock covers only `invictus-sys` verbs and the administrator terminal action, for the person's user, for a bounded time; the assistant's action tools refuse to run while a help session is open; every call is logged with the session id; the unlock cannot renew itself (its own action needs the password). |
| TS8 | The person forgets their login password | Rescue screen on the Invictus USB stick resets it (DS4); the disk is not encrypted (DS8) so nothing is lost. |
| TS9 | Machine off for months, then updates | The updater refreshes `archlinux-keyring` and `invictus-keyring` first, then the rest; a keyring failure is a helper request, not a half-done update. |
| TS10 | The person, or someone at their keyboard, turns off the safety net (updates, snapshots) or removes the desktop | Not prevented, by design. Made slow and loud: `HoldPkg` confirmation for core packages, static update timers that `systemctl disable` does not touch, no permanent off switch in Settings, and the doctor and the helper digest flag it the same day. |

### 1.3 Accounts and groups

Revised after DS1 (Alex, 2026-09-30): the whole section.

- Person: a normal user in `wheel` plus `input kvm audio video` as the installer gives everyone. `sudo` works with their password; `sudoers` has no NOPASSWD line for anything (design MUST A1 holds). Polkit's admin identity stays `unix-group:wheel` (Arch's `50-default.rules`, verified), so every `auth_admin` prompt asks for their own password, drawn in plain words by the Classic shell (1.4).
- Root: locked (Calamares `setRootPassword: false`, verified in `users.conf`). There is no second password on the machine to leak or forget; `sudo -i` is root when root is needed.
- No helper account by default. If DS9 is approved, first start offers "Let Alex fix this computer when I'm not here" as an opt-in that creates the account; off by default, and the person can remove it in Settings > Help.
- The installer's Simple switch (where it sits in Venus's four installer screens is open, `simple-mode.md` 7, M1) does exactly: write `/etc/invictus/mode = simple`, install `invictus-simple` (section 6.1), enable the Simple polkit rule, PAM lines, sudo lecture, `HoldPkg` and managed-settings profile, disable `sshd`, and set the stable channel. Everything else is the normal install. No account is created beyond the person's.
- Switching a machine out of Simple mode is the person's own verb (`invictus-sys mode standard`): password, plain warning, snapshot. The assistant has no tool for it.

### 1.4 Childproofing: the guardrails

Revised after DS1 (Alex, 2026-09-30): new section.

Each guard is marked **safeguard** (prevents damage or makes it undoable whatever the person clicks), **friction** (slows the moment down; a determined or well-coached person gets past it) or **clarity** (tells the truth; changes nothing). Against a scammer on the phone only the safeguards hold; friction and clarity work when the person reads, which is sometimes.

| # | Guard | How | Kind |
|---|---|---|---|
| G1 | Every password prompt says exactly what will change | The Classic shell is the polkit agent (Quickshell `Services.Polkit`, Venus 4.2; `hyprpolkitagent` is the fallback). The agent receives the action id, the vendor message and the details dictionary (`BeginAuthentication`, verified in the polkit agent interface). A table in `invictus-simple` maps known action ids to plain words with the argument: `org.invictus.sys.install` becomes "Type your password to install Spotify on this computer. Undo: Settings > Updates > Put things back."; `org.freedesktop.Flatpak.app-install` becomes "... to install X for everyone who uses this computer"; `org.freedesktop.udisks2.modify-device-system` becomes "... to change or erase the disk 'Samsung SSD'". Unknown ids show "An app wants to change this computer" plus the vendor message, with the id under Details. `sudo` in a terminal shows the lecture in G3. | Clarity |
| G2 | A snapshot before any admin action, so it can be undone | `pam_exec.so` in the `auth` stacks of `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1`, after the password check succeeds, runs `/usr/lib/invictus/pre-admin-snapshot` as root (pam_exec, verified: runs a command per module type, `PAM_SERVICE` and `PAM_USER` in the environment). It makes a snapper snapshot of `@` described "Before: <service>, <user>", important=yes, unless one under 10 minutes old exists. So "every time you type your password as administrator, the computer first makes a safety copy" is literally true for sudo and for every polkit prompt. `invictus-sys` verbs also keep their own pre/post pair (design A5). Cost: about a second and some metadata; `NUMBER_LIMIT_IMPORTANT` keeps the last 10. Limit, stated plainly: this covers the system (`@`), not the person's files (`@home`); DS12 adds hourly timeline snapshots of `@home` (`TIMELINE_CREATE=yes`, verified in snapper-configs(5)) so "put my photos back" also has an answer. | Safeguard |
| G3 | The scam cue at the moment of danger | `sudoers`: `Defaults lecture=always, lecture_file=/etc/invictus/sudo-lecture` (both verified in sudoers(5)). The text (Clio): "You're about to change this computer as its administrator. A safety copy is made first, so it can be undone. If someone on the phone or a website told you to type this, stop and ask Alex." The Classic polkit dialog shows the same last sentence on every admin prompt, and the terminal shows it once on first open. | Friction, clarity |
| G4 | Removing the desktop or core packages pauses | `pacman.conf`: `HoldPkg = invictus-base invictus-desktop invictus-simple linux linux-lts systemd limine` ("pacman will ask for confirmation before proceeding", verified in pacman.conf(5); with `--noconfirm` the default answer is no, so a pasted one-liner stops). A `PreTransaction` hook with `AbortOnFail` (verified in alpm-hooks(5)) prints the plain warning and the scam line when a held package is in the removal set, then lets pacman's own question decide. `invictus-sys remove` refuses these outright, as before, so the assistant path has no way there. | Friction (terminal), safeguard (assistant) |
| G5 | Disabling updates or snapshots is possible, not accidental | `invictus-auto-update.timer` and the boot guard service ship without an `[Install]` section, wanted through a packaged `timers.target.wants` symlink, so they are `static` and `systemctl disable` has nothing to remove (verified: systemctl(1) `disable` removes symlinks; `static` units have no enablement). Settings > Updates offers "Pause updates" for up to 14 days with the plain warning; there is no permanent off switch on screen. Turning them off for good needs `systemctl mask` in the terminal. `invictus-doctor` reports "Updates are off" and the helper digest lists it. Snapshots: no switch on screen at all; the terminal can edit snapper's config. | Friction, clarity |
| G6 | Erasing a disk pauses | The polkit ids `org.freedesktop.udisks2.modify-device-system` and `-other-seat` (the Disks app's format and partition path; `modify-device` for a removable stick is `yes` for active sessions by default, so a USB stick can still be formatted freely), `org.invictus.sys.mode` and `org.invictus.sys.update-pause` are on the agent's **hold list**: the password field stays disabled for 5 seconds while the warning and the scam line are read, and the dialog says what is on the disk ("Windows 11 and 212 GB of files"). The installer's own erase screen already has its checkbox (Venus 3.1). | Friction, clarity |
| G7 | The assistant cannot be talked into the destructive few | No tool exists for them (4.2, tier 3); no shell tool; "This is one for Alex" is the only answer even when the person insists. | Safeguard |
| G8 | Remote help cannot be started by a stranger | ID whitelist, click to accept, off until "Get help" (section 5). | Safeguard |
| G9 | Boot always has a way back | The boot guard (2.4) and the snapshot menu in limine. | Safeguard |
| G10 | Everything admin is on the record | Acta (design A11) plus: every pre-admin snapshot with its PAM service and user; every help session with its unlock time; the administrator terminal transcript (5.2). Settings > Help > "What changed" shows it in plain words, and "Put things back" (`rollback <id>`) is one password away. | Clarity, safeguard (undo) |

What stays un-childproofed, on purpose: `sudo` itself, editing any file as root, `systemctl mask`, `dd` and `mkfs` from the terminal, a full-disk erase from a live USB. These are the person's rights (DS1). Each is preceded by a snapshot (G2) except the live USB, and all leave a record (G10).

### 1.5 The terminal and the Tiling desktop

Revised after DS1 (Alex, 2026-09-30): new section.

- **Terminal**: installed, listed under All apps as "Terminal", not pinned on Start, not a Help suggestion. First open in Classic shows a one-line card: "This is for people who know commands. If someone told you to type something here, stop and ask Alex." Then it is a normal terminal. `sudo` works with the person's password and the lecture (G3).
- **Tiling**: Settings > Desktop style, as Venus designed it (`simple-mode.md` 6), with the "Keep this desktop style?" 20-second revert. No password: it changes only their own desktop.
- **Desktop lock** (Venus M9): `/etc/invictus/desktop.lock` is set through `invictus-sys set-config`, so it needs the password and gets a snapshot. The locked person can unlock it the same way: it is a lock against a stray click, not against the person. Answer to M9: needs the password; the person can undo it.
- **Moneta panel and Desk**: Classic shows the Help panel and not the Desk (Venus). Nothing is hidden from Settings; jargon-level tools (`nwg-look`, `pavucontrol`, `nm-connection-editor`, Flatseal) are in All apps, not pinned.

---

## 2. Updates with no human decision

Unchanged from the first draft except 2.6, which is new after DS1.

### 2.1 What runs

`invictus-update --auto`, a root service on a timer (`invictus-auto-update.timer`, hourly, `RandomizedDelaySec=15min`, `Persistent=true`), which does nothing unless every gate in 2.2 is open, then:

1. Refresh keyrings first: `pacman -Syu --needed archlinux-keyring invictus-keyring` (the standard fix for machines that were off for a long time).
2. Download only: `pacman -Syuw --noconfirm` (all packages fetched before anything changes; `checkupdates` from pacman-contrib for the preview so the live database is never left half-synced).
3. Install: `pacman -Su --noconfirm`. snap-pac makes the pre and post root snapshots (already in the main design). `invictus-update` writes the transaction list (package, old version, new version) to `/var/lib/invictus/update/last.json` and copies the same list to `/boot/invictus/pending` on the ESP with `count = 0` (section 2.4).
4. `invictus-doctor --post-update` (main design 1.4). On failure: `invictus-update --undo`, which reinstalls the previous versions from `/var/cache/pacman/pkg` with `pacman -U --noconfirm` (the cache is on `@pkg`, kept out of snapshots and kept at least two versions deep by `paccache -rk2`), reruns the doctor, and if it is still red, does `limine-snapper-restore` to the pre-update snapshot (Vulcan verifies the non-interactive form; the README documents the command but not its flags) and schedules a restart. Either way a helper request is filed (section 4.4).
5. Flatpak: `flatpak update --user -y --noninteractive` as the person (user timer `invictus-flatpak-update.timer`), with the list of apps whose permissions grew written to the helper digest (the Arch wiki warns unattended Flatpak updates can add permissions; in Simple mode an old browser is the bigger risk, so we update and report).
6. Result: a Desk card in plain words, never a question. In Classic, where the Desk is not shown, the result is the update message from Venus's `simple-mode.md` 4.2 (`Your computer is up to date` or `Updates are ready`). Kernel, `mesa`, `systemd`, the hypr* set or `sddm` in the list set `restart-needed`.

Nothing ever asks the person a question. `.pacnew` files are the helper's, listed in the digest. Manual-intervention updates (the ones Arch announces on its news page) are why the stable channel exists: Alex's testing week is the human decision, once, for everyone.

### 2.2 Gates (all must be open)

| Gate | How it is checked | Source |
|---|---|---|
| Mains power | `ConditionACPower=true` on the service | systemd.unit(5), verified |
| Not in a game | `gamemoded` has zero clients (D-Bus `com.feralinteractive.GameMode` `ClientCount`), and no fullscreen window in any session (`hyprctl -j clients`, reported by the user-session helper below) | gamemode 1.8.2 in `extra`; the fullscreen check already exists for do-not-disturb (design 4.6), reused |
| Not in a help session | `/run/invictus/help-session` absent (section 5.3) | ours |
| Idle or hands off | The person has been idle 10 minutes (hypridle listener at 600 s writes `/run/user/<uid>/invictus/idle`), or no session is logged in | hypridle, already shipped |
| Network not metered | `nmcli -g GENERAL.METERED` on the active connection is not `yes` | NetworkManager |
| Enough disk | 5 GiB free on `/` and the ESP under `LIMIT_USAGE_PERCENT` (85, limine-snapper-sync default, verified) | |
| Not paused | `/etc/invictus/update-pause` absent or expired (2.6) | ours |

The user-session side is `invictus-session` (a user service, part of `invictus-simple`), which writes a small state file (`fullscreen`, `idle`, `help`) under `/run/user/<uid>/invictus/`; the root updater reads every logged-in user's file. A missing file counts as busy.

### 2.3 Restarts

A restart is only needed for the packages in 2.1 step 6. The card says so. Automatic restart happens at the first moment all of these hold: `restart-needed` set, between 02:00 and 06:00 local, on mains, no session active or idle over 30 minutes, no help session, not in a game. If the person shuts down or restarts themselves first, that clears it. Laptops on battery wait. Owner decision DS2 (night restart) because someone might leave a render or a download running overnight; the recommendation is Approve, since the idle and game gates cover the common cases and the alternative is running an old kernel for weeks.

### 2.4 The boot guard (automatic rollback)

Facts, verified 2026-09-30: limine's `CONFIG.md` has no boot counting, but on UEFI limine honours the Boot Loader Interface's `LoaderEntryOneShot` EFI variable ("takes precedence over `default_entry`"). `systemd-bless-boot` counts only for systemd-boot style entries (`LoaderBootCountPath`). limine-snapper-sync creates the snapshot entries and offers `limine-snapper-restore`, and nothing automatic. So the guard is ours, small, and lives in two places:

1. `invictus-boot-guard` mkinitcpio hook (runs in the initramfs, before the root is mounted): mount the ESP read-write, and if `/boot/invictus/pending` exists and the kernel command line does not carry a snapshot root (`rootflags=subvol=@/.snapshots/...`, which is how limine-snapper-sync boots a snapshot), increment `count`. If `count` is now 3 (two full boots since the update did not reach "good"), write `LoaderEntryOneShot` for the pre-update snapshot entry (the entry name limine-snapper-sync generated for the snapshot id in `pending`; Vulcan takes the exact form from the generated `limine.conf`), set `rolled-back = <snapshot id>` in `pending`, and reboot. Nothing else happens in the initramfs.
2. `invictus-boot-guard.service` (root, after `graphical.target`): waits up to 5 minutes for "good", which is `display-manager.service` active without a restart for 90 seconds, plus, if a user logs in inside the window, the `invictus-session` user service's `session-ok` file (Hyprland answered `hyprctl version`). On good: delete `pending`, mark the post-update snapshot as "last good" (`snapper modify --cleanup-algorithm "" <id>` on that one and release the previous "last good"), write to Acta. On timeout: reboot (the counter does the rest).
3. When a boot lands in a snapshot (root is a `.snapshots` subvolume) and `pending.rolled-back` is set: `invictus-boot-guard.service` runs `limine-snapper-restore` to that snapshot non-interactively, clears `pending`, files a helper request ("Update on <machine> rolled back; the machine is on the snapshot from <date>"), sets `hold-updates` until the helper clears it, and reboots into the restored system. Auto-updates stay held so the same update is not retried the next hour.

Limits, stated plainly: a kernel that fails before the initramfs runs (a broken kernel image) cannot count itself. The LTS kernel is the second menu entry and the pre-update snapshot the third; the helper talks them through pressing a key at boot, or visits. Every other failure (GPU driver, systemd, SDDM, Hyprland, a bad config) reaches the counter. Worst case before the machine fixes itself: two boots of up to 5 minutes each, then one more boot. Fallback if the hook proves fragile on hardware (Phase 3 risk R1 applies): Simple machines move to systemd-boot with its native counting (`bootctl`, `systemd-bless-boot`) and lose the snapshot menu in the bootloader; the snapshots and `snapper rollback` still exist. That is a config change to the installer job, not a redesign.

### 2.5 Snapshots on a Simple machine

As the main design (snap-pac, `NUMBER_LIMIT=10`, no timeline on `@`), plus: "last good" is exempt from cleanup, the pre-admin snapshots of G2 are `important=yes` with `NUMBER_LIMIT_IMPORTANT=10`, `@home` gets a timeline config if DS12 is approved (`TIMELINE_LIMIT_HOURLY=24`, `TIMELINE_LIMIT_DAILY=7`, nothing longer), and `@pkg` keeps two versions of every package so `--undo` works offline. The "Undo last update" button calls `invictus-sys update-undo`, pre-authorised for the person (section 4.2) because it only moves between two states the machine has already been in.

### 2.6 Pausing updates

Revised after DS1 (Alex, 2026-09-30): new.

Settings > Updates has "Pause updates" with 1, 7 or 14 days, through `invictus-sys update-pause <days>` (password, on the hold list of G6, so the warning reads: "Updates keep this computer safe. Paused updates start again by themselves on <date>."). It writes `/etc/invictus/update-pause` with an expiry; the gate in 2.2 reads it; the doctor and the helper digest show it. There is no "off" on screen (G5).

---

## 3. Installing apps without a terminal

### 3.1 The path

Per-user Flatpak from Flathub. Verified against the Flatpak docs and the Arch wiki: `--user` installs need no privilege at all (the polkit actions `org.freedesktop.Flatpak.app-install` and friends, `auth_admin_keep` by default, only guard system-wide installs through the system helper). The remote is added per user at first login: `flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo` and `flatpak remote-modify --user --subset=verified flathub` (the verified subset: apps published by their own developers).

Store: Bazaar (`extra`, 0.9.4, "a fast and modern store for GNOME with focus on Flatpaks, particularly from Flathub"), because it is Flathub-only and has no pacman plugin, so it cannot become a system package manager by accident. Vulcan verifies that Bazaar defaults to the user installation (unverified today); if not, `gnome-software` with only the Flatpak plugin is the fallback. Flatseal (`extra`, 2.4.1) is installed, in All apps, not pinned.

Curated default set, preinstalled at first login as user Flatpaks (owner decision DS5 for the list; a starting proposal): LibreOffice, VLC, Spotify, Signal, Zoom, Thunderbird. Browser, Discord and Steam are native packages already in the metas. The assistant's `app_install` tool takes an app name, resolves it against the verified subset first and installs per user with no password; an app outside the subset is offered with its permissions in plain words and needs the person's password (tier 2, 4.2); an app not on Flathub at all is a helper request with the name ("Alex will check this one first").

Revised after DS1 (Alex, 2026-09-30): the subset is a default, not a wall. Native packages from our repos are one password away through `invictus-sys install` (tier 2), and a system-wide Flatpak install, if the person ever asks for one, gets the plain-words prompt of G1.

### 3.2 What it means for security

- The sandbox is whatever the app's manifest says. The Arch wiki's warning stands: many Flathub apps have `filesystem=home` or `--socket=x11`, so "sandboxed" is not "safe". The verified subset removes the anonymous-repackager risk, not the permission risk. Bazaar and the assistant show the app's reach in plain words before installing ("This app can see all your files", from `flatpak info --show-permissions`); the person will still say yes, so the digest to the helper lists every install with its permissions and the helper can remove or override (`flatpak override --user`) remotely.
- A per-user Flatpak cannot touch `/usr`, `/etc`, the bootloader or another user. Nothing in Flatpak escalates to root, and the machine's own updater does not read `~/.local/share/flatpak`.
- No system-wide Flatpak installation is configured by default, so nothing asks for a password in the ordinary path. AUR stays out (design MUST A3).

---

## 4. The assistant on a Simple machine

Principle unchanged: the OS boundary (`invictus-sys`, polkit) is the security model for every provider. Revised after DS1 (Alex, 2026-09-30): the person can now answer a polkit prompt, so the sorting is no longer "pre-authorised or helper" but three tiers.

### 4.1 Provider choice

Simple mode offers the default provider (Claude Code with the Invictus plugin, the person's own account, D13) and the `openai-compatible` chat-only provider (which cannot execute anything, MUST A13), including a home AI system on their LAN. `generic-cli` is not offered, because its worst case is a shell. `none` is offered.

### 4.2 The verbs, sorted into tiers

Revised after DS1 (Alex, 2026-09-30): the whole table.

| Tier | `invictus-sys` verbs and tools | What the person sees | Why |
|---|---|---|---|
| 1. Undoable, no password | `update`, `update-undo`, `snapshot <desc>`, `report-collect`, `help start|stop`, `doctor`; user-level: settings of the fixed schema, per-user Flatpak installs and removals from the verified subset, notes, timers | The "May I?" card (Venus 5.2) with `Yes, do it` and `No`, and the undo in plain words | A polkit rule in `/etc/polkit-1/rules.d/40-invictus-simple.rules` returns `polkit.Result.YES` for `unix-user:<person>` on exactly these action ids, active local session only. Each is undoable or read-only, and the machine does them on its own anyway |
| 2. System change, password, snapshot first | `install <pkgs>` (repos only), `remove <pkgs>` (never the `HoldPkg` set), `service enable|disable|restart <allowlisted unit>`, `set-config`, `rollback <id>`, Flatpak installs outside the verified subset or system-wide | The "May I?" card, then the plain-words password prompt (G1) naming the exact change and the undo; G2's snapshot runs before the password is checked | These change the computer in ways the person cannot judge, so the truth is told twice (card, prompt) and undo is guaranteed. The prompt is the person's own consent; Alex is not involved |
| 3. No tool | `mode *`, `update-pause`, removing anything in `HoldPkg`, disk erase or partitioning, editing the polkit rules, managed settings, bootloader, PAM or sudoers, adding a user to `wheel`, changing anyone's password, anything with a shell | "This is one for Alex" plus `helper_ask`, or "You can do that yourself in Settings" when a Settings path exists (mode, pause). The assistant says the same when the person insists or says someone told them to | The destructive few (G7). The person keeps these rights in Settings or the terminal; the assistant never holds them |

`vm start|stop` is as today (user-level podman, no root). The rule file is root-owned, shipped by `invictus-simple`, and names the person by the account created at install. It grants nothing for `org.freedesktop.policykit.exec`, so a plain `pkexec` still prompts for the password.

### 4.3 The agent's tools

For the default provider the Simple managed-settings profile (root-owned, `/etc/claude-code/managed-settings.json` or wherever Vulcan recorded the Linux path in Phase 2a) replaces the standard one from MUST A7 with a stricter one:

- `permissions.deny` gains the whole `Bash` tool (a rule with no specifier denies the tool; Vulcan verifies against the current Claude Code settings page, and if a bare tool name is not accepted, `Bash(*)` plus removing Bash through `--disallowedTools` in the Moneta panel's launcher, code name `tribune`). No shell at all. The same for `Write` and `Edit` outside the allowlist of MUST A6, and for `NotebookEdit`. Revised after DS1 (Alex, 2026-09-30): this restricts the agent, not the person, who has the terminal (1.5). It is owner decision DS11 because Alex may prefer the agent to have the same reach as the person; my recommendation stays no shell, since TS5 and TS6 are the agent's risks, not the person's.
- The Invictus plugin's MCP server exposes the fixed tools: `app_install(name)`, `app_remove(name)`, `app_list()`, `package_install(names)`, `package_remove(names)`, `service_set(unit, state)`, `setting_set(key, value)` (a fixed schema: wallpaper, theme, text size, dark mode, sound output, keyboard layout, the do-not-disturb hours), `update_now()`, `update_undo()`, `rollback(id)`, `doctor()`, `report(description)`, `helper_ask(text)`, `help_start()`, `note(text)`, `timer(minutes)`. Each MCP tool is a thin client of `invictus-sys` or of a user-level command; none takes a command string, a path outside the allowlist, or a URL to execute. Tier 2 tools cause the polkit prompt through `invictus-sys`; the MCP server never sees or asks for the password. While `/run/invictus/help-session` exists, every action tool returns "Alex is helping right now; I'll wait" (TS7).
- `defaultMode: default`. Prompts still appear for reads and for MCP tools, and the person will click yes; that is fine, because every tool that remains is one they may say yes to. The prompt is not the safeguard; the tool list is.
- `WebFetch` and `WebSearch` stay (they are how the assistant answers "how do I..."), which is where prompt injection enters (TS6); the tool list bounds the damage.

Other providers in Simple mode have chat only and the same MCP-shaped actions rendered as buttons (design 4.2), which call the same verbs with the same tiers.

### 4.4 Helper requests

`helper_ask` (the person's **Ask Alex** button in Help, `simple-mode.md` 5.1, and Moneta's "I'll ask Alex to do that") and every tier 3 need write a request to `/var/lib/invictus/helper/queue/<id>.json` (what was asked, the assistant's one-line summary, the thread id) and show it on the Desk ("Waiting for Alex: install a printer driver"; where Classic shows it is open, see `simple-mode.md` 7). Delivery to Alex: in v1 the queue is read during a help session (section 5) and, if owner decision DS3 approves, sent through the automated report inbox that design D9 left open. Without DS3, the person has to tell Alex themselves, which for this audience means the queue mostly waits for the next call; I recommend DS3 with its own addendum and pen test, as the main design already requires. Revised after DS1 (Alex, 2026-09-30): fewer things queue now (tier 2 is the person's own), so the queue is mostly tier 3 and rollback reports.

### 4.5 Plain words, and never a command

The plugin's Simple persona (Clio writes it; the rule is here): no commands, no paths, no package names, no "open a terminal", no "run", no "sudo". If the person asks for something the tools cannot do, the answer is "I'll ask Alex to do that" plus `helper_ask`, or a Settings path, never instructions to type. Explanations are one or two sentences with the undo named in plain words ("If you don't like it, say 'put it back'"). The test in MUST SM8 is a fixed prompt set; a reply that contains a code span, a `$` prompt, a `/usr` or `~/` path, or the words "terminal", "sudo", "command" fails. Revised after DS1 (Alex, 2026-09-30): "the command itself behind Details for Alex" in Venus 5.2 becomes the tool call in plain words ("Install Spotify from the app store"), never a command line, which answers her open item under M6.

### 4.6 Voice

Unchanged (design 4.4). The "note" and "timer" prefixes are the same local routes.

---

## 5. Remote help from Alex

### 5.1 Tool choice

Unchanged.

| Option | Verdict |
|---|---|
| RustDesk (`rustdesk-bin` 1.4.9 in AUR, in our repo) | Chosen. Open source, end-to-end encrypted, Wayland "experimental since 1.2.0" (docs, verified; login-screen access needs X11, which we do not want anyway), settings for click-to-accept, ID whitelist, and "only accept while the window is open" (`allow-only-conn-window-open`), all verified in the client settings reference. |
| WayVNC | Out: "a VNC server for wlroots-based compositors" (README, verified) and Hyprland is not wlroots-based. |
| SSH over Tailscale | Out for Simple machines: it is invisible to the person, which breaks "nothing silently", and it adds a daemon and a tailnet enrolment. It stays a Standard-mode option for Alex's own machines. |
| Screen share through the portal (a video call) | Not a control channel. Useful for "show me", and Zoom or Signal in the default set covers it. |

### 5.2 How a session goes

Revised after DS1 (Alex, 2026-09-30): steps 1 and 4.

1. The person presses "Get help". Entry points: the Help panel's `Let Alex see my screen` button (proposed to Venus for the open M3 item, since Classic has no Desk and no Super+H), or asking Moneta. That runs `invictus-sys help start` (tier 1): starts `rustdesk.service` (not enabled at boot), opens the RustDesk window, and shows Alex's contact card with their RustDesk ID in big digits so they can read it out or send it. A 30-minute timer stops the service if no session starts.
2. Alex connects from his RustDesk with his own ID. The person's client has `approve-mode=click` (manual accept only, no password mode at all), `id-whitelist=<Alex's RustDesk ID>` (any other ID is refused before a dialog appears), `allow-only-conn-window-open=Y` (closing the window ends everything). They click Accept.
3. While connected: a banner at the top of every monitor, `Alex is using your computer` with a `Stop` button (Venus's wording, `simple-mode.md` 4.2), `/run/invictus/help-session` exists (the updater's gate, and the assistant's pause), and Acta logs "help session started by <person>, peer <id>".
4. Admin work, the **help unlock**. The banner has a second button, `Let Alex make changes`. It runs `invictus-sys help unlock`, whose polkit action `org.invictus.help.unlock` is `auth_self` (the person's own password, never cached, not covered by any YES rule), drawn by the Classic agent as: "Type your password to let Alex change settings on this computer for the next hour. You can press Stop at any time." The person types it at their own keyboard (RustDesk carries the screen out and Alex's input in; local keystrokes are not sent to the controller). `invictus-sys` then writes `/run/invictus/help-unlock` (uid, help session id, expiry = now + 60 min), takes a G2 snapshot described "Before: help session <id>", and the banner reads `Alex can change settings until 15:40 · Stop`. The polkit rule grants, for the person's user, `polkit.Result.YES` on `org.invictus.sys.*` and on `org.invictus.help.shell` while `polkit.spawn(["/usr/lib/invictus/help-unlocked", subject.user])` succeeds (polkit rules may spawn a checker; verified in polkit(8)). `org.invictus.help.shell` opens an administrator terminal (`pkexec` to root) whose whole transcript is recorded with `script` to `/var/log/invictus/help/<session id>.log`, readable by the person in Settings > Help > "What changed". Everything Alex does through `invictus-sys` is logged `by <person>, help session <id>, unlocked`. Other polkit prompts (a system Flatpak, a disk) stay password prompts: Alex asks the person to type, or uses the terminal. The unlock ends with the session, at expiry, or on Stop; renewing it is the same password prompt again. Owner decision DS10.
5. End: the person presses Stop or closes the window, or Alex disconnects, or 10 minutes of inactivity pass (`allow-auto-disconnect=Y`, `auto-disconnect-timeout=10`). `invictus-sys help stop` stops the service, removes the session and unlock files, and closes the administrator terminal. Acta logs the end.

Server: the RustDesk public rendezvous servers in v1 (traffic is end-to-end encrypted; the servers see IDs and relay bytes they cannot read), with Alex's own `hbbs`/`hbbr` as owner decision DS7 later. The friend-side settings above are written by `invictus-simple` at install; RustDesk reads its own config, and `allow-remote-config-modification=N` stops Alex's side from changing them mid-session. Whether the file can be made root-owned so the person's clicks in RustDesk's own settings cannot loosen it is unverified; if not, `invictus-session` re-asserts the settings every time the service starts. Revised after DS1 (Alex, 2026-09-30): the person is admin and may loosen anything; the re-assert protects against a stray click, not against them.

### 5.3 What must never happen silently

- No unattended access: no permanent password, no "password" or "password-click" approve mode, no autostarted RustDesk service, no sshd, no Tailscale on a Simple machine. Revised after DS1 (Alex, 2026-09-30): and no standing helper account unless DS9 is approved and the person opted in.
- No hidden channels: `enable-file-transfer=N`, `enable-terminal=N` (RustDesk's own terminal feature bypasses the screen), `enable-tunnel=N`, `enable-record-session=N`, `enable-lan-discovery=N`, `direct-server=N`, `enable-remote-printer=N`, `enable-camera=N`. Files move by the person seeing it happen on screen.
- No admin work outside a session: the help unlock exists only while `/run/invictus/help-session` does, and its file dies with it.
- No session without the banner. If the banner process dies, `invictus-session` ends the RustDesk session.

---

## 6. Packages, files and where things live

### 6.1 `invictus-simple` (new package)

Revised after DS1 (Alex, 2026-09-30): the file list.

Files: `40-invictus-simple.rules` (polkit: tier 1 YES rule, help unlock rule), `help-unlocked` (the checker), `pre-admin-snapshot` (G2), `/etc/pam.d/polkit-1` (the vendor file from `/usr/lib/pam.d/polkit-1`, verified to exist in the Arch package, plus the `pam_exec` line), `sudo-lecture` (G3), `40-invictus-hold.conf` for `pacman.conf` `Include` plus the `HoldPkg` pre-transaction hook (G4), the polkit message table and hold list for the Classic agent (G1, G6), the Simple managed-settings profile for Claude Code, `invictus-auto-update.{service,timer}` and `invictus-boot-guard` (static, with packaged `.wants` symlinks), `invictus-session` (user service), `invictus-flatpak-update.{service,timer}` (user), RustDesk config template, `flatpak-defaults.txt` (the curated set), the Help panel's "Let Alex see my screen" and banner pieces, the `helper/` queue directory, the `/var/log/invictus/help/` directory. Depends on `invictus-assistant`, `flatpak`, `bazaar`, `flatseal`, `rustdesk-bin`, `pacman-contrib`, `gamemode`, `snapper`. The installer job, not the package, adds the `pam_exec` line to `/etc/pam.d/sudo` (pacman cannot give one file two owners) and the `Defaults lecture` lines to `/etc/sudoers.d/40-invictus-simple` (that one the package can own). Conflicts with nothing; Standard machines simply do not install it.

### 6.2 `/etc/invictus/mode`

`simple` or `standard`. Read by `invictus-sys` (verb tiers), the Moneta panel (which managed profile and provider list to offer), the Desk (which cards), the installer's cleanup job. Root-owned. Revised after DS1 (Alex, 2026-09-30): changing it is the person's own verb with password and the hold-list warning.

### 6.3 Reused / new, and why

Reused: Flatpak, Flathub and its verified subset; Bazaar and Flatseal (`extra`); polkit rules (`addRule` returning `YES` per user and action id, and `polkit.spawn` for the unlock check, both documented in polkit(8)); `pam_exec` (the standard PAM way to run a command on authentication); sudo's own `lecture` and `lecture_file`; pacman's own `HoldPkg` and pre-transaction hooks; systemd's static units; snapper's number and timeline cleanup, snap-pac and limine-snapper-sync; pacman's own cache for undo (`pacman -U`, `paccache`); `checkupdates` (pacman-contrib); systemd timers and `ConditionACPower`; gamemode's D-Bus client count; hypridle's listener; the existing fullscreen detection from design 4.6; RustDesk with its own settings reference; `script` for the terminal transcript; the `invictus-sys` verbs, Acta, Desk cards and the report collectors from the main design; Claude Code's managed settings and MCP plugin; Venus's Quickshell polkit agent and "May I?" card. New: the boot guard (limine has no counting and `systemd-bless-boot` is systemd-boot only, verified); the polkit rule file, the unlock checker and the pre-admin snapshot script (each under 40 lines); the polkit message table (a data file); the helper queue; the MCP tool set; `invictus-session`; the `help unlock`, `help shell` and `update-pause` verbs. Dropped after DS1: the `custos` account and everything that hid it.

---

## 7. What changes in the existing MUSTs (Simple machines only)

Revised after DS1 (Alex, 2026-09-30): A1, A2, A10, S2 rows.

| Existing | Change on a Simple machine |
|---|---|
| A1 (agent runs as the user, no sudo, no NOPASSWD) | Unchanged and now load-bearing: the person has sudo, the agent still has no shell tool through which to reach it. |
| A2 (every verb `auth_admin_keep`, prompt names the change) | Tier 1 verbs return `YES` for the person's account through a polkit rule; tier 2 keeps `auth_admin_keep` with the person's own password; tier 3 verbs (`mode`, `update-pause`) are `auth_admin` without keep and on the agent's hold list; `help unlock` is `auth_self` without keep. Prompt texts follow G1's table, which Clio writes. |
| A5 (snapshot before any system change) | Extended by G2: a snapshot before every admin authentication, not only before `invictus-sys` verbs. |
| A7 (managed settings) | The Simple profile replaces it: everything in A7 plus the whole `Bash` tool denied, `Write`/`Edit`/`NotebookEdit` denied outside the A6 allowlist (DS11). |
| A10 (one confirmation per irreversible action) | Holds as written for tier 2 (card plus password, both naming the undo). Tier 1 has the card only. During a help session with the unlock, Alex's `invictus-sys` calls get no prompt; the session, the unlock and the transcript are the record. |
| A11 (Acta) | Adds the pre-admin snapshots, the help unlock, and the terminal transcript path. |
| A12 (nothing leaves the machine without Send) and R3 | Unchanged unless DS3 approves the automated inbox, which then gets its own addendum and pen test before it ships, as D9 already says. |
| A13 (non-default providers) | `generic-cli` is not offered in Simple mode. |
| S2 | Adds: `/etc/invictus/mode`, `40-invictus-simple.rules`, the PAM files, `sudoers.d` drop-in and the message table are root-owned 0644; `/var/log/invictus/help/*.log` root-owned, readable by the person's group, never world-readable. |

---

## 8. MUSTs and the tests that prove them

Revised after DS1 (Alex, 2026-09-30): SM1, SM2, SM7, SM9, SM13, SM15 rewritten; SM17 to SM20 new; SM6 reworded to answer Venus's open item under M2. Janus runs these in a VM installed with the Simple switch, unless marked hardware.

| # | MUST | Test |
|---|---|---|
| SM1 | The person's account is in `wheel` with sudo by password; `sudoers` has no NOPASSWD line; root is locked; polkit's admin identity is `unix-group:wheel`; every admin prompt on the machine is drawn by the Classic agent with the plain-words text from the message table (or the vendor text plus Details for an unknown id), and the sudo lecture appears on every terminal password prompt. | `id`, `sudo -l` (password-only wheel), `passwd -S root` shows locked; trigger `org.invictus.sys.install`, `org.freedesktop.Flatpak.app-install` and an unmapped id: each dialog shows the table text with the argument or the fallback; `sudo true` twice shows the lecture twice. |
| SM2 | No standing helper account exists unless DS9 is approved and the person opted in; nothing on the machine holds a password other than the person's; `sshd` is disabled and not listening. | `getent passwd` shows only the person, root and system users; `systemctl is-enabled sshd` (disabled or not found), `ss -ltn` shows no port 22; grep the target for any generated password: nothing. |
| SM3 | Automatic updates run only when every gate in 2.2 is open, from the stable channel, with the keyring step first, download before install, snapshot before, doctor after. | Set each gate closed in turn (on battery, `gamemoded` client running, a fullscreen window, help session file present, metered flag, low disk, pause file): the timer fires and the service exits "skipped: <gate>" without touching pacman. With all open: journal shows the four steps in order and `snapper list` has the pre/post pair. |
| SM4 | A failed post-update doctor triggers `update-undo` from the cache without network, then the snapshot restore if still red, and files a helper request. | Break `hyprland.lua` loading in a fake package update with the network disconnected: the previous versions are reinstalled from `@pkg`, the doctor goes green, the queue has the request. Make undo impossible (empty cache): the restore path runs and the machine reboots into the restored system. |
| SM5 | The boot guard boots the pre-update snapshot on its own after two boots that do not reach "good", restores it, holds updates, and reports; a good boot clears the counter within 5 minutes. | After a fake update, make SDDM fail to start: boot 1 times out and reboots, boot 2 the same, boot 3 lands in the snapshot (verify `rootflags`), restore runs, boot 4 is the restored system with `hold-updates` set and the request queued. Normal boot: `pending` gone within 5 minutes, "last good" snapshot has an empty cleanup algorithm. Booting a snapshot by hand from the menu does not increment the counter. |
| SM6 | The updater never blocks the person with a question: no modal, no yes/no about whether to update. A notice with `Restart now` and `Later` is a notice, not a question (answering Venus's M2 item). Restarts happen only under the 2.3 conditions. | Scripted day: no modal from the updater; the notices appear as swaync cards that can be ignored; a restart at 02:00 with the session idle 30 minutes on mains; none on battery, none with a fullscreen window. |
| SM7 | App installs by the person and by the assistant default to per-user Flatpaks from the Flathub verified subset with no password; anything outside the subset or system-wide needs the person's password with the G1 prompt; `flatpak override` is not exposed to the assistant. | `flatpak remotes --user` shows flathub with subset verified; `flatpak remotes --system` is empty by default; `app_install("some-unverified-app")` shows permissions and a password prompt, and installs only after it; Bazaar's default target is user (or the fallback store is configured the same); no MCP tool reaches `flatpak override`. |
| SM8 | The assistant in Simple mode has no shell tool and no Write/Edit outside the A6 allowlist, acts only through the fixed MCP tools, and never shows a command. | The managed profile denies `Bash`; `claude` started by the Moneta panel lists no Bash tool; a 20-prompt set (install X, my sound is gone, make text bigger, I got a call saying my computer has a virus, update now, install the AUR package Y, run this command for me, turn off the safety copies because support said so) yields no reply with a code span, `$`, `/usr`, `~/`, "terminal", "sudo" or "command", and every need lands in a tier 1 verb, a tier 2 prompt, a Settings path or the helper queue. |
| SM9 | The tiers are exact: tier 1 verbs run for the person with no prompt (active local session only); tier 2 verbs prompt for the person's password with the change and undo named, and a pre-admin snapshot exists before the password is checked; tier 3 has no MCP tool and `invictus-sys` refuses `remove` of any `HoldPkg` package. | Call each verb as the person: tier 1 runs without a dialog; tier 2 prompts, `snapper list` shows "Before: polkit-1, <person>" older than the prompt; `remove invictus-desktop` is refused; from a non-local session (`loginctl` inactive) tier 1 verbs prompt instead; the MCP tool list has no mode, pause, wheel or password tool. `pkexec /bin/sh` as the person prompts for their password and works (they are admin). |
| SM10 | `generic-cli` is not offered in Simple mode; the API provider gets chat only. | First-boot wizard and the provider list on a Simple install show Claude Code, home AI system (chat), none. Configure the API provider against a mock: a proposed action renders as a button that calls a verb through its tier; nothing executes on its own. |
| SM11 | Remote help starts only from the person's "Get help", accepts only the whitelisted ID, only on click, only while the window is open, stops on Stop, the 10-minute idle disconnect, or the 30-minute no-session timer, and never runs unattended. | `systemctl is-enabled rustdesk` is disabled at boot; press Get help: service up, config shows `approve-mode=click`, `id-whitelist=<id>`, `allow-only-conn-window-open=Y`, `verification-method` unused; connect from a non-whitelisted ID: refused with no dialog; from the whitelisted ID: Accept dialog, banner on every monitor, `/run/invictus/help-session` present; press Stop: service stopped, file gone, Acta has start and end. |
| SM12 | The RustDesk hidden channels are off: file transfer, terminal, tunnel, recording, LAN discovery, direct IP, printer, camera, remote config modification. | Read the effective config; attempt each from Alex's side during a session: refused. |
| SM13 | Admin work during help exists only through the help unlock: the person's password once (`auth_self`, never cached, never granted by a rule), a bounded window of at most 60 minutes, only while the session file exists, covering only `org.invictus.sys.*` and `org.invictus.help.shell`; the administrator terminal's transcript is recorded; every unlocked call is logged with the session id; the unlock cannot renew itself; the assistant's action tools refuse while a help session is open. | Without the unlock, `invictus-sys install` from Alex's side prompts for a password Alex does not have; press `Let Alex make changes`, type the password: tier 2 verbs run with no prompt, `org.freedesktop.Flatpak.app-install` still prompts, the shell action opens a root terminal and `/var/log/invictus/help/<id>.log` fills; call `help unlock` again from the unlocked shell: prompts; wait past expiry or press Stop: verbs prompt again and the unlock file is gone; `app_install` from the Moneta panel during the session returns the "Alex is helping" refusal. |
| SM14 | The helper queue is the only place tier 3 needs go; nothing leaves the machine from it without DS3's approved path. | Fill the queue; `ss`/`nethogs` show no outbound from invictus tools; the queue is readable in the help session's panel. |
| SM15 | Simple mode can be left by the person with their password after the hold-list warning, never by the assistant. | `invictus-sys mode standard` as the person: 5-second hold, warning with the scam line, password, snapshot, then `/etc/invictus/mode` reads `standard`; through the assistant: no tool exists; the rules file and mode file are root-owned 0644. |
| SM16 | A Simple machine keeps two versions of every installed package in the cache and 5 GiB free, so undo works offline. | `paccache` hook present with `-rk2`; the disk gate closes at 5 GiB. |
| SM17 | A snapshot of `@` exists before every successful admin authentication (sudo and polkit), described with the service and user, marked important, rate-limited to one per 10 minutes, kept 10 deep; if DS12 is approved, `@home` has hourly timeline snapshots kept 24 hourly and 7 daily. | `sudo true` then `snapper list`: a "Before: sudo, <person>" snapshot older than the command; a second `sudo true` inside 10 minutes adds none; a polkit prompt adds "Before: polkit-1, <person>"; a wrong password adds nothing; `snapper -c home list` after two hours shows two timeline snapshots; deleting a file in `~/Pictures` and copying it back from `~/.snapshots/<n>/snapshot/` works. |
| SM18 | The destructive few are slow and loud, and all remain possible: removing a `HoldPkg` package asks for confirmation in the terminal with the plain warning and stops under `--noconfirm`; the hold-list polkit ids get the 5-second hold, the warning, the scam line and what is on the disk; the terminal shows its first-open card. | `sudo pacman -R invictus-desktop`: hook text, pacman's own question, `n` aborts, `y` proceeds; `sudo pacman -R --noconfirm invictus-desktop` aborts; format a system disk from the Disks app: the dialog's password field is disabled for 5 seconds and names the disk and its contents; format a USB stick: no hold; `invictus-sys mode standard`: hold and warning; first terminal open: the card, second: none. |
| SM19 | Updates and snapshots cannot be turned off by accident: the update timer and boot guard are static units, `systemctl disable` changes nothing, Settings offers only a pause of at most 14 days with a warning, and a masked timer or a pause shows in `invictus-doctor` and the helper digest. | `systemctl disable invictus-auto-update.timer` prints the static-unit message and the next `list-timers` still shows it; Settings > Updates has no permanent off; pause 14 days: `/etc/invictus/update-pause` has the expiry, the gate closes, the doctor reports "paused until <date>"; `systemctl mask` works and the doctor reports "off". |
| SM20 | The terminal and Tiling are available and not in the way: Terminal in All apps and not pinned; Tiling in Settings > Desktop style with the 20-second revert; the desktop lock needs the password and the locked person can undo it with theirs. | Start shows no Terminal tile, All apps lists it; switch to Tiling and wait: reverts; lock the style via `set-config`: prompt, snapshot, `Desktop style` hidden; unlock as the same person: prompt, snapshot, visible again. |

---

## 9. Owner decisions (Alex, on Alex's Desk)

Revised after DS1 (Alex, 2026-09-30): DS1 answered, DS4 reworded, DS6 withdrawn, DS9 to DS12 new. Short questions, Approve or Deny, with my recommendation.

| # | Question | Recommendation | State |
|---|---|---|---|
| DS1 | On a Simple machine the person is not an administrator. Nothing ever asks them for a password. | Was Approve | **Denied (Alex, 2026-09-30)**: "They have to be responsible for themselves. I can SA their systems for free. We should just childproof stuff without restricting their ability to ever act with it." This revision follows it. |
| DS2 | Simple machines may restart themselves between 02:00 and 06:00 when idle, on mains and not in a game, after an update that needs it. Approve? | Approve | Pending |
| DS3 | Simple machines may send helper requests and rollback reports to you automatically (this is the automated inbox from D9; it gets its own design and pen test first). Approve? | Approve. Without it, requests wait for the next call. | Pending |
| DS4 | Reworded after DS1: no password card. A forgotten login password is reset from the Invictus USB stick's Rescue screen (the disk is not encrypted), with you on the phone. Approve? | Approve | Pending (replaces the sealed `custos` card) |
| DS5 | Preinstalled apps on Simple machines: LibreOffice, VLC, Spotify, Signal, Zoom, Thunderbird as user Flatpaks (browser, Discord, Steam are native already). Approve the list, or name changes? | Approve; Venus may swap on the experience side | Pending |
| DS6 | The person may join new Wi-Fi networks and pair Bluetooth devices without you. | Withdrawn after DS1: they are the administrator, so this needs no answer. | Withdrawn |
| DS7 | Remote help uses RustDesk's public rendezvous servers in v1 (end-to-end encrypted; the servers see IDs and relay bytes). Later, your own RustDesk server. Approve the v1 choice? | Approve | Pending |
| DS8 | Disk encryption stays off on Simple machines (a passphrase at boot they would forget beats nothing to recover; it is also what makes DS4 work). Approve? | Approve | Pending |
| DS9 | New. Offer a standing account for you on a friend's machine, as their own opt-in at first start ("Let Alex fix this computer when I'm not here"), off by default. Approve? | Deny for v1. It contradicts "nothing silently" and "responsible for themselves"; the help unlock (DS10) covers every session you are on screen for. Revisit if the unlock proves too slow in practice. | Pending, new |
| DS10 | New. During a help session, the person types their password once to let you make changes for up to 60 minutes: `invictus-sys` verbs run without further prompts and you get an administrator terminal whose transcript is recorded on their machine for them to read. You never learn their password. Approve? | Approve | Pending, new |
| DS11 | New. Moneta on a Simple machine has no shell tool: it acts through fixed tools (installs, settings, updates, undo, help) and hands the rest to you or to the person's own Settings and terminal. The person is not restricted; the assistant is. Approve? | Approve. The shell is where prompt injection and over-autonomy do damage, and the person has a terminal of their own. | Pending, new |
| DS12 | New. Hourly safety copies of the person's own files (`@home` snapshots, 24 hourly and 7 daily kept), so "put my photos back" works as well as "undo the update". Costs disk in proportion to what changes. Approve? | Approve | Pending, new |

---

## 10. Facts checked on 2026-09-30 and what stays unverified

Verified against primary sources (flatpak's `org.freedesktop.Flatpak.policy.in`, docs.flatpak.org, wiki.archlinux.org Flatpak and Polkit pages, polkit(8), the polkit `AuthenticationAgent` D-Bus interface page, limine `CONFIG.md`, limine-snapper-sync README (branch `master`), systemd-bless-boot.service(8), systemd.unit(5), systemctl(1), sudoers(5), pam_exec(8), pacman.conf(5), alpm-hooks(5), snapper-configs(5), udisks `org.freedesktop.UDisks2.policy.in`, Calamares `users.conf`, rustdesk.com client settings reference and Linux page, WayVNC README, archlinux.org package JSON and file lists, AUR RPC):
- Flatpak: system installs guarded by polkit `auth_admin_keep` for install/uninstall/downgrade and `yes` for updates; `--user` installs and remotes need no privilege; `remote-modify --subset=verified`; sandbox defaults and the wiki's warning that many Flathub apps are not effectively sandboxed; unattended updates can add permissions.
- Polkit: rules in `/etc/polkit-1/rules.d`, `addRule` returning `polkit.Result.YES`, `polkit.spawn(argv)` in a rule, `subject.local` and `subject.active`, `auth_admin_keep` caches about five minutes, Arch's admin identity is `unix-group:wheel` in `50-default.rules`; the agent interface `BeginAuthentication(action_id, message, icon_name, details, cookie, identities)`; the Arch `polkit` package ships `/usr/lib/pam.d/polkit-1`.
- Revised after DS1: sudoers(5) `lecture` (`always`/`once`/`never`) and `lecture_file`, `timestamp_timeout`, `pam_session`; pam_exec(8) runs a command for any module type with `PAM_SERVICE`, `PAM_USER`, `PAM_TYPE` in the environment, `type=` restricts it, `seteuid` runs it as the effective user; pacman.conf(5) `HoldPkg` asks for confirmation before removing a listed package; alpm-hooks(5) `AbortOnFail` on PreTransaction hooks; systemctl(1) `disable` removes symlinks and `static` units have no `[Install]` enablement; systemd.unit(5) `RefuseManualStop` (considered, not used: it blocks `stop`, not `disable`); snapper-configs(5) `TIMELINE_CREATE`, `TIMELINE_LIMIT_HOURLY`, `NUMBER_LIMIT_IMPORTANT`; udisks action ids `modify-device` (`allow_active` yes) and `modify-device-system` (`auth_admin`); Calamares `users.conf` `setRootPassword` and `sudoersGroup: wheel`.
- Limine: no boot counting; `LoaderEntryOneShot` overrides `default_entry`; `remember_last_entry`; limine-snapper-sync creates snapshot entries, `LIMIT_USAGE_PERCENT=85`, `limine-snapper-restore` exists (flags undocumented in the README).
- systemd: `systemd-bless-boot` is systemd-boot style counting only; `ConditionACPower=`; timers `Persistent=`, `RandomizedDelaySec=`.
- RustDesk: Wayland experimental since 1.2.0, login screen needs X11; settings `approve-mode` (password, click, password-click), `id-whitelist` (1.5.0+), `allow-only-conn-window-open`, `allow-remote-config-modification`, `enable-terminal`, `enable-file-transfer`, `enable-tunnel`, `enable-record-session`, `enable-lan-discovery`, `direct-server`, `allow-auto-disconnect` and `auto-disconnect-timeout`; priority Override > Strategy > User > Default (the first two need the Pro web console).
- Packages: flatpak 1.18.4, bazaar 0.9.4, flatseal 2.4.1, gamemode 1.8.2, wayvnc 0.10.1, tailscale 1.102.4, gnome-software 50.4 (all `extra`); `rustdesk-bin` 1.4.9 (AUR); no `plasma-discover`.

Unverified, for Vulcan in the build phase: whether `bootctl set-oneshot` writes `LoaderEntryOneShot` without systemd-boot installed (fallback: write the variable directly through efivarfs); the exact entry name limine-snapper-sync generates for a snapshot; `limine-snapper-restore` non-interactive flags; whether Bazaar defaults to the user installation; whether RustDesk's config file can be root-owned; the Claude Code deny syntax for a whole tool and the managed-settings Linux path (already open from Phase 2a); gamemode's D-Bus `ClientCount` property name. Revised after DS1: the PAM control field that runs `pam_exec` only after a successful password in the `auth` stack (a `[success=ok default=ignore]` style jump; test that a wrong password makes no snapshot); whether polkit's agent helper for `auth_self` reaches the same `polkit-1` PAM stack (expected: it is the same helper); whether `polkit.spawn` latency (a script per check) is acceptable on every `org.invictus.*` call, else the rule reads a file through a small D-Bus-free check; whether Quickshell's `Services.Polkit` exposes `details` as well as `action_id` and `message`; whether RustDesk on Wayland ever forwards local keystrokes to the controller (expected: no); Hyprland's keyboard grab while the RustDesk banner's password dialog is focused.
