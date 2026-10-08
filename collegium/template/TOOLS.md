# Tools for agents on an Invictus computer

You run as the person who uses this computer, with no sudo. Anything that changes the system goes through one command, and the person answers its password prompt themselves.

## invictus-sys

`invictus-sys [--request <your thread id>] <verb> ...`. Propose the call, say in one plain sentence what it will change and how to undo it, and let the person confirm. Never run `sudo`, `pkexec`, `pacman` or `makepkg` yourself, never edit files under `/etc`, `/usr` or `/boot`.

| Verb | What it does |
|---|---|
| `update` | update everything |
| `install <packages>` | install from the configured repositories (never the AUR; for something not there, file a package request with `invictus-report`) |
| `remove <packages>` | remove; refuses what keeps the computer working |
| `snapshot <description>` | make a safety copy now |
| `rollback <id>` | put the system back to a safety copy |
| `service enable\|disable\|restart <unit>` | from a short list of services |
| `set-config <key> on\|off` | the safety-copy switches and the desktop-style lock |
| `report-collect` | collect the error log a problem report needs |

The last line of the output is `invictus-sys: <result> snapshot=<id>`. Exit 126 means the person said no, 127 that the account is not allowed: stop and say so. The guard rails (`guardrails set ...`), full access (`set-config assistant.full-access`) and AI itself (`ai on|off`) are the person's own choices in Settings; you have no tool for them. `ai off` stops you and signs everyone out of you.

The full reference, with exit codes and polkit actions, is `docs/invictus-sys.md` in the Invictus repository.

How you reach it depends on how you run:
- **Claude Code in the Cicero panel**: the `invictus` MCP tools (`update_now`, `package_install`, `package_remove`, `snapshot`, `rollback`, `service_set`, `report_collect`, `doctor`, `acta`). They call `invictus-sys` for you, with your thread id. Without Full access you have no shell; these tools are how you act.
- **Another command-line agent** (Full access): run `invictus-sys` yourself.
- **A chat service** (no tools): write each proposed call in a fenced block, one per line, and the panel shows it as a button the person presses:

  ````
  ```invictus-sys
  install firefox
  ```
  ````

## Your own config files

Which files you may change depends on the guard rails.

- **Without Full access** (Custodia, or Libertas with Full access off): data files only. Theme files in `~/.config/invictus/themes/` (`*.toml`), the motion level in `~/.config/invictus/motion`, and waybar's style sheets (`~/.config/waybar/*.css`). Nothing else, not even under `~/.config/invictus`. Files a program executes (`~/.config/hypr/user.lua`, `monitors.lua`, waybar's config) are the person's or a tool's, because any of them can start a program. A monitor layout or a keybind is the person's to change: tell them where in Settings.
- **With Full access:** `~/.config/hypr/user.lua`, `~/.config/hypr/monitors.lua`, `~/.config/waybar/` and `~/.config/invictus/` (not `cicero.toml`, `providers/` or `theme-hooks.d/`: who answers, and what runs on a theme change, are the person's choice), and the person's own files outside the dot folders.

A copy is saved under `~/.local/state/invictus/backups/` before each change, and a change to the Hyprland config that fails `invictus-doctor --hypr` is put back. Anything else in the home, such as `~/.bashrc`, is the person's to change.

Without Full access, Claude Code's settings also deny edits to files that start programs (shell start-up files, autostart, desktop entries, git and ssh settings, and more). That list is a backstop for the rare case the guard does not answer in time, not the boundary: a file missing from it is still not yours to change unless the guard above allows it.

## invictus-doctor

`invictus-doctor` runs read-only checks and prints `ok`, `note`, `warn` or `FAIL` lines. Run it before you guess.

## Acta

`tribune acta` (or the `acta` tool) lists what `invictus-sys` changed, when, and the safety copy that undoes it. Use it to answer "what changed yesterday".
