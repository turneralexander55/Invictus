# Invictus: Simple mode, the admin, update and safety model

Author: Minerva (consultant). Date: 2026-09-30. Status: draft for Alex's owner decisions (section 8), then build. Addendum to `design.md`; the experience side is Venus's `simple-mode.md`.

The ask (Alex, 2026-09-30): an "ultra dumb mode" for friends who do not know what "run as administrator" means. This document decides who holds the keys on such a machine, how it stays updated and bootable with no human decision, how apps get installed without a terminal or a password, what the assistant may do, and how Alex helps from afar. Everything in `design.md` still holds unless a line here says otherwise; section 7 lists the exact changes to the existing MUSTs.

Read section 0 for the decisions and section 8 for what only Alex can decide.

---

## 0. Decisions in one screen

| Area | Decision | Why (short) |
|---|---|---|
| Admin | The person is not an administrator: not in `wheel`, no sudo, and nothing on the machine ever asks them for a password except their own screen lock. A second local account, `custos`, is the administrator; only Alex knows its password. | A non-technical person approves any prompt, so a prompt protects nothing. With no admin password to give, a scam call ("open a terminal and type...") has nothing to take. |
| Updates | Automatic, stable channel only, daily when the machine is idle, on mains power, not in a game, not in a help session. Snapshot before, doctor after, undo from the package cache if the doctor fails, and a boot guard that boots the pre-update snapshot by itself if two boots in a row do not reach the desktop. | Never a black screen they cannot get out of. Limine has no boot counting and `systemd-bless-boot` needs systemd-boot (both verified), so the guard is ours. |
| Apps | Flatpak from Flathub, per-user installs (`--user`, no root needed, verified), the Flathub "verified" subset by default, through a store (Bazaar, in `extra`) and through the assistant. A curated default set is preinstalled. Native packages are the helper's job. | Per-user Flatpak is the only install path on Linux that needs no privilege at all and sandboxes what it installs. |
| Assistant | Same `invictus-sys` boundary, but the person cannot pass a polkit prompt, so every verb is either pre-authorised for them (safe and undoable: update, snapshot, doctor, report, start help) or becomes a request to the helper. The agent has no shell tool at all in Simple mode; it acts through fixed MCP tools. It never shows a command. | What cannot be typed cannot be pasted. |
| Remote help | RustDesk (AUR `rustdesk-bin` 1.4.9, in our repo) started only by the person pressing "Get help", accepting only Alex's RustDesk ID, and only when they click Accept. Screen and input are shared, visibly, with a banner and an End button. No unattended mode, no SSH, no file transfer channel, no terminal channel, no recording. Admin work in the session unlocks with the `custos` password. | Consent every time, nothing silent, and the person can watch what Alex does. |
| Break glass | A sealed card with the `custos` password stays with the machine (owner decision DS4). | For the day Alex is unreachable and someone technical is nearby. |

---

## 1. Who is admin on a Simple machine

### 1.1 The three options

| Option | What it means | Why not |
|---|---|---|
| A. The person has no admin rights; nothing asks for a password | They live in a normal account. Root work is done by the machine itself (updates) or by a helper. | This is the recommendation. Cost: some things need Alex (a native package, a driver quirk, a printer that needs a system daemon). |
| B. Only a remote helper administers | Same as A for the person, plus a way for Alex to do admin work. | Not an alternative to A, a complement. Taken, with consent rules (section 5). |
| C. The person is admin, every prompt in plain words | `wheel`, sudo with password, polkit prompts reworded. | A person who does not know what admin means will type their password into any box that asks nicely, including a scam site's fake dialog and a phone scammer's dictated command. The prompt becomes theatre. Rejected. |

### 1.2 Threat model for a Simple machine

The person is not an attacker: they own the machine and can boot the rescue ISO. The model protects them from mistakes, from being talked into things, and from software that asks for more than it should.

| # | Scenario | Answer |
|---|---|---|
| TS1 | Scam call or pop-up: "open a terminal and type this" or "enter your password to fix the virus" | There is no admin password to enter, no sudo, the assistant never shows a command, and remote help only accepts Alex's RustDesk ID (section 5). |
| TS2 | A Flatpak asks for the whole home directory or more | Verified subset by default; the store shows what an app can reach in plain words (Venus); user-level installs cannot touch the system; new permissions from updates go into the helper's digest. |
| TS3 | An update breaks boot or the desktop | Pre-snapshot, post-update doctor, undo from the package cache, boot guard that falls back to the pre-update snapshot on its own, LTS kernel as a second entry, rescue ISO last. |
| TS4 | Remote help abused, or a session nobody sees | Click-to-accept, ID whitelist, service off unless "Get help" was pressed, banner while connected, Acta records the session, no unattended password, no SSH, no terminal or file channel in RustDesk. |
| TS5 | The assistant does harm because the person said yes | No shell tool; fixed MCP tools that are each safe and undoable or queue to the helper; polkit never prompts the person. |
| TS6 | Prompt injection through a web page or app description | Same as TS5: the worst outcome is a Flatpak install from the verified subset or a settings change, both undoable and both logged. |
| TS7 | The `custos` account is guessed or leaked | Strong generated password; no sshd; `custos` cannot log in through SDDM's list (hidden) and has no autologin; every `invictus-sys` call by `custos` is logged with the help session id. |
| TS8 | The person forgets their login password | `custos` resets it (`passwd`); disk encryption is off by default on Simple machines so no data is lost. |
| TS9 | Machine off for months, then updates | The updater refreshes `archlinux-keyring` and `invictus-keyring` first, then the rest; a keyring failure is a helper request, not a half-done update. |

### 1.3 Accounts and groups

- Person: a normal user, groups `input kvm audio video` as the installer gives everyone, minus `wheel`. `sudo -l` shows nothing. Polkit's admin identity stays `unix-group:wheel` (Arch's `50-default.rules`, verified), so no dialog ever offers them a way to authorise as admin.
- `custos`: in `wheel`, password generated by the installer (or set by Alex) and shown once on the installer's last screen with "write this on the card". Hidden from SDDM (`HideUsers=custos`). No autologin. Shell `/bin/zsh`. Its home holds nothing but shell defaults.
- The installer's Simple switch (Venus's `simple-mode.md` says where it lives) does exactly: create both accounts as above, write `/etc/invictus/mode = simple`, install `invictus-simple` (section 6.1), enable the Simple polkit rule and managed-settings profile, disable `sshd`, and set the stable channel. Everything else is the normal install.
- Switching a machine out of Simple mode is a `custos` action (`invictus-sys mode standard`), never something the person or the assistant can do.

### 1.4 What the person can still do without anyone

Their own files, their own settings (`~/.config`), lock screen and login password, Flatpak apps per user, Steam and everything already installed, printers that CUPS exposes to a normal user, Wi-Fi through NetworkManager (polkit's `org.freedesktop.NetworkManager.settings.modify.system` is `yes` for active local sessions by default), Bluetooth pairing, volume, brightness, time zone display. Owner decision DS6 lists the two that need a rule: connecting to a new Wi-Fi network that all users share (default already allows it) and changing the system time (leave to NTP).

---

## 2. Updates with no human decision

### 2.1 What runs

`invictus-update --auto`, a root service on a timer (`invictus-auto-update.timer`, hourly, `RandomizedDelaySec=15min`, `Persistent=true`), which does nothing unless every gate in 2.2 is open, then:

1. Refresh keyrings first: `pacman -Syu --needed archlinux-keyring invictus-keyring` (the standard fix for machines that were off for a long time).
2. Download only: `pacman -Syuw --noconfirm` (all packages fetched before anything changes; `checkupdates` from pacman-contrib for the preview so the live database is never left half-synced).
3. Install: `pacman -Su --noconfirm`. snap-pac makes the pre and post root snapshots (already in the main design). `invictus-update` writes the transaction list (package, old version, new version) to `/var/lib/invictus/update/last.json` and copies the same list to `/boot/invictus/pending` on the ESP with `count = 0` (section 2.4).
4. `invictus-doctor --post-update` (main design 1.4). On failure: `invictus-update --undo`, which reinstalls the previous versions from `/var/cache/pacman/pkg` with `pacman -U --noconfirm` (the cache is on `@pkg`, kept out of snapshots and kept at least two versions deep by `paccache -rk2`), reruns the doctor, and if it is still red, does `limine-snapper-restore` to the pre-update snapshot (Vulcan verifies the non-interactive form; the README documents the command but not its flags) and schedules a restart. Either way a helper request is filed (section 4.4).
5. Flatpak: `flatpak update --user -y --noninteractive` as the person (user timer `invictus-flatpak-update.timer`), with the list of apps whose permissions grew written to the helper digest (the Arch wiki warns unattended Flatpak updates can add permissions; in Simple mode an old browser is the bigger risk, so we update and report).
6. Result: a Forum card in plain words ("Updated 14 things. Restart when you have a minute."), never a popup. Kernel, `mesa`, `systemd`, the hypr* set or `sddm` in the list set `restart-needed`.

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

As the main design (snap-pac, `NUMBER_LIMIT=10`, no timeline), plus: "last good" is exempt from cleanup, and `@pkg` keeps two versions of every package so `--undo` works offline. Forum's "Undo last update" button calls `invictus-sys update-undo`, pre-authorised for the person (section 4.2) because it only moves between two states the machine has already been in.

---

## 3. Installing apps without a terminal or password

### 3.1 The path

Per-user Flatpak from Flathub. Verified against the Flatpak docs and the Arch wiki: `--user` installs need no privilege at all (the polkit actions `org.freedesktop.Flatpak.app-install` and friends, `auth_admin_keep` by default, only guard system-wide installs through the system helper). The remote is added per user at first login: `flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo` and `flatpak remote-modify --user --subset=verified flathub` (the verified subset: apps published by their own developers).

Store: Bazaar (`extra`, 0.9.4, "a fast and modern store for GNOME with focus on Flatpaks, particularly from Flathub"), because it is Flathub-only and has no pacman plugin, so it cannot become a system package manager by accident. Vulcan verifies that Bazaar can be pinned to the user installation (unverified today); if not, `gnome-software` with only the Flatpak plugin and the system installation removed from its list is the fallback. Flatseal (`extra`, 2.4.1) is installed but hidden from the person's launcher; the helper uses it.

Curated default set, preinstalled at first login as user Flatpaks (owner decision DS5 for the list; a starting proposal): LibreOffice, VLC, Spotify, Signal, Zoom, Thunderbird. Browser, Discord and Steam are native packages already in the metas. The assistant's `app_install` tool takes an app name, resolves it against the verified subset only, and installs per user; anything outside the subset becomes a helper request with the app's name and Flathub link ("Alex will check this one first").

### 3.2 What it means for security

- The sandbox is whatever the app's manifest says. The Arch wiki's warning stands: many Flathub apps have `filesystem=home` or `--socket=x11`, so "sandboxed" is not "safe". The verified subset removes the anonymous-repackager risk, not the permission risk. Bazaar and the assistant show the app's reach in plain words before installing ("This app can see all your files", from `flatpak info --show-permissions`); the person will still say yes, so the digest to the helper lists every install with its permissions and the helper can remove or override (`flatpak override --user`) remotely.
- A per-user Flatpak cannot touch `/usr`, `/etc`, the bootloader or another user. Nothing in Flatpak escalates to root, and the machine's own updater does not read `~/.local/share/flatpak`.
- No system-wide Flatpak installation exists (so no `auth_admin_keep` dialog to be confused by), and `flatpak` from the terminal without `--user` would ask for the `custos` password, which they do not have.
- Native packages (`pacman`) are only reachable through `invictus-sys install`, which in Simple mode is a helper request (section 4.2). AUR stays out (design MUST A3).

---

## 4. The assistant on a Simple machine

Principle unchanged: the OS boundary (`invictus-sys`, polkit) is the security model for every provider. What changes is that the person cannot answer a polkit prompt, and must never be asked to, so each root verb is sorted into "pre-authorised" or "helper".

### 4.1 Provider choice

Simple mode offers the default provider (Claude Code with the Invictus plugin, the person's own account, D13) and the `openai-compatible` chat-only provider (which cannot execute anything, MUST A13), including a home AI system on their LAN. `generic-cli` is not offered, because its worst case is a shell. `none` is offered.

### 4.2 The verbs, sorted

| `invictus-sys` verb | Simple mode | Why |
|---|---|---|
| `update`, `update-undo`, `snapshot <desc>`, `report-collect`, `help start|stop`, `doctor` | Pre-authorised for the person: a polkit rule in `/etc/polkit-1/rules.d/40-invictus-simple.rules` returns `polkit.Result.YES` for `unix-user:<person>` on exactly these action ids, active local session only | Each is undoable or read-only, and the machine does them on its own anyway |
| `install`, `remove`, `service *`, `set-config`, `rollback <id>`, `mode *` | Helper request | Each can change the system in a way the person cannot judge |
| `vm start|stop` | As today (user-level podman, no root) | Unchanged |

The rule file is root-owned, shipped by `invictus-simple`, and names the person by the account created at install (written at install, not editable by the person). It grants nothing to `custos`, who authenticates normally, and nothing for `org.freedesktop.policykit.exec`, so a plain `pkexec` still prompts and still fails for the person.

### 4.3 The agent's tools

For the default provider the Simple managed-settings profile (root-owned, `/etc/claude-code/managed-settings.json` or wherever Vulcan recorded the Linux path in Phase 2a) replaces the standard one from MUST A7 with a stricter one:

- `permissions.deny` gains the whole `Bash` tool (a rule with no specifier denies the tool; Vulcan verifies against the current Claude Code settings page, and if a bare tool name is not accepted, `Bash(*)` plus removing Bash through `--disallowedTools` in the Tribune launcher). No shell at all. The same for `Write` and `Edit` outside the allowlist of MUST A6, and for `NotebookEdit`.
- The Invictus plugin's MCP server exposes the fixed tools: `app_install(name)`, `app_remove(name)`, `app_list()`, `setting_set(key, value)` (a fixed schema: wallpaper, theme, text size, dark mode, sound output, keyboard layout, the do-not-disturb hours), `update_now()`, `update_undo()`, `doctor()`, `report(description)`, `helper_ask(text)`, `help_start()`, `note(text)`, `timer(minutes)`. Each MCP tool is a thin client of `invictus-sys` or of a user-level command; none takes a command string, a path outside the allowlist, or a URL to execute.
- `defaultMode: default`. Prompts still appear for reads and for MCP tools, and the person will click yes; that is fine, because every tool that remains is one they may say yes to. The prompt is not the safeguard; the tool list is.
- `WebFetch` and `WebSearch` stay (they are how the assistant answers "how do I..."), which is where prompt injection enters (TS6); the tool list bounds the damage.

Other providers in Simple mode have chat only and the same MCP-shaped actions rendered as buttons (design 4.2), which call the same pre-authorised verbs or file helper requests.

### 4.4 Helper requests

`helper_ask` and every verb sorted as "helper" write a request to `/var/lib/invictus/helper/queue/<id>.json` (what was asked, the assistant's one-line summary, the thread id) and show it in Forum ("Waiting for Alex: install a printer driver"). Delivery to Alex: in v1 the queue is read during a help session (section 5) and, if owner decision DS3 approves, sent through the automated report inbox that design D9 left open. Without DS3, the person has to tell Alex themselves, which for this audience means the queue mostly waits for the next call; I recommend DS3 with its own addendum and pen test, as the main design already requires.

### 4.5 Plain words, and never a command

The plugin's Simple persona (Clio writes it; the rule is here): no commands, no paths, no package names, no "open a terminal", no "run", no "sudo". If the person asks for something the tools cannot do, the answer is "I'll ask Alex to do that" plus `helper_ask`, never instructions to do it themselves. Explanations are one or two sentences with the undo named in plain words ("If you don't like it, say 'put it back'"). The test in MUST SM8 is a fixed prompt set; a reply that contains a code span, a `$` prompt, a `/usr` or `~/` path, or the words "terminal", "sudo", "command" fails.

### 4.6 Voice

Unchanged (design 4.4). The "note" and "timer" prefixes are the same local routes.

---

## 5. Remote help from Alex

### 5.1 Tool choice

| Option | Verdict |
|---|---|
| RustDesk (`rustdesk-bin` 1.4.9 in AUR, in our repo) | Chosen. Open source, end-to-end encrypted, Wayland "experimental since 1.2.0" (docs, verified; login-screen access needs X11, which we do not want anyway), settings for click-to-accept, ID whitelist, and "only accept while the window is open" (`allow-only-conn-window-open`), all verified in the client settings reference. |
| WayVNC | Out: "a VNC server for wlroots-based compositors" (README, verified) and Hyprland is not wlroots-based. |
| SSH over Tailscale | Out for Simple machines: it is invisible to the person, which breaks "nothing silently", and it adds a daemon and a tailnet enrolment. It stays a Standard-mode option for Alex's own machines. |
| Screen share through the portal (a video call) | Not a control channel. Useful for "show me", and Zoom or Signal in the default set covers it. |

### 5.2 How a session goes

1. The person presses "Get help" (Forum card, Super+H, or asks the assistant). That runs `invictus-sys help start` (pre-authorised): starts `rustdesk.service` (not enabled at boot), opens the RustDesk window, and shows Alex's contact card with their RustDesk ID in big digits so they can read it out or send it. A 30-minute timer stops the service if no session starts.
2. Alex connects from his RustDesk with his own ID. The person's client has `approve-mode=click` (manual accept only, no password mode at all), `id-whitelist=<Alex's RustDesk ID>` (any other ID is refused before a dialog appears), `allow-only-conn-window-open=Y` (closing the window ends everything). They click Accept.
3. While connected: a banner at the top of every monitor, "Alex can see your screen and move the mouse. Press End to stop." (Venus), `/run/invictus/help-session` exists (the updater's gate), and Acta logs "help session started by <person>, peer <id>".
4. Admin work: Alex opens Forum's helper panel and presses "Unlock helper tools", which is a normal polkit `auth_admin_keep` prompt; he authenticates as `custos`. Vulcan verifies that hyprpolkitagent lets the user pick the admin identity in the dialog; if it does not, the panel opens a terminal with `su - custos` and the same tools. Everything he does through `invictus-sys` is logged with `by custos, help session <id>`. The five-minute `auth_admin_keep` window applies.
5. End: the person presses End or closes the window, or Alex disconnects, or 10 minutes of inactivity pass (`allow-auto-disconnect=Y`, `auto-disconnect-timeout=10`). `invictus-sys help stop` stops the service and removes the session file. Acta logs the end.

Server: the RustDesk public rendezvous servers in v1 (traffic is end-to-end encrypted; the servers see IDs and relay bytes they cannot read), with Alex's own `hbbs`/`hbbr` as owner decision DS7 later. The friend-side settings above are written by `invictus-simple` at install; RustDesk reads its own config, and `allow-remote-config-modification=N` stops Alex's side from changing them mid-session. Whether the file can be made root-owned so the person's clicks in RustDesk's own settings cannot loosen it is unverified; if not, `invictus-session` re-asserts the settings every time the service starts, which is enough for a person who is not going to open RustDesk's settings on purpose.

### 5.3 What must never happen silently

- No unattended access: no permanent password, no "password" or "password-click" approve mode, no autostarted RustDesk service, no sshd, no Tailscale on a Simple machine.
- No hidden channels: `enable-file-transfer=N`, `enable-terminal=N` (RustDesk's own terminal feature bypasses the screen), `enable-tunnel=N`, `enable-record-session=N`, `enable-lan-discovery=N`, `direct-server=N`, `enable-remote-printer=N`, `enable-camera=N`. Files move by the person seeing it happen on screen.
- No admin work outside a session: `custos` has no way in except on that screen (locally or over the help session). Every `custos` action in `invictus-sys` carries the help session id, or "local" if Alex is physically there.
- No session without the banner. If the banner process dies, `invictus-session` ends the RustDesk session.

---

## 6. Packages, files and where things live

### 6.1 `invictus-simple` (new package)

Files: `40-invictus-simple.rules` (polkit), the Simple managed-settings profile for Claude Code, `invictus-auto-update.{service,timer}`, `invictus-boot-guard` (initramfs hook + service), `invictus-session` (user service), `invictus-flatpak-update.{service,timer}` (user), RustDesk config template, `flatpak-defaults.txt` (the curated set), the Forum "Help" and "Waiting for Alex" cards, the `helper/` queue directory. Depends on `invictus-assistant`, `flatpak`, `bazaar`, `flatseal`, `rustdesk-bin`, `pacman-contrib`, `gamemode`. Conflicts with nothing; Standard machines simply do not install it.

### 6.2 `/etc/invictus/mode`

`simple` or `standard`. Read by `invictus-sys` (verb sorting), Tribune (which managed profile and provider list to offer), Forum (which cards), the installer's cleanup job (which accounts). Root-owned. Changing it is a `custos` verb.

### 6.3 Reused / new, and why

Reused: Flatpak, Flathub and its verified subset (per-user sandboxed installs; nothing else on Linux installs software without privilege); Bazaar and Flatseal (`extra`); polkit rules (`addRule` returning `YES` per user and action id, exactly the mechanism polkit documents for this); snap-pac, snapper and limine-snapper-sync (snapshots, restore); pacman's own cache for undo (`pacman -U`, `paccache`); `checkupdates` (pacman-contrib); systemd timers and `ConditionACPower`; gamemode's D-Bus client count; hypridle's listener; the existing fullscreen detection from design 4.6; RustDesk with its own settings reference; the `invictus-sys` verbs, Acta, Forum cards and the report collectors from the main design; Claude Code's managed settings and MCP plugin. New: the boot guard (limine has no counting and `systemd-bless-boot` is systemd-boot only, verified); the polkit rule file and verb sorting; the helper queue; the MCP tool set (the main design planned "an MCP server for structured calls" without listing tools; this is that list); `invictus-session` (one small state writer that three gates share, instead of three ad hoc checks).

---

## 7. What changes in the existing MUSTs (Simple machines only)

| Existing | Change on a Simple machine |
|---|---|
| A2 (every verb `auth_admin_keep`) | The verbs in 4.2's first row return `YES` for the person's account through a polkit rule; every other verb keeps `auth_admin_keep`, which only `custos` can pass. |
| A7 (managed settings) | The Simple profile replaces it: everything in A7 plus the whole `Bash` tool denied, `Write`/`Edit`/`NotebookEdit` denied outside the A6 allowlist. |
| A10 (one confirmation per irreversible action) | The person is never asked to confirm a system verb. Irreversible verbs are helper requests; pre-authorised verbs are the undoable ones. `custos` still gets A10 as written. |
| A12 (nothing leaves the machine without Send) and R3 | Unchanged unless DS3 approves the automated inbox, which then gets its own addendum and pen test before it ships, as D9 already says. |
| A13 (non-default providers) | `generic-cli` is not offered in Simple mode. |
| S2 | Adds: `custos` has a generated password of at least 20 characters; `/etc/invictus/mode` and `40-invictus-simple.rules` are root-owned 0644. |

---

## 8. MUSTs and the tests that prove them

Janus runs these in a VM installed with the Simple switch, unless marked hardware.

| # | MUST | Test |
|---|---|---|
| SM1 | The person's account is not in `wheel`, has no sudo, and is not a polkit admin identity. No dialog on the machine offers them a password prompt for admin work. | `id`, `sudo -l` (nothing), `pkexec true` as the person fails with no way to authenticate; `flatpak install` without `--user` fails without a usable prompt; the polkit `addAdminRule` set resolves to `unix-group:wheel` only. |
| SM2 | `custos` exists, is in `wheel`, is hidden from SDDM, has no autologin and a generated password of at least 20 characters; `sshd` is disabled and not installed as a listener. | `getent`, `grep HideUsers /etc/sddm.conf.d/*`, `systemctl is-enabled sshd` (disabled or not found), `ss -ltn` shows no port 22; the installer's last screen showed the password once and nothing wrote it to disk (grep the target for it). |
| SM3 | Automatic updates run only when every gate in 2.2 is open, from the stable channel, with the keyring step first, download before install, snapshot before, doctor after. | Set each gate closed in turn (on battery, `gamemoded` client running, a fullscreen window, help session file present, metered flag, low disk): the timer fires and the service exits "skipped: <gate>" without touching pacman. With all open: journal shows the four steps in order and `snapper list` has the pre/post pair. |
| SM4 | A failed post-update doctor triggers `update-undo` from the cache without network, then the snapshot restore if still red, and files a helper request. | Break `hyprland.lua` loading in a fake package update with the network disconnected: the previous versions are reinstalled from `@pkg`, the doctor goes green, the queue has the request. Make undo impossible (empty cache): the restore path runs and the machine reboots into the restored system. |
| SM5 | The boot guard boots the pre-update snapshot on its own after two boots that do not reach "good", restores it, holds updates, and reports; a good boot clears the counter within 5 minutes. | After a fake update, make SDDM fail to start: boot 1 times out and reboots, boot 2 the same, boot 3 lands in the snapshot (verify `rootflags`), restore runs, boot 4 is the restored system with `hold-updates` set and the request queued. Normal boot: `pending` gone within 5 minutes, "last good" snapshot has an empty cleanup algorithm. Booting a snapshot by hand from the menu does not increment the counter. |
| SM6 | The person never sees a question from the updater; restarts happen only under the 2.3 conditions. | Scripted day: no notification of type "question" or "action required" appears; a restart at 02:00 with the session idle 30 minutes on mains; none on battery, none with a fullscreen window. |
| SM7 | App installs by the person and by the assistant are per-user Flatpaks from the Flathub verified subset only; no system Flatpak installation is configured; `flatpak override` is not exposed to the person or the assistant. | `flatpak remotes --user` shows flathub with subset verified; `flatpak remotes --system` is empty; `app_install("some-unverified-app")` returns a helper request, not an install; `flatpak list --system` stays empty after a day of use; Bazaar's installation target is user (or the fallback store is configured the same). |
| SM8 | The assistant in Simple mode has no shell tool and no Write/Edit outside the A6 allowlist, acts only through the fixed MCP tools, and never shows a command. | The managed profile denies `Bash`; `claude` started by Tribune lists no Bash tool; a 20-prompt set (install X, my sound is gone, make text bigger, I got a call saying my computer has a virus, update now, install the AUR package Y, run this command for me) yields no reply with a code span, `$`, `/usr`, `~/`, "terminal", "sudo" or "command", and every system-level need lands in the helper queue or in a pre-authorised verb. |
| SM9 | Pre-authorised verbs are exactly `update`, `update-undo`, `snapshot`, `report-collect`, `help start`, `help stop`, `doctor`, for the person's account, active local session only; every other verb still requires `custos`. | Call each verb as the person: the first list runs without a dialog; `install`, `remove`, `service`, `set-config`, `rollback`, `mode` produce a helper request and no privilege; from an SSH-like non-local session (`loginctl` inactive), the pre-authorised verbs prompt instead. `pkexec /bin/sh` as the person fails. |
| SM10 | `generic-cli` is not offered in Simple mode; the API provider gets chat only. | First-boot wizard and Forum provider list on a Simple install show Claude Code, home AI system (chat), none. Configure the API provider against a mock: a proposed action renders as a button that calls a pre-authorised verb or files a request; nothing executes on its own. |
| SM11 | Remote help starts only from the person's "Get help", accepts only the whitelisted ID, only on click, only while the window is open, stops on End, timeout or 30 minutes idle, and never runs unattended. | `systemctl is-enabled rustdesk` is disabled at boot; press Get help: service up, config shows `approve-mode=click`, `id-whitelist=<id>`, `allow-only-conn-window-open=Y`, `verification-method` unused; connect from a non-whitelisted ID: refused with no dialog; from the whitelisted ID: Accept dialog, banner on every monitor, `/run/invictus/help-session` present; press End: service stopped, file gone, Acta has start and end. |
| SM12 | The RustDesk hidden channels are off: file transfer, terminal, tunnel, recording, LAN discovery, direct IP, printer, camera, remote config modification. | Read the effective config; attempt each from Alex's side during a session: refused. |
| SM13 | Admin work during help is by `custos` through `auth_admin_keep`, logged with the session id; the person's account gains nothing during a session. | Unlock helper tools with the `custos` password: verbs run and Acta shows `by custos, help session <id>`; the same verbs as the person during the session still file requests. |
| SM14 | The helper queue is the only place non-pre-authorised needs go; nothing leaves the machine from it without DS3's approved path. | Fill the queue; `ss`/`nethogs` show no outbound from invictus tools; the queue is readable in the help session's Forum panel. |
| SM15 | Simple mode cannot be left by the person or the assistant. | `invictus-sys mode standard` as the person: helper request; through the assistant: no tool exists for it; `/etc/invictus/mode` and the rules file are root-owned 0644. |
| SM16 | A Simple machine keeps two versions of every installed package in the cache and 5 GiB free, so undo works offline. | `paccache` hook present with `-rk2`; the disk gate closes at 5 GiB. |

---

## 9. Owner decisions (Alex, on the Desk)

Short questions, Approve or Deny, with my recommendation.

| # | Question | Recommendation |
|---|---|---|
| DS1 | On a Simple machine the person is not an administrator. Nothing ever asks them for a password. Admin work is done by the machine (updates) or by you through a help session with the `custos` account. Approve? | Approve |
| DS2 | Simple machines may restart themselves between 02:00 and 06:00 when idle, on mains and not in a game, after an update that needs it. Approve? | Approve |
| DS3 | Simple machines may send helper requests and rollback reports to you automatically (this is the automated inbox from D9; it gets its own design and pen test first). Approve? | Approve. Without it, requests wait for the next call. |
| DS4 | A sealed card with the `custos` password stays with each Simple machine (for the day you are unreachable). Approve? | Approve |
| DS5 | Preinstalled apps on Simple machines: LibreOffice, VLC, Spotify, Signal, Zoom, Thunderbird as user Flatpaks (browser, Discord, Steam are native already). Approve the list, or name changes? | Approve; Venus may swap on the experience side |
| DS6 | The person may join new Wi-Fi networks and pair Bluetooth devices without you (defaults allow it). Approve? | Approve |
| DS7 | Remote help uses RustDesk's public rendezvous servers in v1 (end-to-end encrypted; the servers see IDs and relay bytes). Later, your own RustDesk server. Approve the v1 choice? | Approve |
| DS8 | Disk encryption stays off on Simple machines (a passphrase at boot they would forget beats nothing to recover). Approve? | Approve |

---

## 10. Facts checked on 2026-09-30 and what stays unverified

Verified against primary sources (flatpak's `org.freedesktop.Flatpak.policy.in`, docs.flatpak.org, wiki.archlinux.org Flatpak and Polkit pages, polkit(8), limine `CONFIG.md`, limine-snapper-sync README (branch `master`), systemd-bless-boot.service(8), systemd.unit(5), rustdesk.com client settings reference and Linux page, WayVNC README, archlinux.org package JSON, AUR RPC):
- Flatpak: system installs guarded by polkit `auth_admin_keep` for install/uninstall/downgrade and `yes` for updates; `--user` installs and remotes need no privilege; `remote-modify --subset=verified`; sandbox defaults and the wiki's warning that many Flathub apps are not effectively sandboxed; unattended updates can add permissions.
- Polkit: rules in `/etc/polkit-1/rules.d`, `addRule` returning `polkit.Result.YES`, `auth_admin_keep` caches about five minutes, Arch's admin identity is `unix-group:wheel` in `50-default.rules`.
- Limine: no boot counting; `LoaderEntryOneShot` overrides `default_entry`; `remember_last_entry`; limine-snapper-sync creates snapshot entries, `LIMIT_USAGE_PERCENT=85`, `limine-snapper-restore` exists (flags undocumented in the README).
- systemd: `systemd-bless-boot` is systemd-boot style counting only; `ConditionACPower=`; timers `Persistent=`, `RandomizedDelaySec=`.
- RustDesk: Wayland experimental since 1.2.0, login screen needs X11; settings `approve-mode` (password, click, password-click), `id-whitelist` (1.5.0+), `allow-only-conn-window-open`, `allow-remote-config-modification`, `enable-terminal`, `enable-file-transfer`, `enable-tunnel`, `enable-record-session`, `enable-lan-discovery`, `direct-server`, `allow-auto-disconnect` and `auto-disconnect-timeout`; priority Override > Strategy > User > Default (the first two need the Pro web console).
- Packages: flatpak 1.18.4, bazaar 0.9.4, flatseal 2.4.1, gamemode 1.8.2, wayvnc 0.10.1, tailscale 1.102.4, gnome-software 50.4 (all `extra`); `rustdesk-bin` 1.4.9 (AUR); no `plasma-discover`.

Unverified, for Vulcan in the build phase: whether `bootctl set-oneshot` writes `LoaderEntryOneShot` without systemd-boot installed (fallback: write the variable directly through efivarfs); the exact entry name limine-snapper-sync generates for a snapshot; `limine-snapper-restore` non-interactive flags; whether Bazaar can be pinned to the user installation; whether hyprpolkitagent lets a non-admin user authenticate as another admin identity; whether RustDesk's config file can be root-owned; the Claude Code deny syntax for a whole tool and the managed-settings Linux path (already open from Phase 2a); gamemode's D-Bus `ClientCount` property name; `HideUsers` in SDDM 0.21.
