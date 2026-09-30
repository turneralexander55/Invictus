# Invictus package sets

What each meta package is for, what is in it and why. Audit of Alex's old lists (`legacy/packages/pacman.txt`, `aur.txt`) and the Phase 0/1 metas, 2026-09-30, Vulcan. Every name was checked in an Arch container that day (`pacman -Si`, `pacman -F`, AUR RPC).

## The sets

| Set | One job | Who installs it |
|---|---|---|
| `invictus-base` | The system under any machine: kernels, firmware, limine with bootable snapshots, btrfs, network, command line. Headless-safe | ISO and installer only. `adopt.sh` never installs it |
| `invictus-desktop` | The session both flavours share: Hyprland, login, portals, audio, bluetooth, power, keyring, files, viewers, fonts, the shell the shipped `~/.zshrc` needs, and the config itself | Every machine with a screen |
| `invictus-tessera` | Tessera, the tiling flavour: waybar, rofi and what its binds and bar open | Every install (users switch flavour live); Alex's machine by `adopt.sh` |
| `invictus-atrium` | Atrium, the windows-and-taskbar flavour: the everyday apps behind Start, printing, scanning, Flatpak apps, a disk tool. The Atrium shell joins when it is built | Every install |
| `invictus-gaming` | Steam, Proton GE, gamescope, MangoHud, GameMode, Lutris with umu. Needs `[multilib]` | Opt-in |
| `invictus-dev` | Build tools, git, Zed and VS Code, Node, Python, podman. No AI | Opt-in |
| `invictus-moneta` | The AI set's meta: Claude Code now; the Moneta panel, plugin and MCP server, providers and Collegium as they are built | Only when someone picks an AI (first start or Settings, `invictus-sys ai on`); never on a No AI machine |
| `invictus-windows` | Placeholder: FreeRDP 3 and rootless podman for the Windows VM | Opt-in, Phase 4 |
| `invictus-voice` | Placeholder: whisper.cpp with the Vulkan backend, both from `[extra]` | Opt-in, when `invictus-ptt` exists |

Rules the tests hold (`tests/pkgs/run.sh`, group "package sets"):
- One package, one set. The only intended overlap is `podman podman-compose crun` in dev and windows, so each works alone. A set may depend on another set: tessera, atrium, gaming, windows, voice and moneta depend on `invictus-desktop`.
- No AI outside the AI set (design-no-ai.md N5): the AI set is `claude-code`, `invictus-moneta`, `invictus-voice`, `whisper-cpp`, `ggml-vulkan`, `invictus-collegium` and any local model package (`tests/pkgs/lib/ai-set.sh`). No other set or own package depends on it or suggests it, directly or through other sets. `tests/pkgs/run.sh` checks the PKGBUILDs; `tests/pkgs/no-ai-in-base.sh` (CI `no-ai-in-base`, NA3) checks the built repo with pacman's resolver before every publish, and `e2e-arch.sh` runs it too. When `invictus-guardrails` and `invictus-sys` exist they depend on nothing in the AI set.
- `invictus-desktop` never relies on `invictus-base` (adopt installs it without base), so anything the shipped config or our scripts run comes from desktop, a flavour, our own packages or Arch's `base`.
- A set names what we run or rely on directly, not the hard dependencies of what it names (`hyprland` already pulls `xorg-xwayland` and `mesa`'s VA-API driver comes with `mesa`).
- `pkgs/meta/sources.txt` says where every name comes from (`core`, `extra`, `multilib`, `aur` built from `pkgs/aur`, `aur-paru`, `invictus`). `tests/pkgs/live-arch.sh` rechecks it against Arch and the AUR, checks each command in `tests/pkgs/fixtures/commands.txt` is a file of its package, and resolves every set in one transaction: no conflicts, and Steam gets `vulkan-radeon`/`lib32-vulkan-radeon`, never another driver.

For the ISO (Vulcan 2): install `invictus-base invictus-desktop invictus-tessera invictus-atrium pipewire-jack` (`pipewire-jack` as a target so `jack` resolves to it, see desktop below; plus `invictus-guardrails` once it exists, design-simple-mode 6.1); gaming, dev, windows are opt-in; moneta and voice (the AI set) are never on the ISO's install list, first start or Settings adds them. `calamares`, `limine-mkinitcpio-hook` and `limine-snapper-sync` are in `pkgs/aur` now (same names as `iso/aur-needed`, which can go). Installer jobs these sets need: enable `NetworkManager`, `bluetooth`, `sddm`, `power-profiles-daemon`, `cups.socket`, `avahi-daemon`, `paccache.timer`; add `mdns_minimal [NOTFOUND=return]` before `resolve` on the `hosts` line of `/etc/nsswitch.conf`; nothing for the keyring: Arch's `/etc/pam.d/sddm` already unlocks and starts gnome-keyring at login (`pam_gnome_keyring.so` in auth, password and session, checked in the sddm package).

## invictus-base

| Package | Why | Used by |
|---|---|---|
| `base` | Arch's minimal system | everything |
| `invictus-keyring` | Trusts our repo's key | pacman |
| `linux`, `linux-lts` | Kernel, and the second boot entry (design 2.1) | boot |
| `mkinitcpio` | The initramfs the limine hook drives | `limine-mkinitcpio-hook` |
| `linux-firmware` | GPU, Wi-Fi, bluetooth firmware for any machine a friend brings | kernel |
| `sof-firmware` | Laptop audio (Intel and AMD SOF DSPs) | kernel |
| `amd-ucode`, `intel-ucode` | CPU microcode; AMD GPUs only, but friends' CPUs may be Intel | limine entries |
| `fwupd` | Firmware updates for SSDs, docks, laptops (LVFS) | Desk later |
| `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, `efibootmgr` | Boot with a Snapshots menu; the installer registers the entry | installer, updates |
| `btrfs-progs`, `snapper`, `snap-pac` | btrfs root, snapshots around every pacman run | `invictus-update`, doctor |
| `dosfstools`, `exfatprogs`, `ntfs-3g` | ESP checks, USB sticks, Windows disks | udisks, installer |
| `networkmanager` | Network | everything |
| `openssh` | ssh and git over ssh (sshd stays off) | people, dev |
| `polkit` | `invictus-sys` authorises through it | assistant, guard rails |
| `pacman-contrib` | `paccache` cleanup | `paccache.timer` |
| `sudo nano less tree man-db man-pages` | Everyday command line and manuals | people |
| `unzip zip 7zip rsync usbutils lm_sensors` | Archives, copies, `lsusb`, temperatures | people, Desk later |

## invictus-desktop

| Package | Why | Used by |
|---|---|---|
| `invictus-tools`, `invictus-branding` | Our commands, wallpapers, logo | binds, waybar, first login |
| `mesa`, `vulkan-radeon` | AMD OpenGL, Vulkan, VA-API video decode | Hyprland, Zed, games, browsers |
| `hyprland hyprpaper hypridle hyprlock hyprpolkitagent` | Compositor, wallpaper, idle, lock, password prompts (pinned set) | autostart, binds |
| `hyprshutdown` | Closes apps cleanly on log out (now pinned) | Super+Delete |
| `xdg-desktop-portal`, `-hyprland`, `-gtk` | Screen sharing, file pickers, dark-mode setting | apps, autostart |
| `qt6-wayland`, `qt6-svg` | Qt apps on Wayland; SVG icons (Papirus) in Qt apps | Qt apps |
| `sddm` | Login | boot |
| `pipewire pipewire-alsa pipewire-pulse wireplumber` | Sound | volume keys (`wpctl`), waybar, FreeRDP |
| `bluez bluez-utils blueman` | Bluetooth and a window to pair (the voice pen button) | people |
| `power-profiles-daemon`, `upower` | Power profiles, battery state | Atrium quick settings, Desk |
| `gnome-keyring`, `libsecret` | Secret store unlocked at login; `secret-tool` | FreeRDP askpass, first boot (design 2.3) |
| `xdg-user-dirs`, `xdg-utils` | Home folders; `xdg-open` for links and files | first login, apps |
| `swaync` | Notifications (both flavours) | autostart, waybar |
| `kitty` | Terminal | binds, theme tool |
| `wl-clipboard`, `hyprshot`, `brightnessctl`, `playerctl` | Clipboard, screenshots, hardware keys | binds |
| `thunar thunar-volman thunar-archive-plugin tumbler ffmpegthumbnailer gvfs gvfs-mtp gvfs-smb file-roller` | Files: drives, phones, shares, archives, thumbnails | Super+E, Atrium "Files" |
| `loupe showtime papers` | Open photos, video, PDFs (both flavours download files) | Thunar, browsers, Atrium tiles |
| `gst-plugins-good -bad -ugly gst-libav gst-plugin-va` | Codecs for Showtime and GTK apps, GPU decode | Showtime, Loupe |
| `zen-browser-bin` | Browser (AUR) | Super+W, Atrium "Internet" |
| `papirus-icon-theme`, `capitaine-cursors`, `adw-gtk-theme`, `qt6ct` | Icons, the cursor `env.lua` sets (`XCURSOR_THEME`), the GTK theme `invictus-theme` recolours, the Qt platform theme `env.lua` sets (`QT_QPA_PLATFORMTHEME=qt6ct`) | theme tool, rofi, Qt apps |
| `fontconfig`, `ttf-ibm-plex`, `ttf-nerd-fonts-symbols-mono` | The UI and mono face and the glyph font the config names | kitty, waybar, rofi, swaync, first login |
| `noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation` | Every script, emoji, Arial/Times/Courier metrics | web, documents, games |
| `zsh zsh-syntax-highlighting zsh-autosuggestions spaceship-prompt fastfetch` | The shipped `~/.zshrc` | every terminal |

Optional: the two flavours, `pipewire-jack`, `libva-utils` (vainfo), `seahorse`.

`pipewire-jack` is optional on purpose. waybar, ffmpeg and cava depend on `jack`, and pacman's default provider is `jack2`, so a machine set up by the old scripts (Alex's) has `jack2`; a set that depends on `pipewire-jack` makes `pacman -Syu --noconfirm` stop on the conflict (found by `e2e-adopt.sh`). The ISO names `pipewire-jack` as an install target, so a fresh machine resolves `jack` to it.

## invictus-tessera

| Package | Why | Used by |
|---|---|---|
| `invictus-desktop` | The shared session | |
| `waybar`, `rofi` | Bar, launcher (rofi also serves our pickers) | autostart, Super+Space |
| `pavucontrol`, `nm-connection-editor`, `btop` | What waybar modules open | waybar clicks |
| `cliphist` | Clipboard history | autostart |
| `yazi`, `discord`, `xwaylandvideobridge` | Super+Y, Super+D; the bridge lets XWayland Discord share a Wayland window | binds, autostart |
| `cava`, `nwg-look` | Visualiser the theme tool recolours; GTK settings by hand | Alex |

Optional: `invictus-gaming` (Super+G), `invictus-dev` (Super+T opens Zed).

## invictus-atrium

| Package | Why | Used by |
|---|---|---|
| `invictus-desktop` | The shared session | |
| `libreoffice-fresh`, `ttf-carlito`, `ttf-caladea` | Documents; Calibri and Cambria metrics | "Documents" |
| `gnome-calculator`, `gnome-text-editor` | Calculator, plain text | Start tiles |
| `cups system-config-printer ipp-usb nss-mdns` | Driverless network and USB printers | "Printers" |
| `simple-scan`, `sane-airscan` | Driverless scanners | All apps |
| `flatpak bazaar flatseal` | Per-user Flathub apps (design-simple-mode 3.1) | "Get apps" |
| `gnome-disk-utility` | Format a USB stick without a terminal | All apps |
| `gvfs-afc` | Photos from an iPhone | Files |

## invictus-gaming

| Package | Why | Used by |
|---|---|---|
| `invictus-desktop` | Games need the session and its 64-bit driver | |
| `steam`, `lib32-mesa`, `lib32-vulkan-radeon` | Steam with the AMD 32-bit drivers named (alone, Steam picks `nvidia-utils`) | Super+G |
| `gamescope mangohud lib32-mangohud gamemode lib32-gamemode` | Game compositor, overlay, tuning | launch options, rules |
| `lutris`, `umu-launcher` | Non-Steam games through Proton | people |
| `proton-ge-custom-bin` | Proton GE (AUR, large) | Steam, umu |

Optional: `vulkan-tools`, `lact` (AMD clocks and fans).

## invictus-dev

| Package | Why | Used by |
|---|---|---|
| `base-devel git github-cli` | Build packages (AUR too), version control | people, agents |
| `zed`, `visual-studio-code-bin` | Zed (Super+T); Microsoft's VS Code (marketplace extensions, Remote; Alex, 2026-09-30), from our pin in `pkgs/aur`. It conflicts with Arch's `code`: `adopt.sh` warns and refuses `--yes` while `code` is installed | people |
| `nodejs npm python` | Languages | people |
| `podman podman-compose crun` | Rootless containers; crun named so podman does not ask | people |
| `ripgrep fd jq` | Search, find, JSON | people, agents |

Optional: `uv`, `rustup`, `go`, `shellcheck`, `distrobox`. Claude Code left dev for `invictus-moneta` (design-no-ai.md N5): a No AI machine can have the dev tools.

## invictus-moneta (the AI set)

| Package | Why | Used by |
|---|---|---|
| `invictus-desktop` | The panel is a desktop app | |
| `claude-code` | Claude Code, from our pin in `pkgs/aur` | people, the Moneta panel later |

Joins as built: the panel, the plugin and MCP server, the provider files, `invictus-collegium`. `/etc/claude-code/` and the managed profiles belong to `invictus-guardrails` on every machine, not to this set (design-no-ai.md N4).

## invictus-windows and invictus-voice (placeholders)

| Set | Package | Why |
|---|---|---|
| windows | `invictus-desktop`, `freerdp`, `podman podman-compose crun` | FreeRDP 3 (`sdl-freerdp3`, `xfreerdp3`), dockur/windows under rootless podman; `secret-tool` comes with desktop |
| voice | `invictus-desktop`, `whisper-cpp`, `ggml-vulkan` | `whisper-server` on the GPU; models downloaded at first boot |

## Removed and why

| Package | Was in | Why |
|---|---|---|
| `vscode` | pacman.txt | Not an Arch package; `code` is (fixed in Phase 0) |
| `nordic-darker-theme` | aur.txt, desktop | look.md replaces it with `adw-gtk-theme` recoloured by `invictus-theme`; AUR, last updated 2022. `env.lua` no longer sets `GTK_THEME` (Felix, 2026-09-30) |
| `ttf-jetbrains-mono`, `ttf-dejavu` | pacman.txt, desktop | The config uses IBM Plex; look.md drops both; Noto covers fallback |
| `ttf-nerd-fonts-symbols` | pacman.txt, desktop | The config asks for "Symbols Nerd Font Mono", which is `ttf-nerd-fonts-symbols-mono` |
| `qt6-declarative` | pacman.txt, desktop | `sddm` depends on it; nothing of ours uses it directly |
| `qt6-5compat` | pacman.txt, desktop | Only the old blackglass SDDM theme needed it (gone) |
| `dbus` | pacman.txt, desktop | Part of every systemd install |
| `xorg-xwayland` | pacman.txt, desktop | A hard dependency of `hyprland` |
| `sysstat` | pacman.txt, desktop, tools | Only the unpackaged `cpu.sh` used `mpstat`, behind `command -v` |
| `lm_sensors` | desktop, tools | Nothing shipped calls `sensors`; kept in base as a tool |
| `pacman-contrib`, `libnotify` | desktop | `invictus-tools` depends on them (its scripts call them) |
| `jq` | base, desktop | No shipped script uses it any more; `hyprshot` pulls it; kept in dev |
| `zsh` | base | Moved to desktop: the shipped `~/.zshrc` needs it, base stays shell-neutral |
| `podman` | base | Moved to dev and windows: friends' machines do not need containers |
| `zed` | desktop | Only in dev; Tessera suggests dev for Super+T |
| `mako` | old autostart | swaync is the daemon (Phase 0) |

Moved, not removed: audio, bluetooth, `mesa`, `vulkan-radeon` from base to desktop (desktop must work without base); waybar, rofi, cliphist, yazi, btop, cava, nwg-look, pavucontrol, nm-connection-editor, discord, xwaylandvideobridge from desktop to tessera.

Design plans dropped: `virtiofsd` in windows (dockur shares folders over SMB, not virtiofs); an AUR `whisper.cpp` Vulkan build (`whisper-cpp` and `ggml-vulkan` are in `[extra]`); `winapps` from the AUR (there is no such AUR package; it becomes our own); `limine-entry-tool` (the 1.40 hook no longer depends on it); `invictus-everyday` (its list is `invictus-atrium` now).

## Considered and rejected

- `tuned`, `tuned-ppd`: `power-profiles-daemon` is simpler and is what Quickshell, GNOME and waybar read. `tlp` conflicts with it.
- KeePassXC as the Secret Service: needs its own unlock; gnome-keyring unlocks at login.
- `code` (Code - OSS, `[extra]`): Alex chose Microsoft's build (`visual-studio-code-bin`) for the marketplace and Remote extensions (2026-09-30).
- `firefox` instead of Zen: Zen is Alex's pick and Atrium's "Internet"; it costs an AUR package.
- `heroic-games-launcher-bin`, `protonup-qt`, `protonplus` (AUR): Lutris with umu covers Epic and GOG, Proton GE comes from our repo; friends can get Heroic as a Flatpak.
- `corectrl`: `lact` is the maintained AMD tool (optional).
- `gparted`: `gnome-disk-utility` works through udisks without running a root app.
- `xarchiver`: `file-roller` matches the GTK 4 apps.
- `cups-browsed`: CUPS 2.4 finds driverless printers itself.
- `qt5ct`, `papirus-folders` (AUR), `otf-cormorant` (look.md): the config does not use them yet (`env.lua` sets `QT_QPA_PLATFORMTHEME=qt6ct`, so Qt 5 apps get no theme); add each when the config does. `qt6ct` and `capitaine-cursors` joined desktop when `env.lua` switched to them (2026-09-30); `adwaita-cursors` left.
- `quickshell`: nothing runs it yet; joins with the Desk or the Atrium shell.
- A firewall (`ufw`, `firewalld`): nothing listens on the network by default (sshd off, the VM's RDP on 127.0.0.1). Revisit with RustDesk.
- `zram-generator`: the design uses a swapfile. `reflector`: the installer's job.
- `paru`: optional for `invictus-update --aur`; not built here (a Rust build every release).
- `linux-headers`/DKMS, `xpadneo`: no out-of-tree modules; the kernel's `xpad` and bluez handle Xbox pads.
- `libreoffice-still`, `gvfs-gphoto2`, `wine`, `lib32-pipewire` (Steam pulls it), `cmatrix` (the zshrc only aliases it).

## AUR packages

Every AUR package a set names is built from a pin in `pkgs/aur` (`sources.txt` says `aur`), plus `calamares` for the live ISO. Each pin is the AUR's PKGBUILD at a reviewed commit (`# aur-commit:` in its header), every source checksum pinned, signatures checked against the signer's key in `keys/pgp/` where upstream signs, and our changes listed at the top.

| Package | Set | Pinned AUR commit | Upstream proof | AUR maintainer (checked 2026-09-30) | Pin maintained by | Bump |
|---|---|---|---|---|---|---|
| `spaceship-prompt` | desktop | 876c787 (4.22.5-1) | sha256 (no signature upstream) | FSPP | Vulcan | when the weekly check flags it |
| `xwaylandvideobridge` | tessera | 6682410 (0.5.3-1) | KDE tarball signature | mhdi | Vulcan | when the weekly check flags it |
| `zen-browser-bin` | desktop | f4c4f31 (1.22.3b-1) | sha256 only: Zen publishes no signature or checksum file; AUR's sum and ours agree | Larvey | Felix runs, Vulcan reviews | weekly (Firefox security fixes) |
| `claude-code` | moneta | 5f4ea22 (2.1.285-1) | Anthropic-signed release manifest (key 31DD DE24 ... 1A7E CACE); the binary must match it | cg505 | Felix runs, Vulcan reviews | weekly |
| `visual-studio-code-bin` | dev | 7fe1834 (1.139.1-1) | sha256 in Microsoft's signed apt index (`upstream-check.sh`) | dcelasun | Felix runs, Vulcan reviews | weekly |
| `proton-ge-custom-bin` | gaming | 4b40426 (1:GE_Proton11_7-1) | sha512 (matches GE's `.sha512sum`; no signature) | eliteschw31n | Felix runs, Vulcan reviews | each GE release, about every two weeks |
| `limine-mkinitcpio-hook` | base | 94ffde9 (1.40.0-1) | Zesko's signed git tag; GraalVM sha256; Gradle dependency checksums | Zesko | Vulcan | when the weekly check flags it; new Gradle deps need `scripts/dev/gradle-metadata.sh` |
| `limine-snapper-sync` | base | cc400d0 (1.32.0-1) | as above | Zesko | Vulcan | as above |
| `calamares` | live ISO only | 167151b (3.4.2-2, ours 2.2) | Codeberg tarball signature (Adriaan de Groot) | gyfooya | Vulcan 2 (ISO) | with ISO work; the Calamares schemas in `tests/iso` move with it |
| `paru` | tools (optional) | not pinned: people install it themselves | | Morganamilo | nobody | |

Coming with later phases: `rustdesk-bin` (kuhtoxo) for `invictus-guardrails`.

### AUR pins: keeping them current

- **Check (weekly, Monday).** `scripts/dev/bump-aur.sh --check` lists pins behind the AUR. The `aur-pins` workflow runs it every Monday at 06:17 UTC, but GitHub runs schedules only on the default branch, so until the work is on `main` Felix runs it by hand on Mondays and tells Moneta.
- **Bump.** `scripts/dev/bump-aur.sh NAME --reviewer <name>` clones the AUR, prints its log and diff since our commit, applies it only if nothing but the version and checksums changed, recomputes every checksum by downloading (in an Arch container unless run on Arch), checks each one the AUR names came out the same, checks signatures (and `upstream-check.sh` where there is one), and moves the header lines. It never commits. If the AUR changed anything else (a new source, a build step, a helper file) it stops with exit 3: Vulcan merges that by hand and reruns with `--sums-only`.
- **Who.** Felix (cheap, routine) runs the weekly bumps of zen, claude-code, VS Code and Proton GE, pastes the AUR diff into the hand-back, and Vulcan reviews before Moneta merges. Anything that stops with exit 3, 4 or 5 goes to Vulcan. Vulcan 2 owns calamares with the ISO.
- **Proton GE's size.** About 560 MB download and a 500 MB package, under GitHub's 2 GiB per-asset limit (`build-repo.sh` refuses any package of 2 GiB or more). CI rebuilds and uploads it only when its version changes: the build job reuses the published file, and publish uploads only package files the release does not have yet. A cold CI build of every pin took about 15 minutes here (4 cores).
- **Tests.** `tests/pkgs/run.sh` group 11 checks every pin's header, that no checksum is SKIP and that signers' keys match `validpgpkeys`; the `aur-pins` workflow builds every pin on its own when one changes. The e2e tests use empty stand-ins for the big ones (`tests/pkgs/fixtures/aur-heavy.txt`).

## Open questions

- LibreOffice native in `invictus-atrium` (updates and rollback with the system) or a Flatpak (DS5)? Native here until decided.
- `xwaylandvideobridge`: only Discord under XWayland needs it. If Discord shares screens natively under Wayland on Alex's machine (not checked here), drop it and its autostart line.
