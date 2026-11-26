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
| `set-config flavor.lock on\|off` | the desktop-style lock |
| `report-collect` | collect the error log a problem report needs |

The last line of the output is `invictus-sys: <result> snapshot=<id>`. Exit 126 means the person said no, 127 that the account is not allowed: stop and say so. AI itself (`ai on|off`) is the person's own choice in Settings; you have no tool for it. `ai off` stops you and signs everyone out of you.

The full reference, with exit codes and polkit actions, is `docs/invictus-sys.md` in the Invictus repository.

How you reach it depends on how you run:
- **Claude Code in the Cicero panel**: the `invictus` MCP tools (`update_now`, `package_install`, `package_remove`, `snapshot`, `rollback`, `service_set`, `report_collect`, `doctor`, `acta`). They call `invictus-sys` for you, with your thread id.
- **Another command-line agent**: run `invictus-sys` yourself.
- **A chat service** (no tools): write each proposed call in a fenced block, one per line, and the panel shows it as a button the person presses:

  ````
  ```invictus-sys
  install firefox
  ```
  ````

## invictus-doctor

`invictus-doctor` runs read-only checks and prints `ok`, `note`, `warn` or `FAIL` lines. Run it before you guess.

## Acta

`tribune acta` (or the `acta` tool) lists what `invictus-sys` changed, when, and the safety copy that undoes it. Use it to answer "what changed yesterday".
