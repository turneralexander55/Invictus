# Reuse catalog

Shared pieces in this repo. Search here, then the code, before building
anything new (charter rule "Reuse before building"). The lead engineer who
merges a new shared piece adds it here in the same merge.

Each entry: what it is, where it lives, how to reuse it, and its tests.

## Config and desktop

| Piece | Where | Reuse it for | Tests |
|---|---|---|---|
| Hyprland loader | `config/hypr/hyprland.lua` | The only file in `~/.config/hypr` that loads our modules. Puts `/usr/share/invictus/hypr/?.lua` first on `package.path` (once per reload), requires `invictus.core`, then `monitors.lua` and `user.lua` from the config dir if present. Anything that needs to add config for a user writes `user.lua` or `monitors.lua`, never the shipped modules | `tests/hyprland-lua` (five loader tests) |
| Shipped Hyprland modules | `config/hypr/invictus/*.lua`, listed in `invictus/core.lua` | New desktop behaviour goes in a module here and a `require` line in `core.lua` | `tests/hyprland-lua` |
| App defaults table | `config/hypr/invictus/variables.lua` | `local apps = require("invictus.variables")` for terminal, launcher, browser, file manager and the main modifier. Do not hardcode `kitty` or `SUPER` elsewhere | `tests/hyprland-lua` |
| Bind helper and descriptions | `config/hypr/invictus/binds.lua` (`bind(keys, dispatcher, "Section: action", flags)`) | Every bind carries a "Section: action" description; the cheatsheet and anything that lists binds read it from `hyprctl binds` | `tests/hyprland-lua` (description format, old binds) |
| Confirm dialog | `scripts/confirm.sh` | `confirm.sh "Prompt?" -- command args`: a yes/no rofi menu, default No, only an exact "Yes" runs the command. Use it for any destructive bind (power off, log out). The `ROFI` env var swaps in a fake for tests | `tests/hyprland-lua/run.sh` section 4 |
| Keybinding cheatsheet | `scripts/show-keybindings.sh` | Lists live binds grouped by section from `hyprctl binds`; `--stdout` for text. `HYPRCTL` swaps in a fake | `tests/hyprland-lua/run.sh` section 3 |
| Waybar data scripts | `scripts/waybar/{cpu,gpu,memory,updates}.sh` | JSON (`text`, `tooltip`, `class`) for waybar custom modules. Forum's health and update cards should read these, not re-measure (design 1.2). `updates.sh` caches `checkupdates` for 5 minutes behind a lock | none yet (Phase 1, Felix) |
| Theme tool and tokens | `theme/invictus-theme`, `theme/*.toml`, `theme/templates/*` | Colours for any surface come from the theme tokens (`night`, `sol`, `marble`, ...) through a template in `theme/templates/`, never hardcoded. `invictus-theme generate/apply` writes per-app files; Hyprland reads `hyprland-colors.lua`, web pages `desk-tokens.css` | `tests/theme/run.sh` |

## Packaging and CI

| Piece | Where | Reuse it for | Tests |
|---|---|---|---|
| Repo build script | `scripts/build-repo.sh` | Building any `pkgs/*/*/PKGBUILD` into `[invictus-testing]`, locally (Arch or a container) or in CI. Reuses published versions, signs in a separate step | `tests/pkgs/e2e-arch.sh` |
| Meta package pattern | `pkgs/meta/*/PKGBUILD` | New software sets are a depends-only meta. Every command the Hyprland config runs must map to a package in a meta (`COMMAND_PACKAGES` in `tests/hyprland-lua/run.lua`) | `tests/hyprland-lua`, `tests/pkgs/run.sh` |
| Keyring package | `pkgs/own/invictus-keyring` | The one place the repo's public key lives; `invictus-trusted` is derived from it at build time | `tests/pkgs/run.sh`, `tests/pkgs/e2e-arch.sh` |
| Lua config test harness | `tests/hyprland-lua/` (`mock_hl.lua` checks every `hl.*` call against the 0.56.2 stubs and xkbcommon keysyms; `hyprlang.lua` parses old `.conf` files; `run.lua` emulates Hyprland's `require`) | Testing any Hyprland Lua without Hyprland, including `invictus-doctor --hypr` (design 1.5), which should load the config through this mock rather than a new one | itself |
| Signed-repo end-to-end test | `tests/pkgs/e2e-arch.sh` | Any change to signing, repo layout or the keyring: builds, signs with a throwaway key, installs with `SigLevel = Required` in a container | itself |
| Pinned CI tools | `.github/workflows/checks.yml` | Actions pinned by commit, binaries by checksum. Copy the gitleaks install step for any new downloaded tool | CI |
