# Invictus: No AI

Status: design, not yet built. Owner: Venus (designer). Date: 2026-09-30.
Asked for by Alex (2026-09-30): "there should be a 3rd option... No harness. Not everyone is thrilled with AI."

This is the one place for the rule and everything it touches, and the only place the first-start Help screen is described (section 2). The Help panel with No AI is in `simple-mode.md` 5.3, the Settings page in `settings.md` (3.9). Security questions for Minerva are marked **[N1]** to **[N8]** and listed in section 7; they are answered in `design-no-ai.md` (Minerva, 2026-09-30), and the text below carries her answers where they changed it.

Mockups (`docs/mockups/`, 1920 x 1080, same fonts, tokens and scale-to-fit script as the other mockups; sample names and data are made up):

| File | State |
|---|---|
| `simple-firstboot-3-help-no-ai-picked.html` | First start 3 of 4, "How should Help work?", No AI picked; the AI card shows Claude and a home AI system without expanding |
| `simple-firstboot-3-help-ai-picked.html` | The same screen, An AI assistant picked, Claude preselected inside it, `Sign in to Claude` |
| `simple-firstboot-3-help-password.html` | After `Sign in to Claude`: the password prompt to add Moneta (Minerva N1) |
| `simple-help-not-signed-in.html` | Atrium, Not signed in (2.3): the Help panel with the sign-in card over the guides |
| `settings-moneta-not-signed-in.html` | Settings in Atrium, Not signed in: the Moneta page with the Account card first |
| `simple-help-no-ai-guide.html` | Atrium, No AI: the Help panel, searched for "print", the guide open, Ask Support and Let Support see my screen |
| `settings-ai-off.html` | Settings in Atrium: the AI page with No AI on, and Moneta's kept memory from before |
| `settings-moneta-tessera.html` | Redrawn: the Moneta page with AI on, No AI now the fourth answer under "Who answers" |

---

## 0. In one screen

- **Two ways for Help to work, chosen at first start, changed any time in Settings > AI**: an AI assistant (Moneta, with Claude, a home AI system or another AI service) or **No AI**. The config value is the provider `none` (`design.md` 4.2); on screen it is `No AI`.
- **No AI means none anywhere Invictus ships.** No Moneta panel, no Super+A, no Moneta button, no voice, no AI summaries on the Desk, no Collegium, and no AI packages or models on disk.
- **Help still works.** In Atrium the Help button stays where it is, with the same name. Behind it: short how-to guides, searchable, that ship with the system and work offline; **Ask Support** (a request); **Let Support see my screen**.
- **No nudging.** Nothing says AI is missing, nothing greys out, nothing suggests turning it on. The only place AI is mentioned on a No AI machine is Settings > AI and one guide that is found only by searching for it.
- **Guard rails, safety copies, updates, the polkit agent and remote help are unchanged.** No Custodia rule changes (Minerva **[N4]**, `design-no-ai.md`): every guard is OS-level, and the assistant steps become no-ops.
- **Switching on installs the pieces then; switching off removes them and signs out.** Moneta's memory and past conversations stay on the computer until the person deletes them, with one button on the AI page.

---

## 1. What "No AI" removes, and what it keeps

| Piece | No AI | Why |
|---|---|---|
| Moneta panel (Tessera), Help's conversation (Atrium), Super+A, the bar's Moneta button | Gone | They are Moneta |
| `claude-code`, the Invictus plugin and MCP server, provider files | Not installed | "No AI packages on disk" |
| Voice: `invictus-ptt`, `whisper-cpp`, `ggml-vulkan`, the speech model in `~/.local/share/invictus/whisper/` | Not installed, model not downloaded | Speech recognition is a model; Alex listed voice |
| A local model (D15) | Not installed | Same |
| Collegium (`~/Collegium`) | Not created | It exists so agents have rules and memory |
| AI summaries on the Desk | Gone; the Desk shows plain facts (section 4) | They come from the provider's `run` |
| Browser AI features (Zen is Firefox-based: the chatbot sidebar, link previews) | Turned off by browser policy | "No AI anywhere" includes the apps we ship. Unverified which prefs Zen honours; Vulcan checks **[N7]** |
| The Help button, messages, Settings, guard rails, safety copies, updates, `invictus-doctor`, `invictus-report`, Acta, remote help | Unchanged | None of them is AI |
| The Now line and the Desk | Kept, set by hand (section 4) | The Now line is the ADHD anchor, not an AI feature |
| Notes (`~/Invictus/notes/`) and timers | Kept, typed | They are the person's; only the voice route to them goes |

Apps a person installs themselves (a Flatpak with its own AI) are theirs. No AI covers what Invictus ships and sets up, and the guide "Turn AI on or off" says so in one line.

**Packages (for Vulcan).** Today `claude-code` sits in `invictus-dev` (`packages.md`), so a No AI person who adds the dev set would get it. Proposal: a new meta `invictus-moneta` (claude-code, the plugin and MCP server, the provider files, the panel) that nothing else depends on, `invictus-voice` as is, and `claude-code` out of `invictus-dev`. The ISO installs neither; first start or Settings adds them. A test holds it: on a No AI machine, a full update installs none of them **[N5]**. Minerva adds the rule behind it (`design-no-ai.md` N5): nothing always installed may depend on the AI set, so `invictus-guardrails` depends on the `invictus-sys` half of `invictus-assistant`, never on `invictus-moneta`, and CI checks every meta (NA3).

**The state.** One machine-wide value, `/etc/invictus/ai` (`on` or `off`), root-owned 0644, written by the installer (`off`) and after that only by an `invictus-sys ai on|off` verb; a missing file reads as `off` everywhere. Machine-wide because the packages are. When AI is picked offline, the file reads `on` from the moment of the choice and a root job installs the packages at the first connection (Minerva N1). Read by the Atrium shell (which Help panel to draw), the Tessera config (binds, bar), the Desk, Settings, first start and the doctor. The provider choice (Claude, home, another service) stays where it is today. **[N1]**, **[N2]**.

---

## 2. First start

**This section is the single source for the first-start Help screen** (Atrium's screen 3 in `simple-mode.md` 3.2, and step 3 of Tessera's wizard in `design.md` 2.3). The other docs point here and do not repeat its words, flow or counts.

### 2.1 The screen: How should Help work?

Mockups: `simple-firstboot-3-help-no-ai-picked.html` (No AI picked), `simple-firstboot-3-help-ai-picked.html` (An AI assistant picked).

- Line under the heading: `Help is the button at the bottom right of the screen. You can change this later in Settings.`
- Two cards of the same size, side by side, each with a small picture of what Help will look like:
  - **An AI assistant**: `Moneta answers questions, by voice or typing, and fixes things after asking you.` Under it, always visible, two plain choices:
    - `Claude (your own account)` / `Anthropic's Claude. You sign in next.` **Preselected** (D13: Claude is the default).
    - `A home AI system` / `An AI on this computer or your home network. Nothing leaves your home.` Picking it opens an address field in the card (`Address, like atlas.local`), or offers `Use this computer` when the local model package is installed (D15; the Settings row, `settings.md` 3.9).
    - `Another AI`, collapsed. Opening it adds a third choice, `Another AI service` / `An account you already have with another AI company. It answers; it can't do things by itself.` (the chat-only `openai-compatible` provider; its key goes to the keyring). Never `generic-cli` (SM10).
  - **No AI**: `Short how-to guides you can search, and Support when you need a person. Nothing on this computer uses AI.`
- Clicking a choice inside the AI card also picks the card, so the home AI path costs no extra click.
- **The card is not preselected.** AI or not is the person's call; a preselected card is a nudge either way. The provider inside the card is preselected, because that one is a technical default. The gold button is disabled until a card is picked, then reads what it does: `Sign in to Claude` (Claude), `Continue` (home AI, another service, No AI).
- `Set up later` is gone: No AI is the honest "not now", and Settings turns AI on later.

Why the home AI system is inside the AI card and not a third card (Alex's D13: "a first-class option in the first-boot wizard, not a hidden add-on"; Moneta's ruling, 2026-09-30): it is visible without expanding, named in plain words, and one click away, which is what first-class means on this screen. A third card would put two AI options beside one No AI and make No AI the odd one out, and it is a provider, not a way of working. Only `Another AI` stays collapsed: it is for someone who already pays another company and knows it.

### 2.2 The flow after each choice

**Claude.** `Sign in to Claude`, then the password prompt, then the Claude sign-in in the browser, then screen 4.

1. **Password** (`simple-firstboot-3-help-password.html`; Minerva N1, `org.invictus.sys.ai-on`, `auth_admin` without keep; Moneta accepted the cost, 2026-09-30). The Invictus polkit agent over screen 3: `Your password is needed` / `Type your password to add Moneta, an AI assistant, to this computer` / `It asks before it changes anything. To remove it later: Settings, Moneta, No AI.` (Clio polishes; Minerva's draft said `Settings > AI`, but the page is named Moneta once AI is on) / the G3 scam line under Custodia / `Password for Maria` / `Cancel` and `Add Moneta`, equal weight / `Asked by First start. A safety copy is made first.` It comes before the sign-in on purpose: consent to the program comes before an account is tied to it, and a cancelled prompt changes nothing (back on screen 3, AI card still picked).
2. **What the password starts.** `invictus-sys ai on`: the G2 safety copy, `/etc/invictus/ai` reads `on`, and the packages download in the background. Offline: the pending marker, and the install waits for the first connection (N1).
3. **Sign-in.** The browser opens Claude's sign-in; the window comes back when it is done. The wizard only checks that the credentials file exists; it never sees the token. Then screen 4, with `Moneta is getting ready` in the Help panel until the packages are in.
4. **Sign-in not finished** (the browser closed, no account yet, offline). Screen 3 comes back with the AI card picked and one line under the cards: `Not signed in yet. You can try again now, or sign in later from Help.` The gold button still reads `Sign in to Claude`; a text button `Later` sits beside it and goes to screen 4. The machine is now in the **Not signed in** state (2.3). Picking No AI here runs `ai off` (no password, N1) and continues.

**A home AI system.** `A home AI system`, the address (or `Use this computer`), `Continue`, the password (same prompt), screen 4. Nothing to sign in to. If the address does not answer, the card says `Can't reach atlas.local. Check the address, or ask Support.` and the person can still continue: that is the Not signed in state with a home AI.

**Another AI service.** `Another AI`, `Another AI service`, the key, `Continue`, the password, screen 4.

**No AI.** `No AI`, `Continue`, screen 4. Nothing installs. Screen 4's third card changes its line from `Ask a question by talking or typing.` to `Guides for everyday things, and a way to ask Support.`

The friend's machine never needs a terminal on any path.

### 2.3 The Not signed in state

**Name:** *Not signed in* (on screen `Not signed in yet`; in the doctor and Acta `ai on, provider not signed in`). **When:** `/etc/invictus/ai` reads `on`, the packages are installed (or pending), and the chosen provider has no working credential: no `~/.claude/.credentials.json` for Claude, no key for another service, no answer from a home AI's address. It comes from a sign-in abandoned at first start (Minerva's `design-no-ai.md` 6.2), from Settings, or from `Sign out`.

**Help** (`simple-help-not-signed-in.html`). Help still works, because the guides install on every machine (`simple-mode.md` 5.3). The panel is the No AI panel with one card on top, lapis (information, nothing is broken):

> **Sign in to start Moneta**
> Moneta is on this computer but isn't signed in yet. Until then, Help has guides and Support.
> `Sign in to Claude` · `Other choices`

`Sign in to Claude` opens the same browser sign-in (no password: the program is already there). `Other choices` opens Settings > Moneta. With a home AI the card reads `Moneta can't reach your home AI` / `Check that it is on, or change it in Settings.` / `Try again` · `Other choices`. In Tessera, Super+A opens the Moneta panel showing the same card, and the bar's Moneta button stays. No message card, no badge on the Help button, no reminder: the person chose AI, and nagging them to finish is the nudge we don't make. The card goes away the moment a sign-in works.

**Settings > Moneta** (`settings-moneta-not-signed-in.html`). The page keeps its name (AI is on) and moves the **Account** card to the top:

- `Not signed in yet` / `Moneta can't answer until you sign in with your Claude account. Don't want AI after all? Pick No AI below.` / `Sign in to Claude...` / a quiet line `Moneta is on this computer, waiting for a sign-in since 28 September.`
- **Who answers** as always, with `No AI` as the fourth answer and its usual confirm (`no-ai.md` 5): that is the switch to No AI, no second button for it.
- **Voice** with `Talk to Moneta` off; no speech model downloads until a sign-in works. Full access and Options are hidden until then: they have nothing to act on.

Finish: Help, Sign in to Claude, the browser sign-in: 2 clicks + sign-in. Switch to No AI: Help, Other choices, No AI, Turn off AI: 4 clicks, no password (or Start, Settings, Moneta, No AI, Turn off AI: 5).

### 2.4 Clicks and decisions

| | Before (the old wizard) | After |
|---|---|---|
| Decisions | 1 (preselected) | 1 (the card; the provider inside it is preselected) |
| Clicks, Claude | 1 (Sign in) | 2 (card, Sign in to Claude) + password (1 click: Add Moneta) + the browser sign-in: **3 clicks + password + sign-in** |
| Clicks, a home AI | Not offered on screen | 2 (A home AI system, Continue) + address + password (1): **3 clicks + address + password** (with the local model: Use this computer instead of the address, 4 clicks + password) |
| Clicks, another AI service | Not offered on screen | 4 (Another AI, Another AI service, Continue, Add Moneta) + key + password |
| Clicks, no AI | 1 (Set up later; AI packages still on disk) | 2 (card, Continue) |

The password is new since the first version of this screen (Minerva N1, accepted by Moneta, 2026-09-30). It is the first plain-words consent the person sees.

---

## 3. Help with No AI (Atrium)

Full design in `simple-mode.md` 5.3. In short: the same button and panel, with a search field (`What do you need help with?`) over the guides, a short list of common ones when the field is empty, and two equal buttons at the bottom, `Ask Support` and `Let Support see my screen`. A guide is a title, one line on when it applies, at most seven numbered steps that name what is on screen, one `Open <place>` button that goes straight there, and `Didn't work? Ask Support about this`.

---

## 4. Tessera with No AI

**Keys** (`config/hypr/invictus/binds.lua`, and `show-keybindings`):

| Bind | No AI |
|---|---|
| Super+A (Moneta panel) | Not bound, not listed. The key does nothing, like any free key |
| The pen button (`invictus-ptt`) | Not installed; the button sends whatever key it sends by itself |
| Super+D (Desk, per look.md; clashes with Discord in binds.lua, open since the look job) | Unchanged |

**Bar** (`config/waybar/config.json`, look.md "Bar"):

| Module | No AI |
|---|---|
| Moneta button | Removed from `modules-right` |
| Now (`custom/now`, reads `~/.local/state/invictus/now`) | **Kept.** It already reads a plain file. Set by hand from the Desk's Now card; click opens the Desk instead of the Moneta panel; hidden when nothing is set, as now |
| Everything else | Unchanged |

The config is chosen at load: the waybar config and the Hyprland binds read `/etc/invictus/ai` (a second waybar config, or a generated `modules-right`, Vulcan's call). The `moneta-panel` layer and motion rules can stay; they match nothing.

**The Desk** (`look.md`, "The Desk"). One job still: what matters now. Without AI it shows facts, never summaries:

| Section | AI on | No AI |
|---|---|---|
| Greeting and date | As now | As now |
| Now card | Set by Moneta or by hand | Set by hand: `Nothing set. What are you working on?` with an input; `Done` and `Switch` as now |
| Left column | Open threads (Moneta) | **Today**: today's notes (`~/Invictus/notes/<date>.md`, newest first) and a running timer, if any |
| Right column | Waiting on you (team repo) | Waiting on you from the system only: `Restart when you're ready`, a safety net that is off or failing, a reply from Support. Hidden when empty; Today takes the width |
| System row | As now (it is already plain data) | Same, minus the team repo sync state |
| Bottom input | `Ask Moneta` | `Add a note` (writes to today's notes) |
| Stoic line | As now | As now |

No empty box where the threads were, no "Moneta is off" line. The Desk looks finished, not reduced.

---

## 5. Switching

In Settings > AI (`settings.md` 3.9).

**Turning AI on.** Pick `An AI assistant`, `Turn on Moneta...`, then the password (the Invictus polkit agent, like every system change), then the Claude sign-in or the provider's details. What happens, in order: a safety copy (the G2 net, as for any password change); `invictus-sys ai on` installs `invictus-moneta` (and `invictus-voice` only when the person turns on `Talk to Moneta`, which then downloads the speech model); the state file changes; the Help panel, the Tessera bar and binds reload. The page shows progress in the card (`Downloading Moneta, 40%`), then becomes the Moneta page. Clicks from the desktop: Start, Settings, AI, the card, Turn on Moneta: 5 clicks + password + sign-in.

**Turning AI off.** Pick `No AI` under Who answers; a confirm opens in the row:

> **Turn off AI?**
> Moneta and voice are removed from this computer, and you're signed out of Claude on this computer. Moneta's memory and past conversations stay on this computer until you delete them. Help keeps its guides and Ask Support.
> `Turn off AI` · `Cancel` (equal weight)

What happens, in order, and which is removed or kept:

| Step | Removed or kept |
|---|---|
| Moneta and any agent it started stop at once (the guard-rails restart path, G7) | Stopped |
| Sign-out (Minerva N3, in this order): `claude auth logout` (revokes the credential when online, verified), then in every home `~/.claude/.credentials.json`, the `oauthAccount` block of `~/.claude.json`, the provider keys in the keyring, and `gh` credentials only if Invictus created them | **Removed** **[N3]** |
| `invictus-moneta`, `invictus-voice`, a local model package: removed | **Removed** |
| Speech model and local model files (`~/.local/share/invictus/whisper/`, the model directory) | **Removed**: they are large and only AI uses them |
| Moneta's memory and past conversations (`~/.claude/` without the credentials, `~/Collegium/`, the panel's history) | **Kept**, listed on the AI page with its size and `Delete...` **[N6]** |
| Notes, timers, the Now line, Acta | **Kept**: they are not AI |
| Full access (Libertas) and a configured command-line agent | Cleared, as on a return to Custodia (Minerva 12.3) |

No password to turn off: it only takes capability away, like switching back to Custodia, and like that switch it is instant only from a local active session (Minerva **[N1]**). Clicks: Start, Settings, Moneta, No AI, Turn off AI: 5 clicks.

**Deleting the kept memory.** `Delete...` on the AI page: `Delete Moneta's memory?` / `This can't be undone. Your own files and notes are not touched.` / `Delete` · `Cancel`. No password: it is the person's own data. Why kept by default: turning AI off and on again should not wipe months of memory, deleting cannot be undone, and the choice is one button away on the page the person is already on. Asking in the turn-off confirm would put two decisions in one card.

---

## 6. Messages and other surfaces

| Where | AI on | No AI |
|---|---|---|
| Error cards' quiet button (`simple-mode.md` 4.1 rule 7) | `Help with this`, opens Help with the problem written in | `Help with this`, opens the guide for that message (each message names one), or Ask Support with the message's title filled in when there is no guide |
| `Your computer is almost full` | `Free up space` opens Help with "Help me free up space" | `Free up space` opens the guide `Free up space` |
| `No internet` | `Help and updates need the internet.` | `Updates need the internet.` (guides work offline) |
| `This needs Support` | Moneta's card | Not used |
| First start, Wi-Fi `Skip for now` | `everything works offline except Help and updates` | `everything works offline except updates and Ask Support` |
| Settings search "AI", "assistant", "Claude", "Moneta" | Moneta page | The AI page |
| Settings > Guard rails, "What Custodia does, in detail" | Includes `Help sticks to a fixed set of tools` | That line is left out (Minerva's G-list item has nothing to apply to; agreed, **[N4]**) |
| Settings > Safety copies, a net that is failing | `Fix` opens Help with the problem written in | `Fix` opens the guide the net names, or Ask Support with the problem filled in (rule 7) |
| The Help panel while Libertas is on | The guard-rails notice in the header | The same notice as one row under the header (it is not a status word; `simple-mode.md` 5.3) |

---

## 7. For Minerva (security touchpoints, not decided here)

Answered in `design-no-ai.md` section 2 (Minerva, 2026-09-30). Where the answer differs from the assumption below: N1 (`ai on` costs the password at first start too; `ai off` is instant from a local active session only), N2 (the person may turn AI on during a help session at their own keyboard; Alex may not), N3 (the list and its order, `claude auth logout` first), N7 (Firefox's `GenerativeAI` policy, verified; Zen's path unverified), N8 (the request runs through the report scrubber first).

| # | Question | Design assumes |
|---|---|---|
| N1 | Tiers for `invictus-sys ai on` and `ai off` | On: the person's password and a safety copy (it adds a program that can act on the computer). Off: tier 1, no password (it only removes capability, like Custodia's one-click return) |
| N2 | Who may turn AI on: only the person at the keyboard, or also Alex during a help session, or a script running as the user | Local active session only, like the switch to Libertas. Never from a help session: it is consent to AI |
| N3 | What "signed out" must delete to be true: `~/.claude/.credentials.json`, keyring entries for the API provider, anything else a provider leaves (MCP configs with tokens, `gh` credentials made for the Collegium). Whether the Claude token is also revoked server-side | Every credential file and keyring entry the providers are known to write; server-side revocation unverified |
| N4 | Does No AI change any Custodia rule? The managed-settings symlink when `claude-code` is absent; `guardrails apply` with no `/etc/claude-code`; the `assistant-full-access` action with no assistant; SM21's "claude pid gone" check; the G-list line about Help's tools | No rule changes; the steps that manage the assistant become no-ops, and `guardrails apply` must succeed on a No AI machine |
| N5 | Keeping AI packages off a No AI machine: updates, meta dependencies, a person installing `invictus-dev` | Test NA3 below; `claude-code` moves to `invictus-moneta` |
| N6 | Kept memory: transcripts can hold anything a person pasted, including secrets. Keep by default, or delete by default, or ask | Keep, listed with its size and `Delete...` on the AI page |
| N7 | Browser AI features turned off by a root-managed browser policy on No AI machines, and back on (to the browser's default) when AI is turned on | A policy file written by `ai off`; which keys Zen honours is unverified |
| N8 | Ask Support without Moneta: the request is written by the person and carries the About page's `Copy details for Support` block (no serials, MACs or user names). Same M8 preview, same helper queue | Same queue, same preview; "Support usually answers within a day" still waits on the inbox (M8) Delivery: `design-inbox.md` (2026-09-30). |

Proposed tests, adopted and extended by Minerva as NA1 to NA5, with NA6 to NA9 new (`design-no-ai.md` 4; Vera and Janus run them). The originals, for the record:

- **NA1** No AI install: none of `claude-code`, `invictus-moneta`, `invictus-voice`, `whisper-cpp`, `ggml-vulkan` or a local model package is installed; no `claude` on `PATH`; `~/.local/share/invictus/whisper/` and `~/Collegium` do not exist.
- **NA2** `ai off` on an AI machine: NA1's package list holds; no Claude credentials file; no provider key in the keyring; the kept memory directories exist unless deleted; no Moneta or agent process within 5 s.
- **NA3** A full update on a No AI machine installs none of NA1's packages.
- **NA4** On a No AI machine, the shell, Help, Desk and bar show no string naming Moneta, AI, Claude or voice, except Settings > AI and the guide `Turn AI on or off` (grep of the shipped QML and config strings, plus a screenshot pass).
- **NA5** Guard rails switched both ways on a No AI machine: both succeed, nothing in the journal from the assistant steps.

---

## 8. Reused / new, and why

Reused: the provider `none` (`design.md` 4.2); the Settings Who answers rows and their words, inside the first-start AI card; the polkit agent dialog from Guard rails, for the first-start password; the No AI Help panel and guides, under the Not signed in card; the setup card and the parchment selection border (first start); the Help panel's frame, header, Ask Support and Let Support see my screen (Minerva 5.2); Settings' search matcher and its synonym list (guide search); `invictus-settings open` deep links (a guide's `Open <place>` button); the About page's `Copy details for Support` (what Ask Support sends); the choice cards and rows from Guard rails and Moneta (the AI page); the guard-rails restart path (stopping Moneta); the G2 safety copy; the Now file (`custom/now` already reads it); the Desk's Now card and its input.

New: the guides (`invictus-help`: plain Markdown, no code), the `ai on|off` verb and `/etc/invictus/ai`, the `invictus-moneta` meta, the No AI waybar and bind variants, the Desk's Today column. Nothing existing does these jobs.

## Note: Claude plan requirement (Moneta, 2026-09-30, verified)

Claude Code's setup page (code.claude.com/docs/en/setup, "Authenticate", read 2026-09-30): "Claude Code requires a Pro, Max, Team, Enterprise, or Console account. The free claude.ai plan does not include Claude Code access." So "Claude (your own account)" on the first-start card means a paid plan. The card and the Not signed in state must say so in plain words (Clio), and a free-plan sign-in must land in the Not signed in state with that explanation, not an error. For friends without a paid plan, "A home AI system" or No AI are the real choices.
