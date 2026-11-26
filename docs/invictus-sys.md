# invictus-sys: verb reference

`invictus-sys` is the only door to root on Invictus (design 4.1). Settings, the Help panel, the Cicero panel (part 6), the Desk and people in a terminal all call the same command. This page is the contract: verbs, arguments, polkit action ids, output and exit codes. Change it only with a design note and a test.

Package: `invictus-sys` (the command, the root helper, the polkit policy, the shared libs, `ai-signout`, `ai-pending` and its service). Source: `scripts/sys/`, `scripts/lib/{sys-verbs,pacman,acta,ai-set}.sh`. Tests: `tests/pkgs/sys.sh` (groups 14 to 16 of `tests/pkgs/run.sh`).

## How a call works

```
invictus-sys [--request ID] VERB ARGS
  -> checks the arguments (no password is asked for a typo)
  -> pkexec /usr/lib/invictus/invictus-sys ROOTVERB ARGS
       pkexec picks org.invictus.sys.ROOTVERB from argv[1]
       (policy annotation org.freedesktop.policykit.exec.argv1)
  -> the root helper checks again, takes the snapshot, acts, logs to Acta
```

Running as root (installer, a root terminal) skips pkexec. Every verb is its own polkit action, so a password typed for one never covers another (MUST A10). The polkit messages carry no arguments: the root helper checks them only after the password, and any program can call pkexec directly.

`--request ID` (letters, digits, `._:-`, up to 64) labels the call in Acta: the Cicero panel passes its thread id. It is read from the environment of the process that ran pkexec, so it is a label, never trusted for anything else.

## Verbs

| Command | Root verb and polkit action `org.invictus.sys.*` | Password | What it does |
|---|---|---|---|
| `update` | `update` | password, kept 5 min | as root: `invictus-update --noconfirm --system` (`pacman -Syu`, then the doctor's system checks; nothing in any home is read); without `invictus-tools`, `pacman -Syu` alone. Then, as you: `invictus-doctor --post-update --user` (your Hyprland config and defaults) and your waybar counter; exit 3 if that finds a problem |
| `install PKG...` | `install` | password, kept | `pacman -Syu --needed --noconfirm -- PKG...`: the configured repos only, never `-Sy` alone (A3, A4). 1 to 64 names; no options, paths, URLs |
| `remove PKG...` | `remove` | password, kept | `pacman -Rs --noconfirm -- PKG...`; refused if the names, or anything pacman would take with them, are in `/usr/share/invictus/sys/protected-packages` |
| `snapshot DESCRIPTION...` | `snapshot` | password, kept | a single snapper snapshot of `/`, important, number cleanup; description cut to 200 bytes |
| `rollback ID` | `rollback` | password, kept | booted into snapshot ID: `limine-snapper-restore`. Otherwise writes `/var/lib/invictus/rollback-pending` and says how to pick it in the boot menu. Never restarts the computer |
| `service enable\|disable\|restart UNIT` | `service` | password, kept | `systemctl enable --now`, `disable --now` or `restart`, for units in `/usr/share/invictus/sys/services.allow` only |
| `set-config KEY on\|off` | `set-config` | password, kept | key: `flavor.lock` (`/etc/invictus/flavor.lock`) |
| `ai on` | `ai-on` | password, never kept | `/etc/invictus/ai` on; removes our browser policy; `pacman -Syu --needed -- invictus-cicero`. No connection: result `pending`, `/var/lib/invictus/ai-install-pending`, and `invictus-ai-pending.service` installs it later (only while AI still reads on) |
| `ai off` | `ai-off` | password, never kept | No AI: `/etc/invictus/ai` off, pending install cancelled, the Firefox `GenerativeAI` policy written (never over someone else's `policies.json`), each person signed out by a process running as them (`claude auth logout` for you only, then `~/.claude/.credentials.json` and the `oauthAccount` block; memory kept), `/var/lib/invictus/ai-off-pending/<uid>` for their keyring at next login, then `pacman -Rs` of the installed AI set |
| `report-collect` | `report-collect` | password, kept | this boot's errors from the journal to `/var/lib/invictus/report/` (root:wheel 0640, last 5 kept). Sends nothing |
| `vm start\|stop` | none (runs as you) |  | placeholder for the Windows module (0.4.0); exits 3 |
| `help` | | | the list |

"Kept" is polkit's `auth_admin_keep` (about five minutes, per verb). No Invictus polkit rule skips a password.

Not built yet, with hooks left: `update-undo`, `update-pause` (unattended updates, next job), `help start|stop|unlock|shell` (remote help), `helper-ask`, `inbox enrol|disconnect` (design-inbox.md). Each will be its own root verb and polkit action, added to the table above.

## Output and exit codes

Each call to the root helper ends with one line on stdout:

```
invictus-sys: RESULT snapshot=ID|none
```

RESULT is `ok`, `ok, the doctor found a problem` (update), `pending` (rollback; `ai on` with no connection), `refused`, `bad-arguments`, `busy` or `failed`. For pacman verbs the snapshot is snap-pac's pre snapshot (or invictus-sys's own pre when snap-pac is missing); for `service`, `set-config` and `ai on|off`, invictus-sys's pre; for `snapshot`, the new one.

| Exit | Meaning |
|---|---|
| 0 | done |
| 1 | the change failed (pacman, systemctl or snapper said no) |
| 2 | bad arguments; nothing asked, nothing run |
| 3 | refused: a protected package, no safety copy possible, No AI, or not set up |
| 126 | the password prompt was cancelled (pkexec) |
| 127 | not allowed (polkit said no), or pkexec could not run |

## Acta

Every call writes one journal entry, `SYSLOG_IDENTIFIER=invictus-sys`, with fields `INVICTUS_VERB`, `INVICTUS_ARGS`, `INVICTUS_SNAPSHOT`, `INVICTUS_RESULT`, `INVICTUS_SESSION` (logind session of the caller), `INVICTUS_REQUEST`, `INVICTUS_UID`, `INVICTUS_USER`. `INVICTUS_SESSION` and `INVICTUS_REQUEST` are labels the caller controls, not proof of who asked; `INVICTUS_UID` comes from pkexec and can be trusted. Read it with:

```
journalctl -t invictus-sys -o json
```

## For the Cicero panel (part 6)

Built in `invictus-tribune` (branch invictus-panel); its own contract, including the provider setup the wizard calls, is `docs/cicero-panel.md`. What it relies on here:


- Call `invictus-sys --request <thread id> VERB ...` as the user; never `pkexec` or the root helper directly.
- Read the last stdout line for the result and snapshot id; read the exit code for the outcome. 126 means the person said no; say so and stop.
- Whether a provider may run comes from `/etc/invictus/ai` (root-owned), never from the person's own config.
