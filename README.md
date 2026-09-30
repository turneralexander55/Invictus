# Invictus

A personal Linux distribution based on Arch Linux, built around Hyprland,
for AMD machines. For gaming, development and a Windows-for-work VM. Friends
and family only.

The design is in [docs/design.md](docs/design.md). This repo is the build
source: machines get Invictus through packages from the `[invictus]` pacman
repo, not by cloning this repo.

## Status

Phase 0 (foundation). The repo layout, the package repo with its signing
key, and CI are in place. Nothing installs the desktop from packages yet.

## If you run the old install on your machine

The old `hyprdots` scripts moved to [legacy/](legacy/README.md) and still
work from there (`./legacy/install.sh`, `./legacy/deploy-configs.sh --force`,
`./legacy/update.sh`). `scripts/update.sh` forwards to the legacy updater,
because the waybar update button calls that path. They stay until Phase 1's
`scripts/dev/adopt.sh` moves an existing install onto the packages.

## Layout

```
config/          desktop defaults, installed under /usr/share/invictus
  hypr/
    hyprland.lua     five-line loader (copied to ~/.config/hypr once)
    invictus/*.lua   the shipped Hyprland config; updates replace it
    monitors.lua     template for your monitor layout
    user.lua         template for your own changes (loaded last, wins)
    hyprpaper.conf
  waybar/ kitty/ rofi/ swaync/ fastfetch/ btop/ cava/ zed/ shell/
pkgs/            one PKGBUILD per folder: own/, meta/ (aur/, pinned/ from Phase 1)
scripts/         build-repo.sh, plus the desktop scripts binds and waybar call
theme/           invictus-theme and the theme files
tests/           hyprland-lua/, pkgs/, theme/
docs/            design.md, look.md, reuse-catalog.md, checklists/
legacy/          the old install scripts, frozen
.github/         CI: checks.yml, packages.yml
```

On an installed machine, change Hyprland in `~/.config/hypr/user.lua` and
monitors in `~/.config/hypr/monitors.lua`. Updates never touch those two
files.

## Build the package repo

```
scripts/build-repo.sh
```

Runs natively on Arch, or in an `archlinux:base-devel` container through
podman or docker elsewhere. Output goes to `out/repo`. Signing:
[docs/checklists/signing-key.md](docs/checklists/signing-key.md).

CI builds and publishes `[invictus-testing]` from `main` to the
`invictus-testing` release. pacman line:

```
[invictus-testing]
Server = https://github.com/turneralexander55/invictus/releases/download/invictus-testing
```

## Tests

```
tests/hyprland-lua/run.sh   Hyprland config against the 0.56.2 Lua API (needs lua 5.4+, libxkbcommon headers)
tests/pkgs/run.sh           PKGBUILDs and the keyring guards (needs gpg)
tests/theme/run.sh          the theme tool (needs python 3.11+)
luacheck .
```

`tests/pkgs/e2e-arch.sh` builds, signs and installs the repo inside a
throwaway Arch container; CI runs it on every push.

Shared pieces to reuse before building anything: [docs/reuse-catalog.md](docs/reuse-catalog.md).

## Licence

GPL-3.0. Based on Arch Linux; not affiliated with or endorsed by Arch Linux.
