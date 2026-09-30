# Packages

One PKGBUILD per directory. `scripts/build-repo.sh` builds them all into a
pacman repo; `.github/workflows/packages.yml` does the same in CI, signs and
publishes to the `invictus-testing` release.

| Folder | What goes there | Now |
|---|---|---|
| `own/` | Our own packages. They install files from elsewhere in this repo (`scripts/`, `config/`, `theme/`, `assets/`), found at `$startdir/../../..`; `build-repo.sh` stages the whole checkout | `invictus-keyring`, `invictus-tools`, `invictus-branding` |
| `meta/` | Packages that pull a set of software. `invictus-desktop` also carries the desktop config and the first-login unit | `invictus-base`, `-desktop`, `-gaming`, `-dev` |
| `aur/` | AUR PKGBUILDs copied at a reviewed commit, with checksums, and the upstream signing key in `keys/pgp/` when the source is signed. Never built from a live AUR checkout | `xwaylandvideobridge` |
| `pinned/` | `hypr.lock`: the exact Arch files of the hypr* set, fetched and verified by `scripts/fetch-pinned.sh` at build time. No binaries in git | 16 packages, Hyprland 0.56.2-3 |

Rules:
- Bump `pkgrel` whenever a file a PKGBUILD installs changes. CI reuses a
  published package with the same file name instead of rebuilding it.
- Repo file names only use `[A-Za-z0-9._-]` (`scripts/lib/repo-names.sh`),
  because GitHub renames release assets with other characters (an epoch's
  `:`).
- Moving the pin: `scripts/fetch-pinned.sh --lock-current` in an Arch
  container, run `tests/hyprland-lua/run.sh` against the new stubs, commit.

Still AUR-only and not in `aur/` yet (the metas name them; a machine must
have them from paru until they are added): `zen-browser-bin`,
`nordic-darker-theme` (desktop), `proton-ge-custom-bin` (gaming),
`claude-code` (dev), `limine-mkinitcpio-hook`, `limine-snapper-sync` (base).
`scripts/dev/adopt.sh` lists any that are missing before it changes anything.
