# Invictus: architecture design

Author: Minerva (consultant). Date: 2026-09-30. Status: draft for Alex's owner decisions (section 10), then build.

Invictus is Alex's personal Linux distro, based on Arch, built around Hyprland, for AMD machines, for gaming, development and a Windows-for-work VM, with an AI assistant, a home dashboard and a team harness built in. Friends and family only. The old `hyprdots` repo is the seed; this document says what the new thing is, what we keep, what we drop, how it is built and installed, and the security rules for the parts that can hurt.

Read section 0 for the decisions, section 10 for what only Alex can decide. Everything else is the reasoning and the detail the builders need.

Addendum: Custodia guard rails, the machine-wide admin model for friends' machines (the person is admin, childproofed by snapshots and plain words, automatic updates with a boot guard, per-user Flatpak apps, helper requests, remote help by RustDesk) is in `design-simple-mode.md` (2026-09-30); its section 7 lists which MUSTs here it changes on Simple machines. The desktop those friends see is the Atrium flavor (`simple-mode.md`); Alex's is Tessera. Guard rails (Custodia or Libertas) and flavor (Atrium or Tessera) are two independent settings, both switchable live (design-simple-mode.md 1.6).

Addendum: the Desk as a native part of Invictus and the Collegium (git as the one store, the claude.ai page as Alex's phone view through a bridge, the agent-neutral protocol, friends' Desks, local Push through a Claude Code channel, GD1 to GD16) is in `design-desk.md` (2026-09-30); it changes 4.3 (a `desk` repo beside `mine`), 4.6 (Waiting on you reads the desk repo) and Phase 2c.

Naming: we say "based on Arch Linux" and never use the Arch name or logo in the distro's own name, artwork or boot screens (trademark policy, verified 2026-09-30: non-Arch packages and a new installer rule out "Remix" use).

---

## 0. Decisions in one screen

| Area | Decision | Why (short) |
|---|---|---|
| Repo | One monorepo `invictus`: `iso/`, `pkgs/`, `config/`, `assistant/`, `collegium/`, `installer/`, `scripts/`, `docs/` | Everything an installed machine gets comes from packages; the repo is the build source, not something users `git pull` |
| Package repo | Our own pacman repo `[invictus]` (signed, two channels: `testing` for Alex, `stable` for everyone else), listed before `[extra]` | pacman takes the first repo that has a package, regardless of version (pacman.conf(5), verified), so listing ours first pins what we choose to pin |
| Updates | `invictus-update` (pacman `-Syu` wrapped with pre/post snapshots via snap-pac and a config check). Never `git pull`, never `git stash` | One update path for system and desktop config; rollback is a boot-menu entry |
| Hyprland breakage | Pin the whole hypr* set (hyprland, aquamarine, hyprutils, hyprlang, hyprgraphics, hyprcursor, xdg-desktop-portal-hyprland, hyprpaper, hypridle, hyprlock, hyprpolkitagent) in `[invictus]`; promote testing to stable after Alex runs it a week | Config-format churn (0.53 windowrule rewrite, 0.55 Lua) is the real breakage; binary pinning plus a snapshot before every update covers it |
| Config language | `hyprland.lua` (Hyprland 0.55+). hyprpaper/hypridle/hyprlock stay hyprlang (upstream said so, verified) | Required by Alex; hyprlang is on a 1 to 2 release clock |
| Installer | archiso profile + Calamares 3.4.2 (AUR, in our repo), offline install by unpacking the live image | Graphical "Install" button; the live system is the installed system, so what Alex tests live is what gets installed |
| Filesystem | btrfs, subvolumes `@ @home @log @cache @pkg @snapshots @vm`, snapper on `/` with snap-pac | Standard snapper layout; `@vm` keeps the Windows disk out of root snapshots and out of copy-on-write |
| Bootloader | limine + limine-mkinitcpio-hook + limine-snapper-sync, 4 GiB FAT32 ESP at `/boot`; installed by our own Calamares job because upstream Calamares has no limine module (verified) | Bootable snapshots in a "Snapshots" menu and a one-command restore (`limine-snapper-restore`). Fallback if the job misbehaves on hardware: grub + grub-btrfs (both in `extra`), a config change not a redesign |
| Windows | Local VM: rootless podman + `dockur/windows` (KVM), RDP bound to 127.0.0.1 only. Client: FreeRDP 3 (`freerdp` 3.32.1 in `extra` ships `sdl-freerdp3`, `xfreerdp3`, `wlfreerdp3`). Full desktop via `sdl-freerdp3 /multimon`; seamless apps via WinApps, which is documented against `xfreerdp3`; `sdl-freerdp3` RemoteApp support is unverified and gets tested first | Automated Windows install, no passthrough, one client family, keyring-held credentials |
| Assistant | Moneta, in the Moneta panel (Super+A; code name `tribune`): a dropdown terminal running an agent through a provider adapter. Default provider: Claude Code with an Invictus plugin. Every system change goes through `invictus-sys` (root-owned, polkit-authenticated, fixed verbs). The agent never gets sudo | Security lives in the OS boundary, so any agent (Claude, another CLI, a local model) gets the same rules |
| Voice | Pen-style Bluetooth button grabbed exclusively by `invictus-ptt`; audio to a local `whisper-server` (whisper.cpp built with `GGML_VULKAN=1`, verified) on 127.0.0.1; only text leaves, typed into the Moneta panel | Push-to-talk by hardware, no wake word, no audio off the machine |
| Dashboard | The Desk (code name `forum`): a Quickshell (in `extra`, 0.3.1) page with updates, snapshots, health, notes, threads, and the assistant's action log ("Acta") | One UI toolkit for welcome, first boot, the Desk and overlays |
| Team harness | "Collegium": an agent-neutral git repo (markdown + `collegium.toml`) with roles, rules, skills, projects and memory; thin adapters generate `CLAUDE.md`/`.claude/*` for Claude Code and `AGENTS.md` for others. Connect existing, create new, or local-only, in one wizard step | Alex's asks 1 to 4 of 2026-09-30 (AI-agnostic, harness by default, few-click connect, clean template) |
| Report-back | `invictus-report`: allowlisted collectors, full preview, user sends (GitHub issue form or mail draft). Nothing automatic in v1 | No secrets in the repo means no shared upload token; automation is an owner decision later |
| Claude sign-in | At first boot, in the user's home (`~/.claude/.credentials.json`, mode 0600, verified). Never in the ISO, never in the repo | |

---

## 1. Repo layout, what to keep, updates, Hyprland breakage

### 1.1 Layout of the new repo

```
invictus/
  README.md                  what it is, who it is for, how to build
  LICENSE                    GPL-3 (kept from hyprdots)
  docs/
    design.md                this document
    reuse-catalog.md         shared pieces (charter rule); Vulcan adds on each merge
    checklists/              hardware test checklists Iris turns into pages for Alex
  iso/                       archiso profile (copied from releng, then edited)
    profiledef.sh, packages.x86_64, pacman.conf, airootfs/, efiboot/
  installer/                 Calamares: settings.conf, modules/*.conf, branding/invictus/, jobs/*.sh
  pkgs/                      one PKGBUILD per directory
    meta/                    invictus-base, -desktop, -gaming, -dev, -windows, -assistant, -voice, -collegium, -iso-live
    own/                     invictus-keyring, invictus-sys, invictus-tools, invictus-forum, invictus-tribune, invictus-ptt,
                             invictus-collegium, invictus-calamares-config, invictus-branding, invictus-sddm-theme
    aur/                     pinned copies of AUR PKGBUILDs we build: calamares, limine-mkinitcpio-hook, limine-entry-tool,
                             limine-snapper-sync, whisper.cpp (Vulkan), proton-ge-custom-bin, claude-code, winapps,
                             zen-browser-bin, nordic-darker-theme, xwaylandvideobridge
    pinned/                  the hypr* binary set, copied from Arch at a tested version (no rebuild)
  config/                    desktop defaults shipped by invictus-desktop (installed under /usr/share/invictus/config)
    hypr/hyprland.lua, hypr/invictus/*.lua, hypr/hyprpaper.conf, hypr/hypridle.conf, hypr/hyprlock.conf
    waybar/, kitty/, rofi/, swaync/, fastfetch/, btop/, cava/, zed/, shell/zshrc
  assistant/                 tribune (panel), forum (dashboard), ptt (voice), report, doctor, providers/, claude-plugin/
  collegium/                 the harness: template/, adapters/, cli/
  scripts/                   build-repo.sh, build-iso.sh, promote.sh (testing -> stable), dev/adopt.sh (existing installs)
  .github/workflows/         packages.yml (build + sign + publish), iso.yml, checks.yml (shellcheck, luacheck, secrets scan)
```

Rules:
- Users never clone this repo to use Invictus. Everything reaches a machine as a package.
- User-editable config lives in `~/.config/...`; shipped defaults live in `/usr/share/invictus/...`. A default is copied into the home only on first login, and only if the file does not exist (the old repo's copy-once idea, kept). Updates change `/usr/share`, never a user's file.
- Hyprland config structure: `~/.config/hypr/hyprland.lua` is a five-line file that puts `/usr/share/invictus/hypr/?.lua` on `package.path`, requires `invictus.core`, then requires `~/.config/hypr/user.lua` if it exists. `user.lua` is where the user (and the assistant) makes changes; `invictus/*.lua` is ours and updates with the package. Monitor layout goes in `~/.config/hypr/monitors.lua`, generated by the first-boot wizard. Vulcan checks the wiki's "Require" and "Ignoring require's protection" sections (wiki.hypr.land/configuring/core/) for the exact path rules before building.

### 1.2 What happens to the old repo

| Old | Fate | Note |
|---|---|---|
| `scripts/install.sh`, `install-packages.sh`, `deploy-configs.sh`, `deploy-shell.sh` | Drop | Replaced by packages, Calamares and first boot |
| `scripts/init-user.sh` | Rewrite as `invictus-first-login` (systemd user unit, sentinel in `~/.local/state`) | Keep its logic: XDG dirs, user services, caches |
| `scripts/update.sh` | Rewrite as `invictus-update` | Drop `git pull`, drop the auto-stash (charter: never stash), add snapshot check and config check |
| `scripts/install-sddm.sh` | Rewrite as package `invictus-sddm-theme` | The README lists `assets/SDDM/blackglass` (vendored, own licence) but the checkout has only `hyprland.desktop`; Vulcan restores it from history or picks another theme. Owner decision D12 |
| `scripts/waybar/{cpu,gpu,memory,updates}.sh` | Keep, move into `invictus-tools` | They also feed the Desk's health cards. `gpu.sh`: drop the NVIDIA branch (AMD only) |
| `scripts/show-keybindings.sh` | Rewrite | It parses hyprlang; the Lua binds carry a description and `hyprctl binds -j` produces the cheatsheet |
| `config/hypr/*.conf` | Rewrite in Lua, by hand | Small config; do not depend on `hyprconf2lua` (unverified) |
| `config/hypr/hyprpaper.conf` | Keep | Path changes from `~/hyprdots/assets/...` to `/usr/share/invictus/wallpapers/...` |
| `config/waybar`, `kitty`, `rofi`, `swaync`, `fastfetch`, `btop`, `cava`, `zed`, `shell/zshrc` | Keep | Waybar stays until a Quickshell bar is a strict superset (reuse rule) |
| `packages/pacman.txt`, `aur.txt` | Become `depends` of the meta packages | Fixes on the way: `vscode` is not an Arch package (`code` is); `mako` and `swaync` are both autostarted (two notification daemons); `xwaylandvideobridge`, `discord`, `steam`, `brightnessctl`, `playerctl`, `jq` are used by binds or autostart but not listed |
| `assets/wallpapers/Berserk.jpg`, `girl.png`, `blossom.png` | Owner decision D11 | Copyrighted anime art in a distro image; recommend replacing with own or CC0 art in the Roman theme (Venus) |
| `README.md` | Rewrite | It describes files that no longer exist (`nvidea.sh`, `symlink-configs.sh`, `.mine` files) |
| `.gitignore` (`.mine`, `.developer`) | Replace | The `.mine` idea becomes `user.lua` and `monitors.lua` in the home |
| `config/hypr/config/permissions.conf` (commented out) | Vulcan decides in Phase 1 | Enabling `ecosystem:enforce_permissions` is good hygiene but can break screen sharing; test before shipping |

### 1.3 Package repo `[invictus]`

- Hosting: static files (`invictus.db`, `*.pkg.tar.zst`, `*.sig`). GitHub Releases assets on the private repo under a fixed tag work with pacman's `Server =` (redirects are followed) and take large files (proton-ge is hundreds of MB, too big for git or Pages). Owner decision D3 if Alex prefers his own host.
- Signing: one repo key. Public key ships in `invictus-keyring` (the ISO's `pacman.conf` and the installed system trust it). Private key location is owner decision D4 (GitHub Actions secret means GitHub can sign; Alex's machine means builds only there, with `scripts/build-repo.sh` in a podman `archlinux:base-devel` container).
- Two channels: `[invictus-testing]` (Alex's machine) and `[invictus]` (family). `scripts/promote.sh` copies a tested set from testing to stable. Family machines list only stable.
- Every AUR PKGBUILD we build is copied into `pkgs/aur/` at a reviewed commit, with its source checksums. We do not build from a moving AUR checkout in CI (supply chain).
- Meta packages: `invictus-base` (kernel, amd-ucode, mesa, vulkan-radeon, btrfs-progs, snapper, snap-pac, limine set, networkmanager, pipewire, bluez, podman), `invictus-desktop` (hypr* pinned set, waybar, rofi, kitty, swaync, sddm, portals, fonts, themes, the config), `invictus-gaming` (steam, gamescope, mangohud, umu-launcher, lutris, proton-ge-custom-bin), `invictus-dev` (base-devel, git, zed, code, nodejs, python, podman-compose, claude-code), `invictus-windows` (freerdp, winapps, podman-compose, virtiofsd), `invictus-assistant` (invictus-sys, tribune, forum, report, doctor, providers), `invictus-voice` (whisper.cpp Vulkan, invictus-ptt, models downloaded at first boot, not packaged), `invictus-collegium` (harness CLI, template, adapters), `invictus-iso-live` (calamares, live-only bits; removed by the installer).

### 1.4 How updates reach a machine

1. `invictus-update` (Desk button, Moneta, or terminal) runs: `pacman -Syu` (snap-pac creates pre/post root snapshots around it), then `invictus-doctor --post-update` (Hyprland config load check, kernel and limine entries present, snapshot list sane), then shows a plain result: what changed, which snapshot to boot if something is wrong.
2. Desktop config updates arrive as new files in `/usr/share/invictus/`. If a shipped file that the user copied on first login has changed upstream, `invictus-doctor` lists it and offers a diff; it never overwrites.
3. Partial upgrades (`pacman -Sy pkg`) are forbidden everywhere in our tools. Installing a package is `pacman -Syu --needed pkg`.
4. Family machines get stable only. Alex's machine runs testing and is the canary; promotion after a week of use, or sooner for a fix.

### 1.5 Hyprland breakage protection

- Pin the hypr* set as binary copies in `[invictus-testing]`/`[invictus]` at the version our Lua config was tested with (currently 0.56.2). Because pacman prefers the first repo listed, Arch's `extra` cannot move Hyprland under us. Risk: a soname bump in a non-pinned dependency (mesa, libdisplay-info, wayland) can still break a pinned Hyprland; the canary week and the post-update doctor check catch it, and the snapshot menu recovers it.
- Every update has a pre-snapshot (snap-pac). Every snapshot with a matching kernel appears in the limine "Snapshots" boot menu (limine-snapper-sync). Restore: `limine-snapper-restore` or the Desk's "Roll back" (which calls `invictus-sys rollback <id>` and reboots).
- Config check before reload: `invictus-doctor --hypr` loads `hyprland.lua` in a Lua sandbox with a stub `hl` table to catch syntax and obvious API errors before `hyprctl reload`. Vulcan checks whether Hyprland 0.56 exposes a `--verify-config` flag and uses it if so; the stub check is the fallback.
- The old config's `.mine` overrides survive as `user.lua`, so an update never touches user changes.

---

## 2. Install flow

### 2.1 ISO (archiso)

- Profile copied from archiso's `releng` (verified layout: `profiledef.sh`, `packages.x86_64`, `pacman.conf`, `airootfs/`, `efiboot/`, `grub/`, `syslinux/`). Changes: `iso_name="invictus"`, publisher/application strings without the Arch name, `bootmodes=('uefi.systemd-boot')` only (owner decision D5 if any BIOS-only family machine exists), `pacman.conf` with `[invictus]` first, `packages.x86_64` = `invictus-base invictus-desktop invictus-iso-live` plus archiso's live essentials (`mkinitcpio-archiso`, firmware).
- Live session: user `liber`, autologin on tty1, `start-hyprland` from the profile, a Quickshell welcome window with two buttons: "Install Invictus" (launches `calamares`) and "Try it". Live boot also works as a rescue disk: `invictus-rescue` menu (mount installed system, `limine-snapper-restore`, chroot).
- Kernel: `linux` (7.2.7 verified) plus `linux-lts` as a second boot entry on installed systems. `amd-ucode`. No NVIDIA anything.
- CI builds the ISO (`iso.yml`) with `mkarchiso` in a privileged container; artifacts as release assets. Secrets scan of the squashfs before publish (test T8).

### 2.2 Calamares

Calamares 3.4.2 from AUR, built in our repo. Modules (show phase): `welcome`, `locale`, `keyboard`, `partition`, `users`, `summary`. Exec phase: `partition`, `mount`, `unpackfs`, `machineid`, `fstab`, `locale`, `keyboard`, `localecfg`, `users`, `networkcfg`, `hwclock`, `services-systemd`, `shellprocess@invictus-bootloader`, `initcpio`, `shellprocess@invictus-post` (runs `limine-update` because the pacman hook does not fire inside the installer's `mkinitcpio -P`), `shellprocess@invictus-snapper`, `shellprocess@invictus-cleanup`, `umount`. Then `finished` with reboot.

Configuration points (all in `installer/`):
- `partition.conf`: `defaultFileSystemType: btrfs`, `efi.mountPoint: /boot`, `efi.recommendedSize: 4GiB`, `efi.minimumSize: 1GiB` (limine-snapper-sync copies kernels and initramfs per snapshot into the ESP and recommends at least 4 GiB, verified), swap: `file` (a swapfile in `@swap`, Calamares handles the subvolume), `userSwapChoices: [none, file]`, encryption offered, default off (owner decision D6).
- `mount.conf`: `btrfsSubvolumes`: `/ -> /@`, `/home -> /@home`, `/var/log -> /@log`, `/var/cache -> /@cache`, `/var/cache/pacman/pkg -> /@pkg`, `/.snapshots -> /@snapshots`, `/var/lib/invictus/vm -> /@vm`. Mount options: `noatime,compress=zstd:1` for all but `@vm`, which gets `noatime,nodatacow` (the VM disk image must not be CoW'd or snapshotted).
- `bootloader` module: disabled. `jobs/invictus-bootloader.sh` in the target: install `limine` files to the ESP, write `/etc/default/limine` (`ESP_PATH=/boot`, OS name "Invictus"), add `sd-btrfs-overlayfs` after `filesystems` in `/etc/mkinitcpio.conf` HOOKS (we use the systemd hooks; the wiki says `btrfs-overlayfs` is incompatible with them), run `limine-install`/`limine-update`, and register the EFI entry with `efibootmgr`. A second EFI entry for the live ISO's systemd-boot is not kept.
- `jobs/invictus-snapper.sh`: `snapper --no-dbus -c root create-config /`, replace snapper's `.snapshots` subvolume with the mounted `@snapshots`, set `TIMELINE_CREATE=no` (we snapshot on change, not on a timer, to keep the ESP within `LIMIT_USAGE_PERCENT`), `NUMBER_LIMIT=10`, enable `snapper-cleanup.timer`, `limine-snapper-sync.service`, create snapshot 1 "Fresh install".
- `jobs/invictus-cleanup.sh`: remove `invictus-iso-live`, the `liber` user and live autologin, the live `pacman.conf` mirror overrides; write `/etc/invictus/release` (version, channel).
- `users.conf`: default groups include `wheel input kvm` (kvm for rootless podman with `/dev/kvm`, verified requirement), `sudo` for wheel with password.
- Branding: `installer/branding/invictus/` (Venus). No Arch logo.

Why limine rather than grub-btrfs, since Calamares knows grub and not limine: grub-btrfs boots a snapshot but restoring is a manual subvolume swap unless we write it; grub's btrfs code gets slow with many snapshots; limine-snapper-sync gives the boot menu, the restore command (kernel-matched), and ESP space management, and it is maintained (1.32.0, 2026-09-20). Cost: three AUR packages (in our repo anyway) and one shell job. If the job proves flaky on Alex's hardware in Phase 3, switch `bootloader` back on with `efiBootLoader: grub` and add `grub-btrfs` (4.14 in `extra`); the subvolume layout and snapper config stay.

### 2.3 First boot

`invictus-first-boot` (a Quickshell wizard, run once per user by `invictus-first-login`):
1. Monitors: detect with `hyprctl monitors -j`, let the user drag a layout, write `~/.config/hypr/monitors.lua`.
2. Look: wallpaper, light/dark, keyboard layout (already set), the "Roman" theme on by default.
3. Assistant: the screen, its flow (password, then sign-in) and its states are in `no-ai.md` 2, the single source, in both wizards. The wizard never sees or stores a token; for Claude it only checks that `~/.claude/.credentials.json` exists afterwards. Claude Code is not preinstalled: it arrives with `invictus-moneta` after the person's password (`design-no-ai.md` N1). No AI skips steps 4 and 6. Otherwise: the wizard sets `DISABLE_AUTOUPDATER=1` in the session environment so the package is the only update path (Vulcan verifies the variable name on the setup page's "Disable auto-updates" section).
4. Collegium: connect existing, create new, or local-only (section 4.3). Skippable.
5. Windows (optional): local VM now, later, or never; remote work profile fields (section 3).
6. Voice (optional): pair the button (section 4.4), download the whisper model (`small.en` default, `large-v3-turbo` optional).
7. Baseline snapshot "First boot done" and a two-minute tour of Super+A, the Desk, and where the undo lives.

No step stores a secret anywhere but the user's keyring (`secret-tool`, `gnome-keyring` unlocked by SDDM PAM) or the tool's own home file (Claude Code's credentials file). The ISO and the repo contain no credential, key, token or password (test T8).

Existing installs (Alex's current machine): `scripts/dev/adopt.sh` adds `[invictus-testing]`, installs the meta packages, runs the first-login copy, and, only if `/` is already btrfs with a snapper-compatible layout, sets up snapper + snap-pac (bootable snapshots need the limine move, which is Phase 3). Owner decision D1: is the current install btrfs?

---

## 3. Windows module

Goal: Windows for work with no GPU passthrough, as a full desktop across all monitors and as seamless apps, plus a remote work machine, all through FreeRDP 3, snappy, with two-way audio.

### 3.1 Local VM

- Backend: rootless podman + `dockur/windows`. Verified: podman is a supported backend, KVM via `/dev/kvm` is required, the user must be in `kvm`, runtime `crun`, `group_add: keep-groups`. Windows 11 Pro installs unattended; user and password come from `USERNAME`/`PASSWORD` in the compose file; RDP is on 3389 and carries audio ("audio is disabled by default unless you are using RDP", verified).
- Our `compose.yaml` (generated by `invictus-win init`, in `~/.config/invictus/windows/`, mode 0600, never in the repo): ports `127.0.0.1:3389:3389/tcp` and `/udp`, `127.0.0.1:8006:8006` (web viewer, install only), storage `/var/lib/invictus/vm/<name>` (the `@vm` subvolume, nodatacow), `RAM_SIZE`/`CPU_CORES` from a slider (default half of the machine), shared folder `~/Invictus/Share` mounted read-write in the VM, `VERSION: "11"`. License key is the user's own (owner decision D7; dockur installs unactivated).
- Why not libvirt first: WinApps recommends docker/podman because the install is automated; libvirt needs a hand-built VM. libvirt remains the escape hatch if latency or audio disappoint (CPU pinning, hugepages, VirtIO-FS are easier there). `invictus-win` keeps the backend behind one interface so the switch does not change the client side.
- Lifecycle: `invictus-win start|stop|pause|status`, a Desk card, and `podman-compose` under the hood. The VM does not autostart; the Desk offers "Start work" which starts the VM and opens the desktop.

### 3.2 Client: FreeRDP 3

All from the `freerdp` 3.32.1 package (verified: ships `sdl-freerdp3`, `xfreerdp3`, `wlfreerdp3`).

Full desktop (`invictus-win desktop`):
```
sdl-freerdp3 /v:127.0.0.1 /u:<user> /multimon /f +dynamic-resolution \
  /sound:latency:20 /microphone /gfx:AVC444 /network:lan /cert:tofu \
  +clipboard /drive:share,$HOME/Invictus/Share /kbd:unicode /floatbar:sticky:off
```
Password via `FREERDP_ASKPASS` (verified env var) pointing at `secret-tool lookup invictus rdp-local`, so it is never on the command line. Hyprland rules in `invictus/windows.lua`: the client goes to workspace "work", fullscreen, on every monitor; Super+Escape releases the keyboard grab (FreeRDP's own Ctrl+Alt+Enter toggles fullscreen, verified default). `FREERDP_WLROOTS_HACK` (verified env var) controls FreeRDP's multi-monitor detection for wlroots-like compositors; Hyprland is not wlroots, so Vulcan tests `unset`, `1` and `force`. WinApps warns `/multimon` can black-screen on a FreeRDP bug; if it does, fall back to one window per monitor (`/monitors:` list, marked experimental in the man page) and report upstream.

Seamless apps (`invictus-win app <name>`): WinApps (`winapps` from AUR, in our repo) with `WAFLAVOR="podman"`, `RDP_IP=127.0.0.1`, `RDP_ASKPASS` (verified option; the plain `RDP_PASS` is left empty), `RDP_FLAGS="/cert:tofu /sound /microphone /gfx:AVC444 +dynamic-resolution"`, `FREERDP_COMMAND` set to `xfreerdp3` first, because that is what WinApps documents and RemoteApp (RAIL) windows are separate top-level windows the client must implement; whether `sdl-freerdp3` implements RAIL is unverified. Phase 4b test: run WinApps with `FREERDP_COMMAND=sdl-freerdp3`; if apps appear as separate windows, switch and drop XWayland from this path. Either way the user sees one launcher entry per Windows app in rofi.

Audio: RDP audio in (`/microphone`) and out (`/sound`) over PipeWire (FreeRDP's pulse backend talks to `pipewire-pulse`). `/sound:latency:` is a verified option; tune on hardware with a Teams test call. If two-way audio over RDP is not good enough, plan B is a virtual PipeWire pair over the VM's network (Scream or PipeWire RTP), an owner call later.

### 3.3 Remote work machine

`invictus-win remote <profile>`: same client, a profile file `~/.config/invictus/windows/profiles/<name>.toml` with host, port, user, domain, optional RD Gateway (`/g:` in FreeRDP 3, Vulcan verifies), monitors mode (all or one), and per-profile redirection switches: drive redirection off by default, clipboard on, printer off, USB off. Certificate: TOFU on first connect, then the fingerprint is pinned in the profile. Credentials in the keyring only. VPN is outside this module (the employer's client, or NetworkManager). Employer policies on third-party RDP clients are the user's responsibility; the module changes nothing on the work machine.

### 3.4 Data separation

The work profile's credentials and any employer data (drive redirection to the local VM's share, clipboard from the remote machine) are out of the assistant's reach by rule (MUST A9). The local VM disk is on its own subvolume, excluded from root snapshots, and never read by `invictus-doctor` or `invictus-report`.

---

## 4. The assistant, the harness and the voice (sensitive)

The default assistant persona is **Moneta** (Alex, 2026-09-30): the same voice as the team's PO, who reminds, keeps the threads and hands build work to the team. `tribune` is the panel's code and package name only; people see Moneta and "the Moneta panel". Other providers keep the persona from the Collegium's default PO role unless the user changes it.

Names (settled by Moneta, 2026-09-30): Moneta and the Moneta panel (Super+A; code name `tribune`), the Desk (home dashboard; code name `forum`), Acta (the assistant's action log), Collegium (the team harness and memory repo), `invictus-sys` (the only door to root).

### 4.1 Components

```
 [pen button] --evdev grab--> invictus-ptt --wav--> whisper-server (127.0.0.1, Vulkan)
                                   |                         |
                                   +------- text ------------+---> wtype ---> Moneta panel
                                                                                 |
 Super+A ---> Moneta panel (dropdown terminal or Quickshell chat) ---> provider adapter ---> agent
                                                                             |                (claude-code CLI |
                                                                             |                 other CLI | API)
                                                          runs as user, no sudo|
                                                                             v
                                                        invictus-sys <verb> (pkexec, polkit, root-owned script)
                                                                             |
                                                        pacman / snapper / systemctl / /etc/invictus edits
                                                                             |
                                                        journal tag invictus-sys  --->  Desk "Acta" card
 Desk (Quickshell) <--- invictus-doctor (read-only collectors), snapper list, checkupdates, Collegium status
 invictus-report ---> preview ---> user sends (GitHub issue form / mail draft)
 Collegium repo (~/Collegium) ---> adapters ---> CLAUDE.md/.claude/* , AGENTS.md , ...
```

Principle: the OS boundary is the security model. The agent runs as the logged-in user with no sudo. Anything root goes through `invictus-sys`, a root-owned script with fixed verbs, invoked by `pkexec` under polkit actions that require the user's password (`auth_admin_keep`), each verb with its own action id so the prompt says exactly what will happen. This holds for every provider; Claude Code's own deny rules and hooks are a second layer for the default provider, not the primary one.

`invictus-sys` verbs (v1, complete list): `update`, `install <pkgs>` (repos in `pacman.conf` only), `remove <pkgs>` (never `invictus-base`/`-desktop`), `snapshot <description>`, `rollback <id>` (then reboot), `service enable|disable|restart <unit from allowlist>`, `set-config <file under /etc/invictus/> <content>` (with pre/post snapshot), `vm start|stop` (delegates to the user's podman, no root needed, listed for one entry point), `report-collect` (runs the allowlisted collectors that need root, such as `journalctl -b -p err`). Anything else is a new verb with a design note, a polkit action and a test.

### 4.2 AI-agnostic provider layer

A provider is a directory under `/usr/share/invictus/providers/<name>/` or `~/.config/invictus/providers/<name>/` with `provider.toml`:

```toml
name = "claude-code"
kind = "cli"                       # cli | api
chat = ["claude"]                  # interactive, runs inside the Moneta panel's terminal
run  = ["claude", "-p", "{prompt}", "--output-format", "text"]   # one-shot; optional
resume = ["claude", "--continue"]  # optional
login = ["claude"]                 # what first boot runs; optional
harness = "claude-code"            # which Collegium adapter to apply; "agents-md" is the generic one
capabilities = ["tools", "sessions"]
```

Shipped providers: `claude-code` (default), `generic-cli` (any command that takes a prompt on argv or stdin; the user fills the command), `openai-compatible` (an API endpoint, key from the keyring, model name; covers ollama, llama.cpp server, a hosted provider), `none`. The Moneta panel for `cli` providers is a dropdown kitty on a special workspace running `chat`; for `api` providers it is a Quickshell chat view that streams from the endpoint. API providers get chat only in v1: they can propose an `invictus-sys` command, which the Moneta panel shows as a button the user presses (so the same polkit prompt applies); they do not get a tool loop from us.

What is the same across providers: Super+A, the voice input (text typed into whichever Moneta panel is open), the Desk's summaries (uses `run` if the provider has it, otherwise shows raw data), `invictus-report` and `invictus-doctor` (plain CLI tools any agent can call; a short `TOOLS.md` in the Collegium tells an agent how), the Collegium (through an adapter), and the security boundary (section 4.1). What differs: the Claude Code plugin gives the default provider skills, hooks and an MCP server for structured calls; other providers get the markdown equivalents only.

Local models: AMD only means Vulkan is the common path (llama.cpp with `GGML_VULKAN`), ROCm optional. Packaging a local model server is Phase 7, after the interface exists; the `openai-compatible` provider makes it plug in without changes.

### 4.3 Collegium: the team harness and memory repo

Shape (agent-neutral, plain markdown plus one manifest), modelled on `/home/user/claude-team`:

```
collegium/
  collegium.toml       name, version, extends (optional upstream url), paths, trust rules, role list with model hints
  RULES.md             the charter: decision rights, standing rules, voice, modes
  roles/<role>.md      one file per role (what it owns, how it works, "Concerns" section rule)
  skills/<name>/SKILL.md
  workflows/*.md       sensitive-work, merge-and-backup, progress-report, writing-briefs
  team/{lessons,decisions,hiring,modes}.md
  projects/_template/{team.md,status.md,veto-log.md,concerns.md,memory/<role>.md}
  projects/<app>/...   per project, including memory files
  TOOLS.md             how an agent uses invictus-doctor, invictus-report, invictus-sys (proposes, user confirms)
```

Adapters (`invictus-collegium sync`) generate agent-facing files and mark them generated:
- `claude-code`: `CLAUDE.md` (RULES.md plus pointers), `.claude/agents/<role>.md` (frontmatter `name`, `description`, `model` from the manifest's hints, body from `roles/`), `.claude/skills/<name>` (symlinks to `skills/`). No `.claude/settings.json` hooks or MCP entries are generated from a connected repo unless the user enables each one (MUST C4).
- `agents-md`: a single `AGENTS.md` (rules plus the role list and skill index), which several other agent CLIs read.
- Others can be added as a directory under `collegium/adapters/` with a `render` script; the manifest is the only input.

Connect flows (first boot step 4, or the Desk's Collegium card, at most a few clicks):
- (a) Connect existing: paste a git URL. HTTPS with a GitHub sign-in through `gh auth login` (device flow, user does it in the browser), or SSH where the wizard generates a key and shows the public key to add as a read-only deploy key. Clone to `~/Collegium/upstream`. The wizard then shows the trust screen (below). Own writable layer is created at `~/Collegium/mine` (local, or its own remote via (b)).
- (b) Create new: `git init ~/Collegium/mine` from the clean template; optionally `gh repo create --private` and push.
- (c) Local-only: (b) without a remote; the Desk reminds monthly that it is not backed up and offers (b).

Layering: `mine` overlays `upstream`. Rules, roles, skills and workflows come from upstream unless a file of the same path exists in `mine`; `projects/` and every `memory/` file live only in `mine`. An agent's memory is therefore always writable by its owner and never written into someone else's repo. `extends` in `mine/collegium.toml` records the upstream URL and the approved commit.

Clean template: authored fresh in `collegium/template/` in the invictus repo, generic wording, the Roman roster names kept as defaults (they are flavour, not personal data), no projects, nothing from Alex's Desk, no people, no emails, no URLs to Alex's things. It is generated into the package, not copied from Alex's live repo. CI test `no-personal-data` greps the built template against a marker list kept in the private CI config (Alex's names, email, project names, Alex's Desk hosts); the marker list itself is not packaged (test C1). There is no export of Alex's live repo (D14, 10.1): a friend's Collegium is made from this template by `invictus-collegium new`.

### 4.4 Voice pipeline

- Button: a pen-style Bluetooth HID button (owner decision D8: which device; it must present as a HID keyboard or consumer-control device, not an app-only BLE beacon). Pairing through `bluetoothctl` in the wizard. A udev rule tags the device (`ENV{INVICTUS_PTT}="1"`, `TAG+="uaccess"`) so the seat user can open it.
- `invictus-ptt` (user service, python-evdev from `extra`): opens the tagged event device, grabs it exclusively (`EVIOCGRAB`), so its key never reaches Hyprland or any app; key down starts `pw-record` (16 kHz mono) to a tmpfs file with an on-screen "Listening" overlay; key up stops recording, posts the wav to `whisper-server` on 127.0.0.1 (user service, model loaded once, so no per-press model load), shows the transcript in the overlay for two seconds, and types it into the Moneta panel with `wtype` (virtual keyboard protocol, in `extra`). Send happens on a second short press or on Enter; a long hold cancels. A prefix word routes locally instead: "note ..." appends to `~/Invictus/notes/<date>.md` without going to any agent; "timer 25" starts a Desk timer.
- Model: `small.en` default (about 466 MiB per the whisper.cpp README), `large-v3-turbo` optional; downloaded at first boot to `~/.local/share/invictus/whisper/`, never packaged. Vulkan build (`cmake -DGGML_VULKAN=1`, verified) as `whisper.cpp` in our repo.
- Latency target: under 1.5 s from key up to text for a ten-second clip on Alex's GPU. Unverified until measured (Diana's flag stands); the model size is the knob.
- Nothing about audio leaves the machine: the server binds 127.0.0.1, the wav is deleted after transcription, the overlay shows exactly what was heard.

### 4.5 Report-back channel

`invictus-report [--about <unit|app>]`:
1. Collect by allowlist only: `/etc/invictus/release`, package versions of the invictus set, `hyprctl version`, monitor list, GPU model, kernel, the last 200 lines of the Hyprland log, `journalctl -b -p err` (through `invictus-sys report-collect`), the failing unit's last 100 lines if named, `snapper list`, the Moneta panel's last action ids from Acta. Never home file contents, never `~/.claude`, `~/.ssh`, keyrings, WinApps or Windows profiles, never full environment dumps.
2. Scrub: a pattern scanner for tokens (`sk-ant-`, `ghp_`, `AKIA`, PEM headers, `password=`, `RDP_PASS=`), IPs outside RFC1918 optional, e-mail addresses. A hit blocks sending and names the line.
3. Preview: the full text in a window, editable, with a description field. Nothing is sent until the user presses Send.
4. Send: opens the invictus repo's new-issue page with title and body prefilled (for family with repo access, the URL length limit means long logs are attached by the user), or a mail draft (`xdg-email`) to the address in `/etc/invictus/report.conf` (owner decision D9). The bundle is also saved under `~/Invictus/reports/`. Revised (design-inbox.md 3.5, 2026-09-30): the mail draft goes to `helper_contact` in `/etc/invictus/helper.conf` (shipped `solinvictus.support@gmail.com`); `report.conf` holds no address.
5. Where it lands: GitHub issues on the invictus repo, labelled `from-machine`. Moneta triages; nothing on the sending side is automated in v1. Automation (an inbox service with per-device enrolment tokens issued by Alex, or a bot mailbox Iris reads) is owner decision D9, and if chosen gets its own design addendum and pen test. **DS3 approved (2026-09-30): the automated inbox is designed in `design-inbox.md` (GitHub issues, one private repo per device under a machine account, per-device fine-grained tokens, offline queue, authenticated replies); it changes A2, A7, A12 and S1 as its section 10 lists.**

### 4.6 ADHD support (Desk and Moneta panel behaviour)

- The Desk opens on "Now": the last Moneta thread's one-line summary and cwd, the timer, today's notes. Then "Threads": Claude Code sessions (`claude --resume` list; other providers: what they expose) with one-line summaries generated on close.
- The Moneta panel shows "You were: ..." on open, and asks nothing it can look up itself.
- Updates are a daily card, never a popup; do-not-disturb is automatic while a fullscreen game runs (swaync dnd toggled from a Hyprland Lua event on fullscreen).
- Acta: every `invictus-sys` action with time, verb, snapshot id, and the thread that asked for it, so "what did I change yesterday" has an answer.
- One confirmation per irreversible action, worded as "This will X. Undo: boot snapshot N". No "yes to all".

### 4.7 Threat model

Assets: the user's files and credentials (`~/.claude`, `~/.ssh`, browser profiles, keyring, Windows VM and work profile credentials); bootability and the snapshot chain; the family's privacy (voice, screen, notes); employer data reachable through the work profile; Alex's team channel (issues inbox); the package repo's integrity; the Collegium (rules that shape what agents do).

Actors and failure scenarios:
- T1 Prompt injection: content the agent reads (web pages, package descriptions, logs, issue text, a connected Collegium) instructs it to run a destructive command or exfiltrate a file.
- T2 Over-autonomy: the model does more than asked (`pacman -Rns`, editing fstab, deleting `.snapshots`).
- T3 Confirmation fatigue: an ADHD user says yes to a stacked or vague prompt.
- T4 Supply chain: a bad AUR PKGBUILD or a compromised package in our repo, or an agent building AUR packages on its own.
- T5 Voice: someone else, or a TV, triggers a command; audio leaves the machine.
- T6 Report bundle leaks a secret or private data.
- T7 The agent turns its own guardrails off (edits settings, enables bypass or auto mode, adds a NOPASSWD rule).
- T8 Secrets in the ISO or repo (baked credentials, a shared upload token).
- T9 Untrusted Collegium: a connected repo's rules, skills or hooks make the agent do something the user did not approve; or a friend's connection writes into Alex's repo or reads his projects.
- T10 Personal data in the template: the shipped harness leaks Alex's details to every install.
- T11 Provider substitution: a non-default provider (an API endpoint or a random CLI) lacks Claude Code's permission layer.

### 4.8 MUSTs and the tests that prove them

Assistant and system access (A):

| # | MUST | Test (Janus runs in a VM unless marked hardware) |
|---|---|---|
| A1 | Every agent runs as the logged-in user. No agent process has sudo, and `sudoers` contains no NOPASSWD entry for any invictus tool. | `sudo -l` as the user shows password-only wheel; `Bash(sudo ...)` from the Moneta panel is denied by rule and, if reached, fails for lack of a password prompt in a non-tty. |
| A2 | Every root action goes through `invictus-sys`, root-owned, mode 0755, with a fixed verb list; each verb has its own polkit action requiring `auth_admin_keep`, and the prompt text names the exact packages, unit, file or snapshot. | Read `/usr/lib/invictus/invictus-sys` and `/usr/share/polkit-1/actions/org.invictus.sys.policy`; call each verb; a polkit dialog appears with the argument in the message; `invictus-sys "pacman -Syu; rm -rf /"` is rejected as an unknown verb. |
| A3 | Package installs come only from repos in `pacman.conf` (official and invictus). No agent path builds AUR packages or runs `makepkg`. A missing package becomes a "package request" report. | Ask Moneta to install an AUR-only package: it declines and offers `invictus-report --package-request`. `grep -r makepkg` over the plugin and tools finds nothing executable. |
| A4 | No partial upgrades: every install is `pacman -Syu --needed <pkgs>`; `-Sy` without `u` never appears in our tools. | `grep -rn "pacman -Sy" pkgs/own assistant/` shows only `-Syu`; run `invictus-sys install foo` with pending updates and watch the transaction include them. |
| A5 | A root snapshot exists before any system change: snap-pac for pacman, `invictus-sys` for `set-config` and `service`, and the snapshot id is returned to the caller and logged to Acta. | Run each verb; `snapper list` shows a pre/post pair with the verb in the description; Acta shows the id. |
| A6 | Config edits by an agent in the home are limited to an allowlist (`~/.config/hypr/user.lua`, `~/.config/hypr/monitors.lua`, `~/.config/invictus/**`, `~/.config/waybar/**`). Each edit is preceded by a timestamped backup under `~/.local/state/invictus/backups/` and followed by `invictus-doctor --hypr`; a failed check restores the backup before reload. | Ask for a change that yields invalid Lua; the file is restored and the failure explained. Ask Moneta to edit `~/.bashrc`: denied by rule (Claude Code) or refused by `TOOLS.md` rule and no tool exists for it (other providers). |
| A7 | Default provider permissions are enforced by a root-owned managed settings file (Linux managed settings path per the Claude Code settings page; Vulcan records the exact path): `defaultMode: default` (prompt), `disableBypassPermissionsMode: "disable"`, `permissions.disableAutoMode: "disable"`, deny rules for `Bash(sudo *)`, `Bash(rm -rf *)`, `Bash(dd *)`, `Bash(mkfs*)`, `Bash(btrfs subvolume delete *)`, `Bash(makepkg *)`, `Bash(pacman *)` (all pacman goes through invictus-sys), `Read(~/.claude/.credentials.json)`, `Read(~/.ssh/**)`, `Read(~/.local/share/keyrings/**)`, `Read(~/.config/invictus/windows/**)`, `Read(~/.config/winapps/**)`, `Edit(//etc/**)`, `Edit(//boot/**)`, `Edit(//usr/**)`. Deny rules apply even in bypass mode (verified). | Attempt each denied action from the Moneta panel; each is blocked. `ls -l` shows the managed file root-owned 0644. Ask Moneta to enable bypass mode: the setting is refused. |
| A8 | The agent cannot change its own rules: the managed settings file, the plugin directory `/usr/share/invictus/claude-plugin/` and `/usr/share/invictus/providers/` are root-owned and outside every Edit allowlist; user-scope settings cannot override managed restrictions (verified precedence). | Ask Moneta to "allow yourself sudo": edit denied. Put an allow rule in `~/.claude/settings.json` for `Bash(sudo *)`: the managed deny still wins. |
| A9 | Work data isolation: the agent has no read path to Windows VM or work profile credentials or disks; `invictus-doctor` and `invictus-report` never read `/var/lib/invictus/vm/**`, `~/.config/invictus/windows/**`, `~/.config/winapps/**`. The remote work profile has drive redirection off by default. | Ask Moneta for the work RDP password: refused, read denied. `strace -f invictus-report` shows no open() under those paths. Profile default shows `/drive` absent. |
| A10 | One confirmation per irreversible action, with the action and the undo (snapshot id or backup path) in the prompt. No "approve all" for system verbs. | Scripted session with three changes yields three distinct polkit prompts; `auth_admin_keep` caching is limited to 5 minutes (polkit default) and never spans different verbs' action ids. |
| A11 | Acta logs every `invictus-sys` call (journal tag `invictus-sys`, fields: verb, args, snapshot id, requesting session id, result). The Desk shows it. | `journalctl -t invictus-sys -o json` after each verb; the Desk card matches. |
| A12 | Network: the only tool that sends system data off the machine is `invictus-report`, and it sends nothing without the user's Send. | Run the report flow to the preview and cancel; `ss`/`nethogs` show no outbound from invictus tools; grep the tools for `curl -d`, `--data`, `-X POST`, `requests.post`: none except the optional automated inbox path when D9 enables it. |
| A13 | Non-default providers get the same boundary: they run as the user, have no sudo, and reach root only through `invictus-sys` prompts; API providers cannot execute anything, they only propose. | Configure `generic-cli` as `bash -c "$PROMPT"` (the worst case); ask it to update the system; the only way through is a polkit prompt. Configure `openai-compatible` against a local mock; a proposed command renders as a button, never runs on its own. |

Voice (V):

| # | MUST | Test |
|---|---|---|
| V1 | Recording happens only while the tagged button is held (or a visible on-screen toggle is on); no wake word, no always-on capture. | Hardware (Alex): press, release; `pw-record` process exists only between the two; the overlay is visible throughout. |
| V2 | Audio never leaves the machine: `whisper-server` binds 127.0.0.1 only; the wav lives on tmpfs and is deleted after transcription. | `ss -ltnp` shows the server on 127.0.0.1; after a transcription `ls /run/user/$UID/invictus-ptt/` is empty; a packet capture during transcription shows no outbound. |
| V3 | The button's key events reach no other application (exclusive grab). | With the grab active, `wev` and a text field see nothing on press. |
| V4 | The transcript is shown before it is sent; a local prefix ("note", "timer") never goes to any agent. | Say "note buy milk": the notes file gains a line, the Moneta panel receives nothing. |

Report-back (R):

| # | MUST | Test |
|---|---|---|
| R1 | Collection is by allowlist; the collector list is in one file (`assistant/report/collectors.toml`) and nothing else is read. | `strace -f -e openat invictus-report --dry-run` shows only allowlisted paths. |
| R2 | A secrets scanner runs over the bundle and blocks Send on a hit, naming the line. | Plant `sk-ant-test` in a log the doctor reads: Send is disabled with the line shown. |
| R3 | The user sees the full text and edits it before anything is sent; nothing sends automatically. | Cancel from preview; nothing left the machine (A12 tooling). |
| R4 | The bundle contains no home file contents, no credentials, no VM or work data, no full environment. | Review the collector list; grep a real bundle for `$HOME` paths outside `~/Invictus/reports`. |

Secrets (S):

| # | MUST | Test |
|---|---|---|
| S1 | The ISO, the packages and the repo contain no credential, token, key or password. Sign-in happens on the installed machine in the user's home. | CI: `gitleaks` on the repo, a pattern scan over the built squashfs and packages before publish; a fresh VM install has no `~/.claude/.credentials.json` until the user logs in. |
| S2 | Credentials at rest: Claude Code's file 0600 (its own behaviour, verified); RDP and API keys in the keyring; compose file 0600. | `stat` each after first boot. |

Collegium (C):

| # | MUST | Test |
|---|---|---|
| C1 | The shipped template contains none of Alex's personal data, projects or Alex's Desk details. It is generated from `collegium/template/`, never copied from a live team repo, and CI fails the build on any marker hit; the marker list is not packaged. | CI `no-personal-data` job; `pacman -Ql invictus-collegium` shows no marker file; Janus greps the installed template for the marker list. |
| C2 | A connected upstream is read-only for the connecting user by construction (read-only deploy key or read collaborator), and the tool never pushes to `upstream`; memory and projects are written only under `mine`. | Connect with a read-only key; attempt a memory write through the agent; it lands in `mine`; `git -C ~/Collegium/upstream log origin/HEAD..HEAD` is empty and `git push` is disabled by a pre-push hook plus `pushurl = DISABLED`. |
| C3 | Instructions from a connected repo are untrusted until approved: on connect and on every pull that changes `RULES.md`, `roles/`, `skills/`, `workflows/`, `collegium.toml` or any file an adapter turns into agent instructions, the wizard shows the diff and the user approves before adapters regenerate. Unapproved content is not projected into any agent's config. | Change a role file upstream to include "run rm -rf ~"; pull; the generated `CLAUDE.md`/`.claude/agents` stay at the approved commit until the diff is accepted; the diff view shows the line. |
| C4 | Executable content from a connected repo (hooks, MCP server definitions, scripts referenced by skills) is never enabled automatically; each item is listed by name and path and enabled one by one by the user. Adapters generate no `settings.json` hooks or MCP entries by default. | Upstream adds a `.claude/settings.json` with a PreToolUse hook; after sync the generated settings contain no hook; the wizard lists it as "not enabled". |
| C5 | Secrets never enter a Collegium: a pre-commit scanner (same patterns as R2) blocks commits in `mine`, and connect refuses an upstream whose scan hits unless the user overrides with the finding shown. | Commit a fake token in `mine`: blocked. Connect a repo with a planted token: refused with the line shown. |
| C6 | Dropped with D14 (10.1): there is no export command. | None. |
| C7 | An agent's memory file is only ever written by that agent's role and read by all, as the charter says; the adapter encodes this as a rule in the generated instructions and the Claude Code adapter adds `Edit` allow rules only for `mine/projects/**/memory/<role>.md` of the active role. | Ask a role agent to edit another role's memory: denied. |

### 4.9 Owner decisions this section needs

D8 (voice button), D9 (report inbox), D13 (default provider and whether family may use their own Claude accounts with the Claude Code CLI, which is the user's own login into Anthropic's product; note that the Agent SDK docs state third parties may not offer claude.ai login for products built on the SDK, which is why the Moneta panel wraps the CLI rather than embedding the SDK), D14 (answered in 10.1: no export; friends get `invictus-collegium new` from the template), D15 (whether to ship a local-model provider preinstalled in v1 or as an opt-in package). Full list in section 10.

---

## 5. Phased plan

Each phase is shippable and lands on Alex's current machine first (through `[invictus-testing]`), except Phase 3 which needs a VM and then a spare disk. Roles named per phase. "Alex only" lists what cannot be tested without his hardware.

| Phase | What ships | Who | Alex only | Gate |
|---|---|---|---|---|
| 0. Foundation (1 to 2 days) | Repo renamed and restructured; `docs/reuse-catalog.md`; `invictus-keyring`; `[invictus-testing]` online with keyring and one AUR package; CI: shellcheck, luacheck, gitleaks, package build and sign | Vulcan; Vesta for the hosting and signing key handling (D3, D4) | Add the repo on his current install and install a package | Moneta review |
| 1. Desktop on the current install | Lua config port (`invictus/*.lua`, `user.lua`, `monitors.lua`); `invictus-desktop`, `invictus-gaming`, `invictus-dev` metas; pinned hypr* set; `invictus-update`; `invictus-doctor` (read-only checks); `scripts/dev/adopt.sh`; snapper + snap-pac on the current box if btrfs (D1) | Vulcan (config and metas), Felix (doctor collectors, waybar script moves), Clio (README rewrite), Vera (checklist for Alex) | Multi-monitor layout, binds, screenshots, screen share, Steam and gamescope on his GPU | Alex uses it a week; QA checklist passes |
| 2a. Moneta panel and invictus-sys (sensitive) | `invictus-sys` with polkit policy; Claude Code package, plugin (skills, `TOOLS.md`, MCP for structured calls) and managed settings; provider layer with `claude-code`, `generic-cli`, `openai-compatible` (chat only), `none`; Super+A dropdown; Acta logging | Vulcan builds; Janus pen-tests A1 to A13, S1, S2; Minerva final review | The polkit dialog through hyprpolkitagent on his session | Pen test clean, Minerva ship |
| 2b. Collegium (sensitive) | Template authored fresh; `invictus-collegium` CLI (new, connect, local, sync); adapters `claude-code` and `agents-md`; trust screen; pre-commit scanner; `no-personal-data` CI | Clio writes the template from the charter (generic wording); Vulcan builds the CLI and adapters; Janus tests C1 to C7 (C6 dropped); Minerva final | From a second user account on his machine, create a Collegium with `invictus-collegium new` | Pen test clean, Minerva ship |
| 2c. Desk and report | Quickshell Desk (Now, Threads, Updates, Snapshots, Health, Notes, Acta, Collegium card, Windows card); `invictus-report` with preview and scrubber; do-not-disturb on fullscreen | Venus (Desk design in the Roman theme), Felix (cards from the doctor collectors), Vulcan (report tool), Janus (R1 to R4) | Look and feel on his monitors | Vera QA, Janus on R |
| 3. ISO and installer | archiso profile; Calamares config, branding, the three jobs; limine + snapper first boot; `invictus-first-boot` wizard steps 1, 2, 3, 4, 7; rescue menu; CI ISO build with the squashfs secrets scan | Vulcan; Venus for branding; Aurora for the release pipeline and versioning | Boot the ISO on his machine, install to a spare disk, boot a snapshot from the limine menu, run `limine-snapper-restore` | Install in a QEMU/OVMF VM by Vera, then Alex on hardware |
| 4a. Windows: local VM, full desktop | `invictus-win init/start/desktop`; compose generation; keyring credentials; Hyprland "work" workspace rules; wizard step 5 | Vulcan | Latency, `/multimon` across his monitors, two-way audio in a real call, `FREERDP_WLROOTS_HACK` variants | Alex's call on "snappy" |
| 4b. Windows: seamless apps | WinApps with podman; `xfreerdp3` first, `sdl-freerdp3` if RAIL works; rofi entries | Vulcan, Felix (app entries) | Whether apps appear as normal windows on his setup | Same |
| 4c. Windows: remote work profile | Profiles, TOFU pinning, redirection defaults, gateway option | Vulcan; Justitia not needed (no legal review), but the doc notes employer policy is the user's | Connect to his work machine | Alex |
| 5. Voice (sensitive) | `whisper.cpp` Vulkan package; `whisper-server` user unit; `invictus-ptt`; pairing and model download in wizard step 6; overlay | Vulcan; Janus tests V1 to V4 (V1 on hardware by Alex with Vera's checklist) | The button, the mic, latency numbers | Pen test clean |
| 6. Roman look and copy | Theme (SDDM, the Desk, wallpapers, icons), names, wizard and error copy | Venus, Clio; Felix applies | Taste | Moneta |
| 7. Extras and family | Local model provider package (D15); family onboarding guide via Iris; report inbox automation if D9 says so (own design addendum and pen test); stable channel promotion process | Vulcan, Iris, Minerva if D9 | The friend-and-family install on a second machine | Alex |

Ordering note: 2a before 2c because the Desk's Acta and update buttons call `invictus-sys`. 2b can run in parallel with 2a (different files). Phase 3 needs Phase 1's packages but nothing from 2. Phase 4 and 5 are independent of each other.

---

## 6. Reused / new, and why

Reused: archiso `releng` profile (the ISO skeleton); Calamares (installer UI and every standard module, only the bootloader step is ours); btrfs + snapper + snap-pac (in `extra`); limine + limine-mkinitcpio-hook + limine-snapper-sync (bootable snapshots and restore, instead of writing our own); pacman repos and hooks (updates and pinning, instead of a git-based updater); FreeRDP 3 clients and WinApps (RDP and seamless apps); `dockur/windows` (unattended Windows VM); podman (no daemon, rootless); Claude Code CLI with its plugin, permissions, hooks and managed settings (the assistant loop and its second-layer guardrails, instead of an SDK app, which also avoids the SDK's claude.ai-login restriction); polkit + hyprpolkitagent (the confirmation dialog, already in the old package list); whisper.cpp `whisper-server` and `whisper-stream` (STT); PipeWire tools (`pw-record`); `wtype` and `python-evdev` (typing and button grab, both in `extra`); Quickshell (one toolkit for welcome, wizard, the Desk, overlays); the old repo's waybar scripts, kitty/rofi/swaync/zsh configs, the copy-once idea and the `.mine` override idea; the charter in `/home/user/claude-team` as the Collegium's shape; `gh` for GitHub sign-in and repo creation; `secret-tool` for the keyring.

New (and why nothing existing fits): `invictus-sys` (a fixed-verb root door with per-verb polkit actions; generic sudo or `pkexec` on arbitrary commands is exactly what we must not give an agent); the provider layer (no existing standard for "any agent behind one panel"); the Collegium manifest, adapters and trust screen (agent-neutral harness with an approval step; nothing off the shelf does the untrusted-repo part); `invictus-ptt` (a device-grabbing push-to-talk with local routing; existing dictation tools use wake words or global hotkeys); `invictus-report` (allowlist collector plus scrubber plus preview); `invictus-doctor` (read-only checks feeding the Desk and updates); the three Calamares jobs; the Lua config.

---

## 7. Facts checked on 2026-09-30 and what stays unverified

Verified against primary sources (archlinux.org package JSON, AUR RPC, wiki.hypr.land, hypr.land news, man.archlinux.org, wiki.archlinux.org, gitlab.com/Zesko READMEs, raw GitHub READMEs for winapps, dockur/windows, whisper.cpp, calamares, code.claude.com docs):
- Arch: hyprland 0.56.2-3, freerdp 3.32.1 (sdl/wl/x clients), limine 12.9.1, snapper 0.13.2, snap-pac 3.0.1 (extra), grub-btrfs 4.14 (extra), quickshell 0.3.1, podman 6.1.2, libvirt 12.7.0, gamescope 3.16.31, mangohud 0.8.4, steam and umu-launcher (multilib), archiso 91 (extra), python-evdev 2.0.0, wtype 0.4, lua 5.5.1 / lua54 5.4.9, plymouth, sddm 0.21.0, greetd 0.10.3.
- AUR: calamares 3.4.2-2, limine-snapper-sync 1.32.0 (2026-09-20), limine-mkinitcpio-hook and limine-entry-tool 1.40.0, claude-code 2.1.285 (2026-09-29), proton-ge-custom-bin GE_Proton11_7, zen-browser-bin, xwaylandvideobridge, paru; whisper.cpp only as `whisper.cpp-git` (2025), so we carry our own PKGBUILD; no `winapps` package was returned by the RPC query (Vulcan checks the exact name or packages it from the winapps repo).
- Hyprland: Lua config is primary from 0.55; `hyprland.lua` at `~/.config/hypr/`; hyprlang supported 1 to 2 releases after 0.55; other hypr* tools stay hyprlang; `hl.bind("SUPER + SHIFT + Q", hl.dsp.exec_cmd("firefox"))` syntax; bind callbacks must not block.
- pacman: first listed repo wins regardless of version; `IgnorePkg` exists.
- Calamares: bootloader options are grub, sb-shim, refind, systemd-boot (no limine); `mount.conf` `btrfsSubvolumes` and `btrfsSwapSubvol`; `partition.conf` `efi.recommendedSize`/`minimumSize`, swap choices include `file`; the packages module has a pacman backend.
- limine-snapper-sync: 4 GiB FAT32 ESP recommended, `sd-btrfs-overlayfs` with systemd hooks, `limine-snapper-restore`, `LIMIT_USAGE_PERCENT`, snap-pac integration, requires Snapper layouts.
- FreeRDP 3 `sdl-freerdp3` options: `/multimon`, `/monitors`, `/span`, `+dynamic-resolution`, `/sound[...latency...]`, `/microphone`, `/app:...`, `/gfx:AVC444`, `/kbd:unicode`, `/cert:tofu`, `FREERDP_ASKPASS`, `FREERDP_WLROOTS_HACK`, Ctrl+Alt+Enter fullscreen toggle.
- WinApps: podman backend, FreeRDP 3 required, `RDP_ASKPASS`, `FREERDP_COMMAND`, `/multimon` black-screen warning, rootless podman needs `kvm` group and `crun`.
- dockur/windows: podman supported, `/dev/kvm`, ports 3389 and 8006, `USERNAME`/`PASSWORD`, `RAM_SIZE`/`CPU_CORES`, audio over RDP.
- whisper.cpp: `cmake -DGGML_VULKAN=1`, `whisper-server`, `whisper-stream`, model sizes.
- Claude Code: native installer command; Linux credentials in `~/.claude/.credentials.json` 0600; permission modes and `disableBypassPermissionsMode`; deny rules win even in bypass; managed settings cannot be overridden by user scope; plugins package skills, agents, hooks and MCP servers; Agent SDK docs: third parties may not offer claude.ai login for SDK-built products without approval.
- Arch trademark policy: as Diana recorded.

Unverified, to be checked in the phase that needs them: `sdl-freerdp3` RemoteApp (RAIL) support; `/g:` gateway syntax in FreeRDP 3; whisper latency on Alex's GPU; `Hyprland --verify-config`; the exact Linux managed settings path for Claude Code and the `DISABLE_AUTOUPDATER` variable name; whether GitHub Releases as a pacman `Server` behaves under load; `hyprconf2lua`; the pen button's HID behaviour (depends on D8); WinApps package name in AUR; `wlfreerdp3` deprecation status (irrelevant, we do not use it).

---

## 8. Risks

- R1 The limine Calamares job is custom and only fully testable on real UEFI hardware. Mitigation: OVMF VM first, grub fallback path kept.
- R2 `/multimon` under Hyprland (SDL client, wlroots hack heuristics) may need per-monitor windows. Mitigation: `/monitors:` fallback, upstream report.
- R3 RDP audio latency for calls may disappoint. Mitigation: `/sound:latency` tuning, plan B (PipeWire RTP) as an addendum.
- R4 Pinning hypr* shifts breakage to dependency soname bumps. Mitigation: canary week, doctor post-update check, snapshot menu.
- R5 The Claude Code permission surface changes often (doc versions cite v2.1.2xx behaviours). Mitigation: the OS boundary (`invictus-sys`) is the primary control; Janus re-tests A7/A8 on each Claude Code package bump.
- R6 Voice hardware variance. Mitigation: exclusive grab is device-agnostic; the wizard's pairing test shows the raw key.
- R7 Collegium trust screen fatigue if upstream changes often. Mitigation: batch approvals per pull with a readable diff; instruction files change rarely.

---

## 9. Naming and flavour (for Clio and Venus)

Settled (Moneta, 2026-09-30): Invictus (the distro), the Desk (dashboard; code name `forum`), Moneta and the Moneta panel (assistant; code name `tribune`), Atrium and Tessera (flavors, the two desktop styles; Custodia and Libertas are the guard-rails settings, Alex, 2026-09-30), Collegium (team harness). Still proposals: Acta (action log), Annales (the snapshot list on the Desk), Lares (the first-boot wizard, the household guardians), `liber` (the live user). Copy tone: plain and Stoic, short sentences, no exclamation marks, the odd Marcus Aurelius line on the lock screen if Alex likes it. Boot and installer artwork: laurel, marble, bronze, no eagles-and-fasces kitsch, and no Arch logo anywhere.

---

## 10. Owner decisions (Alex)

| # | Decision | Recommendation |
|---|---|---|
| D1 | Is the current install on btrfs with `@`/`@home` style subvolumes? (Determines whether Phase 1 gets snapshots or they wait for Phase 3.) | Tell us; `findmnt / -o FSTYPE,OPTIONS` answers it |
| D2 | Repo name and visibility: rename `hyprdots` to `invictus`, keep private | Yes |
| D3 | Package repo hosting: GitHub Releases on the private repo, or a host of Alex's | GitHub Releases to start |
| D4 | Where the package signing key lives: GitHub Actions secret (CI signs) or Alex's machine only (Alex builds) | CI secret, rotate if the repo's collaborator set changes |
| D5 | UEFI only, or keep BIOS boot for an old family machine | UEFI only |
| D6 | Disk encryption default: off (offered) or on | Off by default, offered in the installer |
| D7 | Windows licence: Alex's own key per VM; the VM is unactivated otherwise | Acknowledge |
| D8 | Which Bluetooth pen button (must be a HID button); or a keyboard key as a first step | Buy one that lists "camera shutter / presenter" HID; use a keyboard key until it arrives |
| D9 | Report inbox: manual (issue form or mail draft) in v1, or an automated inbox (needs its own design and pen test) | Manual in v1; revisit after five reports. Answered by DS3 (approved 2026-09-30): `design-inbox.md`. |
| D10 | Channel policy: Alex on testing, family on stable, promotion weekly | Yes |
| D11 | Wallpapers: replace the anime images (copyright) with own or CC0 art | Replace |
| D12 | SDDM theme: restore blackglass from git history (it has its own licence) or commission a Roman one from Venus | Venus, Phase 6; blackglass meanwhile if it is still in history |
| D13 | Default provider is Claude Code, used through each user's own claude.ai login in the CLI; family members bring their own account or pick another provider | Yes |
| D14 | What friends connect to: Alex's scrubbed export repo (recommended) or a hand-maintained shared repo; never the live team repo with `projects/` | Export repo (denied, see 10.1) |
| D15 | Ship a local-model provider (llama.cpp Vulkan) preinstalled in v1, or as an opt-in package | Opt-in package, Phase 7 |
| D16 | Secure Boot: not supported in v1 (limine enrolment can brick boot per the wiki's warning) | Agree, revisit later |

### 10.1 Alex's answers (2026-09-30, on Alex's Desk)

| # | Answer |
|---|---|
| D2 | Renamed to `invictus` (GitHub shows `Invictus`). |
| D3 | Package repo public. Before the repo goes public, Phase 0 scans the full history for secrets. |
| D4, D5, D7 to D12, D15, D16 | Team defaults approved as one bundle. D11: the old wallpapers are deleted from the repo. |
| D6 | Encryption offered, off by default. |
| D13 | Approved: each person uses their own account, never a shared one. Claude is the default, but the choice of provider **must include home AI systems** (a local model on the user's GPU, or a server on their LAN) as a first-class option in the first-boot wizard, not a hidden add-on. The local provider package stays optional to install, but it is offered at first boot. |
| D14 | **Denied, replaced.** No export of Alex's repo, ever. A friend gets a Collegium built from the default template by a script: `invictus-collegium new` creates a repo on their own GitHub (or locally) from the shipped template, so none of Alex's data is ever copied. The `export` command and its scrubber are dropped from 2b. Connecting to someone else's repo (C-rules, trust screen) stays for people who choose to. |
| D1 | Waiting on `findmnt` output. |

---

## 11. Build notes (departures from this design, recorded by the builder)

### Phase 0 (Vulcan, 2026-09-30, branch invictus-p0)

1. **Loader details (1.1).** `hyprland.lua` loads `monitors.lua` and `user.lua` by absolute file path from the config file's own folder, not through `package.path`. Reason: the shared path goes first on `package.path`, so a plain `require("user")` could pick up a file of that name elsewhere on the path. Hyprland 0.56.2's `require` accepts absolute paths (`isExplicitRequirePath` in `src/config/lua/ConfigManager.cpp`), and a missing module raises, so the loader checks the file exists first. The shared path is added only if absent, because Hyprland keeps one Lua state across reloads and a plain prepend would grow `package.path` on every reload. The loader, not `invictus.core`, loads `monitors.lua`.
2. **Install paths.** Shipped modules install to `/usr/share/invictus/hypr/invictus/*.lua` (the path the loader names, as in 1.1). The copy-once templates (`hyprland.lua`, `monitors.lua`, `user.lua`, `hyprpaper.conf`, waybar and the rest) install under `/usr/share/invictus/config/`. Phase 1 packages it that way.
3. **Runtime scripts stay in `scripts/`** (`show-keybindings.sh`, `confirm.sh`, `waybar/*.sh`) until `invictus-tools` packages them in Phase 1, because deployed configs on Alex's machine call them at `$HOME/invictus/scripts/...`. The old install scripts are in `legacy/`, not deleted, for the same reason.
4. **Keyring file name.** The public key is `pkgs/own/invictus-keyring/invictus.gpg` (ASCII-armoured). makepkg treats any `.asc` source as a signature for another file. `invictus-trusted` is generated from the key at build time.
5. **CI split.** Build (runs PKGBUILD code, no secrets) and sign (has the key, runs no PKGBUILD code) are separate jobs; the build job hands over a manifest that the sign step validates. Published packages are reused at the same version instead of rebuilt, so a file name never gets new bytes (pacman caches would reject it). Changes publish with a pkgrel bump.
6. **Meta contents beyond 1.3.** `invictus-base` also has `sudo zsh nano less tree jq bluez-utils pipewire-alsa pipewire-pulse wireplumber`. `invictus-desktop` also has `discord zed` (binds open them), `pacman-contrib lm_sensors sysstat libnotify` (waybar scripts), `adwaita-cursors`, and names `xwaylandvideobridge` (AUR now, not `extra`: checked 2026-09-30). `invictus-gaming` adds `lib32-mesa lib32-vulkan-radeon gamemode lib32-gamemode lib32-mangohud` so Steam gets the AMD 32-bit driver. `invictus-dev` adds `github-cli npm podman`.
7. **D12 fallback is not available.** `assets/SDDM/blackglass` was only ever a submodule pointer with no `.gitmodules`; the theme files were never in this repo's history. The pointer is removed.
8. **Unsigned until the key exists.** With no `REPO_SIGNING_KEY` secret, CI publishes the repo unsigned with a warning (as the brief asked), and skips `invictus-keyring` while its key file is the placeholder.

### Phase 1, packaging (Vulcan, 2026-09-30, branch invictus-p1)

1. **Runtime scripts stay where they are.** `invictus-tools` and `invictus-desktop` install files straight from the checkout (`$startdir/../../..`); `scripts/build-repo.sh` stages the whole checkout, not only `pkgs/`. The scripts were not moved into the package folders because Alex's machine runs `main`, whose deployed configs call `~/hyprdots/scripts/...` (list: `tests/pkgs/fixtures/main-references.txt`, checked by `tests/pkgs/run.sh`). Rule that follows: bump `pkgrel` when any file a PKGBUILD installs changes, or CI reuses the published package.
2. **Install paths.** `/usr/bin/invictus-{theme,motion,update,doctor}`; `/usr/lib/invictus/{show-keybindings,confirm-poweroff,first-login}`, `/usr/lib/invictus/waybar/{alert,updates}`, `/usr/lib/invictus/lib/defaults.sh`, `/usr/lib/invictus/doctor/` (the test mock); `/usr/share/invictus/{config,hypr,theme,wallpapers,brand}`, `/usr/share/invictus/pinned-hypr.txt`; `/usr/share/applications/invictus-{theme,motion}.desktop`; user unit `invictus-first-login.service`, enabled for every user by a `default.target.wants` link in the package.
3. **`invictus-desktop` carries the config**, so it is no longer depends-only (0.2.0). It depends on `invictus-tools` and `invictus-branding`.
4. **cpu, gpu and memory.sh are not packaged** (design 1.2 said move them into `invictus-tools`). The new bar uses `alert.sh` instead (Felix, Venus's look). They stay in `scripts/waybar/` for machines still on the old config. Forum's health cards should take `alert.sh`'s readings.
5. **Pinned set is the whole hypr* closure: 15 packages, not 11.** `hyprwire`, `hyprland-guiutils`, `hyprtoolkit` and `hyprland-qt-support` link the same `libhyprutils`/`libhyprlang` sonames; leaving them to `[extra]` would let Arch move a soname under the pinned Hyprland. Mechanism: `pkgs/pinned/hypr.lock` (name, version, arch, sha256) and `scripts/fetch-pinned.sh`, which downloads from archive.archlinux.org, verifies Arch's signature with `pacman-key --verify` (full trust required) and the locked sha256, then hands the file to the repo step, which signs it with our key like everything else. Other hypr* apps Alex may have (hyprpicker, hyprsunset, hyprlauncher) are outside the set and can block `-Syu` if Arch moves them first; adopt and the doctor say so.
6. **Repo file names use only `[A-Za-z0-9._-]`** (`scripts/lib/repo-names.sh`): an epoch's `:` (proton-ge-custom-bin `1:GE_Proton11_7-1`) and `+` become `.` before `repo-add`, so the database names the file as uploaded. pacman takes name and version from the database, not the file name; `tests/pkgs/e2e-adopt.sh` installs an epoch package this way. Whether GitHub keeps `:` was not verified (no push from here), so the publish step now checks that every file arrived under its own name and fails otherwise.
7. **AUR package: xwaylandvideobridge** (autostart runs it; it was never in the old package lists, so Alex most likely does not have it; zen-browser-bin and nordic-darker-theme came from his `aur.txt`). Pinned at AUR commit 6682410 with the tarball and signature checksums and the signer's key in `keys/pgp/`; `build-repo.sh` imports keys from there. Own and meta packages build with `--nodeps`; only `pkgs/aur` resolves dependencies.
8. **Config check (1.5): `Hyprland --verify-config` exists in 0.56.2** and works without a session on a Lua config (checked in an Arch container: "config ok", and a bad key is named with file and line). `invictus-doctor --hypr` runs it, then the stub check (the tests' mock of `hl`, installed from `tests/hyprland-lua/`, against `/usr/share/hypr/stubs/hl.meta.lua` from the hyprland package). Hyprland's `require` emulation moved to `tests/hyprland-lua/hyprrequire.lua` so both use one copy.
9. **`invictus-update`** runs `sudo pacman -Syu` (interactive unless `--noconfirm`), clears waybar's update cache, then `invictus-doctor --post-update`; exit 3 if the doctor finds a problem. It does not run `paru -Sua` unless `--aur` is given (the old script did, with `--noconfirm`): building AUR updates unattended runs whatever the AUR serves that day. It prints how many AUR updates are waiting.
10. **First login never switches a hyprlang user silently.** Hyprland takes `hyprland.lua` over `hyprland.conf` when both exist (`Jeremy::getMainConfigPath`), so `invictus-first-login` does not add `hyprland.lua` to a home that has `hyprland.conf`; `adopt.sh` makes that switch on purpose. For the same reason nothing ships `/etc/xdg/hypr/hyprland.lua`: Hyprland searches `XDG_CONFIG_DIRS` for a `.lua` before it looks for a user's `.conf`. A brand-new account can race Hyprland, which writes an example config when it finds none; first login backs that file up and replaces it (Hyprland's autoreload picks up the change). First login also runs `invictus-theme apply`, because waybar, swaync and rofi import `~/.config/invictus/current/*`.
11. **Adopt replaces only the desktop pieces:** hypr, waybar, rofi, kitty, swaync (after a backup). zshrc, zed, btop, cava and fastfetch stay the user's; the doctor lists how they differ from the defaults. `hyprland.conf` and `config/*.conf` stay in place, unused, which makes undo simple. Personal lines are ported by `scripts/dev/port-hyprlang.lua`: exec binds that run something from the home (dashboard-tmux) or that are not in the old clone become `hl.bind` lines in `user.lua`, monitor lines become `hl.monitor{}` in `monitors.lua`, anything else is copied into `user.lua` as comments. Undo does not reset the GTK settings the theme writes through gsettings.
12. **`invictus-motion`** (Felix's hand-off, in `invictus-tools`): the switcher look.md describes. Game mode's marker file (`$XDG_RUNTIME_DIR/invictus/game-mode`) is read by the theme tool, `state.lua` and `invictus-motion`, but nothing creates it yet; the game-mode bind should.
13. **Not done here: machine-specific outputs.** The primary bar output and the workspace-to-monitor map (waybar `config.json`), are still Alex's DP-1/DP-2/HDMI-A-2. The Discord and Zen monitor rules are out of the shipped `rules.lua`; the porter writes them into his `user.lua`. Proposal for the first-boot wizard: one file, `~/.config/invictus/outputs` (a line per monitor, `<output> <workspaces...>`, first line is the primary), read by `invictus/workspaces.lua` for workspace rules and by a small generator for waybar; the app-to-monitor rules live in `user.lua`. Needs a decision on how waybar gets it (waybar's `include` merge rules versus generating the user's `config.json`, which fights copy-once).
14. **Phase 0 fix: local signing.** `INVICTUS_SIGN_KEY` mode passed an empty passphrase through loopback, so a passphrase-protected key (the checklist makes one) failed with "No passphrase given" unless gpg-agent already had it cached. Local mode now lets gpg-agent ask; CI mode still hands the passphrase over.
15. **Bind paths.** After Felix's round merged, the cheatsheet and confirm binds in `binds.lua` call `/usr/lib/invictus/show-keybindings` and `/usr/lib/invictus/confirm` (path change only). The dashboard-tmux bind is out of the shipped `binds.lua` (Alex's own script); adopt writes it into his `user.lua`. Window rules that pin an app to a monitor (Discord, Zen) are ported the same way, as `hl.window_rule` in `user.lua`. A bind or rule the shipped files already have is skipped.

### Package audit (Vulcan, 2026-09-30, branch invictus-pkg-audit)

The sets, their contents and every removal are in `docs/packages.md`; it replaces the meta list in 1.3 and the `invictus-everyday` list in `simple-mode.md` 2.4.

1. **Sets.** `invictus-base` (system, headless), `invictus-desktop` (the session both flavours share, and the config), `invictus-tessera` and `invictus-atrium` (the flavours; both are installed on every machine because people switch live, so they never share a package), `invictus-gaming`, `invictus-dev`, and placeholders `invictus-windows` and `invictus-voice`. `invictus-everyday` is folded into `invictus-atrium`; its viewers (Loupe, Showtime, Papers) went to desktop, because Tessera opens files too. `invictus-assistant`, `-collegium` and `-iso-live` from 1.3 are not made yet.
2. **Desktop does not rely on base.** `adopt.sh` installs desktop without base, so audio, bluetooth, `mesa` and `vulkan-radeon` moved from base to desktop, `zsh` too (the shipped `~/.zshrc`). `podman` left base for dev and windows (friends' machines do not need containers); those two share the podman trio on purpose.
3. **Pinned set: 16.** `hyprshutdown` (in `[extra]` now; the log-out bind uses it) links `libhyprtoolkit` and `libhyprutils`, so it joins the pin.
4. **Design facts that changed.** `whisper-cpp` and `ggml-vulkan` are in `[extra]`, so no AUR whisper build (4.4, 1.1's `pkgs/aur` list). `winapps` is not in the AUR; it needs our own package (3.2). `virtiofsd` is dropped: dockur shares folders over SMB. `limine-mkinitcpio-hook` 1.40 no longer depends on `limine-entry-tool`. `libva-mesa-driver` is part of `mesa`.
5. **Look follows the config where they differ.** The config uses IBM Plex, Symbols Nerd Font Mono, Adwaita cursors, `adw-gtk3` (theme tool) and `QT_QPA_PLATFORMTHEME=gtk3`; the metas now install those (the old ones installed JetBrains Mono, DejaVu and the non-mono Nerd symbols, and not Plex). look.md's `capitaine-cursors`, `qt6ct`, `papirus-folders` and `otf-cormorant` wait until the config uses them. `nordic-darker-theme` is dropped as look.md says, but `config/hypr/invictus/env.lua` still sets `GTK_THEME=Nordic-Darker`, which overrides the theme tool; that line should go (outside this job's files).
6. **Where names come from.** `pkgs/meta/sources.txt` records each name's source; `tests/pkgs/run.sh` checks it offline, `tests/pkgs/live-arch.sh` (new CI job `packages-live`) against Arch and the AUR, plus command files and one conflict-free transaction. `spaceship-prompt` (the zshrc's prompt, missing from every list) is pinned in `pkgs/aur` with its prompt link moved from `/usr/local` to `/usr/share/zsh/site-functions`.
7. **CI shellcheck pinned to 0.11.0** (checksum-checked release download), the version used locally; the runner's apt 0.9.0 is no longer used.
8. **`pipewire-jack` is optional, not a depends.** waybar, ffmpeg and cava need `jack`; pacman's default provider is `jack2`, so a machine set up by the old scripts has it, and a depends on `pipewire-jack` made `adopt.sh`'s `pacman -Syu --noconfirm` stop on the conflict (found by `e2e-adopt.sh`). The ISO names `pipewire-jack` as a target so fresh installs get it; `tests/pkgs/run.sh` (adopt-jack2-conflict) and `live-arch.sh` hold both halves.

### AUR pins, one-command build, No AI split (Vulcan, 2026-09-30, branch invictus-pins)

The record is `docs/packages.md` ("AUR packages", "invictus-moneta"); departures and choices here.

1. **Every AUR package a set names is pinned** in `pkgs/aur` (limine hook and snapper sync, zen, claude-code, proton-ge, VS Code, calamares). All pins are x86_64 only (AMD PCs; aarch64/i686 sources dropped). Beyond the AUR: the limine git tags must carry Zesko's signature (`?signed`), and Gradle checks every Maven artifact against a committed `gradle-verification-metadata.xml` (the AUR build trusts whatever Maven serves at build time); claude-code checks Anthropic's signed release manifest and that the binary matches it, and ships a committed copy of the licence page instead of a SKIP download; calamares checks its Codeberg tarball signature; VS Code's sha256 is checked against Microsoft's signed apt index by `upstream-check.sh` on every bump.
2. **calamares is Vulcan 2's build** (packagechooser, python, the diskcheck page) plus the signature. Its `prepare()` copies `installer/diskcheck`, so this branch carries a byte-identical copy of `installer/diskcheck/` from `invictus-iso` (ea4cd2c): the two branches add the same files and merge cleanly unless one changes them first. The pins use the same names as `iso/aur-needed/`; `build-iso.sh` prefers `pkgs/` copies, so those can go.
3. **Pins stay current with `scripts/dev/bump-aur.sh`** (who and when: `docs/packages.md`). It applies only version-and-checksum changes by itself; a real rehearsal (claude-code 2.1.284 to 2.1.285) found that `updpkgsums` writes SKIP for signature files, now fixed and tested (bump-sig-skip).
4. **`build-repo.sh --in-container` is one command** for Alex: the container builds with no key and no signing variables, hands the files back to whoever owns the output folder (`chown` to the mount's owner inside the container, which is right for docker and rootless podman), and the repo step runs on the host. Where the host has no `repo-add` (CI's Ubuntu) the repo step runs in a second container; with `INVICTUS_SIGN_KEY` and no `repo-add` it stops before building. The signing variables are now also kept out of package code when both steps run without a container (they were in makepkg's environment before when not root).
5. **No AI split (design-no-ai.md N5).** `invictus-moneta` holds `claude-code`; `invictus-dev` no longer does. `invictus-sys` and `invictus-guardrails` do not exist yet; the offline test covers every set and own package, so they are checked when they land. NA3's `no-ai-in-base` runs on the built repo in `packages.yml` before publishing and in `e2e-arch.sh`. `adopt.sh` still installs `desktop tessera gaming dev`, so adopting no longer adds Claude Code; Alex keeps the one paru installed, and our repo now updates it.
6. **VS Code replaces Code - OSS in dev** (Alex). `visual-studio-code-bin` conflicts with `code`; `pacman -Sp` does not see conflicts, so `adopt.sh`'s plan now names installed packages ours conflict with and refuses `--yes` on them (adopt-conflict-noconfirm).
7. **Vendored AUR helper scripts** (`pkgs/aur/*/*.sh`) are left out of CI's shellcheck so a bump stays a plain diff; our own `upstream-check.sh` files are checked.

### Phase 3, ISO and installer (Vulcan 2, 2026-09-30, branch invictus-iso)

Where the pieces are: `iso/` (profile, live-only and keep lists, secrets scan, Plymouth and os-release under `boot-branding/`, our two new packages under `own-needed/`), `installer/` (Calamares config, jobs, diskcheck page, branding, live launcher), `scripts/build-iso.sh`, `.github/workflows/iso.yml`, `tests/iso/`, `docs/checklists/iso-test.md`.

1. **Live session: Hyprland, with a kiosk fallback; no welcome window yet (2.1).** The live user `liber` logs in on tty1 and gets Hyprland with the shipped config; its `user.lua` opens the installer on start. The Quickshell welcome window with "Install" and "Try it" is not built (no Quickshell code exists yet): the installer window opens by itself and "Try it" is closing it. When there is no GPU render node, when the boot menu's safe-graphics entry is picked, or when Hyprland exits within 30 s, the session runs `cage` (wlroots kiosk, software rendering) with only the installer. The rescue menu (`invictus-rescue`) is not built.
2. **ISO boot menu is systemd-boot, not limine (look.md).** archiso 91 has no limine boot mode (`bios.syslinux`, `uefi.grub`, `uefi.systemd-boot` only), and systemd-boot has no colour settings, so the ISO's menu is plain text with Invictus titles; the Plymouth splash carries the look. The installed system's limine menu has the Dusk colours. `uefi.grub` could be themed but moves away from the boot path Ventoy lists as tested for Arch ISOs; kept systemd-boot.
3. **Installer pages: Calamares' own pages in Dusk, not Venus's four cards (simple-mode 3.1).** Plain path: Welcome (language), Location (time zone, from GeoIP), Keyboard, You, Disk, Your files. Six pages, not four: Calamares cannot skip the locale and keyboard pages and still configure them, and matching Venus's card layout needs QML pages (`welcomeq`, `usersq`) that cannot be checked without a screen. The tick box page is ours (`installer/diskcheck`, a small C++ Calamares module) and is the last page before anything is written, so the order is You then Disk (Venus has Disk then You); the button there reads "Install", Calamares' fixed label, not "Erase and install". The hostname is made from the user name (`<user>-invictus`) and not shown. "Save a report for Alex" is not built: the ISO stick is read-only, and install logs are never sent anywhere (`uploadServer: none`). Venus's QML pages are follow-up work.
4. **Advanced path.** A second Calamares configuration, started by the boot menu's Advanced entry, the launcher entry "Install Invictus (Advanced)" or `invictus-install --advanced`: two choice pages (flavor Atrium/Tessera, guard rails Custodia/Libertas, Calamares `packagechooser`, which the AUR build skipped and our pinned copy builds), manual partitioning, LUKS2 offered and unticked (D6), and the summary page. It does not stop someone choosing Custodia and encryption together (DS8 says Custodia machines stay unencrypted); the Advanced path is Alex's.
5. **Job list (2.2).** Stock `bootloader`, `initcpio` and `initramfs` modules are off. `invictus-post` is folded into `invictus-bootloader`, which runs `limine-install --no-efi-register` and `limine-mkinitcpio` itself (Calamares' `initcpio` would call `mkinitcpio -P`, which limine-mkinitcpio-hook wraps with an interactive prompt). `invictus-cleanup` runs right after `unpackfs`/`machineid`, before `users` (so the new account gets uid 1000 and the archiso mkinitcpio drop-in is gone before `initcpiocfg`), not at the end. New job `invictus-settings` writes the guard rails, the flavor, `/etc/invictus/release` and (plain path) the hostname. `initcpiocfg` uses the systemd hooks and appends `sd-btrfs-overlayfs`; the bootloader job checks the order.
6. **`@vm` gets No_COW with `chattr +C`, not a `nodatacow` mount option (2.2).** btrfs applies such options to the whole file system, not one subvolume. All btrfs subvolumes mount `noatime,compress=zstd:1`.
7. **Firmware entry.** The job adds its own NVRAM entry labelled "Invictus" (limine-install would call it "Limine"; it recognises ours by path afterwards). If the firmware refuses the entry, limine goes in the removable-media path (`EFI/BOOT/BOOTX64.EFI`) with a warning instead of failing the install.
8. **Root is locked by editing the target's shadow (`!*`).** The live image's root has an empty password (as releng's), and Calamares' `setRootPassword: false` only hides the fields; the cleanup job locks it and checks.
9. **`customize_airootfs.sh` is used (archiso marks it deprecated).** limine-mkinitcpio-hook replaces mkinitcpio's kernel pacman hook with one that needs an ESP, so the live initramfs is built in that script with the stock `mkinitcpio` and archiso's hooks. If archiso drops the script, the alternative is a `NoExtract` for that hook in the build pacman.conf plus restoring it in the target.
10. **Packages.** The ISO installs the final sets (`docs/packages.md`, "For the ISO"): `invictus-base invictus-desktop invictus-tessera invictus-atrium pipewire-jack`, plus `invictus-boot-branding`, `plymouth`, `os-prober`, `cryptsetup`, and the live-only `invictus-installer calamares cage` that the cleanup job removes (no `invictus-iso-live` meta). The services the sets need are enabled by Calamares (`services-systemd.conf`) and the settings job puts `mdns_minimal` on the `hosts` line. Two new packages are written under `iso/own-needed/` for `pkgs/own/`: `invictus-installer` (1.3 called it `invictus-calamares-config`) and `invictus-boot-branding` (Plymouth theme, os-release and a hook that re-applies it after `filesystem` upgrades; could fold into `invictus-branding`). The AUR pieces are pinned in `pkgs/aur/` (the other Vulcan's pins took over the copies first written under `iso/aur-needed/`, now deleted). **Our calamares is not the AUR's**: 3.4.2-2.2 builds packagechooser and our diskcheck page (`installer/diskcheck`, copied into the tree in `prepare()`); `tests/iso/profile.sh` fails if that changes.
11. **Channel.** Installed machines use `[invictus-testing]` by default (`build-iso.sh --channel stable` switches to `[invictus]`), because the stable repo is not published yet; design-simple-mode 1.3 asks for stable on every install.
12. **Custodia pieces wait for `invictus-guardrails`.** The settings job writes `/etc/invictus/guardrails` and runs `invictus-sys guardrails apply` when it exists; the `pam_exec` line in `/etc/pam.d/sudo` (6.1) is not added until the pre-admin snapshot script exists (a line pointing at a missing script would be noise at best).
13. **Release ISOs never sign.** `build-iso.sh --release` builds from an already signed repo (downloaded in CI) and checks every signature; it takes no private key. Dev ISOs build every package into an unsigned local repo; while `invictus-keyring` is the placeholder they carry a throwaway public key and say `keyring=dev-throwaway` in `/etc/invictus/release`.
14. **Smaller choices.** Weak passwords are allowed (4 characters minimum) on both paths; GeoIP (geoip.kde.org, the Calamares default service) preselects language and time zone when online; the first-boot wizard steps listed for Phase 3 in section 5 are not in this round.
