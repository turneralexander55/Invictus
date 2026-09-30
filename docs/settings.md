# Invictus: Settings

Status: design, not yet built. Owner: Venus (designer). Date: 2026-09-30.
Replaces the sketch in `simple-mode.md` 8.5. Works in both flavors (Atrium and Tessera) and under both guard rails (Custodia and Libertas). The admin model behind every switch is Minerva's (`design-simple-mode.md`, sections 1.3 to 1.6, 2, 4, and Alex's answers in 11); this document is what people see and touch.

Names (Alex, 2026-09-30): flavors **Atrium** and **Tessera**, guard rails **Custodia** and **Libertas**, the assistant **Moneta**.

Mockups (`docs/mockups/`, 1920 x 1080, self-contained HTML, same fonts, tokens and scale-to-fit script as the other mockups; sample names and data are made up):

| File | State |
|---|---|
| `settings-home.html` | Atrium, Custodia: the home page, search focused |
| `settings-guard-rails-custodia.html` | Guard rails, Custodia on |
| `settings-guard-rails-to-libertas-hold.html` | Switching to Libertas "For an hour", the password prompt mid-hold (3 s left) |
| `settings-guard-rails-libertas-timed.html` | Libertas since 14:20, until 15:20, 42 min left, with the taskbar countdown |
| `settings-safety-copies-libertas-one-off.html` | Libertas, hourly copies of files turned off, the system copies listed |
| `settings-desktop-style.html` | Desktop style, Atrium on |
| `settings-desktop-style-keep.html` | Just switched to Tessera: "Keep this desktop style?", 14 s left |
| `settings-moneta-tessera.html` | Tessera, Libertas, Settings tiled at half the screen: the Moneta page (redrawn 2026-09-30: No AI is the fourth answer) |
| `settings-ai-off.html` | Atrium, No AI: the AI page, with Moneta's kept memory from before (3.9.1) |
| `settings-moneta-not-signed-in.html` | Atrium, AI on but never signed in: the Moneta page, Account first (`no-ai.md` 2.3) |
| `settings-check-text-150.html` | Guard rails at 150% text size (a check, not a state) |

---

## 0. In one screen

- **One window, eleven pages**, a sidebar on the left, search at the top of it. It opens on a home page that says whether everything is fine and lists the six things people change most.
- **Plain words.** No "snapshot", "btrfs", "subvolume", "rollback", "polkit", "root", "sudo". Snapshots are **safety copies**; rolling back is **Go back to this**; the boot guard is the **start-up guard**.
- **Guard rails page**: Custodia and Libertas in two plain sentences each. To Libertas: a choice of how long ("For an hour" preselected, then "Until I turn them back on"), then the system password prompt with the scam line and a 5-second hold. Back to Custodia: one click, no password. A timed Libertas shows its countdown on the page, in the sidebar and in the taskbar or bar.
- **Safety copies page**: the five safety nets (four switchable under Libertas, all locked on under Custodia; the copy before an update is always on) and the list of copies with **Go back to this**, split into **Your files** and **The system**.
- **Mouse for everything, keyboard for everything, readable at 150% text.** One gold (bronze on light) at a time inside the window: where the keyboard is.
- **Built in Quickshell** as its own process and a normal window, sharing QML components with the Atrium shell and the first-start wizard (section 7).
- **No AI** (Alex, 2026-09-30; `no-ai.md`): the Moneta page becomes **AI** while AI is off, with two choices and nothing greyed out. Turning AI on installs Moneta then; turning it off removes it and signs out, and keeps Moneta's memory until the person deletes it.
- **No night restarts** anywhere in Settings (Alex, 2026-09-30): after an update that needs one, the Updates page and a quiet notice say "Restart when you're ready".

---

## 1. Pages

Fewest pages that cover the list, grouped by how often people come (three groups, separated by a gap, no headings):

| # | Page | Covers |
|---|---|---|
| | *Home* (no sidebar entry: it is what opens) | State of the computer, six common tasks |
| 1 | **Wi-Fi and Bluetooth** | Networks, airplane mode, pairing, connected devices |
| 2 | **Sound** | Output, volume, microphone, alert sound |
| 3 | **Screens and text** | Text size, brightness; the monitors file the first-start wizard writes: main screen, arrangement, size of everything (scaling), workspace placement (Tessera) |
| 4 | **Look** | Theme, wallpaper, light or dark apps, motion (Showcase, Calm, Off) |
| 5 | **Desktop style** | Atrium or Tessera, the 20-second keep-this, the lock |
| 6 | **Updates** | State, restart when ready, undo last update, pause (Custodia), where updates come from |
| 7 | **Safety copies** | The safety nets, the copies to go back to |
| 8 | **Guard rails** | Custodia or Libertas |
| 9 | **Moneta** (named **AI** while AI is off) | Who answers (Claude, a home AI system, another AI service, No AI), sign in, voice, full access (Libertas); with No AI, the two choices and kept memory |
| 10 | **Support** | Who helps and how to reach them, Let Support see my screen, Ask Support, what changed on this computer |
| 11 | **About** | This computer, version, space, the support contact, copy details for Support |

Merged to keep the count down: text size into Screens (it is where "make everything bigger" and "make text bigger" can be told apart once); airplane mode into Wi-Fi and Bluetooth; wallpaper and light/dark into Look. Kept apart on purpose: Updates and Safety copies (one is "what's new", the other is "go back"); Guard rails and Safety copies (the brief's two pages, and the Custodia lock on the nets is explained on both).

The page name **Support** is fixed. The name in its buttons and messages comes from `helper_person` (`simple-mode.md` 5.1, Who helps): `Support` by default, or the person the machine's owner named.

---

## 2. Layout and behaviour

### 2.1 The window

- A normal app window, `Settings`, in both flavors. Atrium: it fills the screen like every app and gets the hyprbars title bar. Tessera: it tiles like any window. One instance: opening Settings again (Start, the launcher, a link from a panel or a message) focuses the open window and goes to the page asked for.
- **Light or dark follows the apps setting** (Look). Atrium defaults to light apps, so Settings is Dawn with `bronze` as the focus colour; Tessera defaults to dark, so Dusk with `sol`. Only theme tokens are used (`look.md`); the mockups show both.
- **Sidebar** (320 px at 100% text): the search field, then the eleven pages, 48 px rows, icon and name. The current page: `stone`/`dawn-raised` background and a 3 px bar in `parchment`/`ink-2`. The sidebar scrolls on its own when it does not fit (above 150% text on a 1080p screen).
- **Content**: one column, at most 880 px wide at 100% text (it grows with the text size, so lines stay about 70 characters), left-aligned beside the sidebar. Page title 30 px, one line under it saying what the page is for, then sections of cards with rows. A row: icon, name, one or two lines of explanation, the control on the right.
- **Reflow.** Settings is not meant for phones. It must work tiled: at half a 1920 screen (about 950 px) the layout is unchanged (`settings-moneta-tessera.html`). Below 720 px of window width (a Tessera third, or a small laptop at 175% text), the sidebar becomes the first page and each page opens full width with a Back arrow.

### 2.2 The gold rule inside Settings

Gold (or bronze on light) marks where the keyboard is, and nothing else: the focused field, button, row or sidebar item, as a 2 px ring. That gives at most one on screen. So:

- **Switches are not gold.** On is a dark track (`ink` on light, `marble` on dark) with the word **On** beside it; off is a `line` track with the word **Off**. The word is there so the state never depends on colour.
- **The current page is not gold** (`parchment` bar); it turns gold only while the keyboard is on it.
- **No gold buttons in Settings.** Pages are not one-job step screens. The only "next step" is the Continue after choosing how long Libertas lasts, and that one deliberately stays plain.
- Status colours as everywhere: `laurel` fine, `lapis` information (the Libertas countdown), `pompeii` needs you now (the scam line in the prompt, a net that failed).

### 2.3 Home

Title is the computer's name (`Maria's laptop`), then one line: `Everything is working.` or, when something is not, the first thing that needs doing. Two sections:

1. **This computer**: four rows that link to their page. Updates (`Up to date`, `Restart when you're ready`, or `Updates are paused until 3 October`), Safety copies (`Last safety copy at 14:00`, or `Hourly copies are off`), Guard rails (`Custodia`, or `Libertas until 15:20`), and the connection. Anything that needs the person goes to the top with a `pompeii` icon.
2. **Things people often change**: six task buttons that open the exact control, which then gets the focus ring: `Make text bigger`, `Connect to Wi-Fi`, `Connect headphones`, `Change the wallpaper`, `Get a file back`, `Get help from Support`.

This is also what Alex asks for on the phone: "open Settings and read me the top."

### 2.4 Search

`Find a setting` at the top of the sidebar, focused when Settings opens (Ctrl+F also focuses it). It searches page names, row names and a list of everyday words per row: "font", "zoom", "bigger" find Text size; "backup", "restore", "undo", "deleted" find Safety copies; "admin", "childproof" find Guard rails; "AI", "assistant", "Claude", "Moneta" find the Moneta page (the AI page while AI is off). Results replace the content column as rows (page > row); Enter opens the first. Clio writes the synonym list with the copy.

### 2.5 Keyboard

- Tab order: search, sidebar, content, top to bottom. Up and Down move in the sidebar, Enter opens a page and moves into it. Esc from the content goes back to the sidebar item; Esc in search clears it.
- Every control is 44 px or taller and reachable by Tab. Choice cards and tabs move with the arrow keys, Space or Enter picks. Switches toggle with Space.
- Collapsed **Options** rows open with Enter and say so to the screen reader (expanded or collapsed).
- Deep links for the rest of the system: `invictus-settings open <page>[/<row>]` (for example `wifi`, `guard-rails`, `safety-copies/files`). Quick settings' `More Wi-Fi settings`, Moneta's "you can do that yourself in Settings > Guard rails" and the messages all use it.

### 2.6 Text size

Settings follows the system text size (Screens and text). Everything that holds text grows with it: rows, buttons, the sidebar, the content column. Icons and borders do not. Checked at 150% (`settings-check-text-150.html`): nothing clips, nothing overlaps, the sidebar fits exactly on a 1080 screen, the one change is that it scrolls above that.

---

## 3. The pages

Each page: what it holds, top to bottom. Options rows are collapsed by default. What differs under Custodia and Libertas is marked.

### 3.1 Wi-Fi and Bluetooth

- **Wi-Fi**: On/Off switch. The Quick settings list (`simple-mode.md` 2.5), reused as is, with more rows: every network in range by signal, the connected one first with `Connected`. Click a locked network: the password row opens in place. Click the connected one: `Forget this network`, `Limit data on this network` (metered: updates wait while it is on, Minerva 2.2), `Share password` (shows it as text; the person's own).
- **Airplane mode**: switch.
- **Bluetooth**: On/Off switch. `Your devices`: each paired device with its state and battery if it reports one (`Maria's headphones · Connected · 70%`), click for `Disconnect` and `Forget`. `Pair a device` opens the list of devices in pairing mode near you, with one line: `Put your device in pairing mode. It shows up here.`
- Options: `Join a hidden network`, `Advanced network settings` (opens `nm-connection-editor`, the jargon tool, for the helper).

### 3.2 Sound

- **Output**: one row per device (`Speakers`, `Maria's headphones`, `TV`), the one in use checked, the volume slider under it (the Quick settings slider).
- **Microphone**: the device, a live level bar while the page is open, and `Test`: records 3 seconds and plays them back.
- **Alert sound**: On/Off and a volume.
- Options: `Volume for each app`, `Advanced sound settings` (`pavucontrol`).

### 3.3 Screens and text

1. **Text size**: four big steps, `100%`, `125%`, `150%`, `175%`, with a sample sentence at the chosen size. Applies at once, no keep-this (nothing can become unreadable at a larger size).
2. **Brightness** (laptops, and screens that allow it): the Quick settings slider.
3. **Your screens**: a drawing of the screens in their arrangement, each with its number, the main one marked `Main`. Click a screen to pick it; the rows under the drawing are for that screen:
   - `This is the main screen` (radio): taskbar with the clock, new windows and messages go there.
   - `Size of everything` (scaling): 100% to 200% in steps, the automatic value labelled `Recommended`.
   - Tessera only: `Workspaces on this screen` (for example `1 to 5`), which is the persistent workspace split per monitor.
   - Arrangement: drag a screen in the drawing, or with the keyboard `Move left` / `Move right` buttons on the selected screen.
   - `Identify screens` shows the big number on every screen for 5 seconds, the same card as the first-start question (`simple-mode.md` 3.2).
4. Options: `Sharpness and refresh rate` (resolution and Hz, for games), `Mirror screens`, `Turn this screen off`.

Changes to screens use the **keep-this card** (6.1 of `simple-mode.md`, 20 seconds, `Keep` / `Go back`), because a wrong scale or a screen turned off can leave the person unable to see the button that undoes it. Settings writes `~/.config/hypr/monitors.lua` (the file the wizard writes), through the A6 path: a backup first, `invictus-doctor --hypr` after, restore on failure, then reload.

### 3.4 Look

- **Theme**: four cards with the generated swatches (Dusk, Porphyry, Aegean, Alexandria), the current one checked. Applies with the theme switch ceremony (`invictus-theme apply`).
- **Wallpaper**: the theme's wallpapers, and `Choose a picture...`.
- **Apps**: `Light` / `Dark` (Atrium default Light, Tessera Dark). The shell stays dark.
- **Motion**: `Showcase` (small flourishes when windows open and at log in), `Calm` (gentle fades only), `Off` (no animation). One line under: `Games turn motion off by themselves while you play.` Uses `invictus-motion set`.

### 3.5 Desktop style

Two picture cards, Atrium and Tessera, the current one checked (`settings-desktop-style.html`), and `Switch to Tessera` (or `to Atrium`) under them with the line `You get 20 seconds to keep it. If you do nothing, it switches back.` Pressing it switches at once, no log out; the keep-this card counts down in the middle of the screen, with the keyboard focus on **Go back** so a stray Enter undoes it (`settings-desktop-style-keep.html`). No password: it changes only this person's desktop (Minerva 1.5).

Options: `Lock the desktop style` (writes `/etc/invictus/flavor.lock`, password and a safety copy, Minerva 1.5; the page then shows `Locked by <name> on <date>` and `Unlock`, also with the password), `Show background apps` in the taskbar (Atrium, off by default, `simple-mode.md` 2.3).

### 3.6 Updates

- **State card**: `Up to date. Checked at 13:05.`, or `Updates are ready. Restart when you're ready.` with `Restart now`. After an update that needs a restart, the only nudge is a quiet message, `Restart when you're ready`, at most once a day, never forcing, never at night (Alex, 2026-09-30). There is no night-restart setting.
- **Undo the last update**: `Undo last update` with one line of what it undoes (`38 changes from yesterday 03:10`). No password (Minerva tier 1).
- **What changed**: the last update in plain names (`Internet (Zen Browser) 128 to 129`, then `and 34 parts of the system` collapsed).
- **Custodia**: `Pause updates` with `1 day`, `7 days`, `14 days`. The system prompt holds for 5 seconds and says `Updates keep this computer safe. Paused updates start again by themselves on <date>.` While paused, the card says so with `Resume now`.
- **Libertas**: no Pause. The row `Automatic updates: On` links to Safety copies, where the switch lives with the other nets (accepted by Minerva, 12.4).
- **Where updates come from**: `Stable: tested for a week before it reaches you`. Custodia: locked to Stable, with `Custodia keeps Stable.` Libertas: `Testing` can be chosen, with the password.

### 3.7 Safety copies

See section 5.

### 3.8 Guard rails

See section 4.

### 3.9 Moneta

(`settings-moneta-tessera.html`)

- **Who answers**, one choice:
  - `Claude`: `Anthropic's Claude, with your own Claude account. It can do things for you after asking.` (preselected, D13)
  - `A home AI system`: `A model on this computer or on your home network. Nothing leaves your home.` Picking it asks for the address, or offers `Use this computer` when the local model package is installed (D15).
  - `Another AI service`: `An account you already have with another AI company. It answers; it can't do things by itself.` (the chat-only `openai-compatible` provider; its key goes to the keyring)
  - `No AI`: `Guides and Support. Moneta and voice are removed from this computer.` (`none`; replaces the quiet `Turn Moneta off` link, Alex 2026-09-30). Picking it opens a confirm in the row: `Turn off AI?` / `Moneta and voice are removed from this computer, and you're signed out of Claude on this computer. Moneta's memory and past conversations stay on this computer until you delete them. Help keeps its guides and Ask Support.` / `Turn off AI` and `Cancel`, equal weight. No password: instant from a local active session, like the return to Custodia (Minerva N1, `design-no-ai.md`). What it removes and keeps: `no-ai.md` 5.
- **Account**: `Signed in to Claude`, since when, `Working` or `Can't reach Claude`; `Switch account` and `Sign out`. Not signed in (AI on, no working credential): the Account card moves to the top with `Sign in to Claude...`, and No AI stays the switch; `no-ai.md` 2.3 (`settings-moneta-not-signed-in.html`). Sign in opens the browser; the window comes back when done. Settings never sees the token.
- **Voice and limits**:
  - `Talk to Moneta`: `Hold the pen button and speak. Your voice is turned into text on this computer, then sent.` On/Off.
  - **`Full access`** (Alex, 2026-09-30, DS11): `Let Moneta use the terminal and every tool, like a person at the keyboard. It still asks before each change, and system changes still need your password.` **Libertas: a switch, off by default.** **Custodia: locked off** with `Custodia keeps Moneta to a fixed set of safe tools.` Turning it on asks for the password with no hold and no warning: Libertas was the guarded step (Minerva 12.3: its own action, `org.invictus.sys.assistant-full-access`, password every time, never cached; the value lives in `/etc/invictus/assistant`). Turning it on or off restarts Moneta with `Moneta is starting again with the new rules` (the same restart as a guard-rails switch, Minerva 1.6 G7). **It ends with Libertas**: during a timed Libertas the row says `Ends with Libertas at 15:20`, and any return to Custodia (the click, the hour running out, a restart after the hour) turns it off; the row then says `Turned off when guard rails came back on at 15:20.` Going back to Libertas needs the switch again (not the nets pattern; Minerva 12.3 says why).
- Options: `Team and memory` (local only, connect to a team repo, or make a new one), `A command-line agent` (only while Full access is on: `generic-cli`, the command filled in by the person; with Full access off or under Custodia the row is locked and a configured agent does not start, with `Moneta's command-line agent is off. Pick who answers in Settings > Moneta.`, Minerva 12.3).

### 3.9.1 With No AI

(`settings-ai-off.html`)

The sidebar entry and the title read **AI**: the name of a thing that is not on the computer means nothing, and "AI" is the word the person chose by. Search finds it by the same words.

- Line: `Whether Help includes an AI assistant. It is the same for everyone who uses this computer.` (machine-wide, like Guard rails: the packages are.)
- **Help works with**: two choice cards, the Guard rails pattern (4.1), the current one first with `On now`:
  - **No AI**: `Short how-to guides you can search, and Support when you need a person. Nothing on this computer uses AI.`
  - **An AI assistant**: `Moneta answers questions, by voice or typing, and fixes things after asking you. It uses Claude with your own account, or another AI you choose.` and `Turn on Moneta...` with `Downloads Moneta, then asks for your password.` Clicking it opens the Who answers rows inside the card (Claude preselected, D13), then the password prompt (the polkit agent, a safety copy first; Minerva N1: its own action, `org.invictus.sys.ai-on`, the password every time, never cached, never through the help unlock), then the sign-in. The card shows `Downloading Moneta, 40%` until it is ready; the page then becomes the Moneta page.
- **Kept from before**, only when there is something: `Moneta's memory and past conversations`, `Kept on this computer since AI was turned off on 28 September. Moneta picks them up again if you turn AI back on.`, the size, and `Delete...` (`Delete Moneta's memory?` / `This can't be undone. Your own files and notes are not touched.` / `Delete` · `Cancel`; no password).
- Nothing else. No Account, Voice or Full access rows, not even greyed out, and no line about what AI would add.

### 3.10 Support

Minerva (`design-inbox.md`, 2026-09-30): this page also gets **Connect to Support** (paste the code, password) and **Disconnect** (one click), **Your requests** with their states, the connection's end date, and the top line reads `/etc/invictus/helper.conf`, which only the hold-list password prompt can change (3.5 there).

- **Top line**: `Sol Invictus support · solinvictus.support@gmail.com` (from `helper_person` and `helper_contact`; a person's name and address when the owner set them).
- **Let Support see my screen**: the same label as the Help panel's button, and it starts a help session exactly as that button does (Minerva 5.2): the helper's RustDesk ID only, Accept on the person's screen, the banner and Stop. While a session runs, this page shows `Support is helping now` and `Stop`.
- **Ask Support**: opens the Help panel with Ask Support ready (the helper request, `simple-mode.md` 5.1). One place for the request, not two.
- **What changed on this computer**: the record (Acta) in plain words, newest first: `Today 11:02 · Maria installed Spotify`, `29 Sep · Maria turned off hourly copies`, `22 Sep · Guard rails: Custodia to Libertas, by Maria`. Each system change links to its safety copy with `Go back to this`.
- Options: `Screen help ID` (for when Support asks for it), and if DS9 is ever approved, `Remove the support account`.

### 3.11 About

`Maria's laptop` (rename under Options), `Invictus 1.0 · Stable · updated 29 Sep`, `Atrium · Custodia`, the hardware in one line (`AMD Ryzen 5 7640U · 16 GB memory · Radeon 760M`), space as a bar (`212 GB free of 476 GB`), the support contact (`Sol Invictus support · solinvictus.support@gmail.com`, as on the Support page), and `Copy details for Support`: a plain-text block of the above plus the doctor's summary, with no serial numbers, MAC addresses or user names.

---

## 4. Guard rails

(`settings-guard-rails-custodia.html`, `-to-libertas-hold.html`, `-libertas-timed.html`)

### 4.1 The page

Title `Guard rails`, and the line: `How careful this computer is before big changes. It is the same for everyone who uses this computer.` (machine-wide, unlike Desktop style).

Two cards, Custodia first. The current one has a 2 px `parchment`/`ink-2` border, a filled radio and `On now`.

- **Custodia**: `The computer pauses and explains before anything that could erase or break it, and Help only does safe things on its own. Safety copies are always on, so a change can be undone.` Under it, collapsed: `What Custodia does, in detail`, which lists G3 to G7 in plain words (pauses before erasing a disk or removing core parts of the system; the scam warning on every password prompt; Help sticks to a fixed set of tools; updates can be paused but not turned off; the safety nets stay on). With No AI the Help clauses go from both cards (`and Help only does safe things on its own`, `and Help can do more on its own`) and from this list, since there is nothing for them to describe (`no-ai.md` 6, Minerva N4).
- **Libertas**: `Nothing pauses or warns you before something is erased, and Help can do more on its own. Safety copies stay on unless you turn them off.` Under Custodia it also shows the scam line, `If someone on the phone or a website told you to do this, stop and use Ask Support in Help.`, and `Switch to Libertas...`.

The footer is the honest record, from Acta: `Custodia since this computer was set up, 12 September. Switching back to Custodia is always instant.`

Clio polishes all four sentences; the rule is two sentences each, the first about what happens before a big change, the second about the safety copies.

### 4.2 To Libertas

1. `Switch to Libertas...` (clicking anywhere on the Libertas card does the same) opens a short question inside the card: **For how long?** `For an hour` (preselected; `Guard rails come back on by themselves at 15:20`) and `Until I turn them back on` (DS13). `Continue`, `Cancel`.
2. `Continue` runs `invictus-sys guardrails set libertas --for 1h` (or no `--for`), and the system password prompt appears: the one Invictus polkit agent (G1), not a Settings dialog, so Settings never sees the password. It dims the screen and shows:
   - `Your password is needed`, then the heading `Switch to Libertas for an hour?` (or `...until you turn them back on?`)
   - Minerva's warning, in the page's words: `Nothing pauses or warns you before something is erased, and Help can do more on its own. Safety copies stay on unless you turn them off. Guard rails come back on by themselves at 15:20.`
   - The scam line on a `stone` block with a `pompeii` edge and icon.
   - The password field, disabled for 5 seconds (G6 hold list), with `You can type your password in 3 seconds` counting down and a thin `parchment` bar emptying under it. The count is a countdown, not progress, so it is not gold.
   - `Cancel` and `Switch to Libertas`, equal weight, as the approval cards. **Focus starts on Cancel**, so Enter during the hold cancels. When the hold ends, focus moves to the password field.
   - `Asked by Settings. A safety copy is made first.` and `Details` (the action id, for the helper).
3. On success: the page shows the Libertas state (4.3), and the safety copy `Before guard rails were switched off` is on the Safety copies list.

Clicks from Settings: 3 (Switch to Libertas, Continue, Switch) + wait + password. Decisions: 0 if the hour is right, 1 if not.

### 4.3 While Libertas is on

- **Timed** (`settings-guard-rails-libertas-timed.html`): a card above the two choices, `lapis` edge: `Libertas until 15:20`, `Since 14:20 today. Switched by Maria, with her password. A safety copy was made first.`, the minutes left, large, and a bar that empties (all from `/etc/invictus/guardrails-until`, Minerva 12.1). If Full access is on, one more line: `Moneta's full access ends then too.` The sidebar item shows `42 min`. The **taskbar** (Atrium) or the **bar** (Tessera) shows `Libertas · 42 min` with the shield, `lapis` outline, one click opens this page. When it ends, a message: `Guard rails are back on` / `Custodia is on again.` (`laurel`, 8 s).
- **Until turned back on**: the same card without the countdown: `Libertas since 22 September. Switched by Maria, with her password.` No taskbar badge: someone who chose "until I turn them back on" chose it for good (Alex's own machines), and a permanent badge would be noise. The home page, the doctor and the helper digest still say it (Minerva TS11).
- The Custodia card shows `Turn guard rails back on now`, `Instant. No password.`

### 4.4 To Custodia

One click, no password, no question (Minerva 1.6: instant, local session only). The page updates at once; the Acta line is written; Moneta restarts with the new rules if it was running. If the person had turned nets off under Libertas, the Safety copies page shows them all locked on again, and their choices come back if they go to Libertas again (Minerva's nets file). Moneta's Full access is turned off, not remembered (Minerva 12.3).

### 4.5 Edge cases the page must show honestly

- **During a help session**: switching to Libertas is not possible from the helper's side; the page still offers it to the person, and the prompt still needs their password at their keyboard. The page does not hide this.
- **Finishing an update first**: `guardrails set` waits for a running update. The prompt stays up with `Finishing an update first` under the heading.
- **Changed elsewhere** (the hour ran out, or a terminal): Settings watches `/etc/invictus/guardrails` and redraws; it never shows a stale state.
- **Restart during a timed Libertas**: the hour is a wall-clock end time in `/etc/invictus/guardrails-until` (Minerva 12.1), not a running timer, so a restart does not extend it; a machine that is off when the hour ends comes back as Custodia before anyone can log in, and shows `Guard rails are back on` at the first login. Settings, the taskbar and the bar read the end from that file and never compute one.

---

## 5. Safety copies

(`settings-safety-copies-libertas-one-off.html`)

### 5.1 Words

| On screen | Is |
|---|---|
| Safety copy | A snapshot |
| Your files | `@home` |
| The system | `@` (apps, settings, the system itself) |
| Go back to this | Roll back to that snapshot |
| Look inside | Open the read-only snapshot folder in Files |
| Last good start | The "last good" snapshot the boot guard keeps |
| Start-up guard | The boot guard and automatic rollback (G9) |
| Copy before password changes | The pre-admin snapshot (G2) |

The page is titled `Safety copies`: `Copies the computer can go back to, so a change or a mistake can be undone.`

### 5.2 Safety nets

One card, five rows:

| Row | Explanation | Custodia | Libertas |
|---|---|---|---|
| Copy before password changes | `When you type your password to change the computer, the system is copied first.` | Locked on | Switch (`pre-admin-snapshot`) |
| Copy before every update | `Can't be turned off: without it an update has no way back.` | `Always on` | `Always on` (snap-pac, not a net, Minerva 1.6) |
| Hourly copies of your files | `Your photos, documents and other files, every hour. Kept a day, then one a day for a week.` | Locked on | Switch (`home-snapshots`) |
| Automatic updates | `Updates install by themselves while you're not using the computer.` | Locked on | Switch (`auto-update`) |
| Start-up guard | `If the computer can't start twice after an update, it goes back to before it.` | Locked on | Switch (`boot-guard`) |

- **Custodia**: every row shows a lock and `On`, and the section header says `Custodia keeps these on.` No switch at all (G5b).
- **Libertas**: switches, and the header says `Libertas lets you turn these off, with your password.` Turning one off asks for the password (`invictus-sys set-config nets.<key> off`, `auth_admin_keep`), with no hold and no scam line (Minerva 1.6). A net that is off keeps a line under it saying since when and what that means: `Off since 29 September. Files deleted since then can't be brought back.` Not red: it was the person's choice.
- A net that is on but failing (no copy for over 24 hours, disk too full) shows a `pompeii` line and `Fix` (opens Help with the problem written in; with No AI it opens the guide the net names, `Free up space` or `Safety copies aren't working`, or Ask Support with the problem filled in, as `simple-mode.md` 4.1 rule 7).

### 5.3 Go back

Header `Go back`, with `Copies use 14 GB. Old ones are removed by themselves.` on the right. Two tabs, `Your files (31)` and `The system (8)`.

**The system**: newest first, three shown, `Show all 8`. Each row: when (`Today 11:02`), why in plain words (`Before installing Spotify`, `Before an update`, `Before adding a printer`, `Before guard rails were switched off`; the description comes from G2's "Before: <service>" through the same message table as the password prompts), a `Last good start` tag on that one, and `Go back to this` on every row (visible, not on hover). Line beside the tabs: `Going back restarts the computer. Your own files don't change.`

`Go back to this` opens a confirm card: `Go back to Tuesday 11:02?` / `Apps and settings go back to how they were then, and the computer restarts. Your own files don't change. A copy of now is made first, so you can come back.` Buttons `Go back and restart` and `Cancel`, equal weight; then the password prompt (tier 2 `rollback <id>` under Custodia; `auth_admin_keep` under Libertas).

**Your files**: grouped by day, each hour a row. In v1 one action per row: **Look inside** (opens that copy, `/home/.snapshots/<n>/snapshot/<user>/`, in Files, read-only, to copy one photo back: the common case, "put my photo back"). Minerva 12.2: a whole-files restore is the one action on this page that can silently remove hours of work from every app, and it cannot run cleanly while the person is logged in, so it is v1.1 as a logout-time job. **v1.1: Go back to this** (all your files as they were then; a copy of now first; runs when you log out; confirm card `Put all your files back to 14:00?` / `Files you changed or added since then go back to how they were when you log out. A copy of now is made first.` with `Log out now` and `Later`). No password: they are the person's own files.

The home page's `Get a file back` opens this tab.

---

## 6. Messages Settings adds

Same patterns as `simple-mode.md` 4.

| When | Title | Body | Buttons | Bar |
|---|---|---|---|---|
| Timed Libertas ends | `Guard rails are back on` | `Custodia is on again.` | none (8 s) | laurel |
| An update needs a restart (once a day at most) | `Restart when you're ready` | `An update finishes when the computer restarts. Your apps open again after.` | `Restart now` · `Later` | lapis |
| After going back (system), on the next start | `Your computer went back to Tuesday 11:02` | `Apps and settings are as they were then. Your files are fine.` | `Got it` | laurel |
| After going back (files), at the next login (v1.1) | `Your files are back to 14:00` | `A copy of how they were before is in Safety copies.` | `Open Safety copies` | laurel |
| Screens changed, keep-this | (the card, not a message) | | `Keep` · `Go back` | |

---

## 7. What to build it with

**Quickshell**, as its own config and process (`qs -c invictus-settings`, started by `invictus-settings`), one normal toplevel window (Quickshell's `FloatingWindow`), in both flavors.

Why:

- **The pieces already are QML.** The Atrium shell (Wi-Fi list, sound slider, keep-this card, approval cards), the first-start wizard (monitor question, provider cards) and the polkit agent are Quickshell. Settings reuses them, so the Wi-Fi list is one component, not two.
- **The services are there.** Quickshell 0.3.1 in `extra` ships `Networking`, `Bluetooth`, `Services.Pipewire`, `Services.UPower` and `Services.Polkit` (checked against the package file list, 2026-09-30), and `Quickshell.Io` for watching `/etc/invictus/guardrails` and `nets`.
- **Both flavors have Quickshell anyway**: the polkit agent is Quickshell in Tessera too (G1), so Tessera gains no new runtime.
- **Themes**: the theme tool gets one more template (tokens as a QML singleton), like every other surface.

Against GTK 4 / libadwaita: keyboard navigation, screen reader support and text scaling come free, which is a real loss here; but it would mean a second Wi-Fi list, sound slider and keep-this card in another toolkit, its own NetworkManager, PipeWire and BlueZ bindings, and libadwaita's look and words to fight. Against GNOME Settings (`simple-mode.md` 8.5): its panels lean on GNOME session services, and it brings GNOME's words. Against Qt Widgets: nothing shared.

What Quickshell costs, and the builder must do on purpose: Tab order, focus rings, arrow-key groups and `Accessible` roles and names on every control (Qt Quick Controls give the base; the look is ours). Settings runs as the person; anything root goes through `invictus-sys` verbs and the polkit agent, and Settings never sees a password.

**New shared piece**: `invictus-qml`, a QML module (tokens singleton, Card, Row, Switch with its On/Off word, ChoiceCard, Tabs, KeepThisCard, WifiList, VolumeSlider, ConfirmCard), used by the Atrium shell, the wizard and Settings. Goes into `docs/reuse-catalog.md` when merged.

---

## 8. Taps and decisions, before and after

Before = what exists today in Invictus (Tessera tools and the terminal). Counted from the desktop, Settings closed.

| Task | Before | After |
|---|---|---|
| Make text bigger | Launcher, `nwg-look`, find the font size, change it, apply: about 6 steps, 2 jargon words | Start, Settings, `Make text bigger`, pick 150%: 4 clicks |
| Switch to Libertas for an hour | Not possible on screen (terminal verb) | Start, Settings, Guard rails, Switch to Libertas..., Continue, wait 5 s, password, Switch: 6 clicks + password, 0 decisions |
| Guard rails back on | Terminal | Taskbar `Libertas · 42 min`, Turn guard rails back on now: 2 clicks |
| Get a deleted photo back | Terminal (`snapper`, a mount) | Start, Settings, `Get a file back`, Look inside on the hour, copy the photo in Files: 5 clicks + drag (v1's only files restore, Minerva 12.2) |
| Undo a bad app install (system) | Terminal (`snapper rollback`) | Settings, Safety copies, The system, Go back to this, Go back and restart, password: 5 clicks + password |
| Turn off hourly copies (Libertas) | Edit a config as root | Settings, Safety copies, the switch, password: 3 clicks + password |
| Change motion to Calm | Launcher, `Change motion`, pick: 3 steps | Settings, Look, Calm: 3 clicks |
| Switch to Tessera | Not possible | Settings, Desktop style, Switch to Tessera, Keep: 4 clicks |
| Use a home AI system | First-start wizard only | Settings, Moneta, A home AI system, Use this computer: 4 clicks |
| Turn AI off | Settings, Moneta, Turn Moneta off (provider `none`; everything stays installed) | Start, Settings, Moneta, No AI, Turn off AI: 5 clicks, 0 decisions after the first; removes it |
| Turn AI on (from No AI) | Not possible without the wizard | Start, Settings, AI, Turn on Moneta..., Claude (preselected), password, sign in: 5 clicks + password + sign-in |

---

## 9. For Minerva (questions the pages raise)

Answered (Minerva, 2026-09-30, `design-simple-mode.md` section 12): 1 is 12.1 (the until-file is `/etc/invictus/guardrails-until`, enforced by a root timer, at boot and by `invictus-sys`); 2 accepted, 12.4; 3 is `Look inside` only in v1, the logout job in v1.1, 12.2; 4 confirmed with its own action, no keep, and cleared on every return to Custodia rather than remembered, 12.3; 5 as assumed, both read the until-file. Sections 3.9, 4.5, 5.3 and 6 above carry the changes. No AI's questions (N1 to N8, `no-ai.md` 7) are answered in `design-no-ai.md`; 3.9, 3.9.1 and 5.2 carry those.

1. **Timed Libertas across a restart.** The page says `until 15:20`. The design assumes a wall-clock end (`OnCalendar` with `Persistent=true`), so a restart never extends it and a machine off at 15:20 comes back as Custodia. Also: the end time must be readable by the session (for the countdown), for example `/etc/invictus/guardrails-until`, 0644.
2. **The nets switches' home.** Minerva put the automatic-updates and start-up-guard switches under Settings > Updates; this design puts all nets on Safety copies, with a link from Updates. One place for every net, which is also what the Custodia lock explains once. If she wants them on Updates, the rows move; nothing else changes.
3. **Going back for "Your files".** Restoring all of `@home` swaps a mounted subvolume, which needs root and ideally no open files. Is it a tier 1 verb (it only moves between states the person's own files have been in), a logout-time job, or Look inside only in v1?
4. **Full access (DS11 answer)**: writing the managed-settings choice is root. The page assumes the password, like other `set-config` keys, and no hold. Confirm, and that it follows the nets pattern: ignored under Custodia, remembered for Libertas.
5. **The taskbar badge** for timed Libertas lives in the Atrium shell and in waybar. Both read the same until-file.

---

## 10. Verified, and not

Verified 2026-09-30: Quickshell 0.3.1 (`extra`) package file list includes the QML modules `Bluetooth`, `Networking`, `Io`, `Services/Pipewire`, `Services/Polkit`, `Services/UPower`, and depends on `qt6-declarative` (Qt Quick Controls).

Not verified: that Quickshell's `Networking` joins a secured Wi-Fi network with a password and its `Bluetooth` module pairs (the modules exist; features unread); that a Quickshell `FloatingWindow` behaves as a normal app window under hyprbars and in monocle; that Qt's accessibility bridge exposes Quickshell windows to a screen reader under Hyprland; that `claude` login can run from a button without a visible terminal (it prints a URL; the Moneta panel may need to drive it in a pty). The mockups are drawings, not the built app.

---

## 11. Reused / new, and why

Reused: the theme tokens and both light and dark sets, the gold rule, the Quick settings Wi-Fi list and volume slider, the keep-this card (display-resolution pattern, `simple-mode.md` 6.1) for desktop style and screens, the first-start wizard's screen question for `Identify screens`, the theme picker's generated swatches, `invictus-theme`, `invictus-motion`, `invictus-update`, `invictus-doctor` (home page state, `Copy details`), Acta (what changed, the guard-rails history line), the Invictus polkit agent (every password, the hold, the scam line), `invictus-sys` verbs (`guardrails set`, `set-config`, `update-pause`, `update-undo`, `rollback`), the approval card's equal buttons (the Libertas prompt, the go-back confirm), the setup cards' parchment selection border (choice cards), the Help panel's Ask Support and Get help flows, and the A6 backup-and-check path for `monitors.lua`.

New, because nothing does the job: the Settings app itself (no settings tool on the system speaks plain words; nwg-look, pavucontrol and nm-connection-editor stay as Options links), the `invictus-qml` shared module (extracted from the Atrium shell so three programs use one set), the Libertas countdown badge, the until-file, and the search synonym list.
