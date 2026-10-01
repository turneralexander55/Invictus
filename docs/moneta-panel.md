# The Moneta panel and providers: interface reference

The Moneta panel (code name `tribune`) is the dropdown that Super+A shows and hides. Whoever answers in it is a **provider**: Claude Code (the default), another command-line agent, or a chat service such as a home AI system. This page is the contract for Settings > Moneta and the first-start wizard. Keep it stable; a change needs a note here and a test in `tests/pkgs/moneta_tests.py`.

Package: `invictus-tribune` (in the AI set; `invictus-moneta` pulls it, `invictus-sys ai off` removes it). Source: `scripts/moneta/`, `config/hypr/invictus/moneta.lua`. Design: `design.md` 4.2, `design-simple-mode.md` 12.3. Tests: group 17 of `tests/pkgs/run.sh`, section 7a of `tests/pkgs/e2e-sys.sh`.

## Providers

| Name | Kind | What it runs | Offered when |
|---|---|---|---|
| `claude-code` | cli | `/usr/bin/claude --plugin-dir /usr/share/invictus/claude-plugin`, with the managed settings in `/etc/claude-code` | AI is on |
| `generic-cli` | cli | the command the person sets | AI is on, guard rails **Libertas** and **Full access on** |
| `openai-compatible` | api | the panel's chat client, against the endpoint the person sets | AI is on |
| `none` | none | nothing ("No assistant is set up") | always |

A provider is `/usr/share/invictus/providers/<name>/provider.toml` (shipped, root-owned) or `~/.config/invictus/providers/<name>/provider.toml` (the person's own). Fields: `name`, `kind` (`cli`, `api`, `none`), `label`, `chat` (argv, cli only), `endpoint` and `model` (api only), `harness`, `capabilities`; `run`, `resume` and `login` are kept for the Desk and the wizard. Rules:
- A home provider never replaces a shipped one of the same name.
- Every cli provider whose command is not fixed by a shipped file (`generic-cli`, and every cli provider in a home) is "a command-line agent": offered and started only under Libertas with Full access on.
- Whether anything may run is read from root-owned state only (`/usr/lib/invictus/guardrails status`: rails, Full access, AI). If that cannot be read, only `none` is offered.

The person's choice is `~/.config/invictus/moneta.toml` (0600), written only by `invictus-provider set`:

```toml
provider = "openai-compatible"

["openai-compatible"]
endpoint = "http://192.168.1.20:11434/v1"
model = "llama3.1"
```

## invictus-provider (for Settings and the wizard)

Runs as the person. No password, nothing root.

| Command | Does | Output |
|---|---|---|
| `invictus-provider list [--json]` | the providers | JSON: `[{name, kind, label, source: system\|user, command_agent, offered, selected}]`. Show only `offered` ones. Plain: one line per offered provider, `*` marks the selected one |
| `invictus-provider get [--json]` | the selected one and whether it may run now | `{name, kind, label, permitted, why}` (+ `endpoint`, `model` for api) |
| `invictus-provider check` | may the selected one run now? | exit 0, or exit 3 and the reason on stdout |
| `invictus-provider set NAME` | select a provider | `Moneta now answers with ...` |
| `invictus-provider set generic-cli --command -- PROGRAM ARGS...` | select a command-line agent and its command | refused (3) unless offered |
| `invictus-provider set openai-compatible --endpoint URL --model M` | select a chat service | URL: `https://` anywhere; plain `http://` only to `localhost`, a private, loopback or link-local address, or a `.local`, `.lan`, `.home.arpa` or `.internal` name. No user name or password in the URL |
| `invictus-provider key set NAME` | the API key, one line on **stdin**, into the keyring | never on a command line |
| `invictus-provider key clear [NAME]` | forget the keys (every Moneta key without NAME) | |

Exit codes: 0 done, 1 failed (the keyring refused), 2 bad arguments, 3 refused (guard rails, Full access, No AI).

Keys are stored by `secret-tool` with the attributes `invictus-namespace invictus/provider`, `provider NAME`, `endpoint URL`. The endpoint is part of the lookup, so a key typed for one endpoint is never sent to another (an edited `moneta.toml` finds no key). `ai off` clears the namespace (design-no-ai.md N4: `invictus-provider key clear` in the caller's session; `invictus-session` for the others, not built yet).

First start (wizard): after `invictus-sys ai on`, Claude path: `invictus-provider set claude-code`, then the provider's `login` argv (`claude auth login`) in a terminal. Home AI path: `invictus-provider set openai-compatible --endpoint ... --model ...`, then `key set` only if the service needs a key. No AI path: nothing here.

## The panel (tribune)

- **Super+A** toggles the special workspace `moneta`. Its first show starts `kitty --class invictus-moneta --title Moneta /usr/bin/tribune` (workspace rule `on_created_empty`). On a No AI computer `moneta.lua` is not on disk and there is no bind.
- `tribune` (= `tribune run`) shows the last three Acta lines, then starts the selected provider in its own process group, in the foreground of the terminal, with `INVICTUS_THREAD` (the thread id, for `invictus-sys --request`) and `INVICTUS_PROVIDER` in its environment. When the provider ends, Enter starts it again.
- For an api provider it starts `tribune chat`: the person types, the reply streams in with every control byte removed (no terminal escape sequences), and each `invictus-sys` call the model proposes in a fenced `invictus-sys` block becomes a numbered button. Only the person's number and Enter run one, as `invictus-sys --request THREAD VERB ARGS` with no shell, through the same polkit prompt. Proposals are limited to `update`, `install`, `remove`, `snapshot`, `rollback`, `service`, `set-config nets.*|flavor.lock` and `report-collect`; no argument may start with `-`.
- `tribune acta [-n N]` lists the last invictus-sys calls (Acta) with the thread that asked. The system journal needs an administrator account to read.

### The socket

`$XDG_RUNTIME_DIR/invictus/tribune.sock` (folder 0700, socket 0600). One line per connection, at most 64 bytes, only from root or the person (SO_PEERCRED):

| Message | Panel does |
|---|---|
| `restart-profile` | SIGTERM to the agent's process group and every process it left behind (the panel is a child subreaper), SIGKILL after 5 s, says `Moneta is starting again with the new rules.`, checks again whether the provider may run, starts it or shows why not |
| `stop` | the same end, says `Moneta stopped: AI was turned off on this computer.`, removes the socket and exits |
| anything else | ignored |

A second panel finds the first one's socket answering and exits 3.

## The Claude Code side

- Managed settings: `/etc/claude-code/managed-settings.json`, a link `guardrails apply` points at `/usr/share/invictus/guardrails/claude/fixed.json` or `full.json` (invictus-guardrails, on every machine). Both carry A7's deny rules, bypass and auto mode off, `DISABLE_UPDATES`, and the A6 guard as managed hooks; the fixed one also denies Bash and NotebookEdit and allows only managed hooks.
- The A6 guard: `/usr/lib/invictus/claude-config-guard pre fixed|full` (PreToolUse on Edit, Write, NotebookEdit) and `post` (PostToolUse). See `TOOLS.md` for the allowlist.
- The plugin: `/usr/share/invictus/claude-plugin/` with the `invictus-tools` skill (`collegium/template/TOOLS.md`) and the MCP server `invictus` (`/usr/lib/invictus/moneta/mcp.py`): `doctor`, `acta`, `update_now`, `snapshot`, `package_install`, `package_remove`, `service_set`, `rollback`, `report_collect`. No tool for the guard rails, Full access or AI on/off.
- Updates: the package's `/usr/bin/claude` wrapper and the managed `env` both set `DISABLE_UPDATES=1`; Claude Code updates come with `invictus-sys update` like everything else.
