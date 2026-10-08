# Packages

One PKGBUILD per directory. `scripts/build-repo.sh` builds them all into a
pacman repo; `.github/workflows/packages.yml` does the same in CI, signs and
publishes to the `invictus-testing` release.

| Folder | What goes there | Now |
|---|---|---|
| `own/` | Our own packages. They install files from elsewhere in this repo (`scripts/`, `config/`, `theme/`, `assets/`), found at `$startdir/../../..`; `build-repo.sh` stages the whole checkout | `invictus-keyring`, `invictus-tools`, `invictus-branding` |
| `meta/` | Packages that pull a set of software, one job each (`docs/packages.md`); `sources.txt` says where every name comes from. `invictus-desktop` also carries the desktop config and the first-login unit | `invictus-base`, `-desktop`, `-tessera`, `-atrium`, `-office`, `-gaming`, `-dev`, `-cicero` (the AI set), `-windows` and `-voice` (placeholders) |
| `aur/` | AUR PKGBUILDs copied at a reviewed commit, every checksum pinned (signatures too), and the upstream signing key in `keys/pgp/` when the source is signed. Never built from a live AUR checkout. Moved with `scripts/dev/bump-aur.sh` | `calamares` (live ISO only), `claude-code`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, `proton-ge-custom-bin`, `spaceship-prompt`, `visual-studio-code-bin`, `xwaylandvideobridge`, `zen-browser-bin` |
| `pinned/` | Exact signed binary packages, fetched and verified by `scripts/fetch-pinned.sh` at build time: `hypr.lock` (the hypr* set, from the Arch archive) and `cachyos.lock` (the kernel, from CachyOS, checked with the key in `keys/`). No binaries in git | 16 hypr packages (Hyprland 0.56.2-3); linux-cachyos and headers 7.2.7-1 |

Rules:
- Bump `pkgrel` whenever a file a PKGBUILD installs changes. CI reuses a
  published package with the same file name instead of rebuilding it.
- Repo file names only use `[A-Za-z0-9._-]` (`scripts/lib/repo-names.sh`),
  because GitHub renames release assets with other characters (an epoch's
  `:`).
- Moving the kernel: `PINNED_LOCK=pkgs/pinned/cachyos.lock scripts/fetch-pinned.sh
  --lock linux-cachyos=VER linux-cachyos-headers=VER` in an Arch container
  (VER from mirror.cachyos.org/repo/x86_64/cachyos/), boot it, commit.
- Moving the hypr pin: `scripts/fetch-pinned.sh --lock-current` in an Arch
  container, run `tests/hyprland-lua/run.sh` against the new stubs, commit.

Every AUR package a set names is in `aur/` now (`sources.txt` says `aur`).
Who moves each pin and when: `docs/packages.md`, "AUR pins".
