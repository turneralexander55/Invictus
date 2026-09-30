# Invictus: No AI, the security side

Author: Minerva (consultant). Date: 2026-09-30. Status: design, answers to Venus's `no-ai.md` section 7 (N1 to N8) and an audit of No AI against the Custodia and Libertas designs. Addendum to `design-simple-mode.md` (its section 13 points here); the experience side is `no-ai.md`, `simple-mode.md` 5.3 and `settings.md` 3.9.1.

The ask (Alex, 2026-09-30): No AI as a first-class choice, then "is a No AI person badly off under Custodia?" Moneta's answer, checked in section 1: no, the protections are OS-level; they lose the chat helper, and more lands on Alex.

Names as in `design-simple-mode.md`: guard rails Custodia and Libertas, flavors Atrium and Tessera, the assistant Moneta, the helper Alex. "AI set" below means `claude-code`, `invictus-moneta`, `invictus-voice`, `whisper-cpp`, `ggml-vulkan`, `invictus-collegium` and any local model package.

---

## 0. In one screen

- **Moneta's claim holds.** Every guard G1 to G10 is polkit, PAM, sudoers, pacman, systemd, snapper or RustDesk; none reads or needs the assistant. G7 and the threats TS5, TS6, T1, T2, T7 and T11 have no subject on a No AI machine, so it has strictly less attack surface. What the person loses is the assistant's explanations and its shortcuts to tier 1 verbs, which Settings and Help still surface (section 1).
- **Two verbs, two actions.** `invictus-sys ai on` is `auth_admin` without keep, in no YES rule and outside the help unlock, like Full access. `ai off` is instant from a local active session, like the return to Custodia: it only removes (N1, N2).
- **Signed out means: Moneta stopped, `claude auth logout` (which revokes the credential, verified), the credential file and the provider keys gone in every home, then the packages** (N3). What stays is the person's own data, deletable with one button (N6).
- **No Custodia rule changes.** The derived files never read `/etc/invictus/ai`; `/etc/claude-code/` and both managed profiles belong to `invictus-guardrails` on every machine, so the profile is in force before `claude-code` is ever installed (N4).
- **`invictus-guardrails` must not depend on `invictus-assistant`** (my 6.1 said it did). Nothing always installed may depend on the AI set; CI proves it (N5, NA3).
- **The guides are the help content now, and they are root-owned static files**: no injection path, and under Custodia they pass the same "never a command" scan as Moneta (NA7).
- **Browser AI off by policy**: Firefox's `GenerativeAI` policy, `Enabled: false, Locked: true`, removed again when AI is turned on (N7).
- Fifteen gaps found and fixed (section 3); MUSTs NA1 to NA9 (section 4); no new owner decision; two of Venus's calls for Moneta to check (section 6).

---

## 1. Is a No AI person badly off under Custodia?

| Guard | Depends on the assistant? | On a No AI machine |
|---|---|---|
| G1 plain-words prompts | No (polkit agent, message table) | Unchanged, and now the only explanation the person gets at the moment of an admin action: see NA8 |
| G2 pre-admin snapshot | No (PAM) | Unchanged |
| G3 sudo lecture, scam line | No (sudoers, agent) | Unchanged |
| G4 `HoldPkg` | No (pacman) | Unchanged |
| G5a, G5b updates | No (systemd, Settings) | Unchanged |
| G6 hold list | No (agent) | Unchanged |
| G7 the assistant cannot be talked into the destructive few | It is the assistant | Nothing to protect against: no assistant, no tool, no prompt injection |
| G8 remote help consent | No (RustDesk config) | Unchanged |
| G9 boot guard | No | Unchanged |
| G10 the record | No (Acta) | Unchanged; fewer lines |

Threats: TS1 to TS4 and TS7 to TS12 are unchanged. TS5 and TS6 (the assistant does harm, prompt injection) and `design.md`'s T1, T2, T7 and T11 have no subject. Nothing in `design-simple-mode.md` relies on the assistant to keep the person safe; the assistant was always the thing being contained.

What the person loses, precisely:

| With Moneta | With No AI |
|---|---|
| "May I?" cards and Moneta's one-line explanations | The guides, and the G1 prompt text |
| `update_now`, `update_undo`, `doctor`, `help_start` by asking | The same tier 1 verbs from Settings > Updates (`Undo last update`), Settings' home page (the doctor), the Help panel and Settings > Help from Alex (`help start|stop`). The tier 1 YES rule stays on a No AI machine because these call the same verbs; SM22 is unchanged |
| `snapshot <desc>` by asking | No surface: nothing on screen makes a safety copy on demand. Not a safety loss (G2 and snap-pac cover every change), but Venus may want `Make a safety copy now` on Safety copies; it is tier 1 already |
| Moneta's summary in Ask Alex | The person's own words plus the About block (N8) |
| Moneta pointing to a guide, `Ask Help` with the problem written in | The guide named by the message, or Ask Alex with the title filled in |
| The voice route to notes and timers | Typed |

More lands on Alex: everything tier 3 was his already; what is new is the explaining. Moneta's answer is right, with one addition for the build: on a No AI machine the polkit prompt is the whole explanation, so the G1 message table must cover every action id a person can reach from Settings, Help, Bazaar, Files and Disks; the "An app wants to change this computer" fallback is for unknown apps only (NA8).

---

## 2. Answers N1 to N8

### N1. Tiers for `ai on` and `ai off`

Two polkit actions, because the two directions need different answers (the same lesson as the guard-rails switch, SM22).

- **`org.invictus.sys.ai-on`: `auth_admin` without keep**, under both guard rails, never in a YES rule, never covered by the help unlock. Same class as `guardrails-libertas` and `assistant-full-access`: a choice about the person's own machine that a cached credential from an unrelated prompt, a helper or a process running as the user must not make. It adds a program that can act on the computer, so it costs the password once. Not on the hold list and no extra scam line: under Custodia every admin prompt carries G3's line anyway, and adding a bounded assistant is not destructive. G2's snapshot comes from PAM; the verb also keeps A5's pre/post pair around the package install. Prompt (G1 table, Clio polishes): "Type your password to add Moneta, an AI assistant, to this computer. It asks before it changes anything. Undo: Settings > AI > No AI." **At first start too**: the wizard runs as the person, so picking An AI assistant costs one password prompt after `Sign in to Claude`; Venus's click table now counts it. I considered a one-shot YES rule for the first-start window and rejected it: a standing rule a user process could race, to save one prompt that is the first plain-words prompt the person will see.
- **`org.invictus.sys.ai-off`: `polkit.Result.YES` for `subject.local && subject.active`, `auth_admin` otherwise**, under both guard rails, like `guardrails-custodia`. Why no password, by SM22's test: it only removes. Nothing it deletes is beyond what a process running as the user could already do (kill Moneta, delete `~/.claude/.credentials.json`, clear its own keyring); the one root part is removing packages nothing else depends on, and the machine keeps working. It is not undoable in the strict sense (turning AI on again is a password, a download and a sign-in) but nothing is lost: memory and conversations stay (N6). Alex's remote input during a help session is the person's local active session, so he can click it; it is on the record (`by <user>, help session <id>`) and on the screen the person is watching, the same as a switch to Custodia.

Both verbs write `/etc/invictus/ai` (root 0644, `on` or `off`, temp file and `rename(2)`), an Acta line, and a notice on screen. The installer writes `off`; a missing file reads as `off` everywhere. `ai on` with no network writes `on` and a pending marker (`/var/lib/invictus/ai-install-pending`) and returns; `invictus-guardrails.service` and the updater's gate install the packages at the first connection; `ai off` clears the marker. The person's consent is the password at the time of the choice, not at the time of the download.

### N2. Who may turn AI on

The person at their own keyboard, with their password, from a local active session. A script running as the user hits the prompt. During a help session: still the person, at their keyboard, and still allowed. Here I differ from Venus's "never from a help session": RustDesk does not carry local keystrokes out and Alex's remote input cannot reach the polkit field (5.2 step 4, SM13), and the unlock does not cover the action; so what is excluded is Alex doing it, not the person doing it while Alex is on screen, which is exactly when a non-technical friend will ("Alex, set it up for me"). The sign-in that follows needs the person's own Claude account in their own browser, which Alex cannot supply either.

### N3. What "signed out" must delete

Order matters, because the CLI must still exist for its own logout:

1. Moneta and any agent it started stop (the G7 restart path: SIGTERM to the process group, SIGKILL after 5 s).
2. `claude auth logout` as the person, best effort, 10 s timeout; offline failure is fine. Verified at code.claude.com/docs/en/authentication (2026-09-30): `/logout` "removes and revokes the credential this sign-in wrote", so the token is revoked server-side when the machine is online, not only deleted. Then `claude mcp logout <name>` for every MCP server the Invictus plugin configured with OAuth (none in v1; the list lives in the plugin, so a future one is covered).
3. Delete, in **every** home directory (the setting is machine-wide; root does the files): `~/.claude/.credentials.json` (Linux storage, 0600, verified on the same page); the `oauthAccount` block in `~/.claude.json` (account metadata; Vulcan confirms it holds nothing else worth keeping); `gh` credentials only if `invictus-collegium` created them, which it records at `gh auth login` time in `~/.local/state/invictus/collegium/gh-login` (a `gh` the person set up themselves is theirs). Keyring entries (the `openai-compatible` key, and any provider key) can only be removed inside that user's session, so every Invictus provider writes its keys under one namespace, `invictus/provider/<name>`, and the caller's session clears it now while `/var/lib/invictus/ai-off-pending/<uid>` makes `invictus-session` clear it for any other user at their next login.
4. Remove the AI set, the speech model and any local model files.

On screen: "signed out of Claude on this computer" (the revocation happens only when the logout reached Anthropic; the guide `Turn AI on or off` adds that to end the session everywhere, sign out at claude.ai too). Kept: everything in N6.

### N4. Does No AI change any Custodia rule?

No. Six rules for the build so the assistant steps become no-ops rather than failures:

1. **The derived files are a function of `guardrails` and `assistant` only.** `guardrails apply` never reads `/etc/invictus/ai`. `/etc/claude-code/` and both managed profiles belong to `invictus-guardrails` on every machine, and the symlink is written on a No AI machine too. Reason beyond tidiness: the moment `ai on` installs `claude-code`, the profile the rails require is already in force, so there is no window in which a fresh `claude` runs without it; and a `claude` the person installs by hand with `invictus-sys install` (their right, DS1) runs under the same rules.
2. **The `tribune` restart signal**: socket absent, nothing to signal, logged at debug, exit 0. SM21's "no assistant process with a Bash tool survives" holds vacuously; the test steps that read a `claude` tool list are recorded as not applicable on a No AI machine (NA5).
3. **`assistant-full-access`**: the action and the verb exist on every machine; `set-config assistant.full-access on` is refused while `ai` reads `off` (as under Custodia), Settings hides the row (3.9.1), and `ai off` writes `full-access = off` so a later `ai on` under Libertas starts with the fixed profile. A configured `generic-cli` is cleared with it (12.3).
4. **The tier 1 rule file stays** (section 1): Settings and Help call tier 1 verbs. SM22 unchanged.
5. **The G-list line** "Help sticks to a fixed set of tools" and the two cards' Help clauses are left out under No AI, as Venus wrote (`settings.md` 4.1).
6. **`invictus-guardrails` no longer depends on `invictus-assistant`** (6.1 said it did, which would put the assistant on every machine). It depends on the package that holds `invictus-sys`, the polkit policy, `invictus-doctor` and `invictus-report`; `design.md` 1.3's `invictus-assistant` splits into that (call it `invictus-sys`) and `invictus-moneta` (the panel, the plugin and MCP server, the providers, `claude-code`, `invictus-collegium`). Vulcan owns the split; the rule is N5's.

### N5. Keeping the AI set off a No AI machine

Venus's `invictus-moneta` meta, adopted; `claude-code` leaves `invictus-dev`. The rule: **no package in the always-installed or optional non-AI sets (`invictus-base`, `-desktop`, `-atrium`, `-tessera`, `-guardrails`, `-sys`, `-everyday`, `-dev`, `-gaming`, `-windows`) may depend, directly or transitively, on the AI set**, and CI proves it against the built repo on every promotion (NA3), the way `no-personal-data` guards the Collegium template. A person who installs `claude-code` by hand keeps it (DS1); the doctor reports "AI packages present with AI off" as a fact, the shell stays No AI, and N4.1 means it runs under the rails' profile.

### N6. The kept memory

Keep by default, one `Delete...` button, no password. The transcripts have the same protection as any file in the person's home (0700 home, the unencrypted disk is DS8's accepted risk), `invictus-report` never reads `~/.claude` (`design.md` 4.5), and the helper's recorded root terminal can read them, on the record. A secret pasted into a chat was already on disk while AI was on; turning AI off should not silently destroy months of memory, and asking in the turn-off card would stack two decisions (A10). `Delete...` removes, per user and as that user: `~/.claude/` entirely, `~/.claude.json`, `~/Collegium/`, the panel's history, the Desk's threads cache; the size line sums the same list. It does not touch notes, timers, the Now file or Acta. One wording point for Clio: "This can't be undone" is not literally true while DS12's hourly home copies hold it for up to a week; "Moneta forgets everything from before" says what happens without promising more than the machine does.

### N7. Browser AI features

Verified (mozilla.github.io/policy-templates, 2026-09-30): Firefox 144 and ESR 140.4 have a `GenerativeAI` policy (`Enabled`, `Chatbot`, `LinkPreviews`, `TabGroups`, `Locked`; prefs `browser.ml.chat.enabled`, `browser.ml.chat.page`, `browser.ml.linkPreview.optin`, `browser.tabs.groups.smart.userEnabled`), read from `/etc/firefox/policies/policies.json`. `ai off` writes that file, root 0644, holding exactly `{"policies": {"GenerativeAI": {"Enabled": false, "Locked": true}}}`; `ai on` removes it, so the browser's own default comes back and we never lock AI features on. Unverified, for Vulcan: whether Zen reads `/etc/firefox/policies` or its own path, and whether the Zen build honours `GenerativeAI`; if not, the `Preferences` policy on the same prefs is the fallback. A policy file can also set proxies and install extensions, so ours holds only this block and NA4 checks it. No other shipped app in the DS5 set has an AI feature today; any that grows one gets a row in `no-ai.md` section 1. Not covered, and said in the guide: the web itself (a search engine's AI answers) and apps the person installs.

### N8. Ask Alex without Moneta

Same queue, same preview, same M8 caveat, same delivery once DS3's inbox addendum ships (it covers both kinds of machine). The request carries the About page's `Copy details for Alex` block (no serials, MACs or user names) plus the person's text and the guide or message id it came from. Because the person now types free text, the request runs through the A12 scrubber (`design.md` 4.5 step 2, the token and password scanner) before the preview, like `invictus-report`; a hit blocks and names the line. Nothing leaves the machine without Send (A12). The write to the helper queue uses the same mechanism as `helper_ask`, whichever Vulcan built (a tier 1 verb or a group-writable directory), not a second one.

---

## 3. Audit: what silently assumed an assistant

Across `design-simple-mode.md`, `simple-mode.md`, `settings.md`, `no-ai.md` and `design.md` 2.3, for No AI + Custodia and No AI + Libertas. Each row says where the fix landed.

| # | Where | The gap | Fix |
|---|---|---|---|
| 1 | `design-simple-mode.md` 6.1 | `invictus-guardrails` depends on `invictus-assistant`: every machine gets the assistant | Depends on the `invictus-sys` half (N4.6, N5); 6.1 revised; NA3 |
| 2 | `design-simple-mode.md` 5.2 step 4, SM13 | The help unlock grants `org.invictus.sys.*`, which would include `ai-on` | Excluded, with `guardrails-libertas` and `assistant-full-access`; SM13 revised |
| 3 | `design-simple-mode.md` 1.6 G7 row, SM21 | The `tribune` signal and the `claude` pid check on a machine with no panel | No-ops (N4.2); NA5 |
| 4 | `design-simple-mode.md` 12.3 | Full access and `generic-cli` on a No AI machine | Refused while `ai = off`; `ai off` writes `off` (N4.3) |
| 5 | `design-simple-mode.md` 4.1, SM10 test | "Claude Code, home AI system (chat), none" as a provider list on the wizard | The wizard shows the two cards; SM10 test reworded |
| 6 | `settings.md` 5.2 | A failing net's `Fix` "opens Help with the problem written in" | With No AI it opens the guide the net names or Ask Alex with the problem filled in (rule 7); `settings.md` revised |
| 7 | `simple-mode.md` 5.3 | "No status word" drops the guard-rails notice that 1.5 puts in both flavors and TS11 relies on | The notice stays as one row in the No AI panel; `simple-mode.md` revised |
| 8 | `simple-mode.md` 5.3, TS1 | The guides had no "never a command" rule; under No AI they are the help content | NA7; one line in 5.3 |
| 9 | `simple-mode.md` 6.2 | Flavor lock "through Help's May I? card" | "(with AI)" added; Settings > Desktop style is the No AI path |
| 10 | `design.md` 2.3 step 3 | Tessera's full wizard still offers "Claude Code, another CLI, an endpoint, or none" | Same two-card screen in both wizards; steps 4 (Collegium) and 6 (voice) skipped under No AI; one line added to `design.md` |
| 11 | `no-ai.md` 2 | The AI path's click count omits the password `ai on` needs (N1) | Table revised |
| 12 | `no-ai.md` 5, `settings.md` 3.9 | "you're signed out of Claude" | "on this computer" (N3) |
| 13 | `no-ai.md` 1 | `/etc/invictus/ai` "written only by the verb": no initial value | The installer writes `off`; missing reads as `off` |
| 14 | `no-ai.md` 5 | The pending install when AI is picked offline had no owner | Marker and root job (N1) |
| 15 | G1 message table | With no Moneta, the prompt is the only explanation | NA8: every reachable action id has an entry |

Not gaps, noted: `snapshot <desc>` has no surface under No AI (section 1); `Delete...` wording (N6); the DS3 inbox addendum is still owed and covers both kinds of machine.

---

## 4. MUSTs and the tests that prove them

Venus's NA1 to NA5 adopted and extended; NA6 to NA9 new. Vera runs NA1, NA3, NA4 and NA7's scan; Janus runs NA2, NA5, NA6, NA8 and NA9 in a VM (No AI + Custodia, then NA2, NA5 and NA6 again on No AI + Libertas).

| # | MUST | Test |
|---|---|---|
| NA1 | A No AI install has none of the AI set installed, no `claude` on `PATH`, no speech or local model files, no `~/Collegium`; `/etc/invictus/ai` reads `off`, root 0644; and the guard-rails derived files are complete anyway: `/etc/claude-code/managed-settings.json` points at the profile the rails say. | `pacman -Q` for each package in the AI set fails; `command -v claude` empty; the directories absent; `stat` on the file; `readlink /etc/claude-code/managed-settings.json` is the Custodia (or fixed Libertas) profile; `invictus-sys guardrails apply --check` exits 0; `pactree -r <pkg>` for each AI package is empty. |
| NA2 | `ai off` on an AI machine: stops Moneta within 5 s, runs the CLI logout, deletes the credential file, the `oauthAccount` block and the provider keyring namespace in every home (the caller's now, others at their next login), removes the AI set and the model files, keeps the memory directories unless deleted, writes `full-access = off`, writes the browser policy, clears any pending marker, writes Acta, and then NA1 holds; it is instant from a local active session and prompts from anywhere else. | Sign in, add an `openai-compatible` key, create a second user with a credentials file; `ai off` from Settings: no prompt; within 5 s no `claude` or agent process; the journal shows `claude auth logout` ran; both homes lack `.credentials.json`; `~/.claude.json` has no `oauthAccount`; `secret-tool search` in the namespace is empty for the caller and becomes empty for the second user after login; `~/.claude/projects/`, `~/Collegium/` exist; `/etc/invictus/assistant` reads `off`; the policy file exists; NA1's checks pass; `set-config assistant.full-access on` is refused; from a `systemd-run` unit or an inactive session `ai off` prompts. |
| NA3 | No package outside the AI set depends on it, directly or transitively; a full update on a No AI machine installs none of it; `claude-code` is not in `invictus-dev`. | CI `no-ai-in-base`, on every repo promotion: for each meta in N5's list, `pactree -s` against the built repo contains none of the AI set (adding one fails CI); in the VM: `pacman -Syu` with a newer repo installs none; `pacman -S invictus-dev` on a No AI machine installs no `claude-code`. |
| NA4 | On a No AI machine the shell, Help, Desk, bar, Settings and messages show no string naming Moneta, AI, Claude or voice, except Settings > AI and the guide `Turn AI on or off`; the browser policy file holds only the `GenerativeAI` block. | Grep of the shipped QML, Lua, waybar and message strings with `ai = off` active, plus a screenshot pass; `python -c 'import json;...'` asserts the policy file's keys are exactly `policies.GenerativeAI`. |
| NA5 | Guard rails switch both ways, a timed Libertas expires, and `guardrails apply` runs on a No AI machine with no error from the assistant steps; the managed symlink follows the rails anyway; Full access is refused with the No AI message. | Scripted both ways and one expiry: exit 0 each time, `journalctl -t invictus-sys -p err` empty, the symlink target changes with the rails, `set-config assistant.full-access on` refused; SM21's `claude` tool-list steps recorded as not applicable, every other SM21 step passes. |
| NA6 | `ai on` is `org.invictus.sys.ai-on`, `auth_admin` without keep, in no YES rule, outside the help unlock; a cached credential does not skip it; Alex's remote input cannot answer it; the person can, including during a help session; a G2 snapshot exists; the first `claude` the panel starts runs under the rails' profile; offline, the choice is recorded and the install follows the first connection. | `pkaction --verbose --action-id org.invictus.sys.ai-on`: `auth_admin`, no keep; `sudo -v` then `pkexec true`, then `ai on` from Settings: still prompts; from a help session with the unlock, Alex's keystrokes do not reach the field and the person's do; `snapper list` has "Before: polkit-1, <person>"; after install, the panel's first `claude` lists no Bash under Custodia; with the network down, `/etc/invictus/ai` reads `on`, the marker exists, and the packages arrive within a minute of reconnecting; at first start the same prompt appears after `Sign in to Claude`. |
| NA7 | The guides are the only help content under No AI: root-owned files under `/usr/share/invictus/help/`, read from nowhere else, no network; a guide's `Open` target comes from a fixed list (Settings deep links and shipped apps' desktop ids), never a command or URL, and the panel executes nothing else from a guide; under Custodia every guide passes SM8's scan (no code span, `$`, `/usr`, `~/`, "terminal", "sudo", "command"). | `find /usr/share/invictus/help ! -user root` empty; the person cannot write there without `sudo`; a guide dropped in `~/.local/share/invictus/help/` is not shown; CI scans every Custodia-tagged guide with SM8's pattern set; a guide whose `Open` target is `bash -c ...` or `https://...` is rejected at build; `strace -f` on the panel opening ten guides shows no `execve` beyond the deep-link tool and the app launcher. |
| NA8 | Every polkit action id a person can reach from Settings, Help, Quick settings, Bazaar, Files and Disks has an entry in the G1 message table; the "An app wants to change this computer" fallback appears for none of them. | On a No AI Custodia machine trigger each from the UI (install outside the subset, system Flatpak, format a system disk and a USB stick, pause updates, go back to a copy, switch to Libertas, lock the flavor, turn on AI, join a hidden network if it prompts); each dialog shows the table text with its argument; the list of ids is kept in the test and grows with the UI. |
| NA9 | Ask Alex without Moneta sends only the About block, the person's text and the source id, after the A12 scrubber and the preview, and nothing without Send. | Type `my password is hunter2 and my key is sk-ant-...` into Ask Alex: the scrubber blocks and names the line; a clean request shows the preview, Cancel leaves the queue empty and `ss` shows no outbound; Send writes one file to the queue with exactly those fields; `strings` on it finds no serial, MAC or user name. |

Revised existing MUSTs (`design-simple-mode.md`):

- **SM10** test: "the first-boot wizard shows the screen in `no-ai.md` 2; `generic-cli` is offered nowhere on a Custodia machine" (pointer since 2026-09-30, so the screen is described in one place).
- **SM13**: the unlock covers `org.invictus.sys.*` except `guardrails-libertas`, `assistant-full-access` and `ai-on`.
- **SM21**: on a No AI machine the assistant steps are not applicable (NA5).
- **S2** list adds `/etc/invictus/ai` and `/etc/firefox/policies/policies.json`, root 0644.
- **6.1**: `invictus-guardrails` depends on `invictus-sys`, not `invictus-assistant`.

---

## 5. Threat model delta

- Removed on a No AI machine: TS5, TS6, T1, T2, T7, T11.
- New, contained: **`ai on` as a privilege change** (a program that acts on the computer): the person's password each time, no keep, no rule, no unlock, and under Custodia the new assistant lands in the fixed-tools profile that is already on disk. **`ai off` without a password**: removes only; nothing beyond what the user's own processes could do plus a package removal nothing depends on; local active session only; on the record. **The guides as help content**: static, root-owned, scanned; no injection path and no execution beyond a fixed target list. **The kept memory**: the person's own data at the same protection as the rest of their home; one button deletes it. **The browser policy file**: root-owned, one block, checked.
- A scam script gains nothing new: "turn the AI on" costs the password and yields a bounded assistant; "turn it off" yields nothing.

---

## 6. For Moneta: two of Venus's calls, and one of mine

1. **Two equal cards, nothing preselected.** D13 says "Claude is the default, but the choice of provider must include home AI systems as a first-class option in the first-boot wizard, not a hidden add-on." Venus keeps Claude preselected inside the AI card (holds) and leaves AI-or-not unselected, which Alex's own words support ("not everyone is thrilled") and which costs one click. Security: no view. But she folds the home AI system under a collapsed `Use a different AI` row, which reads as the hidden add-on D13 ruled out. Moneta should check that with Alex or ask Venus for a form that keeps it visible (the AI card's line could name it: "Uses Claude with your account, or an AI at home").
2. **`Set up later` removed.** Fine for security: `off` is the state of a machine that never finishes the screen. One case Venus should name: a person who wants AI but has no Claude account yet. Either they pick No AI now and turn it on later (5 clicks, password, sign-in), or they pick AI and stop at the sign-in, which leaves `ai = on`, packages installed and no credentials: the Help panel then needs a "Sign in to Claude to start" state that no doc describes.
3. **Mine, N1 at first start:** picking An AI assistant now costs a password prompt. It is the right prompt (the first plain-words consent the person sees) but it is a change to Venus's screen, and the PO should own it.

Resolved (Moneta, 2026-09-30): 1, the home AI system is now a visible choice inside the AI card; 2, the state is named Not signed in; 3, accepted. All three in `no-ai.md` 2.

Owner decisions: none new. Moneta's claim to Alex stands as given.

---

## 7. Verified today, and not

Verified (2026-09-30): code.claude.com/docs/en/cli-reference lists `claude auth logout` and `claude mcp logout <name>`; code.claude.com/docs/en/authentication says `/logout` "removes and revokes the credential this sign-in wrote" and that Linux credentials live in `~/.claude/.credentials.json` mode 0600. mozilla.github.io/policy-templates documents `GenerativeAI` (Firefox 144, ESR 140.4), its prefs, and `/etc/firefox/policies/policies.json`.

Unverified, for the build: whether Zen reads `/etc/firefox/policies` and honours `GenerativeAI`; what `~/.claude.json`'s `oauthAccount` holds beyond account metadata; whether `claude auth logout` exits cleanly offline within 10 s; the `pactree -s` form against a remote repo in CI; how `helper_ask` writes the queue today (a verb or a directory).

---

## 8. Reused / new, and why

Reused: the two-action switch pattern and its polkit answers from the guard rails (`auth_admin` no keep one way, `YES` for local active the other); the help-unlock exclusion list; the G7 restart path to stop Moneta; `claude auth logout` and `claude mcp logout` rather than our own token handling; Firefox's own policy mechanism; the A12 scrubber and preview for Ask Alex; the SM8 scan for the guides; the CI grep pattern from `no-personal-data`; `invictus-session` for per-user cleanup at login; the pending-marker pattern from the boot guard (`hold-updates`). New: the two actions and the `ai` verb, the `no-ai-in-base` CI check, the provider keyring namespace, the guide `Open` allowlist. Nothing existing does these jobs.
