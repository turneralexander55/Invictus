# Invictus: the Atrium desktop

Status: design, not yet built. Owner: Venus (designer). Date: 2026-09-30.
Asked for by Alex (2026-09-30): "an ultra dumb mode for some of my non tech friends. Most don't even know what run as admin does on windows, let alone sudo."

Security, admin rights, updates, rollback, app installs, the assistant's limits and remote help are Minerva's (`design-simple-mode.md`). This document designs what people see and touch. Every place where one of her decisions plugs in is marked **[M1]** to **[M9]** and listed in section 7.

Mockups (`docs/mockups/`, 1920 x 1080, self-contained HTML, same fonts and scale-to-fit script as the other mockups). Sample names, apps and conversations are made up.

| File | State |
|---|---|
| `simple-desktop-app-open.html` | Atrium desktop: Files open full size with its title bar, two more apps in the taskbar |
| `simple-start-open.html` | Start open over the desktop |
| `simple-quick-settings-open.html` | Wi-Fi, sound and battery panel open from the taskbar |
| `simple-help-open.html` | The Help panel, mid-conversation, with a "May I?" card and Ask Alex |
| `simple-update-notice.html` | "Restart when you're ready" notice over an open app |
| `simple-messages.html` | Every message pattern in section 4 on one sheet, for Clio |
| `simple-install-1-welcome.html` | Installer 1 of 4: Welcome |
| `simple-install-2-disk.html` | Installer 2 of 4: Erase this computer (the one hard question) |
| `simple-install-3-you.html` | Installer 3 of 4: Your name and password |
| `simple-install-4-installing.html` | Installer 4 of 4: Installing |
| `simple-install-4-done.html` | Installer 4 of 4: Done, restart |
| `simple-firstboot-1-wifi.html` | First start 1 of 4: Wi-Fi (skipped when already online) |
| `simple-firstboot-2-screens.html` | First start 2 of 4: Which screen is in front of you? (only with more than one screen) |
| `simple-firstboot-3-helper.html` | First start 3 of 4: Set up Help |
| `simple-firstboot-4-ready.html` | First start 4 of 4: Three things to know |

---

## 0. In one screen

- **Name on screen: Atrium.** The **flavor** (desktop style) for people who want windows and a taskbar. Alex's flavor is called **Tessera**. Renamed by Alex (2026-09-30) from Classic and Tiling. The **guard rails** (Minerva's admin model, `design-simple-mode.md`) are a second, independent setting: **Custodia** (childproofed) or **Libertas** (Alex's way), both of which do appear on screen under Settings > Guard rails. Any flavor goes with any rails. The file names (`simple-mode.md`, `mockups/simple-*.html`) stay.
- **Windows fill the screen, one at a time**, like a phone or a maximised Windows app, using Hyprland's own `monocle` layout. Every window has a title bar with **minimise, full size / smaller, close**, from the `hyprbars` plugin.
- **A taskbar at the bottom**: a big **Start** button, the open apps, a **Help** button with its name on it, then Wi-Fi, sound, battery and the clock. One click on Wi-Fi, sound or battery opens one small panel with all three.
- **Start** is a grid of big app tiles with plain names ("Internet", "Files", "Photos"), a search field, and Sleep / Restart / Turn off at the bottom.
- **No keyboard shortcut is needed for anything.** Familiar Windows keys work (the Windows key opens Start, Alt+Tab, Alt+F4). Every Tessera key that could surprise someone is off.
- **Install: 4 screens. First start: 2 to 4 screens** (2 on a laptop that is already online; Wi-Fi and "which screen is in front of you?" appear only when needed).
- **Messages** always say what happened, what it means for you, and what to do, with one button named for what it does. No codes, no jargon, no blame.
- **Help** is one labelled button: talk or type to Moneta, and **Ask Alex** when Moneta can't fix it.
- **Motion defaults to Calm.** Themes, wallpapers and the "gold means you are here" rule carry over unchanged.

---

## 1. The name

**Atrium** (on screen), with Alex's desktop called **Tessera**. Alex's names (2026-09-30), replacing the proposed Classic and Tiling; the reasoning below is kept because it still holds.

Both names describe how the windows behave, not how good the person is with computers. "Simple" and "Easy" put a label on the user; a friend who sees "Simple mode" in Settings next to "Full" reads it as "the reduced version for people like me". "Classic" was the word for the desktop most people already know (windows, a taskbar, a Start button), and "Tiling" exactly what a person who wants it would look for; Atrium (the open hall of a Roman house) and Tessera (one tile of a mosaic) say the same in the distro's own voice.

Considered: **Simple** (kind in intent, reads as a verdict on the user), **Easy** (same), **Home** (clashes with the home folder and the Desk), **Everyday** (warm but odd as a noun), **Domus** (Latin nobody reads; Roman names stay out of working surfaces, look.md). Trade-off: neither name says what it does until you have seen it once. Clio should test the pair on two real friends before it ships.

Config value: `flavor = "atrium"` or `"tessera"` (section 6).

---

## 2. The desktop

### 2.1 How windows behave

Atrium uses Hyprland 0.56.2's built-in **`monocle`** layout (`general.layout = "monocle"`, verified in source: `src/layout/algorithm/tiled/monocle/`). Every normal window fills the work area (the screen minus the taskbar), and only one is shown at a time. Focusing another window, by clicking it in the taskbar, shows it; closing the one in front brings back the one used before it (monocle keeps a history). This is how Windows behaves with every app maximised, and how a phone behaves.

Why not "floating and maximised", as first asked: in Hyprland, "maximised" is a fullscreen mode (`FSMODE_MAXIMIZED`), handled per workspace by the fullscreen controller. What happens when a second app opens over a maximised one is set by `misc.on_focus_under_fullscreen`: ignore it, let it take over, or drop the first window out of maximised (source, `ConfigValues.cpp`). None of the three is "the new app opens full size in front and the old one waits full size behind it", which is what a Windows user expects. Getting that from maximise needs a script watching every window. Monocle does it natively. (Read from source; not tried on a running session.)

- **Dialogs and pop-ups** (Save as, Print, a password prompt) float on top, centred, at their own size, as Hyprland already does for dialogs. The window they belong to stays behind them.
- **Smaller** (the middle title-bar button) makes the window float at 70% of the screen, centred, so it can be dragged by its title bar and resized from its edges (`general.resize_on_border = true` in Atrium only: it is the only way to resize without a key). Clicking it again puts the window back to full size.
- **Minimise** sends the window to a hidden workspace (`special:minimised`) and the previous window comes forward. It stays in the taskbar; one click brings it back. Hyprland has no minimised state of its own: a client's or taskbar's "minimise" request only posts a `minimized` IPC event (verified: `src/protocols/ForeignToplevelWlr.cpp`). So a small listener, `invictus-atrium-minimise`, moves the window on that event and moves it back when it is activated again. New, about 60 lines; unbuilt.
- **One workspace per monitor.** No numbers, nothing to learn. Workspaces are gone from the Atrium bar and keys.
- **Borders.** A window that fills the screen has no border (`border_size 0` for tiled windows): there is only one, so a gold frame would say nothing. A floating window (a dialog, or one made smaller) keeps the 2 px `sol` border when focused, so you can see which one you are typing into. That is the look's rule unchanged: gold means you are here.
- **Gaps**: `gaps_in 0`, `gaps_out 0` in Atrium. A full-size app fills the screen, like everywhere else they have used.

### 2.2 Title bars

Every window gets a 36 px title bar from **hyprbars** (hyprwm/hyprland-plugins):

- Background `basalt`; title in IBM Plex Sans 14 px weight 500, `marble` when focused, `ash` when not; title left-aligned after 14 px of padding, the app icon is not shown (hyprbars cannot draw it).
- Buttons on the right, in the order people expect: **minimise** (`–`), **full size / smaller** (`□`), **close** (`×`). Each 28 px, `stone` circle, `marble` glyph, 8 px apart. Close is not red: red means "something is wrong" in Invictus (`pompeii`), and hyprbars 0.56 has no hover colour, so a red close would sit there alarming all day. Position is what people look for; the × sits in the far right corner.
- Double-click the title bar: full size / smaller, as on Windows.
- Apps that draw their own title bar (the browser, and GTK 4 / libadwaita apps such as Photos, Calculator and Settings) would get two bars. Rule: those apps keep their own bar and get `hyprbars:no_bar` (a window rule hyprbars supports). GTK 3 apps such as Files (Thunar) get the hyprbars bar, as in the mockup. Vulcan lists which shipped apps are which. Atrium sets `gtk-decoration-layout` to `:minimize,maximize,close` so apps with their own bar show all three buttons, not only close; whether each app honours it under Hyprland is unverified, so check by eye per app.

**What is verified and what is not:**

- Verified (source, 2026-09-30): hyprland-plugins' `hyprpm.toml` pins Hyprland 0.56.2 (`efb5099`) to plugins commit `7644cec` (2026-07-15). At that commit hyprbars has the Lua API: `hl.config({ plugin = { hyprbars = { ... } } })` for options and `hl.plugin.hyprbars.add_button({ bg_color, fg_color, size, icon, action })` for buttons (`hyprbars/main.cpp`, `newLuaButton`). Options present: `bar_height`, `bar_color`, `col.text`, `bar_text_font`, `bar_text_size`, `bar_text_weight`, `bar_text_align`, `bar_buttons_alignment`, `bar_padding`, `bar_button_padding`, `inactive_button_color`, `on_double_click`, `icon_on_hover`, `bar_part_of_window`, `bar_precedence_over_border`.
- **Unverified: that it runs well on 0.56.2 on real hardware.** Four hyprbars fixes landed after the pinned commit and may matter here: clicks on pop-up menus that overlap the bar were swallowed (#700), bar text blurred after a monitor scale change (#706, matters on laptops at 125%), button icons ignored the bar font (#710), input while disabled (#701). Whether they apply cleanly to the 0.56.2 build is unchecked.
- **Unverified: hover colours.** Not an option at the pinned commit, so the design assumes none.
- Packaging: friends' machines must not build plugins with `hyprpm` (it needs headers and a compiler at login). Ship `invictus-hyprbars` as a package built in our repo against the pinned Hyprland, loaded with `hyprctl plugin load` from the Atrium module. Plugins run inside the compositor, so loading one is a security question **[M7]**.
- Fallback if hyprbars proves flaky: no title bars, and the same three actions on a right-click of the app's taskbar button (Minimise, Full size, Close). Worse (people look at the window, not the taskbar), but everything stays reachable by mouse.

### 2.3 The taskbar

Bottom edge, full width, 56 px, `night` at 90% with the layer blur, 1 px `line` top border. Everything in it is at least 44 px tall to click.

| Left | Middle | Right |
|---|---|---|
| **Start** button: the mark (22 px, `marble`) and the word `Start`, 15 px weight 600, `stone` pill 44 px tall | Open apps: icon 28 px and name 14 px, up to 200 px each, names cut with an ellipsis | **Help** button: a question-mark icon in `lapis` and the word `Help`, 15 px weight 600, `stone` pill |
| | | Wi-Fi, sound, battery icons, 24 px, one shared button |
| | | Clock `14:32` (16 px, weight 600) over the date `Wed 30 Sep` (12 px, `parchment`) |

- **Open apps.** The app in front has a `stone` background and a 3 px `sol` bar under it (the same "you are here" mark as the Tessera workspace number). Others are plain. A minimised app looks the same as the others, since it is one click away either way. One click on an app: bring it forward; one click on the app already in front: minimise it (Windows does this). Right-click: `Close`.
- More apps than fit: the names shrink to icons, then a `+3` button lists the rest.
- While Start, Help or Quick settings is open, its taskbar button gets a `line` background, not gold: focus is inside the panel (its search or text field carries the gold), and one gold at a time is the rule.
- **Wi-Fi, sound, battery** are one button with three icons (section 2.5). The battery shows its number (`82%`) because people ask "how much is left", and it turns `pompeii` below 15%. Desktop computers have no battery icon.
- **Clock.** Click: a month calendar. Nothing else.
- No system tray by default (Discord, Steam and friends put icons there that do nothing useful for this user). Apps that need one still work in Tessera. **Decision point for Clio and Vulcan:** if a friend relies on a tray app (a VPN, a phone sync tool), Settings gets a "Show background apps" switch; off by default.
- No notification bell, no updates counter, no "Now", no workspaces. Things that need attention arrive as a message (section 4) and stay until dismissed if they matter.

Built with **Quickshell** (0.3.1 in `extra`; package ships `Quickshell.Wayland` for the window list, `Services.Pipewire`, `Services.UPower`, `Networking`, `Services.Polkit`, checked against the package file list, not run). Not waybar: the taskbar, Start, Quick settings and Help must know about each other (only one open at a time, Esc or a click outside closes the open one), which one Quickshell shell does in one process and four separate programs do badly. Minerva already chose Quickshell for the first-boot wizard and the Desk.

### 2.4 Start

Opens from the Start button, or the Windows key alone (section 2.7). Rises from the bottom-left corner, 640 x 600, `basalt` at 96% with blur, 1 px `line` border, radius 16, 20 px padding.

1. **Search field** at the top: 48 px, `stone`, radius 10, placeholder `Type to find an app`, focused on open (1 px `sol` border and caret, as in the Tessera launcher). Typing filters the grid to matching apps, by name and by what they do (typing "photo" finds Photos). Enter opens the first match.
2. **Pinned apps**: a 4-column grid of 128 x 112 tiles, icon 56 px, name 14 px `marble` under it, two lines max. Hover or keyboard selection: `stone` background, radius 12; keyboard selection also gets the 3 px `sol` bar under the tile. Twelve by default:
   `Internet`, `Files`, `Photos`, `Music & video`, `Documents`, `Email`, `Calculator`, `Get apps`, `Games` (only if Steam is installed), `Printers`, `Settings`, `Help`.
3. **All apps** row under the grid: `All apps  (34)`, opens an alphabetical list in the same panel with a Back arrow. Right-click any app: `Pin to Start`, `Unpin`.
4. **Footer**, 56 px, a `line` divider above it: the person's name on the left (15 px, `parchment`), and on the right a **Power** button (icon and the word `Power`). Power opens three big buttons in place: `Sleep`, `Restart`, `Turn off`, and `Cancel`. No second "are you sure": the choice is already one deliberate extra click, and an app with unsaved work asks on its own. Lock and Log out are cut: one person per computer, and the lock is automatic (hypridle).

**Names.** Shipped apps are named for their job, not their brand: `Internet` (Zen Browser), `Files` (Thunar), `Photos` (Loupe), `Music & video` (Showtime), `Documents` (LibreOffice), `Printers` (system-config-printer). People say "open the internet". The trade-off: a web search for "how do I clear history in Zen" won't match the tile, so each tile's tooltip and About box keep the real name. Third-party apps keep their own names (`Steam`, `Discord`, `Spotify`).

Built in the Quickshell shell, not rofi: rofi cannot draw the power footer or the pinned / all apps pair. It reuses the launcher's visual spec (search field, selection style, sizes scaled up) so it reads as the same system.

**Apps this needs.** The desktop meta package has no photo viewer, video player, PDF reader, office suite or printing. A new depends-only meta `invictus-everyday` (Vulcan): `loupe`, `showtime`, `papers`, `gnome-calculator`, `gnome-text-editor`, `libreoffice-fresh`, `cups`, `system-config-printer`, `simple-scan` (all in `extra`, checked 2026-09-30). Email and `Get apps` depend on the app-install model **[M4]**.

### 2.5 Quick settings: Wi-Fi, sound, battery

One click on the Wi-Fi, sound or battery icons opens one panel above them (bottom-right, 400 px wide, same card style as Start). One panel, not three menus, so there is one thing to learn. Top to bottom:

1. **Wi-Fi**: the connected network with a check and `Connected`; under it up to 5 nearby networks by signal, each a 48 px row. Click a locked one: a password field opens in the row, with `Show password` and `Connect`. Wrong password says `That password didn't work. Check it and try again.` No "SSID", "WPA", "802.1X". `More Wi-Fi settings` link at the bottom goes to Settings.
2. **Sound**: a large slider (28 px thumb) with the speaker icon as a mute button, the number beside it. `Output: Speakers` under it; clicking lists other outputs (headphones, TV) when there are any.
3. **Brightness**: a slider, laptops only.
4. **Battery**: `82% · about 4 h 10 min left` or `Charging · full in 40 min`. Laptops only.
5. **Airplane mode** and **Do not disturb** as two switch rows.

Reuses nothing from waybar's `pavucontrol` / `nm-connection-editor` clicks: those are the jargon this mode removes. They stay one level down in Settings for Alex when he helps remotely.

### 2.6 Power

- Start > Power > `Sleep`, `Restart`, `Turn off` (three clicks from anywhere).
- Closing the laptop lid: sleep (logind's default). A short press of the power key: sleep too in Atrium, as on a Windows laptop (logind's default is turn off, so Atrium sets `HandlePowerKey=suspend`). Holding the power key still forces off, as on any computer.
- The design asks that an update never restarts the computer on its own while someone is using it; the update messages (section 4) assume that. Minerva's update model decides **[M2]**.

### 2.7 Keys

**No key is needed for anything.** Every action above has a mouse path. Atrium loads its own small bind set instead of `binds.lua`:

| Key | Does | Why keep it |
|---|---|---|
| Windows key, pressed and released alone | Opens or closes Start | What Windows users do |
| Alt + Tab | Next app | Muscle memory from Windows |
| Alt + F4 | Close the app in front | Same |
| Print Screen | Screenshot to Pictures, with a message `Screenshot saved in Pictures` | Same |
| Volume, brightness, media keys | As in Tessera | Hardware keys should just work |

Everything else in Tessera is off in Atrium, on purpose: `Super + Delete` (log out, after a yes/no confirm), `Super + Q`, the workspace keys, float and fullscreen toggles. A stray chord in Atrium does nothing rather than something surprising. Check for Vulcan: the Windows-key-alone bind is a release bind on `SUPER_L`; it must not fire when Super was part of a chord (Hyprland's `bindr` behaviour, unverified on 0.56 Lua).

### 2.8 Messages on screen, and several monitors

- Messages (swaync, reused) move to the bottom-right, above the taskbar, 420 px wide, text 15 px. Section 4 has the patterns.
- Several monitors: each gets a taskbar showing the apps on that monitor. Start, Help and Quick settings open on the monitor the mouse is on. Everything machine-specific is automatic (Alex, 2026-09-30: an install wizard for machine settings is fine, and Atrium gets at most one plain question): scaling from each screen's size and resolution (for example 125% on a 14-inch 1080p laptop), arrangement left to right in port order, keyboard layout from the installer's language, one workspace per screen. The one question, only when more than one screen is plugged in, is which screen is in front of you (3.2); that screen becomes the main one. A wrong guess about arrangement or scaling is fixed in Settings > Screens.

### 2.9 Taps and decisions, before and after

For a person who has never used Hyprland. "Keys to know" counts things someone must be taught.

| Task | Tessera (today) | Atrium |
|---|---|---|
| Open an app | Know `Super + Space`, type the name, Enter (1 key to know) | Start, click the tile: 2 clicks |
| Close an app | Know `Super + Q` (1 key) | Click ×: 1 click |
| Switch to another app | Know focus or workspace keys (2 or more) | Click it in the taskbar: 1 click |
| Make an app smaller / put it aside | Know `Super + F` / a move key | 1 click (□ or –) |
| Join a Wi-Fi network | Click the icon, then a technical dialog (`nm-connection-editor`): about 7 steps and 3 jargon words | Click the icons, click the network, type the password, Connect: 3 clicks + typing |
| Change the volume | Scroll on a small number, or open `pavucontrol` | Click the icons, drag the slider: 1 click + drag (or the volume keys) |
| Turn off | Know `Super + Alt + Ctrl + Escape`, choose Yes (1 key) | Start, Power, Turn off: 3 clicks |
| Ask Moneta | Know `Super + A` (1 key) | Click Help: 1 click |
| **Keys to know** | **6 or more** | **0** |

---

## 3. Install and first start

Two parts: the installer, run from the USB stick (by the friend, or by Alex for them), and first start, run once when the new person logs in for the first time. Every screen has one job, one gold button, and plain words. Nobody sees "partition", "btrfs", "bootloader", "sudo", "repository", "locale" or "snapshot".

### 3.1 Installer: 4 screens

Calamares (Minerva's choice) supports custom module order and QML pages; this is a Calamares configuration and branding, not a new installer. The Tessera user (Alex) gets the same four screens; his options are under a collapsed **Options** row on screens 1 and 2.

Each screen: `night` background with the Sol wallpaper faint behind, one centred card (`basalt`, radius 20, 640 px), the mark at the top, a step line `Step 2 of 4` in `ash`, a heading in Plex Sans 28 px weight 500, one or two lines of body text at 17 px, and a bottom row with `Back` (text button, left) and the one gold next-step button (right, 52 px tall).

1. **Welcome.** `Set up Invictus on this computer`. Body: `This takes about 15 minutes. Keep the computer plugged in.` A `Language: English (UK)` row, preselected from the language the stick booted in, click to change. Button: `Start`. Options (collapsed): keyboard layout (inferred from language), time zone (inferred from the internet if connected, else from language).
2. **The disk.** One hard question, and it gets friction on purpose because it cannot be undone.
   - One disk, nothing on it: this screen is skipped.
   - One disk with something on it: `Invictus will replace everything on this computer.` Under it, in plain words, what is there now: `Found: Windows 11 and 212 GB of files on "Samsung SSD 512 GB".` Then a checkbox, unchecked: `I've saved the photos and files I want to keep.` The gold button `Erase and install` stays disabled until it is ticked. The box is the one extra decision in the whole flow, and it is worth it: this is the only step that can destroy something.
   - More than one disk: one row per disk with its size and what is on it, the empty or largest one preselected, then the same checkbox.
   - Options (collapsed): `Keep Windows and choose at start-up` (dual boot), `Lock the disk with a password` (encryption; off by default as Alex decided, D6), `Choose partitions myself`. Alex lives here; nobody else opens it.
3. **You.** `Who will use this computer?` Fields: `Your name` (e.g. Maria Santos), `Password`, `Type it again`, each 52 px, with a `Show` eye. Under the password: `You'll type this to unlock the computer.` The computer's name is made from the first name (`marias-laptop`) and not shown. The username is made from the first name (`maria`) and not shown. Button: `Install`. Whether this person is an admin, and whether a second admin account for Alex is created here, is **[M1]**; the screen has room for one line such as `Alex can help with this computer from far away` if Minerva's model needs consent at install time. Guard rails and flavor (Alex, 2026-09-30): the plain path installs Atrium + Custodia with no question; the Advanced path (the collapsed Options rows) lets the person pick Tessera and Libertas.
4. **Installing, then Done.** A progress bar (`sol-bright` fill, as look.md says for progress) and one line that changes with the phase: `Copying Invictus to the disk`, `Setting up your account`, `Almost done`, with `About 8 minutes left`. No log unless you click `Details`. When done: `All done. Take out the USB stick, then restart.` Button: `Restart`. If it fails: `Setup couldn't finish. Nothing on the disk has been used yet.` (only when that is true) or `Setup couldn't finish.`, with `Try again` and `Save a report for Alex` (writes the install log to the USB stick) **[M8]**.

Before: Calamares' default Welcome, Location, Keyboard, Partitions, Users, Summary, Install, Finish = 8 screens, about 14 decisions, 6 jargon words. After: 4 screens (3 on an empty disk), 3 decisions (language, tick the box, name and password), no jargon.

### 3.2 First start: 2 to 4 screens

Replaces Minerva's seven-step first-boot wizard for a Atrium user (design.md 2.3). Tessera users still get the full wizard. For Atrium, everything with a safe default is decided for them and changeable later in Settings:

| Minerva's step | In Atrium |
|---|---|
| Monitors | Automatic (2.8), plus one question when there is more than one screen (screen 2 below) |
| Look | Dusk, Calm motion, light apps. Changeable in Settings > Look |
| Assistant provider | Becomes screen 3, "Set up Help" |
| Collegium | Not shown. Local-only, created silently so Help has a memory. Alex can connect one later remotely |
| Windows VM | Not shown |
| Voice (pen button, model) | Not shown. Help uses the built-in microphone; the speech model downloads in the background on first use of the mic |
| Snapshot and tour | Snapshot happens silently; the tour becomes screen 4 |

Screens, same card style as the installer:

1. **Wi-Fi.** Skipped if already online (a cable, or Wi-Fi set in the installer). `Connect to the internet` with the same Wi-Fi list as Quick settings. `Skip for now` text button: everything works offline except Help and updates.
2. **Which screen is in front of you?** Only when more than one screen is plugged in. Every screen shows the same card with its own big number and a `This one` button; the person clicks it on the screen they are looking at. No mapping numbers to a diagram, no dragging. That screen becomes the main one (taskbar with the clock, new windows, messages). If nobody answers in 60 s (a TV that happens to be on), the laptop screen or the largest screen wins and the wizard moves on.
3. **Set up Help.** `Help answers questions and can fix things for you, when you say yes.` Two cards, the first preselected (2 px `parchment` border and a check; gold stays on the one button): `Use Claude` (sign in with a Claude account in the browser; the window comes back when done) and `Use a home AI system` (a local model or one on the home network, Alex's D13). A `Set up later` text button. Nobody sees a terminal. What sign-in costs the friend and who pays is **[M5]** and a concern for Moneta.
4. **Three things to know.** Three cards, left to right, each with a small picture of the real control: `Start opens your apps`, `× closes a window`, `Help is always here`. Button: `Start using Invictus`.

There is no question about Atrium or Tessera. New users created through the installer get **Atrium**; Tessera is one switch in Settings (section 6), and the person who wants it knows to look. Considered: one screen asking "How do you like your windows?" with two pictures. It is a decision a non-technical person cannot make well, it costs everyone a screen, and it is reversible in 3 clicks.

Before (Minerva's first-boot wizard): 7 screens, about 12 decisions, including a monitor layout to drag, provider names and a terminal login. After: 2 screens on a laptop that is online, at most 4, and at most 2 decisions (which screen, only with several; how to set up Help, preselected), no terminal.

---

## 4. Messages

Clio polishes the words; these are the patterns. Every message is a card (swaync, section 2.8) or, when it needs the whole screen (install, rollback at boot), a card on the full-screen style of section 3.

### 4.1 Rules

1. **Title: what happened, in the person's words.** `Updates are ready`, not `System upgrade available (38 packages)`.
2. **Body: what it means for you, and whether anything is lost.** Always say it when nothing is lost: `Nothing is lost.` is the most reassuring sentence we have, and the one people need most after a fright.
3. **One main button, named for what it does.** `Restart now`, `Connect to Wi-Fi`, `Free up space`. Never `OK`, `Yes`, `Proceed`. A second, quieter button only when "not now" is a real choice: `Later`.
4. **No codes, numbers only when they help.** `3 GB left` helps; `exit 1` does not. Technical detail goes behind a collapsed `Details for Alex` line, which Help can read and send **[M8]**.
5. **No blame, no alarm.** `That password didn't work`, not `Invalid password`. No exclamation marks, no capitals for emphasis.
6. **Say who is doing what.** `We` never appears. The computer did something: `Your computer put things back the way they were.` Moneta speaks as itself in the Help panel only.
7. **Offer Help on anything that went wrong.** Every error card has `Ask Help` as its quiet button, which opens Help with the problem already written in, so the person does not have to describe it.
8. **Colour follows the look's status colours**, as a 4 px bar on the card's left edge: `laurel` done, `lapis` information or a choice, `pompeii` something needs you now. Never gold (gold is focus).
9. **How long it stays.** Done and information: 8 s, then kept in Help's "Recent" list. Needs you: stays until acted on or closed.

### 4.2 The messages

| When | Title | Body | Buttons | Bar |
|---|---|---|---|---|
| Updates installed, no restart needed | `Your computer is up to date` | `Updates were installed while you worked.` | none (8 s) | laurel |
| Updates installed, restart needed (at most once a day, never forcing; Alex, 2026-09-30: no automatic restarts, ever) | `Restart when you're ready` | `An update finishes when the computer restarts. It takes about a minute, and your apps will open again.` | `Restart now` · `Later` | lapis |
| An update failed and was undone **[M2]** | `An update didn't work` | `Your computer put things back the way they were. Nothing is lost. Alex has been told.` (last sentence only if the report was really sent **[M8]**) | `Ask Help` | lapis |
| Computer started from the backup copy after a bad update **[M2]** | `Your computer went back to before the last update` | `Something went wrong after an update, so it started from the copy made just before it. Your files are fine.` | `Got it` · `Ask Help` | lapis |
| An app crashed | `Photos closed unexpectedly` | `Anything you saved is safe.` | `Open it again` · `Ask Help` | lapis (it already happened; nothing needs you now) |
| Disk nearly full | `Your computer is almost full` | `3 GB left. When it's full, apps and updates stop working.` | `Free up space` (opens Help with "Help me free up space") · `Later` | pompeii |
| Battery low | `Battery low: 10%` | `Plug in the charger soon.` | none | pompeii |
| Battery very low | `Battery at 5%` | `The computer will go to sleep in about 5 minutes. Plug in the charger.` | none, stays | pompeii |
| No internet | `No internet` | `Help and updates need the internet.` | `Connect to Wi-Fi` | lapis |
| Asked for your password **[M1]** (both guard-rails settings since DS1; under Custodia the prompt also carries the scam line, `design-simple-mode.md` G1, G3) | `Type your password to install Spotify` | `This changes the computer for everyone who uses it.` | `Install` · `Cancel` | lapis |
| Help can't do it alone **[M6]** (in the Help panel, so Moneta speaks as itself) | `This needs Alex` | `I can't change this myself. Want me to ask Alex? I'll tell him what's happening.` | `Ask Alex` · `Not now` | lapis |
| Alex wants to see the screen **[M3]** | `Alex wants to see your screen` | `He'll be able to see and use your computer until you press Stop.` | `Let Alex in` · `Not now` | lapis |
| Alex is connected **[M3]** | `Alex is using your computer` | (a strip at the top of the screen, not a card, for as long as it lasts) | `Stop` | pompeii |
| USB stick plugged in | `USB stick found` | `SANDISK · 29 GB` | `Open it` | lapis |
| Screenshot | `Screenshot saved in Pictures` | none | `Open it` | laurel |
| Wrong password at unlock | (on the lock screen) `That password didn't work` | none | none | pompeii |

The polkit password prompt matters most, because it is the "run as admin" Alex's friends never understood. Its text comes from each polkit action's `<message>`, which Minerva writes for `invictus-sys` **[M1]**: those messages must follow rule 1 (`Type your password to install Spotify`, not `Authentication is required to run /usr/bin/invictus-sys as the super user`). In both flavors the prompt is drawn by the one Invictus Quickshell polkit agent (`Services.Polkit`, `design-simple-mode.md` G1) in this card style, not by `hyprpolkitagent`'s generic dialog. Pen test scope, since a look-alike password dialog is a classic attack **[M1]**.

---

## 5. Help

### 5.1 The button and the panel

`Help` in the taskbar, with its name on it, always in the same place. It opens the Help panel from the right: the Moneta panel's layout (look.md, "The Moneta panel") scaled up for reading, 480 px wide, full height above the taskbar, `basalt` at 96%, radius 16.

1. **Header** (64 px): `Help` in 18 px weight 600, a status word in `ash` (`Ready`, `Listening`, `Thinking`, `Working on it`), a close ×.
2. **Conversation**: Moneta's words in 16 px `marble`, line height 1.55; the person's on `stone` bubbles on the right. Moneta introduces itself once, on first open: `Hi Maria. I'm Moneta. Ask me anything about this computer, or tell me what's wrong.` Steps it gives are numbered and name what is on screen (`Click Start, then Settings`), never keys.
3. **Suggestions** when the conversation is empty: three chips, e.g. `The internet isn't working`, `Make the text bigger`, `Install an app`.
4. **Talk**: a large round microphone button (64 px), left of the text field. Click once to start, click again to stop (holding is hard on a touchpad). While listening: `lapis` ring and the level bar, status `Listening`. Speech is turned into text on the computer (local whisper, design.md 4.4); the text appears in the field so the person sees what was heard before it is sent.
5. **Type**: the field, 52 px, placeholder `Type your question`, Enter sends.
6. **Ask Alex**: a full-width secondary button under the field, `Ask Alex`. It opens a short preview: `I'll send Alex this: [a summary of the problem and what was tried]` with `Send` and `Cancel`. After sending: `Alex has your request. He usually answers within a day.` It is a request, not a live call; the word "call" would promise a ringing phone. This is Minerva's helper request (`design-simple-mode.md` 4.4): the same queue her `helper_ask` tool and every "helper" verb write to, one concept with one name. If Alex then asks to connect, the remote-help message in 4.2 appears **[M3]**. Who the button names comes from the machine's config (`helper_person`), set when Alex installs it, so another helper's friends see their own name **[M3]**.
7. **Recent**: a collapsed row at the bottom, `Recent messages (3)`, listing the last messages from section 4.

### 5.2 When Moneta wants to change something

Uses the Moneta approval card from look.md (1 px `sol` border, two equal buttons so a habit click doesn't approve), in plain words: heading `May I turn on larger text?`, one line on what will change (`Text in every app gets 25% bigger. You can undo it in Settings.`), buttons `Yes, do it` and `No`. The command itself is behind `Details for Alex`. What Moneta may do without asking, with asking, or never, and which of these require the password, is Minerva's **[M6]**. The card design does not change with her answer; only which actions produce one.

---

## 6. Switching between Atrium and Tessera

### 6.1 Where

- **Settings > Desktop style**: two cards with a picture each, `Atrium: windows fill the screen, with a taskbar and Start` and `Tessera: windows share the screen side by side. Uses keyboard shortcuts.` The current one is checked. Picking the other and pressing `Switch` applies it at once, with no log out (Hyprland reloads the config; the Quickshell shell or waybar swaps).
- **From Tessera**: the launcher entry `Atrium desktop` (no key), for Alex helping someone or trying it.
- **Keep it?** After any switch, a card in the middle of the screen: `Keep this desktop style?` with `Keep` and `Go back`, and `Going back in 20 s`. If nobody clicks, it goes back. This is the display-resolution pattern, and it stops a friend from getting stuck in Tessera with no idea which key undoes it.

### 6.2 Who

- **Anyone can switch themselves.** It changes nothing but their own desktop, touches no system file, and needs no password. It is their computer.
- **Alex can lock it.** A machine-wide setting (in `/etc/invictus/`) can hide `Desktop style` for a user; for someone who clicked into Tessera twice by accident. Set by Alex, remotely or through Help's "May I?" card. Whether that setting needs admin, and whether a locked user can ever unlock it, is **[M9]**.
- Default for a new user from the installer: Atrium (3.2). Alex's own account and any account made by `adopt.sh` on an existing machine: Tessera.

### 6.3 How it is wired (for Vulcan)

- `~/.config/invictus/flavor` holds `atrium` or `tessera`; `/etc/invictus/flavor.lock` can force a value per user **[M9]**.
- The Hyprland loader (`config/hypr/hyprland.lua`, reuse catalog) requires `invictus.core`, and `core.lua` requires `invictus.atrium` instead of `binds`, `workspaces` and the tiling layout settings when the value is `atrium`. `monitors.lua` and `user.lua` load in both. `invictus.atrium` sets the layout, gaps, borders, window rules, the hyprbars config and the Atrium binds.
- Autostart starts the Quickshell Atrium shell and Atrium's swaync config in Atrium, waybar and the normal swaync config in Tessera. A switch stops one set and starts the other.
- `invictus-doctor --hypr` and the Lua test harness (`tests/hyprland-lua`) must load both variants; `mock_hl.lua` needs stubs for `hl.plugin.hyprbars.add_button` and `monocle`.

### 6.4 What Atrium keeps from the look

| From look.md | In Atrium |
|---|---|
| Tokens and the four themes (Dusk, Porphyry, Aegean, Alexandria) | All of them. Settings > Look shows the theme picker's rows as four big cards with the same generated swatches; Dusk is the default. No key |
| Gold means you are here | Unchanged: the app in front in the taskbar, the focused field, keyboard selection in Start, a focused floating window's border, and the one next step on install and first-start screens |
| Status colours (laurel, lapis, pompeii) | Unchanged, on message cards (4.1) |
| Wallpapers per theme | All of them, in Settings > Look |
| Motion levels | **Calm by default** in Atrium (Showcase in Tessera). Showcase and Off are in Settings > Look > Motion. Game mode still forces Off |
| Lock screen, login, boot splash | Unchanged. The lock's Marcus Aurelius line stays |
| Type | IBM Plex Sans everywhere, sizes up one step: 15 px in the taskbar (13 in Tessera), 16 px in Help and messages, 14 px on tiles. Settings > Screen > Text size scales everything |
| Shell stays dark, apps follow light or dark | Shell unchanged. Apps default to **light** in Atrium (dark in Tessera): most documents and web pages are light, and look.md's Dawn was made for exactly this reader. Settings > Look switches it |
| The Desk | Not shown in Atrium. It is Alex's work dashboard; its "what matters now" job is done by messages and Help |

---

## 7. Where Minerva's decisions plug in

| # | Question for Minerva | Where it shows |
|---|---|---|
| M1 | Who has admin on a friend's machine; is the friend's own password enough to install an app; the wording of every polkit message | Installer screen 3; the password card (4.2); the Atrium polkit prompt |
| M2 | Automatic updates: when they run, whether restarts ever happen on their own, how a failed update rolls back and what the person is told | Update messages (4.2); Start > Power |
| M3 | Remote help from Alex: consent, what he can see and do, how it ends; the `helper_person` config | Ask Alex (5.1), the two remote-help messages (4.2), installer screen 3 |
| M4 | How apps get installed (our repo, Flatpak, a store app), and what `Get apps` opens | Start tile `Get apps`, the Email tile |
| M5 | Help's provider for a friend: whose account, what it costs, the home-model option | First start screen 3 |
| M6 | What Help may do alone, with a "May I?" card, or never | 5.2, the "This needs Alex" message |
| M7 | Loading a compositor plugin (hyprbars) on friends' machines; `ecosystem.enforce_permissions` | 2.2 |
| M8 | What goes in a report to Alex, with what preview, and when "Alex has been told" is true | 4.1 rule 4, installer failure, update failure |
| M9 | Whether locking the desktop style needs admin, and whether a user can undo it | 6.2 |

### 7.1 Minerva's answers (Clio's reconciliation, 2026-09-30)

Section numbers are `design-simple-mode.md`'s. This table predates DS1 and the guard-rails revision (Minerva, 2026-09-30): where it says the person is not an admin or that a Custodia machine means Atrium, `design-simple-mode.md` sections 1.3 to 1.6 now hold. "Custodia machine" means Minerva's admin model with Custodia guard rails, in either flavor.

| # | Answered by | What it means here | Still open |
|---|---|---|---|
| M1 | 0 (Admin), 1.3, 3.1, DS1 | The person is not an admin and is never asked for a password; `custos` is the admin and only Alex knows it. App installs are per-user Flatpaks with no password. So the password card in 4.2 never appears on a Simple machine, and the Atrium polkit prompt is only seen by Alex as `custos` in a help session | Where the Simple switch and the one-time `custos` password screen ("write this on the card", DS4) go in the four installer screens. Whether Atrium draws the polkit prompt in Quickshell (4.2 here) or `hyprpolkitagent` shows it (Minerva 5.2 step 4, which also needs it to let Alex pick `custos`). The polkit `<message>` texts |
| M2 | 2.1 to 2.4, DS2 | Updates run by themselves behind gates. Superseded by Alex (2026-09-30, DS2 denied): the computer never restarts itself; after an update that needs it, `Restart when you're ready` at most once a day. A failed doctor undoes the update from the cache (`An update didn't work`); two bad boots start the pre-update snapshot (`Your computer went back to before the last update`) | Whether `Restart when you're ready` (`Restart now` · `Later`) counts as a question under SM6, which allows none |
| M3 | 5.1 to 5.3, DS7 | RustDesk, started only when the person presses **Get help**, accepting only the helper's ID and only on a click. The strip `Alex is using your computer` with `Stop` is Minerva's banner (one text, one button name). It ends on Stop, closing the window, Alex disconnecting, or 10 minutes idle. **Ask Alex** is Minerva's helper request | Where Get help sits in Atrium: Minerva puts it on a Desk card and Super+H, and Atrium has neither (Moneta's `help_start` tool is the only path today). Who starts: Minerva has the person start and Alex connect; the card `Alex wants to see your screen` / `Let Alex in` reads as Alex starting, and may be RustDesk's own Accept dialog rather than ours. `helper_person`: Minerva whitelists one RustDesk ID and names no config key. The installer consent line |
| M4 | 3.1, DS5 | Per-user Flatpak from Flathub's verified subset. `Get apps` opens Bazaar (fallback: GNOME Software, Flatpak only). Email is Thunderbird from the DS5 set | LibreOffice is a native package in `invictus-everyday` (2.4) and a user Flatpak in DS5: pick one |
| M5 | 4.1 | Claude Code with the person's own account (D13), a home AI system through the chat-only provider, or none. `generic-cli` is not offered | What the Claude account costs the friend and who pays |
| M6 | 4.2 to 4.5 | Moneta has no shell, only fixed tools. Undoable things (update, undo, snapshot, doctor, report, help, installs from the verified subset) go through the "May I?" card; system changes become helper requests (`This needs Alex`); nothing ever needs the person's password; Moneta never shows a command | 5.2 puts "the command itself behind `Details for Alex`", but Minerva's 4.5 and SM8 say no command is ever shown: Details should show the tool call in plain words, or go. Whether Claude Code's own permission prompt can be drawn as the "May I?" card (Vulcan) |
| M7 | Not answered | | Loading hyprbars on friends' machines and `ecosystem.enforce_permissions` |
| M8 | 4.4, 2.4, DS3; `design.md` 4.5 | Rollbacks and helper requests go to the helper queue. They reach Alex on their own only if DS3 is approved; otherwise at the next help session | DS3. Until it is approved, `Alex has been told`, `I'll send Alex this` and `He usually answers within a day` are not true and need other words. The installer's `Save a report for Alex` is not covered |
| M9 | Not answered directly | By Minerva's rules (`/etc/invictus/` is root-owned, `set-config` is a helper verb), locking needs `custos` and a locked person cannot unlock it | Minerva to confirm |

---

## 8. What is new to build

For Moneta's planning, not a brief. All in the Atrium path; Tessera is unchanged.

1. `invictus.atrium` Hyprland module (monocle, borders, gaps, hyprbars config, binds, window rules). Small.
2. `invictus-hyprbars` package against the pinned Hyprland. Small, with the hardware risk in 2.2.
3. `invictus-atrium-minimise` listener. Small.
4. The Quickshell Atrium shell: taskbar, Start, Quick settings, Help panel, polkit prompt, "Keep this?" card. The bulk of the work. The Help panel shares its conversation and approval components with the Moneta panel for Tessera; build them once.
5. Settings: designed in `settings.md` (eleven pages including Guard rails and Safety copies, built in Quickshell). Nothing on the system does this for a non-technical person today: `nwg-look`, `pavucontrol` and `nm-connection-editor` are the jargon this mode removes; they stay as Options links.
6. Calamares configuration, QML pages and branding for the 4 screens. Medium.
7. First start (Atrium path) inside Minerva's wizard. Small, once the wizard exists.
8. `invictus-everyday` meta package (2.4).
9. swaync Atrium config (bottom-right, larger text, the status bar colours).

---

## 9. Verified, and not

Verified on 2026-09-30:

- Hyprland 0.56.2 source (`/home/user/hyprwm/hyprland`, tag `v0.56.2`, `efb5099`): the `monocle` layout exists and behaves as in 2.1 (one visible, fills the work area, history on close, focus switches the visible window); foreign-toplevel `activate` ignores `misc.focus_on_activate`, so a taskbar click always brings the app forward; minimise requests only post an IPC event; `float` and `maximize` window-rule effects exist; `misc.on_focus_under_fullscreen` exists (why maximise-by-rule was rejected).
- hyprland-plugins: the 0.56.2 pin (`7644cec`) and the hyprbars Lua API and options in 2.2.
- Quickshell 0.3.1 in `extra`, and the QML modules it ships (package file list).
- The `invictus-everyday` packages are in `extra`.

Not verified:

- hyprbars on 0.56.2 on real hardware, and the four later fixes (2.2).
- Whether GTK 4 apps honour `gtk-decoration-layout` under Hyprland, and which shipped apps draw their own title bars.
- The Windows-key-alone release bind in the 0.56 Lua API.
- Quickshell's `Networking` module doing Wi-Fi join with a password (the module exists; its features are unchecked).
- Calamares QML pages matching this layout exactly.
- The mockups are drawings, not screenshots of built software.

---

## 10. Reused / new, and why

Reused: the tokens and all four themes, the theme picker's generated swatches (Settings > Look), the "gold means you are here" rule, status colours, motion levels (Calm as default), the lock, login and boot screens unchanged, the launcher's search field and selection style (Start), the Moneta panel's layout and its equal-button approval card (Help), swaync with a second config (messages), the Hyprland loader and module pattern (`invictus.atrium`), the Lua test harness, the local speech pipeline (Help's microphone), Calamares and Minerva's Quickshell first-boot wizard, Hyprland's own `monocle` layout and hyprbars from hyprwm, and `hyprlock`, `hypridle` and logind for lock and sleep.

New, because nothing does the job: the Quickshell Atrium shell (taskbar, Start, Quick settings, Help, polkit prompt; waybar and rofi can't share state or draw a power footer), Settings (`settings.md`), the minimise listener (Hyprland has no minimised state), the Atrium bind set, the `invictus-everyday` meta, and the Atrium Calamares pages.

---

## 11. Cut, and why

| Cut | Why |
|---|---|
| Workspaces | A second axis of "where did my window go" |
| Keyboard shortcuts as the way to do things | The whole point |
| Tray, notification bell, updates counter, "Now" | Things that need you arrive as a message |
| Desktop icons | Start is the one place apps live; icons on the desktop are hidden behind full-size windows anyway |
| Lock and Log out in Start | One person per computer; the lock is automatic |
| A red close button | Red means something is wrong |
| A Atrium/Tessera question at first start | A choice a non-technical person can't make well, reversible in 3 clicks |
| The Desk | Alex's work dashboard |
