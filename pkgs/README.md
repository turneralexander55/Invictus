# Packages

One PKGBUILD per directory. `scripts/build-repo.sh` builds them all into a
pacman repo; `.github/workflows/packages.yml` does the same in CI, signs and
publishes to the `invictus-testing` release.

| Folder | What goes there | Now |
|---|---|---|
| `own/` | Our own packages | `invictus-keyring` |
| `meta/` | Depends-only packages that pull a set of software | `invictus-base`, `-desktop`, `-gaming`, `-dev` |
| `aur/` | AUR PKGBUILDs copied at a reviewed commit, with checksums. Never built from a live AUR checkout | Empty. Phase 1 adds the AUR packages the metas name (zen-browser-bin, nordic-darker-theme, xwaylandvideobridge, proton-ge-custom-bin, claude-code, limine-mkinitcpio-hook, limine-snapper-sync) |
| `pinned/` | The hypr* binary set copied from Arch at a tested version | Empty. Phase 1 |

Until `aur/` is filled, the metas build but do not install: pacman stops with
"target not found" for the AUR names. In Phase 0 only `invictus-keyring` is
meant to be installed.
