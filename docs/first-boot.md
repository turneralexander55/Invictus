# First start: `invictus-first-boot`

The wizard a person sees the first time they log in (design.md 2.3; Atrium's
screens in simple-mode.md 3.2; the assistant screen in no-ai.md 2). Built in
Beta 0.2.0 part 4 by Vulcan 2 (2026-10-01). Build notes: design.md 11, "First
start" (notes 38 to 46).

## Pieces

| Piece | Where | What it does |
|---|---|---|
| The command | `scripts/first-boot/invictus-first-boot` (`/usr/bin`, invictus-tools) | Everything but drawing: which steps, monitors.lua, look, the assistant calls, sign-in check, the snapshot, run-once state. Each subcommand prints one JSON line |
| The screens | `quickshell/first-boot/*.qml` (`/usr/share/invictus/first-boot/`) | Quickshell 0.3: one window per screen on the Bottom layer (the browser and the password prompt open above it); `Step<Name>.qml` per step; colours from `~/.config/invictus/current/qml-tokens.json` (theme template `qml-tokens.json`) |
| Run once | `first-login` runs `invictus-first-boot mark-pending` on a new home (not `--adopt`, not a home the old hyprdots scripts set up); Hyprland's autostart runs `invictus-first-boot start --if-pending` | `~/.local/state/invictus/first-boot.pending`, then `first-boot.done` |
| Run again | `invictus-first-boot start --again` | For Settings (not built yet): the same screens on a finished home |

## Steps

| Step | Atrium | Tessera | Screen file | Command |
|---|---|---|---|---|
| Wi-Fi | when offline | | not built (hook) | |
| Which screen is in front of you? | with 2+ screens | | `StepScreens.qml` | `monitors-write NAME` (60 s: `auto`) |
| 1 Monitors | | with 2+ screens | `StepMonitors.qml` | `monitors-write MAIN NAME=X,Y...` |
| 2 Look | not asked: Dusk, Calm, light apps at `finish` | yes | `StepLook.qml` | `look THEME MOTION light\|dark` |
| 3 How should Help work? | yes | yes | `StepAssistant.qml` | `assistant ...`, `signin` |
| 4 Collegium | | AI only | not built (hook) | |
| 5 Windows | | | not built (hook) | |
| 6 Voice | | AI only | not built (hook) | |
| 7 Three things to know / tour | yes | yes | `StepReady.qml` | `finish` |

One screen and no monitors step: `finish` first runs `monitors-write auto`,
so monitors.lua always says what the computer has.

**A hook** is a step id in `STEPS` (the command) with no screen file yet. A
later release adds `Step<Name>.qml` (it gets `wiz`, `theme` and `screenName`
like the others, and calls `wiz.next()`), and a subcommand if it needs one.
`needs_ai` steps drop out after No AI. Atrium asks no look question: `finish`
applies the theme in use (Dusk on a new home), Calm and light apps.

## Rules it keeps

- **Never sees or stores a token.** Claude's sign-in is Claude Code's own:
  the `login` argv of the shipped `/usr/share/invictus/providers/claude-code/provider.toml`
  (a file in the home is never read for it, and the program must be a plain
  `/usr/bin/NAME`: no `..`, `.` or `//`), run in a terminal. The command then only asks whether
  `~/.claude/.credentials.json` exists. A key for another AI service is read
  from stdin and passed on stdin to `invictus-provider key set`, which keeps
  it in the keyring; it is never on a command line or in a file we write.
- **Root only through invictus-sys**, labelled `--request first-start` in
  Acta: `ai on` (the password, org.invictus.sys.ai-on, never kept), `ai off`
  (No AI after AI was on), `snapshot "First boot done"`.
- **monitors.lua** (design.md A6): backed up under
  `~/.local/state/invictus/backups/<time>/`, checked with
  `invictus-doctor --hypr`, put back if the check fails, then `hyprctl reload`.
  One `hl.monitor` per screen (`desc:` selector, current mode, position,
  scale, transform), a catch-all for screens plugged in later, and workspace
  1 on the main screen.

- **Test overrides only from a checkout.** The `INVICTUS_*` variables the
  tests use (`INVICTUS_SHARE`, `INVICTUS_TERMINAL`, ...) are read through
  `scripts/lib/invictus_env.py`; an installed copy (under `/usr/`) ignores
  them, and the installed screens always call `/usr/bin/invictus-first-boot`.
  So nothing in a session's environment chooses the provider file, the
  terminal, or the program a key goes to.
- **monitors.lua backups** get a folder of their own each time (two writes in
  one second keep both). Writing the same text again changes nothing and
  runs no check. A `monitors.lua` that is a symlink (a dotfiles repo) is
  replaced by a plain file when the layout changes; the old target is in the
  backup.
- **Wi-Fi passwords are the one exception** (Alex, 2026-10-01,
  `team/decisions.md`): NetworkManager keeps them in its system-owned,
  root-only connection files, so the computer joins Wi-Fi before anyone logs
  in. Every other secret stays in the person's keyring. (The Wi-Fi screen
  itself is a later release.)

## The provider layer

The contract is `docs/moneta-panel.md` (Vulcan, branch `invictus-panel`);
first start calls only what it documents, after `invictus-sys ai on` has
installed the AI set (and `invictus-provider` with it):

| Choice | Calls |
|---|---|
| Claude | `invictus-provider set claude-code`, then the provider's `login` in a terminal |
| A home AI system | `invictus-provider set openai-compatible --endpoint URL`. What the person types becomes the URL: `atlas.local` is `http://atlas.local:11434/v1` (an ollama-style server); a full `http(s)://` address is used as typed. No key |
| Another AI service | `set openai-compatible --endpoint URL` (a bare host becomes `https://HOST/v1`), then `key set openai-compatible` with the key on stdin |
| No AI | nothing here |

`invictus-provider` exits 2 or 3 (an endpoint it will not take, or not
allowed): the screen says `That address can't be used...`. Exit 1 (the
keyring refused the key): `The key couldn't be saved...`. Moneta stays on in
both cases and the person can carry on with `Later`.

Updates: Claude Code's `DISABLE_UPDATES=1` is in the managed profiles and
the package's wrapper (the panel's side); first start sets nothing for it.

**Offline.** When `ai on` comes back `pending`, the packages and
`invictus-provider` arrive later. First start keeps the choice in
`~/.local/state/invictus/first-boot.json` (`provider: {choice, endpoint}`,
`provider_pending: true`), never the key. Every session start runs
`invictus-first-boot start --if-pending` from Hyprland's autostart, and
`start` first runs `apply-pending`: once `invictus-provider` is installed
and AI still reads on, it makes the same `set` call and clears the flag (if
AI was turned off meanwhile, the choice is dropped). A choice
`invictus-provider` refuses (exit 2 or 3) is tried once and then dropped,
with `provider_result` recorded; a kept record that is not well formed is
dropped too, and nothing in this step can stop the wizard from opening. A key for another
service is never kept, so that person adds it in Settings > Moneta, which
shows the Not signed in card; a Claude person signs in from Help's card
(no-ai.md 2.3). No change to the panel is needed.

## Tests

- `tests/pkgs/firstboot.sh` (group 18 of `tests/pkgs/run.sh`): the command
  with every tool faked at the seam; monitors.lua through the stub config
  check.
- `tests/firstboot/qml.sh` (container, CI job `firstboot-qml`): qmllint with
  Quickshell's own type files, then every screen drawn by Quickshell under a
  headless sway and checked (no QML warnings, the card drawn, no gold on the
  fresh assistant screen). Renders land in the folder you pass it.
