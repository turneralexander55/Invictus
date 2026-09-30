# Legacy install scripts (frozen)

These are the old `hyprdots` install and deploy scripts. They are kept only so
Alex's current machine keeps working until Phase 1 ships `scripts/dev/adopt.sh`
and the `invictus-*` packages. Do not extend them. They will be deleted once
the adopt script lands.

| Script | What it did | Replaced by (design section 1.2) |
|---|---|---|
| `install.sh` | Runs the steps below in order | The ISO, Calamares and first boot |
| `install-packages.sh` | Installs `packages/pacman.txt` and `packages/aur.txt` | The meta packages in `pkgs/meta/` |
| `deploy-configs.sh --force` | Copies `config/*` into `~/.config` | `invictus-desktop` plus first-login copy-once |
| `deploy-shell.sh --force` | Copies `config/shell/zshrc` to `~/.zshrc` | Same |
| `init-user.sh` | XDG dirs, user services, caches | `invictus-first-login` |
| `install-sddm.sh` | Installs the blackglass SDDM theme from `assets/SDDM/blackglass`. That folder was never in the repo: commit 9c8d008 added only a submodule pointer (gitlink to commit 3a1a7e4 of an unnamed repo, no `.gitmodules`), so the script has always stopped with "Theme source not found". The dead pointer is removed | `invictus-sddm-theme` |
| `update.sh` | `git pull` plus `pacman -Syu` and `paru -Sua` | `invictus-update` |

`scripts/update.sh` is a two-line forwarder to `legacy/update.sh`, because the
deployed waybar config calls that path.

Known issues left as they are: `update.sh` auto-stashes local changes on a
non-developer checkout (the team rule is never to stash; `invictus-update`
drops this), and `packages/*.txt` still list `vscode` and miss some
dependencies (fixed in `pkgs/meta/`, not here).

Run from the repo root, for example `./legacy/install.sh`.
