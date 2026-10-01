# First start: `invictus-first-boot`

The wizard a person sees the first time they log in (design.md 2.3; Atrium's
screens in simple-mode.md 3.2; the assistant screen in no-ai.md 2). Built in
Beta 0.2.0 part 4 by Vulcan 2 (2026-10-01). Build notes: design.md 11, "First
start".

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

- **Never sees or stores a token.** Claude's sign-in is Claude Code's own
  (`invictus-provider login claude-code`); the command then only asks whether
  `~/.claude/.credentials.json` exists. A key for another AI service is read
  from stdin and passed on stdin to `invictus-provider use ... --key-stdin`,
  which keeps it in the keyring; it is never on a command line or in a file
  we write.
- **Root only through invictus-sys**, labelled `--request first-start` in
  Acta: `ai on` (the password, org.invictus.sys.ai-on, never kept), `ai off`
  (No AI after AI was on), `snapshot "First boot done"`.
- **monitors.lua** (design.md A6): backed up under
  `~/.local/state/invictus/backups/<time>/`, checked with
  `invictus-doctor --hypr`, put back if the check fails, then `hyprctl reload`.
  One `hl.monitor` per screen (`desc:` selector, current mode, position,
  scale, transform), a catch-all for screens plugged in later, and workspace
  1 on the main screen.

## Provider interface (for Vulcan's provider layer, `invictus-panel`)

First start never configures a provider itself. It calls one command, which
the provider layer ships in `invictus-moneta` (so it exists only after
`invictus-sys ai on` has installed the AI set). Written 2026-10-01 against a
stub, because the provider layer was not pushed yet; the tests fake it
(`tests/pkgs/firstboot.sh`). Agree changes here.

```
invictus-provider use claude-code
invictus-provider use openai-compatible --address ADDRESS [--key-stdin]
invictus-provider use local
invictus-provider use none
invictus-provider login claude-code
```

| Call | Must |
|---|---|
| `use NAME` | Make NAME the person's provider. Exit 0 when set up; non-zero otherwise (first start shows `Can't reach ADDRESS...` for a home AI system and lets the person carry on) |
| `use claude-code` | Also set `DISABLE_AUTOUPDATER=1` for Claude Code, so the package is the only update path (design.md 2.3; name checked on code.claude.com/docs/en/setup, "Disable auto-updates", 2026-10-01). Where is the layer's call: the managed settings `env`, or `~/.config/environment.d/`. `DISABLE_UPDATES` also blocks `claude update`; worth considering, since the package owns updates |
| `--address` | A host name (`atlas.local`, `atlas.local:11434`) or an `http(s)://` URL; first start has already refused anything else |
| `--key-stdin` | Read the key from stdin to EOF, store it in the keyring (`secret-tool`, the layer's own attributes), never on disk or argv |
| `use local` | The local model provider (D15), offered only when `/usr/share/invictus/providers/local/` exists |
| `login claude-code` | Run the provider's `login` from `provider.toml` with no terminal: the browser opens, and the command returns when the sign-in ends (any exit code; first start then checks the credentials file itself) |

When `ai on` is pending (no connection), the tool is not installed yet:
first start records the choice (provider name and address, never a key) in
`~/.local/state/invictus/first-boot.json` (`provider`, `provider_pending`).
The provider layer should read it the first time it runs without a provider,
or Settings > Moneta should offer it. Open question for Vulcan.

## Tests

- `tests/pkgs/firstboot.sh` (group 17 of `tests/pkgs/run.sh`): the command
  with every tool faked at the seam; monitors.lua through the stub config
  check.
- `tests/firstboot/qml.sh` (container, CI job `firstboot-qml`): qmllint with
  Quickshell's own type files, then every screen drawn by Quickshell under a
  headless sway and checked (no QML warnings, the card drawn, no gold on the
  fresh assistant screen). Renders land in the folder you pass it.
