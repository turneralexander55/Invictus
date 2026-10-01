# invictus-sys: verb reference

`invictus-sys` is the only door to root on Invictus (design 4.1). Settings, the Help panel, the Moneta panel (part 6), the Desk and people in a terminal all call the same command. This page is the contract: verbs, arguments, polkit action ids, output and exit codes. Change it only with a design note, a test and, for anything in the Custodia tier 1 list, Minerva's review (SM22 standing rule).

Packages: `invictus-sys` (the command, the root helper, the polkit policy, the shared libs, `ai-signout`, `ai-pending` and its service) and `invictus-guardrails` (the guard rails it switches). Source: `scripts/sys/`, `scripts/guardrails/`, `scripts/lib/{sys-verbs,pacman,acta,guardrails-state,ai-set}.sh`. Tests: `tests/pkgs/sys.sh` (groups 14 to 16 of `tests/pkgs/run.sh`).

## How a call works

```
invictus-sys [--request ID] VERB ARGS
  -> checks the arguments (no password is asked for a typo)
  -> pkexec /usr/lib/invictus/invictus-sys ROOTVERB ARGS
       pkexec picks org.invictus.sys.ROOTVERB from argv[1]
       (policy annotation org.freedesktop.policykit.exec.argv1)
  -> the root helper checks again, takes the snapshot, acts, logs to Acta
```

Running as root (installer, a root terminal) skips pkexec. Every verb is its own polkit action, so a password typed for one never covers another (MUST A10). The polkit messages carry no arguments: the root helper checks them only after the password, and any program can call pkexec directly. The Invictus polkit agent shows plain words from `/usr/share/invictus/guardrails/messages.tsv` instead (G1), filling `{args}` only after `sys_validate` accepts them.

`--request ID` (letters, digits, `._:-`, up to 64) labels the call in Acta: the Moneta panel passes its thread id. It is read from the environment of the process that ran pkexec, so it is a label, never trusted for anything else.

## Verbs

| Command | Root verb and polkit action `org.invictus.sys.*` | Libertas | Custodia | What it does |
|---|---|---|---|---|
| `update` | `update` | password, kept 5 min | tier 1: no password at your own desktop (wheel) | as root: `invictus-update --noconfirm --system` (`pacman -Syu`, then the doctor's system checks; nothing in any home is read); without `invictus-tools`, `pacman -Syu` alone. Then, as you: `invictus-doctor --post-update --user` (your Hyprland config and defaults) and your waybar counter; exit 3 if that finds a problem |
| `install PKG...` | `install` | password, kept | password, kept | `pacman -Syu --needed --noconfirm -- PKG...`: the configured repos only, never `-Sy` alone (A3, A4). 1 to 64 names; no options, paths, URLs |
| `remove PKG...` | `remove` | password, kept | password, kept | `pacman -Rs --noconfirm -- PKG...`; refused if the names, or anything pacman would take with them, are in `/usr/share/invictus/sys/protected-packages` |
| `snapshot DESCRIPTION...` | `snapshot` | password, kept | tier 1 | a single snapper snapshot of `/`, important, number cleanup; description cut to 200 bytes |
| `rollback ID` | `rollback` | password, kept | password, kept | booted into snapshot ID: `limine-snapper-restore`. Otherwise writes `/var/lib/invictus/rollback-pending` and says how to pick it in the boot menu. Never restarts the computer |
| `service enable\|disable\|restart UNIT` | `service` | password, kept | password, kept | `systemctl enable --now`, `disable --now` or `restart`, for units in `/usr/share/invictus/sys/services.allow` only |
| `set-config KEY on\|off` | `set-config` | password, kept | `nets.*` refused | keys: `nets.pre-admin-snapshot`, `nets.auto-update`, `nets.boot-guard`, `nets.home-snapshots` (`/etc/invictus/nets`), `flavor.lock` (`/etc/invictus/flavor.lock`) |
| `set-config assistant.full-access on\|off` | `assistant-full-access` | password, never kept | refused | `/etc/invictus/assistant`; `on` also needs AI on (`/etc/invictus/ai`); relinks the managed profile and tells the Moneta panel |
| `ai on` | `ai-on` | password, never kept | password, never kept | `/etc/invictus/ai` on; removes our browser policy; `pacman -Syu --needed -- invictus-moneta`. No connection: result `pending`, `/var/lib/invictus/ai-install-pending`, and `invictus-ai-pending.service` installs it later (only while AI still reads on) |
| `ai off` | `ai-off` | no password from your own active desktop; elsewhere a password | same | No AI: `/etc/invictus/ai` off, pending install cancelled, full access off, the Moneta panel told `stop`, the Firefox `GenerativeAI` policy written (never over someone else's `policies.json`), each person signed out by a process running as them (`claude auth logout` for you only, then `~/.claude/.credentials.json` and the `oauthAccount` block; memory kept), `/var/lib/invictus/ai-off-pending/<uid>` for their keyring at next login, then `pacman -Rs` of the installed AI set |
| `report-collect` | `report-collect` | password, kept | tier 1 | this boot's errors from the journal to `/var/lib/invictus/report/` (root:wheel 0640, last 5 kept). Sends nothing |
| `guardrails set libertas [--for 1h]` | `guardrails-libertas` | (already) | password, never kept; agent hold list | snapshot "Before: guard rails off" first, then the switch; `--for` 1m to 7d writes `/etc/invictus/guardrails-until` and arms the expiry timer |
| `guardrails set custodia` | `guardrails-custodia` | no password from your own active desktop; elsewhere a password | (already) | instant switch; clears cached sudo and polkit credentials; turns full access off |
| `guardrails status` | none (no root) | | | `key=value` lines: `rails`, `effective`, `until`, `since`, `by`, `full-access`, `ai`, `net.<name>` |
| `guardrails check` | none (no root) | | | would `apply` change anything? exit 1 and one line per difference if so |
| `guardrails apply`, `guardrails expire` | none: root only | | | installer, package hook, boot service, timer |
| `vm start\|stop` | none (runs as you) | | | placeholder for the Windows module (0.4.0); exits 3 |
| `help` | | | | the list |

"Kept" is polkit's `auth_admin_keep` (about five minutes, per verb). Tier 1 is the rule `/etc/polkit-1/rules.d/40-invictus-custodia.rules`, present only under Custodia: `update`, `snapshot`, `report-collect` for a member of `wheel` at a local active session.

Not built yet, with hooks left: `update-undo`, `update-pause` (unattended updates, next job), `help start|stop|unlock|shell` (remote help), `helper-ask`, `inbox enrol|disconnect` (design-inbox.md). Each will be its own root verb and polkit action, added to the table above.

## Output and exit codes

Each call to the root helper ends with one line on stdout:

```
invictus-sys: RESULT snapshot=ID|none
```

RESULT is `ok`, `ok, the doctor found a problem` (update), `pending` (rollback; `ai on` with no connection), `refused`, `bad-arguments`, `busy` or `failed`. For pacman verbs the snapshot is snap-pac's pre snapshot (or invictus-sys's own pre when snap-pac is missing); for `service`, `set-config` and `ai on|off`, invictus-sys's pre; for `snapshot`, the new one; for `guardrails set libertas`, "Before: guard rails off".

| Exit | Meaning |
|---|---|
| 0 | done |
| 1 | the change failed (pacman, systemctl or snapper said no) |
| 2 | bad arguments; nothing asked, nothing run |
| 3 | refused: guard rails, a protected package, no safety copy possible, No AI, or not set up |
| 4 | another guard-rails change is running |
| 126 | the password prompt was cancelled (pkexec) |
| 127 | not allowed (polkit said no), or pkexec could not run |

## Acta

Every call writes one journal entry, `SYSLOG_IDENTIFIER=invictus-sys`, with fields `INVICTUS_VERB`, `INVICTUS_ARGS`, `INVICTUS_SNAPSHOT`, `INVICTUS_RESULT`, `INVICTUS_SESSION` (logind session of the caller), `INVICTUS_REQUEST`, `INVICTUS_UID`, `INVICTUS_USER`. `INVICTUS_SESSION` and `INVICTUS_REQUEST` are labels the caller controls, not proof of who asked; `INVICTUS_UID` comes from pkexec and can be trusted. Guard-rails switches add `INVICTUS_FROM`, `INVICTUS_TO`, `INVICTUS_HOW` (`password`, `click`, `expired`, `expired while the computer was off, applied HH:MM`), `INVICTUS_UNTIL`, `INVICTUS_FULL_ACCESS_WAS`; the pre-admin snapshot adds `INVICTUS_PAM_SERVICE`, `INVICTUS_PAM_USER`. Read it with:

```
journalctl -t invictus-sys -o json
```

## For the Moneta panel (part 6)

- Call `invictus-sys --request <thread id> VERB ...` as the user; never `pkexec` or the root helper directly.
- Read the last stdout line for the result and snapshot id; read the exit code for the outcome. 126 means the person said no; say so and stop.
- After a guard-rails or full-access change, the panel receives `restart-profile\n` on its socket `/run/user/<uid>/invictus/tribune.sock` (create it in your own `/run/user/<uid>`; root connects as you, and skips a folder not owned by its uid). End the running agent (SIGTERM to its process group, SIGKILL after 5 s) and start it again: `/etc/claude-code/managed-settings.json` already points at the right profile. On `ai off` it receives `stop\n`: end the agent the same way, then exit.
- The panel decides nothing about tiers: polkit does. A Custodia tier 1 verb simply gets no prompt.
- Notices: `/run/invictus/guardrails-notice` holds the last switch's message ("Guard rails are back on"); `invictus-session` (not built yet) shows it.
