# Tools for agents on an Invictus machine

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

## invictus-doctor

`invictus-doctor` runs read-only checks and prints `ok`, `note`, `warn` or `FAIL` lines. Run it before you guess.
