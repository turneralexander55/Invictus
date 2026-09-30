# Invictus: the Desk

Status: design, not yet built. Owner: Venus (designer). Date: 2026-09-30.
Asked for by Alex (2026-09-30): the Desk becomes fully part of Invictus and its team harness. Minerva designs the architecture (data store, sync with the claude.ai Desk, the agent-neutral protocol) in parallel; where her design plugs in is marked **[D1]** to **[D12]** and listed in section 9.

This doc replaces the Desk part of `look.md` ("The Desk") and the Desk table in `no-ai.md` 4; both now point here. The claude.ai Desk (`projects/personal/iris-dashboard/design.md` in the team repo, sections 16 to 25) is the source for sections and wording: Alex uses it every day, so the Invictus Desk says the same things in the same words and only changes what a keyboard and a 1920 px screen change. The claude.ai page itself is the Desk app session's; nothing here edits it.

Mockups (`docs/mockups/`, 1920 x 1080, self-contained HTML, same tokens, fonts and scale-to-fit script as the other mockups; names, projects and items are sample data):

| File | State |
|---|---|
| `desk-tessera.html` | Tessera, AI and a team: the Desk as home screen, All projects, focus on Now. Mid-session: Team now, In progress and Moneta opened |
| `desk-card-mockups.html` | The same Desk with a decision carrying three mockups at the top of Needs you, selected, a comment being typed |
| `desk-no-ai.html` | Tessera with No AI: Now set by hand with a running timer, Today's notes, system items waiting, Add a note |
| `desk.html` | The first Desk sketch from the look job, kept for history; superseded by the three above |

---

## 0. In one screen

- **Tessera: the Desk is the home screen.** It opens at login on the main screen, and a tap of **Super** (press and release, nothing else) shows or hides it from anywhere. `Esc` hides it too. It slides over whatever is open and slides away; nothing under it moves.
- **The Now line is the anchor.** The bar's `Now · ...` and the Desk's Now card are the same line from the same file. Clicking the bar's Now opens the Desk (with AI and without). When the Desk opens, the keyboard starts on Now.
- **Same sections and words as the Desk on Alex's phone**: Needs you (Approve/Deny, Pass/Fail, Today), Later, Your list, Guides, Done; Team now, In progress, Design decisions, From the team; Moneta (notes, replies, Push to Moneta). Three columns on one screen: **you**, **the team**, **Moneta**.
- **Keyboard first.** Arrows (or `hjkl`) move one gold marker; the selected card answers to one letter (`A` Approve, `D` Deny, `P` Pass, `F` Fail, `Space` tick, `L` Later, `N` note). Every answer has 6 seconds of Undo. A key hint line sits at the bottom, like the launcher's.
- **ADHD rules**: one gold on the Desk (where the next key goes); Needs you shows at most 3 cards, the rest wait their turn in a counted queue; nothing blinks, pulses or counts down in seconds outside the timer; no popup per new item.
- **Projects** are tabs under the Now card with their "need you" counts, keys `0` (All projects) to `9`.
- **No AI**: the same Desk frame with facts only: Now by hand with the timer, Today's notes, system items, `Add a note`. Nothing says AI is missing.
- **Atrium: a Desk only when the person has a team.** Without a team (every friend's machine by default) Atrium has no Desk, as before; with one, the Desk is an ordinary app in Start. Section 1.3 says why.

---

## 1. Where the Desk lives

### 1.1 Tessera

- **Surface.** A full-screen Quickshell window on the special workspace `desk` of the main monitor (look.md motion: `specialWorkspace`, `slidefadevert 16%`, 260 ms in Showcase, a fade in Calm, a cut in Off). It is not in the tiling, so opening it never reflows windows. The bar stays on top. Other monitors are untouched: one place to look.
- **At login** it is the first thing on the main screen. Nothing else opens over it on its own.
- **Super tap.** `bind("SUPER + SUPER_L", dsp.exec_cmd("invictus-desk toggle"), "Desk: show or hide", { release = true })`. Read in Hyprland 0.56.2's `KeybindManager.cpp` (not run): a release bind on the modifier fires only when nothing else was pressed with it, because any bind that fires while Super is down (Super+Q, Super+1, Super+drag, Super+scroll) shadows it until Super is up (`shadowKeybinds`). One gap: Super plus a key that is **not** bound (Super+Z today) does not shadow it, so the Desk opens on release. Acceptable (nothing is lost; tap Super again), but Vulcan checks it on hardware and in `tests/hyprland-lua` (mock_hl already accepts `release`). Super tap is free today in Tessera and matches Atrium, where the same tap opens Start (`simple-mode.md` 2): in both flavors a tap of Super goes home. The launcher is Super+Space, and look.md's old Super+D clashed with Discord (Moneta's ruling: Alex's app keys stay).
- **Hiding.** Super tap, `Esc` (when no field has the keyboard; in a field, `Esc` first leaves the field), clicking the bar's Now again, or switching workspace. The Desk keeps its state while hidden: folds, the selected card and a half-typed note are where Alex left them (it is a window, not a page load).
- **Launcher and cheatsheet.** `Desk` is also a launcher entry and in `show-keybindings` as "Desk: show or hide (tap Super)".

### 1.2 The Now line

- One plain file, `~/.local/state/invictus/now` (already the No AI design): the text, who set it, since when, and a running timer if any. The bar module and the Now card both read it; the card and Moneta both write it **[D10]**.
- Bar: `Now · Port the waybar config to Lua`, `parchment`, 40 characters (look.md). With a running timer the bar adds whole minutes, `· 19 min`, updated once a minute; never seconds in the bar.
- Click opens the Desk with the keyboard on Now. This changes look.md, where a click opened the Moneta panel's threads: the Desk is now where lost threads are found (Switch lists them), and one target for both AI and No AI is one rule to learn.
- The Now card: `NOW`, the text (20 px), who and since when (`Vulcan · Invictus · since 18:40 · 2 of 4 parts`, or `since 20:40` when set by hand), and three buttons: `Done` (`Space`), `Switch` (`S`: a list of open threads, In progress items and recent Nows to pick from; typing filters it; `Enter` picks), `Timer` (`T`: starts 25 minutes, preselected; `T` again pauses; the minutes are under Options in the timer row). While a timer runs, the card shows `18:42 left of 25 min` and `Pause`.

### 1.3 Atrium: a Desk only with a team

Minerva's and Clio's notes (`design-simple-mode.md`, `simple-mode.md` 6) said Atrium has no Desk. That was right for what they were designing: a friend's machine with Help, and a friend has no team, no projects and nothing waiting on them from agents. Since then flavors and guard rails became independent (any combination) and the team harness ships with Invictus, so a person can have Atrium **and** a team (Alex's sister runs Atrium but wants to try a Collegium, or Alex himself on the living-room PC).

Decision: **the Desk follows the team, not the flavor.**

| | No team (Collegium not set up) | Team connected, created or local-only |
|---|---|---|
| Tessera | The Desk without team sections: Now, Today, system items (section 7 frame, AI or not) | The full Desk |
| Atrium | **No Desk.** Help and messages do its job, as `simple-mode.md` says | **Desk is an app in Start** ("Desk", pinned when the team is set up) |

The simplest Atrium form: the same Desk in a normal full-size Atrium window with its title bar, light (Dawn, like every Atrium app), no Super tap, no key hint line (the keys still work), and no Now line in the Atrium taskbar (Atrium has none). New Needs you items arrive as one Atrium message a day at most: `The team has 3 things for you` with `Open Desk` (message rules, `simple-mode.md` 4.1). No mockup: it is the Tessera layout in a window, and the layout already works from 1280 px (section 2.3).

Why not keep "never in Atrium": a person with a team in Atrium would have decisions waiting and nowhere to answer them. Why not a smaller "Atrium Desk": a second design to keep in step, for a handful of people.

---

## 2. Layout

### 2.1 1920 x 1080, top to bottom

```
bar (32)   1 2 3  Desk                     21:14            Now · Port the waybar config to Lua   ...
 ALEX'S DESK                                        [7 Need you] [13 In progress] [35 Done ▂▅▁▇▄▃▆]
 Updated 21:04 by Moneta · Wednesday 30 September
┌NOW  Port the waybar config to Lua   Vulcan · Invictus · since 18:40 · 2 of 4 parts   Done Switch Timer┐
 0 All projects 7 need you   1 Liberalitas 4   2 Invictus 3   3 HawkSearch   4 The Desk     ⟳ Synced 21:06
 YOU (640)                    │ THE TEAM (560)                 │ MONETA (480)
 NEEDS YOU (7)                │ TEAM NOW  3 working  Team (21) │ MONETA  2 new      Push to Moneta
  [card] [card] [card]        │  Vulcan ... bar                │  Since your last push: 1 note, 2 answers.
  4 more wait here  Show all  │ IN PROGRESS 13 · 2 blocked     │  [Note to Moneta        For: Invictus]
 LATER 2                      │  LIBERALITAS / INVICTUS folds  │  notes and replies, newest first
 YOUR LIST 8 · 1 due          │  Paused and done               │  All notes (23)
 GUIDES 1                     │ DESIGN DECISIONS 14            │
 DONE 12 this week            │ FROM THE TEAM 2                │
 ↑↓←→ move · Enter open · A/D approve, deny · P/F pass, fail · Space tick · L later · N note · 0–4 project · ? · Esc
```

- Side gutters 80 px; content 1760 px; columns 640 / 560 / 480 with 40 px gaps. The team column is 560 because that is the claude.ai Desk's column width, so rows and cards carry over unchanged. The you column is wider because answer cards hold a comment field and two buttons on one line.
- Header, Now and project tabs stay put; **each column scrolls on its own**, and the column holding the selection scrolls to keep it in view. A column that runs past the bottom fades out over its last 36 px (no scrollbar until the pointer is over it). This departs from the phone's one page scroll: three columns of different lengths on a wide screen would otherwise scroll each other off.
- Why this split: it is the phone's wide layout (left "you", right "the team", `design.md` 21.2) with Moneta taken out of the team column into its own, because on a desktop the conversation is used while reading the other two.
- **Charts** (phone 21.9) are left out at first: the glance tiles keep the 7-day Done strip, In progress rows already are bars, and four more charts would be a fourth thing to read on the home screen. If Alex misses them, they go in the header's right half in place of the tiles (For Alex, 11).

### 2.2 Header

- `Alex's Desk` in Cormorant SC 32 px (display type, allowed on a glance surface, look.md Typography); the name comes from the account. Under it, `Updated 21:04 by Moneta · Wednesday 30 September` in `ash`.
- **Glance tiles** (phone 21.4 V1, same numbers, same sources): Need you (count; line `8 on your list · 2 later`; a 3 px `marble` stripe when above 0), In progress (count; `2 blocked` in `pompeii`, or `all on track`), Done (last 7 days, with the 7-column strip, today in `marble`). Each is a button that goes to its section and opens it.
- **Sync line** at the right of the tab row: `Synced with your phone 21:06`, or `Offline · 2 answers wait to sync` in `ash`, or `Not synced since 14:02` in `pompeii` after an hour of failure **[D2]**. Words only; no spinner.

### 2.3 Other screen sizes

| Width of the Desk | Layout |
|---|---|
| 1760 and up | As above; the three columns grow to 720 / 620 / 540 at most, then centre |
| 1280 to 1759 | Three columns shrink in proportion; the answer row wraps its buttons under the field below 560 px |
| 900 to 1279 | Two columns: you, and the team with Moneta at its top (the phone's wide layout) |
| under 900 (Atrium window made small, a tall portrait monitor half) | One column in the phone's cover order |

Portrait monitors: the Desk uses the main monitor's width. Text size (Settings > Screen) scales everything; at 150% the 1920 layout behaves like 1280.

---

## 3. The sections

Everything below keeps the phone's rules, words and data (`posting.md`) unless it says otherwise. Section order is fixed; an empty section is left out.

### 3.1 Needs you (you column, first)

- What goes in (phone 16.3): open decisions, unanswered checks (`waiting on you`), Today's tasks and drafts; answered means gone; a team update brings a parked card back tagged `Updated since you parked it`.
- **Capped at 3 cards on screen.** Order as on the phone: decisions, then checks, then Today. The rest sit in one dashed row: `4 more wait here. Each one moves up when you answer one.` and `Show all` (`Enter`), which opens them in place (one level). The heading keeps the full count in its pill (`NEEDS YOU 7`) and says `3 shown, the rest wait their turn`. Three is Today's existing cap and what fits at 1080 without scrolling; one screen of choices is the point.
- **The pill** is the Desk's one filled badge: `marble` on `night`. Not gold (gold is focus), not `pompeii` (nothing is wrong).
- **The card.** Kind label with an icon (`Decide`, `Check`, `Today`, in `parchment`; colour is never the only sign), `· Moneta · Invictus · 40 min ago`, the title (15 px), the body (13 px, the phone's 600-character cap), a check's bar and percent, mockup thumbnails (3.2), then the **answer row**: `Comment (optional)` field, the screenshot button, and the two buttons, equal weight (`stone`, `marble` text, the same width), each with its key: `Approve A` `Deny D`, or `Pass P` `Fail F`. Under it: `Later L` and `Note to Moneta N`. A Today card has a tick box with `Space` instead of the answer row.
- **Comments** follow the phone exactly (16.7, 24): the field is sent with whichever answer is pressed; it opens to a box when it has the keyboard; `Enter` adds a line and never sends; up to 2000 characters with a counter from 80%; over the limit, nothing is cut and the buttons are off. From the keyboard: `C` puts the keyboard in the field; `Esc` leaves it and the card is still selected; then `A` or `D` sends with the comment. The card says so while the field has the keyboard: `To send with the comment: Esc then A or D`.
- **Screenshots**: the camera button, or `S` inside a selected card, runs a region capture (`hyprshot -m region`, already bound to Super+P for the clipboard) and attaches the result, up to 4, same rules as the phone (PNG, 8 MB) **[D5]**. On the phone this is a file picker; on the PC it is one drag.
- **After an answer**: the card fades out (120 ms; Calm and Off: gone at once), the next card in the queue takes its place without sliding the others, and a snackbar at the bottom of the you column says `Approved · in Done · Undo U` for 6 seconds (`Ctrl+Z` also works). Same words as the phone.

### 3.2 Cards with mockups

`desk-card-mockups.html`. A decision (or a check) with `mockups` shows a row of thumbnails, 16:9, 176 px wide, with their captions, above the answer row, as on the phone (`posting.md` Mockups). `M` (or a click) opens the first full size in a viewer over the Desk: the image at its real size or fitted, `←` `→` page through, the caption and `2 of 3` under it, `Esc` back to the card. The viewer has no answer buttons: Alex looks, comes back, answers on the card, so the thing he approves and the button he presses are always in the same place.

### 3.3 Later, Your list, Guides, Drafts, From the team, Done

As the phone (16.5, 16.6, 23): rows, one level, `Space` ticks a task row, `Enter` opens it in place (steps with their own ticks). Your list keeps App / Business labels. Done shows `You: Approved · 9 min ago · <comment>` and `Change answer`.

### 3.4 Team now (team column, first)

Phone section 17 and 20, with two changes for calm:
- The working dot is a still `laurel` dot. The phone's pulse goes (nothing moves on the home screen).
- `for 42 min` updates once a minute; the Team (21) roster opens in place as on the phone.
- The team gap line (`Liberalitas: team list not updated for 16 h`) stays, in `pompeii` text, not a banner.
- Where the list comes from is Minerva's **[D7]**: on Invictus the harness may know which agents are running without anyone posting it.

### 3.5 In progress

Phone section 25 as built: a fold with `13 · 2 blocked · 1 checked by you`; under All projects, one fold per project with count, average and blocked; inside, Blocked, Checked by you, On track; rows with the identity stripe, title, percent and bar; `Paused and done` last. `Enter` on a row opens its parts; `Check again` is there as on the phone.

**Identity hues on Invictus.** The phone's eight hues (19) are bright and not theme tokens. The Desk gets eight muted ones as theme tokens `id1` to `id8` in each `theme/<id>.toml` (Dusk: `#6F93C4 #62A39A #8FA06A #A983A9 #8C87CC #7E9AA8 #6AA37E #B07F92`), shown as a 3 px stripe and the bar only, with no wash. The slot is the phone's (`FNV-1a(id) mod 8`), so an item sits in the same slot on both. Checked for Dusk (CIE76, normal vision): closest pair 11.9, nearest to `sol` 40, nearest to `pompeii` 38, each at least 5.2:1 on `basalt`. Colour-blind checks are for the theme test (the themes job's rule, ΔE 10 or more under deutan and protan).

### 3.6 Design decisions

As the phone (22): a folded list, newest first, read only; `Enter` opens the why, Also considered, mockups and `Note to Moneta`.

### 3.7 Moneta (third column)

- Heading: `MONETA`, the new-replies pill (`2 new`, `lapis`, Moneta's colour), and `Push to Moneta` on the right (outlined, not gold).
- Status line under it, phone 21.3 words: `Since your last push: 1 note, 2 answers.`, `Nothing new since your last push at 16:10.`, `Pushed 21:14. Push again from 21:16.` and the rest of the table, with the error lines as the page has them **[D4]**.
- Composer: `Note to Moneta`, the `For: Invictus` chip (required under All projects, as on the phone), the screenshot button, `N` to get there from anywhere. `Enter` adds a line; `Ctrl+Enter` sends; `Ctrl+Shift+Enter` sends and pushes. The snackbar after Send offers `Push P` for 6 seconds, like the phone's PUSH.
- Thread: the last 3 notes, newest first, with `Sent` / `Seen` / `Moneta replied`, replies under a 2 px `lapis` rule, `New` until they have been on screen a few seconds; `All notes (23)`.
- **Notes to Moneta and the Moneta panel are different things and stay so.** The panel (Super+A) is a live conversation with the assistant on this machine; notes are for the team's Moneta, answered when she next checks in or when pushed. If the team's Moneta is the same assistant on this machine **[D4]**, `Push` simply opens her panel with the notes loaded; the Desk does not change.

---

## 4. Keyboard

The Desk has keys of its own only while it is in front; they are single keys because Alex's hands are on the keyboard and the Desk has one job. None of them is a Hyprland bind.

| Key | Does |
|---|---|
| Tap Super, `Esc` | Hide the Desk (`Esc` leaves a field first) |
| `↑` `↓` / `k` `j` | Move within a column (cards, rows, headings) |
| `←` `→` / `h` `l` | Move to the column beside, to the nearest item at the same height |
| `Tab` / `Shift+Tab` | Move through the controls inside the selected card |
| `Enter` | Open or close the selected row, fold or `Show all`; on a tile, go to its section |
| `A` / `D` | Approve / Deny the selected decision |
| `P` / `F` | Pass / Fail the selected check |
| `Space` | Tick the selected task (or Now: Done) |
| `C` | Comment on the selected card |
| `L` | Later (or Back to Needs you) |
| `N` | Note to Moneta, about the selected item if one is selected |
| `M` | Open the selected card's mockups |
| `S` | On Now: Switch. In a card: attach a screenshot |
| `T` | Timer: start, pause |
| `U`, `Ctrl+Z` | Undo the last answer or tick, for 6 seconds |
| `0` to `9` | Project tabs (`0` All projects) |
| `?` | All keys, in a panel over the Desk |

**Safety against a stray key.** A letter only acts on the one selected card, and the selection is gold, so the target is always visible. When the Desk opens, the keyboard is on **Now**, where `A`, `D`, `P`, `F`, `L` do nothing: a key typed by habit into what Alex thought was his editor cannot answer anything. Every answer has Undo for 6 seconds. Letters never act while a field has the keyboard. The approval cards of the Moneta panel (system commands) are not on the Desk and never get a single-key answer; they stay `Allow once` / `Deny` by click or `Tab` + `Enter` (look.md).

The mouse works everywhere as on the phone; the key hints on buttons are small `line`-bordered caps in `parchment`, so they read as labels, not as extra buttons.

---

## 5. The look and the ADHD rules

- **One gold.** On the Desk, gold (`sol`) marks only where the next key goes: a 1 px border and a 3 px left bar on the selected card, row or Now; a gold border on a field that has the keyboard (the card around it drops to a `parchment` border). The project in view is a `marble` underline, not gold. The bar keeps its own gold (active workspace), as everywhere.
- **Nothing flashes.** No pulsing dots, no blinking badges, no animated counters, no marquee. The timer's seconds change only on the Now card. New items appear on the next draw without motion; answered cards fade out in 120 ms (Calm: no fade). Motion level Off and game mode: nothing animates, the Desk opens with a cut.
- **No popup per item.** New Needs you items do not notify. The count changes on the Desk, and the bar's Moneta button shows its small dot (look.md) when Needs you has something new since Alex last looked. Once a day at most, if Needs you has had items for over 4 hours, one quiet swaync notification: `3 things wait on your Desk`, dismissed by opening the Desk.
- **Folds.** Alex's phone rule (21.10: every fold starts shut on load) stays for the phone. On Invictus the Desk is a window that stays open, so folds are as Alex left them for the whole session. At login they start shut **except Needs you**, which starts open (For Alex, 11.1).
- **Colours** are theme tokens only; the Desk reads `desk-tokens.css` from the theme tool and follows light and dark (Dawn, with `bronze` focus) as apps do. Status stays a word in its colour: `blocked` in `pompeii`, `You: Fail, with the team` in `parchment`.
- **Type**: Plex Sans, 15 px titles, 13 px body, 12 px labels; Plex Mono for times, counts and key caps.

---

## 6. Projects

- The tabs under Now are `meta/projects` in order, `All projects` first: the name and `4 need you` (in `marble`) or `nothing needs you` (`ash`). The one in view has a `marble` underline. Keys `0` to `9`; more than 9 projects: the tenth and after are under a `More` tab.
- A project is a workspace of the claude.ai Desk. Where projects come from when there is more than one team (Alex's team repo plus a friend's), and whether two teams' projects share one tab row, is Minerva's **[D8]**. Proposed: one row, the team's name before the project's only when two teams have a project of the same name.
- In All projects, In progress and Design decisions group by project (phone 21.4 V3, 25); a Needs you card names its project in its meta line.

---

## 7. The No AI Desk

`desk-no-ai.html`. With No AI (`no-ai.md`) the Desk keeps its frame and shows facts only. It is also what a Tessera person with AI but no team sees, minus nothing: the sections simply have no source.

| Part | No AI |
|---|---|
| Header | `Good evening, Julia` (Cormorant Garamond) and the date. No Updated line, no glance tiles, no tabs, no sync line |
| Now | Set by hand: `Nothing set. What are you working on?` with a field; `Done` (`Space`), `Switch` (`S`, recent Nows), `Timer` (`T`). The running timer is on this card: `18:42 left of 25 min`, `Pause` |
| Today (left, 1040 px) | Today's notes from `~/Invictus/notes/<date>.md`, newest first, with their time; `Add a note` at the bottom (`N`), `Enter` saves |
| Waiting on you (right, 680 px) | System items only, each with one button: `Restart when you're ready` · `Restart...`; a safety copy net stopped · `Fix`; `Support replied about the printer` · `Open`. Left out when empty; Today takes the width |
| Bottom | The system row (`Updates`, `Last safety copy` in `pompeii` after 7 days, `Free on /`) and the Stoic line |
| Keys | `↑↓ move · Enter open · N add a note · T timer · S switch Now · ? all keys · Esc close` |

The bar has no Moneta button and hides updates at 0, as always. Nothing on the Desk mentions AI, Moneta, a team or anything missing (`no-ai.md` NA4). The timer moved from Today (the earlier `no-ai.md` table) onto the Now card, so the timer belongs to what you are doing, the same on both Desks.

---

## 8. What happens where: the Desk and the phone together

Alex will answer on either. The rules the phone already has decide it, so the two never disagree about what needs him:
- An answer is one `verdict` with its `at`; the newest `at` wins, and "answered means gone" works the same on both **[D1] [D2]**.
- An item answered on the phone while the Desk is open leaves Needs you on the Desk at the next sync, with the snackbar `Answered on your phone · Deny · 2 min ago` so the card does not vanish unexplained.
- Offline, answers and notes wait in a local queue and the sync line says so; they go on reconnect in order **[D9]**. A card answered offline shows its answer with `waits to sync` in `ash`.
- Fold state, selection and drafts are per device and never synced.

---

## 9. Where Minerva's architecture plugs in

| Id | Question | What the Desk needs from it |
|---|---|---|
| D1 | The data store on Invictus (items, verdicts, later, notes, team, projects) and its schema | The phone's shapes (`posting.md`) unchanged, so wording and rules carry over; the Desk reads a local copy and never waits on the network to draw |
| D2 | Sync with the claude.ai Desk store, conflict rule | Newest `verdict.at` / `later` / `done` wins; a way to tell "answered on the phone" (source of the write) for the snackbar; the last good sync time for the sync line |
| D3 | Who may write what on the local store, and how the Desk proves it is Alex | The page-only writes stay page-only (`verdict`, `later`, `done`, note text); agents write items and team entries; the Desk process is the only writer of Alex's side |
| D4 | Push to Moneta on Invictus: which session, how it is woken, cooldown | The phone's status table and words; whether Push can open the local Moneta panel when she is the team's Moneta |
| D5 | Screenshots and mockup images: where assets live, size limits, upload | Region capture attaches like the phone's picker; mockups load from a local cache so the viewer opens at once |
| D6 | Links: the allowlist on Invictus and what opens them | Same allowlist and `Copy link`; a clickable link opens in the default browser, never inside the Desk |
| D7 | Team now: from agent processes the harness can see, from posted `team` entries, or both | One list, the phone's shape; the stale guard stays |
| D8 | Projects across more than one team | One tab row, names from `meta/projects` |
| D9 | Offline queue and replay order | The sync line's three states; per-card `waits to sync` |
| D10 | The Now file: fields, who may write it (Moneta, the team, Alex), locking | Bar and card read one file; the card writes it |
| D11 | Rendering untrusted text: item text is data | Plain text only, no Markdown or HTML in items, links shown as the phone shows them; nothing in an item can add a key, a button or a style |
| D12 | "A team exists" (for Atrium, 1.3) | One readable flag or file the Atrium shell and Start can check |

---

## 10. Keys and clicks, before and after

Before: the claude.ai Desk in a browser on the same PC. After: the Invictus Desk on Tessera.

| Task | Before | After |
|---|---|---|
| See what needs you, from any window | 4: switch to the browser, find the tab, open the Desk, open NEEDS YOU (shut on load) | **1**: tap Super |
| See the one thing you are doing | open the Moneta panel or remember | **0**: the bar's Now |
| Pass a check, no comment | 4 + scroll, then Pass (5) | **4**: Super, `↓` to it, `P` (plus `↓` per card above it) |
| Approve with a comment | 5, then click the field, type, click Approve (7 + typing) | **5 + typing**: Super, `↓`, `C`, type, `Esc`, `A` |
| Park a card in Later | 5 | **3**: Super, `↓`, `L` |
| Note to Moneta | 5 + typing (open the Desk, open MONETA, field, type, Send) | **3 + typing**: Super, `N`, type, `Ctrl+Enter` |
| Note and push | 6 + typing | **3 + typing**: `Ctrl+Shift+Enter` instead |
| Switch project | 2 (pill, choice) | **1**: its digit |
| Open a card's mockups full size | 1 tap per image | **1**: `M`, then `→` |
| Back to work | 1 (switch window) | **1**: tap Super or `Esc` |

Decisions asked of Alex: unchanged (the Desk asks nothing the phone does not).

---

## 11. For Alex to decide

1. **Needs you starts open at login; every other fold starts shut.** Your phone rule is "every fold starts shut". On the PC the Desk opens once per login and stays, and Needs you is capped at 3, so starting it open costs no scrolling and saves a key every login. Recommended: open. Alternative: shut, as on the phone.
2. **Single-letter answers** (`A`, `D`, `P`, `F`) on the selected card, with 6 s Undo and the keyboard starting on Now. Recommended. Alternative: `Enter` first to "arm" a card, then the letter (one more key per answer, no stray-key risk at all).
3. **Charts left out** of the PC header at first (glance tiles only). Recommended: try without; add them in place of the tiles if you miss them.

---

## 12. Reused / new, and why

Reused: the claude.ai Desk's sections, order, rules and words (Needs you, answer box, Later, Your list, Team now, In progress folds and status groups, Design decisions, Moneta with Push and its status lines, glance tiles and the 7-day strip, the stable-slot identity hues); `posting.md`'s data shapes; look.md's tokens, type, bar, Now module and motion (`specialWorkspace`); the theme tool's `desk-tokens.css`; the launcher's key-hint line; `hyprshot` for screenshots; No AI's Now file, notes and system items; Atrium's message rules for the one daily "things wait" message; the Quickshell stack Settings already uses (proposed shared `invictus-qml`). New: the three-column desktop layout (nothing lays the Desk out for a landscape screen with a keyboard), the Desk key map and its stray-key rules, the Needs you queue row (the phone shows every card), the sync line (the phone is the only place today, so it has none), eight muted identity tokens per theme (the phone's hues are not theme tokens), and the Super-tap bind.

## 13. Changes to other docs in this job

- `look.md`, "The Desk": replaced by a pointer here; the Now module's click opens the Desk (AI and No AI).
- `no-ai.md` 4: the Desk table points here; the timer sits on the Now card; the Super+D row reads "Tap Super".
- `simple-mode.md` 6 and 8: "The Desk" rows now say Atrium shows it only when a team is set up (1.3).

## Team mode control (Alex, 2026-09-30)

The header carries a small **Mode: Lean · Standard · Full** control, the same as the phone Desk (proposal in claude-team `projects/personal/iris-dashboard/proposals/team-mode.md`). It writes `meta/mode` as a person-signed field (design-desk.md), never written by a session. One gold rule holds: the current mode is a marble underline, not gold.

## Alex's answers, 2026-09-30 (recorded by Moneta)

- **Approved**, with: "I'm sure I'll alter once I'm settled in so just make it to where the code can be easily changed and updated live while I'm using it if possible." Build rule: the Desk is a Quickshell config under `~/.config/invictus/desk/` (user copy of the shipped default, copy-once like other configs), hot-reloaded on save (Quickshell reloads QML on file change), with layout, sections, key map and wording in plain QML/JSON files, not compiled code. A broken edit shows an error bar and keeps the last good version running. Moneta (with Full access or in Tessera) can edit it on request.
- **Needs you open at login: approved.** Single-letter answers with 6 s undo stand.
