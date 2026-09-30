# Invictus: the look

Status: design, not yet built. Owner: Venus (designer). Mark: `docs/brand/`.

Mockups (`docs/mockups/`, each 1920 x 1080, self-contained HTML, fonts from Google Fonts, scale down to fit narrower windows):

| File | State |
|---|---|
| `desktop-working-notification.html` | Bar, three tiled windows with the editor focused, a Moneta notification |
| `desktop-launcher-open.html` | The launcher open over the same windows |
| `desktop-moneta-panel.html` | The Moneta panel open, with an approval request |
| `lock-typing.html` | Lock screen, password being typed |
| `login.html` | Login (SDDM), last user preselected |
| `desk.html` | The first Desk sketch (superseded by `desk-*.html`, `docs/desk.md`) |
| `brand-sheet.html` | Mark, palette and type on one page |
| `themes.html` | The four themes side by side (bar, a focused terminal, the launcher) and the theme picker open |
| `motion.html` | Motion, playing: log in, unlock, window open and focus, workspace switch, notification, theme switch. Buttons switch Showcase / Calm / Off and replay one moment |
| `motion.webm` | A 28 s recording of `motion.html` in Showcase (1280 x 720), for sharing |

Sample content in the mockups (thread names, commit messages, and the Lua in the editor, which is not the real Hyprland API) is made up.

The Atrium desktop (for friends who don't use keyboard shortcuts) has its own design and mockups: `docs/simple-mode.md` and `docs/mockups/simple-*.html`. It uses the tokens, themes and rules below unchanged.

## Concept

**Dusk in the stoa.** Warm dark stone, marble-white text, and one gold: the sun. Gold means one thing on this desktop: *you are here*. It marks the focused window, the active workspace, the selected launcher row and the field you are typing in. On a screen with a single job (the ISO's Install card) it also marks the one next step. Nothing else is gold, so the eye always finds its place in one glance.

Everything else is quiet: no live graphs in the bar, no gradients that move, no transparency behind text you read. Roman touches are in the names, the mark, the display type on the login and lock screens, and one line of Marcus Aurelius on the lock screen. They stay out of the working surfaces.

What changed from hyprdots: the old look was black pills on a busy bar, a white gradient border, see-through windows and anime wallpapers. Invictus keeps what worked (IBM Plex Mono, master layout, the block cursor, Papirus) and replaces the rest.

## Palette

Tokens are the contract. Every surface below uses these names; engineers should never type a hex that is not in this table. The Dusk values below live in `theme/dusk.toml`; other themes (see Themes) use the same names with other values.

### Dark (default): "Dusk"

| Token | Hex | Use |
|---|---|---|
| `night` | `#14120F` | Deepest background: terminal, lock, login, boot, bar |
| `basalt` | `#1C1A16` | Panels: launcher, notifications, Moneta panel, Desk cards |
| `stone` | `#27241F` | Raised: selected rows, hovered items, input fields |
| `line` | `#3A352D` | 1 px borders and dividers, inactive window border |
| `marble` | `#ECE6DA` | Primary text |
| `parchment` | `#BDB4A3` | Secondary text, occupied workspace numbers, labels |
| `ash` | `#968E7F` | Muted text: hints, timestamps, empty workspaces |
| `sol` | `#E0A64B` | **Focus only.** Active border, active workspace, selection bar, caret, focused field |
| `sol-bright` | `#F0C274` | Hover on a gold element; progress fill |
| `pompeii` | `#D9725A` | Error, critical notification, failed password, battery/temperature alarm |
| `laurel` | `#94AD7B` | Success, "snapshot taken", healthy |
| `lapis` | `#7C9FD4` | Links and info. Also Moneta's "listening" state |
| `verdigris` | `#72ACA3` | Terminal cyan only |
| `tyrian` | `#B388B0` | Terminal magenta only |

Names are Roman on purpose: Pompeian red, verdigris (bronze patina), Tyrian purple, lapis, laurel. They are easy to remember and hard to confuse with each other.

**Contrast (WCAG 2.x, measured):**

| Text | on `night` | on `basalt` | on `stone` |
|---|---|---|---|
| `marble` | 15.0 | 14.0 | 12.4 |
| `parchment` | 9.1 | 8.5 | 7.5 |
| `ash` | 5.8 | 5.4 | 4.8 |
| `sol` | 8.7 | 8.1 | 7.2 |
| `pompeii` | 5.8 | 5.4 | 4.8 |
| `laurel` | 7.6 | 7.1 | 6.3 |
| `lapis` | 6.9 | 6.4 | 5.7 |
| `night` on `sol` (text on a gold button) | 8.7 | | |

Every text pair passes AA (4.5) for normal text. `line` is never used for text (1.6 on `night`); it is a divider only. Terminal bright black (`#857D6F`, used for comments and zsh autosuggestions) is 4.6 on `night`.

### Light variant: "Dawn" (partial, on purpose)

Worth it for apps, not for the shell. Friends and family will read documents and web pages in daylight, so GTK/Qt apps and the Desk follow the system light/dark setting. The bar, launcher, notifications, lock, login and boot stay dark always: they are small, they sit on the wallpaper, and theming ten surfaces twice doubles the upkeep for little gain.

| Token | Hex | Contrast note |
|---|---|---|
| `dawn` (bg) | `#F4EFE6` | |
| `dawn-surface` | `#FBF8F2` | |
| `dawn-raised` | `#EAE3D6` | |
| `dawn-line` | `#D6CCBB` | divider only |
| `ink` | `#221E18` | 14.5 on `dawn` |
| `ink-2` | `#4A4338` | 8.5 |
| `ink-muted` | `#6B6254` | 5.2 |
| `bronze` (focus/accent) | `#8A5A12` | 5.2; `sol` fails on light (1.8), so light mode uses bronze |
| `pompeii-dark` | `#A8432C` | 5.2 |
| `laurel-dark` | `#4E6B35` | 5.3 |
| `lapis-dark` | `#355F9E` | 5.6 |

### Terminal colours (kitty, and anything that reads ANSI)

| | Normal | Bright |
|---|---|---|
| black | `#27241F` | `#857D6F` |
| red | `#D9725A` | `#E8927C` |
| green | `#94AD7B` | `#AEC596` |
| yellow | `#E0A64B` | `#F0C274` |
| blue | `#7C9FD4` | `#9DB8E2` |
| magenta | `#B388B0` | `#CAA3C7` |
| cyan | `#72ACA3` | `#93C6BE` |
| white | `#BDB4A3` | `#ECE6DA` |

Background `#14120F`, foreground `#ECE6DA`, selection background `#3A352D`, selection foreground `#ECE6DA`, cursor `#ECE6DA`, cursor text `#14120F`, URL `#7C9FD4`. All normal colours are 5.8 or more on the background.

## Typography

| Role | Face | Package (Arch `extra`) | Licence |
|---|---|---|---|
| UI (bar, launcher, notifications, GTK, Desk) | IBM Plex Sans | `ttf-ibm-plex` | OFL |
| Mono (terminal, code, numbers in the bar) | IBM Plex Mono | `ttf-ibm-plex` (same package) | OFL |
| Display (wordmark, lock date, login, boot, ISO) | Cormorant SC, Cormorant Garamond | `otf-cormorant` | OFL |
| Icon glyphs in bar and terminal | Symbols Nerd Font Mono | `ttf-nerd-fonts-symbols-mono` | MIT |

One family for UI and code (Plex) keeps the desktop coherent, and Alex already uses Plex Mono. Cormorant SC is the Roman voice: small caps, wide tracking (`letter-spacing: 0.18em`), used only at 18 px and up and only on surfaces where you are not working. Drop `ttf-dejavu` and `ttf-jetbrains-mono` from the default install; keep `noto-fonts`, `noto-fonts-cjk`, `noto-fonts-emoji` as fallbacks.

Sizes: bar 13 px (clock 14 px, weight 600). Launcher 15 px. Notification title 13 px/600, body 13 px/400. Terminal 12.5 pt with `cell_height 110%` (unchanged). Lock clock 112 px Plex Sans weight 300.

Fontconfig: set `sans-serif` to IBM Plex Sans, `monospace` to IBM Plex Mono, `serif` to Cormorant Garamond, with Symbols Nerd Font Mono appended to each.

## The mark

**The radiate sun.** Sol Invictus on Roman coins wears a crown of rays. The mark is a solid disc with nine short rays around it and a horizon line under it: a sun that has already risen. The rays are 25° apart; the lowest pair (added 2026-09-30 at Alex's request) sits just below the disc's centre line, in what used to be the empty gap above the horizon, so the crown reads as a full half-circle and the sun is clearly clear of the horizon. Files: `docs/brand/invictus-mark.svg` (64 px grid, 3.5 px strokes, round caps) and `docs/brand/invictus-mark-small.svg` (16 px cut, for the bar and favicons).

The 16 px cut has three rays on top and the two low side rays. The side rays are flat, 1 px, butt-capped and sit exactly on pixel row 10, one clear pixel from the disc, because an angled 1.5 px ray at that size rendered as a two-pixel smear that merged with the disc (checked at 1x and 2x in Chromium). They are lighter than the top rays at 1x; that is the price of staying sharp. At 2x and up they read as the big mark does.

- Always one colour, `currentColor`. `marble` on dark, `ink` on light. `sol` only when the mark itself is the focus (the boot splash, the lock screen).
- Wordmark: `INVICTUS` in Cormorant SC, weight 500, tracking 0.18em, set to the right of the mark or under it. Plain `U`, not the inscriptional `V`: people have to read and type the name.
- No Arch logo, no Arch name except the line "based on Arch Linux" in About and fastfetch.

## Surfaces

### Hyprland (windows)

Option names are the Hyprland variable names; Vulcan maps them into the Lua config.

| Option | Value | Why |
|---|---|---|
| `general.gaps_in` | `4` | |
| `general.gaps_out` | `8` | Enough air to read window edges, less wasted space on three monitors |
| `general.border_size` | `2` | Thin and precise; 3 read as heavy |
| `general.col.active_border` | `rgb(E0A64B)` (solid `sol`) in Calm and Off; in Showcase `sol`, `sol-bright`, `sol` at 45° for the glint (see Motion) | The single "you are here" signal |
| `general.col.inactive_border` | `rgb(27241F)` (`stone`) | Present but silent |
| `general.layout` | `master` (unchanged) | |
| `general.resize_on_border` | `false` (unchanged) | |
| `decoration.rounding` | `8` | |
| `decoration.rounding_power` | `2` (unchanged) | |
| `decoration.active_opacity` | `1.0` | Code and text stay fully legible |
| `decoration.inactive_opacity` | `1.0` | |
| `decoration.dim_inactive` | `true` | Unfocused windows step back instead of going see-through |
| `decoration.dim_strength` | `0.12` | Noticeable, never hides content |
| `decoration.shadow.enabled` | `true` | |
| `decoration.shadow.range` | `16` | |
| `decoration.shadow.render_power` | `3` | |
| `decoration.shadow.color` | `rgba(00000073)` (black at 45%) | Focused window lifts a little |
| `decoration.shadow.color_inactive` | `rgba(00000000)` | Unfocused windows get none |
| `decoration.blur.enabled` | `true` | Only visible on layers, since windows are opaque |
| `decoration.blur.size` | `6` | |
| `decoration.blur.passes` | `3` | |
| `decoration.blur.noise` | `0.015` | Stops banding on the dark gradient wallpapers |
| `decoration.blur.vibrancy` | `0.1` | |
| `decoration.blur.new_optimizations` | `true` | |
| `decoration.blur.xray` | `false` | |
| `group.col.border_active` | `rgb(E0A64B)` | |
| `group.col.border_inactive` | `rgb(27241F)` | |
| `group.groupbar.font_family` | `IBM Plex Sans` | |
| `group.groupbar.font_size` | `12` | |
| `group.groupbar.col.active` | `rgb(E0A64B)` | |
| `group.groupbar.col.inactive` | `rgb(3A352D)` | |
| `group.groupbar.text_color` | `rgb(ECE6DA)` | |
| `misc.disable_hyprland_logo` | `true` | |
| `misc.disable_splash_rendering` | `true` | |
| `misc.force_default_wallpaper` | `0` | |
| `misc.background_color` | `rgb(14120F)` | No flash of another colour before the wallpaper loads |
| `misc.focus_on_activate` | `false` | Apps cannot steal focus. Protects attention |
| `misc.vfr` | `true` | |
| `cursor.no_hardware_cursors` | keep what `0a579b7` set | That commit fixed a real bug |

Layer rules (blur the panels that sit on the wallpaper): `blur` and `ignore_alpha 0.3` for namespaces `waybar`, `rofi`, `swaync-notification-window`, `swaync-control-center`, `moneta-panel`.

**Animations.** See **Motion** below. It replaces the single snappy table that was here: everyday changes keep that speed, and a few moments get more.

**Game mode.** A keybind (key to be picked; `Super + G` is Steam in `binds.lua`, see the record on Alex's Desk) and an automatic rule when a Steam/gamescope window goes fullscreen: turn off every animation (motion level Off, see Motion), blur, shadows and dim, set gaps to 0 and border to 0, and turn DND on in swaync. The same key restores. The bar hides on fullscreen as normal. For frame stats in game use MangoHud with its own config coloured `marble` text on `night` at 70%, top-left, not the bar.

### Waybar (the bar)

One continuous bar, not pills. The old bar had nine floating black pills and four stats refreshing every 2 s; the eye had nowhere to rest.

- Position top, attached to the edge (no margins), `height 32`, `layer top`, `exclusive true`.
- Background `rgba(20,18,15,0.82)` (`night` at 82%) with the layer blur; 1 px bottom border `line`.
- Font IBM Plex Sans 13 px; numbers in IBM Plex Mono 13 px (`font-feature-settings: "tnum"`).
- Module padding 0 10 px; 4 px gap between modules; no module backgrounds.
- Text `parchment`; hover `marble` on `stone` with 6 px radius.

**Primary monitor (`DP-1`):**

| Left | Centre | Right |
|---|---|---|
| mark (16 px, `marble`; click opens the Desk) | clock | Moneta "Now" (see below) |
| workspaces | | tray (collapsed, `waybar` `tray` with `icon-size 16`) |
| window title | | updates (hidden when 0) |
| | | system alert (hidden unless hot) |
| | | volume |
| | | network |
| | | notifications (swaync count, dot when unread) |
| | | Moneta button |

**Other monitors (`DP-2`, `HDMI-A-2`):** left: workspaces, window title. Centre: clock. Nothing on the right. One status area, on one monitor, so there is one place to look.

Module details:

- **Workspaces** (`hyprland/workspaces`, `all-outputs false`, persistent 1-3 / 4-6 / 7-9 as now). Arabic numerals in Plex Mono, 22 px wide buttons. Empty: `ash`. Has windows: `parchment`. Active: `marble` with a 2 px `sol` bar under the number (`box-shadow: inset 0 -2px #E0A64B`). Urgent: `pompeii` number. Numbers match the keys you press, so no Roman numerals here.
- **Window title** (`hyprland/window`, `separate-outputs true`, `max-length 60`): `ash`, 13 px. Empty desktop: hidden.
- **Clock**: `%H:%M`, Plex Sans 14 px weight 600, `marble`. Tooltip: `%A %d %B %Y`. Click toggles a calendar in the tooltip.
- **Now** (custom module, depends on the assistant's architecture): the one thing Moneta says you are doing, for example `Now · Port waybar to Lua`, `parchment`, max 40 characters. Click opens the Desk with the keyboard on its Now card (changed 2026-09-30, `desk.md` 1.2; it opened the Moneta panel's threads, which the Desk's Switch now lists). Hidden when nothing is set. This is the ADHD anchor: one line, always in the same place. With No AI (`no-ai.md` 4) it stays, set by hand from the Desk. A running timer adds whole minutes (`· 19 min`), never seconds.
- **Updates**: `󰮯 12` in `parchment`; hidden at 0. Click opens the update terminal as now.
- **System alert** (replaces the GPU, CPU and memory pills): hidden while CPU < 90%, GPU temp < 90 °C, RAM < 90% and root disk < 90%. When one is over, shows that one reading in `pompeii`, e.g. `󰢮 94 °C`. Tooltip always lists all four. Poll every 5 s, not 2.
- **Volume** (`pulseaudio`): icon + number, muted shows the muted icon in `ash`. Scroll 5%. Click opens `pavucontrol`.
- **Network**: icon only; tooltip has the details. Disconnected: icon in `pompeii`.
- **Notifications** (`custom/swaync`, from `swaync-client -swb`): bell icon, `sol` dot when there are unread ones, crossed bell in `ash` when DND is on. Click toggles the control centre.
- **Moneta button**: the Moneta coin glyph (a circle with an `M`, drawn in the icon set as `moneta-symbolic`) in `parchment`. States: idle `parchment`; has something for you: small `sol` dot; listening (push-to-talk held): glyph in `lapis` with a 1 px `lapis` ring. Click toggles the Moneta panel. Not shown with No AI (`no-ai.md` 4).

### Rofi (launcher)

- Mode `drun` only; `window` and `run` stay bound to their own keys (the old `modi` list showed a mode bar nobody used). No mode switcher shown.
- Window: 560 px wide, centred, 18% from the top, `basalt` at 94% with blur, 1 px `line` border, radius 12, padding 12.
- Input row: 44 px tall, `stone` background, radius 8, Plex Sans 15 px `marble`, caret `sol`, placeholder `Search apps` in `ash`, magnifier glyph in `ash` at the left. 1 px `sol` border on the input (it always has focus).
- List: 8 rows, 40 px each, 4 px between input and list, icons 24 px (Papirus), name 15 px `marble`, generic name 13 px `ash` after it on the same line.
- Selected row: `stone` background, radius 8, 3 px `sol` bar on its left edge, name `marble`.
- No scrollbar, no row numbers, no mode tabs. A single hint line under the list: `Enter open   Ctrl+Enter run as typed` in 12 px `ash`.

### Kitty

- Font IBM Plex Mono 12.5, `modify_font cell_height 110%` (unchanged).
- Colours from the terminal table above. `background_opacity 1.0`.
- `window_padding_width 10 14`.
- Cursor: block (unchanged), `cursor #ECE6DA`, `cursor_text_color #14120F`.
- Blink and trail follow the motion level (Alex, 2026-09-30: he likes his original cursor animation, so it is Showcase). Showcase, the default: `cursor_blink_interval 0.5 ease-in-out`, `cursor_stop_blinking_after 0`, `cursor_trail 50`, `cursor_trail_decay 0.12 0.45`, `cursor_trail_start_threshold 2`, `cursor_trail_color none`. Calm: the shorter set, `cursor_stop_blinking_after 15` (a cursor that never stops moving pulls the eye), `cursor_trail 3`, `cursor_trail_decay 0.08 0.3`. Off: `cursor_trail 0` and `cursor_blink_interval 0`. One file per level in `config/kitty/motion/`; `kitty.conf` includes Showcase, then `~/.config/invictus/motion.d/kitty.conf` (the motion switcher links it at the chosen level's file), and kitty re-reads it on `SIGUSR1`.
- Tabs: `tab_bar_style separator`, `tab_separator " · "`, active tab `marble` on `stone`, inactive `ash` on `night`, `tab_bar_edge top`, `tab_bar_min_tabs 2`.
- `active_border_color #E0A64B`, `inactive_border_color #27241F` for kitty splits (the same rule as Hyprland).
- `url_color #7C9FD4`, `url_style single`.

### Notifications (swaync)

- Position top-right, 8 px from the bar and screen edge. Width 380 px. At most 3 popups on screen; the rest go to the control centre.
- Card: `basalt` at 94% with blur, 1 px `line` border, radius 12, padding 14. App icon 32 px, radius 8. Title Plex Sans 13 px weight 600 `marble`; body 13 px `parchment`, 3 lines max; time 12 px `ash` top-right.
- Critical: 3 px `pompeii` bar on the left edge, stays until dismissed. Normal: 5 s. Low: 3 s.
- Action buttons: text only, `parchment`, hover `marble` on `stone`.
- Control centre: 400 px, full height below the bar. Top to bottom: a single "Do not disturb" switch (on = `sol` track), the list grouped by app, "Clear all" at the bottom in `ash`. Cut: the MPRIS player, volume and backlight sliders, button grid. The bar already has volume; the rest is noise.
- Moneta notifications use the Moneta glyph as the app icon and a `lapis` title, so they are told apart from app spam at a glance.

### Lock screen (hyprlock)

See `docs/mockups/lock.html`. Same composition as the login screen, so locking and logging in feel like one place.

- Background: the current wallpaper, `blur_passes 3`, `blur_size 8`, `brightness 0.55`, `contrast 0.95`, `noise 0.01`.
- Mark: 48 px, `sol`, centred, 22% from the top.
- Time: `$TIME` as `HH:MM`, IBM Plex Sans weight 300, 112 px, `marble`, 16 px under the mark.
- Date: Cormorant SC 22 px, tracking 0.18em, `parchment`, e.g. `WEDNESDAY · 30 SEPTEMBER`.
- Input field: 300 x 48, centred, 62% from the top. `inner_color` `rgba(28,26,22,0.9)` (basalt), `outer_color` `rgb(3A352D)` idle, `rgb(E0A64B)` while typing, `outline_thickness 1`, `rounding 12`, `font_color` `rgb(ECE6DA)`, dots size 0.22 spacing 0.3, `placeholder_text` `Password` in `ash`, `fail_color` `rgb(D9725A)` with text `Wrong password`, `check_color` `rgb(94AD7B)`, `fade_on_empty false`.
- One line from the *Meditations*, bottom centre, Cormorant Garamond italic 18 px `parchment`, attribution 12 px `ash`: "The universe is change; our life is what our thoughts make it." Marcus Aurelius, *Meditations* IV.3 (George Long's 1862 translation, public domain). A short list rotates daily; Clio checks the wording against Long's text before it ships.
- Cut: user avatar, battery, media, weather, keyboard layout (show layout only when more than one is configured).
- Unlock animation: see Motion, Ceremonies. The blurred wallpaper dissolves into your desktop.

### Login (SDDM)

Replace blackglass (its folder in `assets/SDDM/` is already empty). New theme `invictus` in QML for SDDM 0.21 / Qt 6. See `docs/mockups/login.html`.

- Same background, mark, clock and date as hyprlock, with the wordmark `INVICTUS` under the mark (Cormorant SC 20 px, tracking 0.3em, `parchment`).
- User row: the last user preselected, name in Plex Sans 16 px `marble`. Other users are behind a small `Switch user` text button, not a list.
- Password field: identical to hyprlock.
- Bottom-left: session name in `ash` (`Hyprland`), click cycles. Bottom-right: power and restart icons, `ash`, hover `marble`. Suspend is not shown here.
- The Hyprland compositor setup for SDDM from `d43490a` stays.

### GTK, Qt, icons, cursor

| Piece | Choice | Package | Notes |
|---|---|---|---|
| GTK 3 / 4 | adw-gtk3 (dark and light), coloured with an override | `adw-gtk-theme` (extra) | Write `@define-color` overrides to `~/.config/gtk-3.0/gtk.css` and `gtk-4.0/gtk.css`: `accent_color` `#E0A64B`, `accent_bg_color` `#E0A64B`, `accent_fg_color` `#14120F`, `window_bg_color` `#1C1A16`, `view_bg_color` `#14120F`, `headerbar_bg_color` `#1C1A16`, `card_bg_color` `#27241F`, `window_fg_color` `#ECE6DA`, `destructive_color` `#D9725A`, `success_color` `#94AD7B`. Light uses the Dawn tokens with `bronze` as accent. |
| Qt 5 / 6 | Fusion + a colour scheme | `qt5ct`, `qt6ct` (extra) | `invictus.conf` colour scheme from the same tokens; `QT_QPA_PLATFORMTHEME=qt6ct`. Kvantum was considered: one more engine to maintain for the few Qt apps Alex uses. |
| Icons | Papirus-Dark, folders grey | `papirus-icon-theme` (extra, already installed) | Grey folders via the `papirus-folders` script (`papirus-folders -C grey --theme Papirus-Dark`). Grey, not yellow: gold is reserved for focus. |
| Cursor | Capitaine Cursors (dark), 24 px | `capitaine-cursors` (extra) | Set `XCURSOR_THEME`, `XCURSOR_SIZE=24`, and `gsettings` `cursor-theme`. |
| Settings tool | nwg-look | `nwg-look` (already installed) | |

Remove `nordic-darker-theme` (AUR). Its cold blue fights the warm palette and it is one fewer AUR package on the ISO.

### Fastfetch

- Logo: the mark in Unicode blocks, coloured `sol`, 9 lines tall (drawn in `config/fastfetch/logo.txt` by the engineer from `invictus-mark.svg`), or `kitty-direct` with a PNG of the mark when running in kitty.
- Title `user@host` in `marble`. Keys in `parchment`, values in `marble`, separator `line` coloured `─`.
- Modules: OS (`Invictus (based on Arch Linux)`), kernel, uptime, packages, WM, terminal, shell, CPU, GPU, memory, disk (`/`). Nothing else.

### btop and cava

- btop: a theme file `invictus.theme` from the tokens: `main_bg` empty (use the terminal background), `main_fg` marble, `title` parchment, `hi_fg` sol, `selected_bg` stone, `selected_fg` marble, `inactive_fg` ash, graph gradients `laurel` → `sol` → `pompeii` (only place gold means "load" rather than focus, accepted since btop is a monitor). `rounded_corners true`.
- cava: two-colour gradient `#3A352D` → `#BDB4A3`. No shaders by default (the six shaders stay available).

### Wallpapers

Remove `Berserk.jpg` (copyrighted art), `girl.png` and `blossom.png` (source and licence unknown) from the default set. Alex can keep them in his own home folder.

The default set is made by us from the palette, as SVG sources plus a 3840 x 2160 PNG export in `assets/wallpapers/`, licensed CC BY 4.0 (Alex as author; see `assets/wallpapers/LICENSE.md`). Other sizes (5120 x 1440 ultrawide, 2560 x 1440) are rendered from the SVG by the theme generator with `rsvg-convert`; every SVG uses `preserveAspectRatio="xMidYMax slice"`, so a wider screen keeps the horizon and loses sky. Each file has a little grain (`feTurbulence`, 2.8% overlay) so the dark gradients do not band.

1. **Sol** (default, `sol.svg`): a low sun just above a horizon between two low hills, `sol` fading through `#3B2A17` into `night`, a faint reflection on the ground, and the mark's nine rays at about 4%, blurred, fanning up from the sun. The sun sits in the lower third so the bar and the centre stay dark. Mockups use this one.
2. **Stoa**: a row of column silhouettes in `basalt` against a `night` to `stone` sky; very low contrast.
3. **Radiate**: the mark's nine rays at huge scale, `line` on `night`, off to one side.
4. **Night**: flat `night` with 1.5% noise, for anyone who wants nothing.

Optional extras, public domain only: photographs from the Met Open Access and Rijksmuseum collections (both CC0), for example Roman coins of Aurelian showing Sol, or Roman architecture. Each file gets its source URL and licence in `assets/wallpapers/SOURCES.md`. Wikimedia Commons only for files marked public domain or CC0.

### Boot splash (Plymouth) and ISO

- Plymouth `script` theme `invictus`: `night` background, the mark 96 px centred in `line` colour. As boot progresses the nine rays light up one by one, left to right in `sol`, then the disc. No spinner, no text. On the LUKS prompt: the same 300 x 48 field as hyprlock under the mark, label `Disk password` in `ash`.
- Boot loader (limine on the ISO and installed system): background `14120F`, text `ECE6DA`, selected entry `E0A64B`, branding `Invictus`, no wallpaper, 3 s timeout.
- ISO desktop: the Sol wallpaper, the bar, and one centred card (`basalt`, radius 16, 440 px): the mark, `INVICTUS` wordmark, one line `Try it, or install it on this computer.`, and a single gold button `Install Invictus` (`night` text on `sol`, 48 px tall, radius 10). A text link under it, `Open a terminal`, in `ash`. Nothing else on screen.
- Installer (Calamares or our own, per Minerva's architecture): sidebar `night`, sidebar text `parchment`, current step `sol` text with a 3 px `sol` left bar, content on `basalt`, primary button `sol`. Product name `Invictus`, the mark as the product logo, the Sol wallpaper as the welcome image.

### The Moneta panel

A layer-shell panel (namespace `moneta-panel`) that slides in from the right edge. It is a helper beside your work, not a window in the tiling.

- 440 px wide, full height under the bar, 8 px gap to the right edge. `basalt` at 96% with blur, 1 px `line` border, radius 12.
- Slide in `layersIn` (180 ms); `Super + A` or the bar button toggles; `Esc` closes. Opening does not steal focus from the game or the window under it until you click or start typing into it.
- Header (48 px): Moneta glyph, `Moneta` in Plex Sans 15 px weight 600, status word in `ash` (`Ready`, `Listening`, `Thinking`, `Working on it`). Right: a collapse button.
- **Now** strip under the header: the current thread in one line, `parchment`, with a `sol` 3 px left bar. `Threads (4)` collapsed row under it; opening it shows the open threads, one line each, click to switch.
- Conversation: Moneta's messages on no background, `marble` text, 14 px, line height 1.5. The person's messages right-aligned on `stone`, radius 12. Code blocks in Plex Mono 13 px on `night`. Tool actions she takes appear as one collapsed line (`Ran 2 commands`) with the details behind it.
- Input: 48 px min, `stone`, radius 12, placeholder `Ask Moneta` in `ash`, `sol` border on focus. A mic glyph at the right shows push-to-talk: `ash` idle, `lapis` with a level bar while the pen button is held, `pompeii` if the mic fails.
- Anything that needs approval (running a command with system access) shows as a card with a 1 px `sol` border (it is where your attention is needed), the exact command in mono, and two buttons of equal weight, `Allow once` and `Deny`, both `marble` on `stone`. Neither is styled as the default, so a habit click does not approve. While the card waits, the input loses its focus border. Never pre-approved, never auto-dismissed.

### The Desk (home dashboard)

Designed in `docs/desk.md` (2026-09-30), with mockups `desk-tessera.html`, `desk-card-mockups.html` and `desk-no-ai.html`. In short: the home screen of Tessera, shown and hidden with a tap of Super, three columns (you, the team, Moneta) with the claude.ai Desk's sections and words, keyboard first, one gold. The first sketch (`desk.html`, greeting, Now, Open threads, Waiting on you) is kept for history.

Cut from the Desk: weather, news, calendar grid, app shortcuts (that is the launcher's job), system graphs (that is btop's job).

## Themes

Alex asked for more looks (2026-09-30): a Roman one, a Greek one, and so on, on a Super key. Dusk stays the default. Three more, each from one clear source. See `docs/mockups/themes.html`.

| Theme | Source | Concept | Focus (`sol`) | Wallpaper |
|---|---|---|---|---|
| **Dusk** (default) | Roman: Sol Invictus, a stoa at sunset | Warm dark stone, marble-white text, and one gold: the sun. | gold `#E0A64B` | Sol |
| **Porphyry** | Roman: imperial porphyry and Tyrian purple, the stone and dye kept for emperors | Dark porphyry, travertine-white text, Tyrian purple for focus. | Tyrian `#CE93C8` | Arcade |
| **Aegean** | Greek: the Aegean at night, Pentelic marble and sea blue | Cool marble grey in shadow, and the blue of the sea for focus. | sea blue `#6DB3F2` | Selene |
| **Alexandria** | Egyptian and Greek: the lapis-blue tomb ceilings of Egypt, papyrus, the Pharos light | Lapis night, papyrus-white text, lamp gold for focus. | lamp gold `#E6B652` | Pharos |

Why these four and not more:

- **Porphyry, not "Pompeii red".** A red Roman theme would put the focus colour next to the error colour (`pompeii`), and the "you are here" rule would stop working. Porphyry keeps the Roman red in the stone and moves focus to Tyrian purple, the other imperial colour.
- **Aegean, not red-figure pottery.** Attic black-and-terracotta is the most famous Greek palette, but terracotta focus sits too close to error red again, and worse for red-green colour blindness. Sea blue is Greek, calm, and survives every colour-blindness simulation we ran.
- **Alexandria earns its place** because it is the only other one with a different ground: a blue-black night instead of warm or cool stone. It keeps gold focus, so it is the gentlest step away from Dusk for someone who likes the gold but wants a change. It also ties the set together: a Greek city in Egypt, later Roman.
- **Byzantine and Etruscan left out.** Byzantine is gold on dark, so it would be Dusk again with a new name. Etruscan is terracotta and black, the same focus-versus-error clash as Attic. Four is also enough to pick from without comparing: every choice is one row in the picker.

### Rules every theme keeps

1. **Same token names.** Every theme defines all 14 dark tokens, 11 light tokens and the 23 terminal values in the same files with the same names. The names are roles, not colours: in Aegean, `sol` is blue and `lapis` (info) is sea green. No app reads a hex; they read tokens.
2. **Focus only.** `sol` still means "you are here" and nothing else. The same surfaces use it in every theme. Terminal yellow may equal `sol` (as in Dusk and Alexandria); nothing in the shell may.
3. **Contrast.** Every text token passes WCAG AA (4.5) on `night`, `basalt` and `stone`, `night` text on a `sol` button passes, terminal bright black passes on the background, and every light token passes on `dawn`, `dawn-surface` and `dawn-raised`. Numbers below; `invictus-theme check` re-measures them and refuses to install a theme that fails.
4. **Focus stays apart from status.** `sol` must differ from `pompeii` (error), `laurel` (success), `lapis` (info) and `parchment` (secondary text) by a CIE76 ΔE of at least 10 under simulated deuteranopia and protanopia (Machado 2009). All four pass; the closest pair is Porphyry focus against info, 12 under deuteranopia. That check is why Aegean's info colour moved to sea green and Porphyry's to verdigris green.
5. **ADHD rules hold.** No theme adds motion, gradients on working surfaces, transparency behind text, or a second accent. Only colour, wallpaper and the shape of the one notification accent change (see Motion); layout, type, sizes and timings are identical, so a switch never moves anything under your hands.
6. **Shell stays dark.** Each theme has its own light set for apps and the Desk; the bar, launcher, notifications and lock stay dark, as with Dusk and Dawn.

### Contrast, measured (WCAG 2.x)

Dusk is the table under Palette above. Colour-blind separation of `sol`, ΔE deutan/protan: Dusk error 22/33, success 33/29; Porphyry error 54/51, info 12/25; Aegean error 73/59, info 36/38, secondary text 41/36; Alexandria error 24/37, success 33/29.

#### Porphyry

| Token | Hex | on `night` | on `basalt` | on `stone` |
|---|---|---|---|---|
| `night` | `#151012` | | | |
| `basalt` | `#1D1618` | | | |
| `stone` | `#291F22` | | | |
| `line` | `#3F3034` | | | |
| `marble` | `#EEE4DF` | 15.1 | 14.2 | 12.8 |
| `parchment` | `#C6B4AF` | 9.5 | 8.9 | 8.0 |
| `ash` | `#A08D89` | 6.0 | 5.6 | 5.1 |
| `sol` | `#CE93C8` | 7.7 | 7.3 | 6.6 |
| `pompeii` | `#E57A5E` | 6.5 | 6.2 | 5.5 |
| `laurel` | `#9DB380` | 8.2 | 7.8 | 7.0 |
| `lapis` | `#7FB8B0` | 8.4 | 8.0 | 7.1 |
| `sol-bright` | `#E0B0DB` | 10.2 | 9.7 | 8.7 |
| `verdigris` | `#76AFA5` | 7.6 | | |
| `tyrian` | `#CE93C8` | 7.7 | | |

`night` on `sol` 7.7; `line` on `night` 1.51 (divider only). Light: `ink` `#241A1C` 13.2, `ink-2` `#4D3D40` 8.0, `ink-muted` `#6E5B5E` 4.9, `bronze` `#86407F` 5.4, `pompeii-dark` `#A9412B` 4.7, `laurel-dark` `#4E6B35` 4.7, `lapis-dark` `#2B6A62` 4.9 (lowest of `dawn`, `dawn-surface`, `dawn-raised`); backgrounds `dawn` `#F5EEEC`, `dawn-surface` `#FBF7F6`, `dawn-raised` `#EBE1DE`, `dawn-line` `#D8C9C5`.

#### Aegean

| Token | Hex | on `night` | on `basalt` | on `stone` |
|---|---|---|---|---|
| `night` | `#101416` | | | |
| `basalt` | `#161B1E` | | | |
| `stone` | `#1F2629` | | | |
| `line` | `#2F393D` | | | |
| `marble` | `#E6EAE8` | 15.3 | 14.3 | 12.6 |
| `parchment` | `#B4BDBB` | 9.6 | 9.0 | 8.0 |
| `ash` | `#8D9896` | 6.2 | 5.8 | 5.2 |
| `sol` | `#6DB3F2` | 8.3 | 7.8 | 6.9 |
| `pompeii` | `#E27C68` | 6.5 | 6.0 | 5.4 |
| `laurel` | `#AEB872` | 8.7 | 8.2 | 7.2 |
| `lapis` | `#62C3B6` | 8.8 | 8.3 | 7.3 |
| `sol-bright` | `#9CCBF6` | 10.8 | 10.2 | 9.0 |
| `verdigris` | `#62C3B6` | 8.8 | | |
| `tyrian` | `#C095C9` | 7.4 | | |

`night` on `sol` 8.3; `line` on `night` 1.56 (divider only). Light: `ink` `#161C1E` 13.7, `ink-2` `#3B4547` 7.8, `ink-muted` `#586466` 4.9, `bronze` `#22609E` 5.1, `pompeii-dark` `#A8432C` 4.8, `laurel-dark` `#5A6624` 5.0, `lapis-dark` `#1C6B62` 5.0 (lowest of `dawn`, `dawn-surface`, `dawn-raised`); backgrounds `dawn` `#EEF1F0`, `dawn-surface` `#F8FAF9`, `dawn-raised` `#E1E6E5`, `dawn-line` `#C9D1CF`.

#### Alexandria

| Token | Hex | on `night` | on `basalt` | on `stone` |
|---|---|---|---|---|
| `night` | `#0F111B` | | | |
| `basalt` | `#151826` | | | |
| `stone` | `#1E2233` | | | |
| `line` | `#2E3449` | | | |
| `marble` | `#EDE6D4` | 15.1 | 14.2 | 12.7 |
| `parchment` | `#C0B79F` | 9.4 | 8.8 | 7.9 |
| `ash` | `#9A9482` | 6.2 | 5.8 | 5.2 |
| `sol` | `#E6B652` | 10.0 | 9.4 | 8.4 |
| `pompeii` | `#E57C64` | 6.6 | 6.2 | 5.6 |
| `laurel` | `#A0BC84` | 9.0 | 8.4 | 7.5 |
| `lapis` | `#5FC6C0` | 9.2 | 8.7 | 7.8 |
| `sol-bright` | `#F4CD7E` | 12.4 | 11.7 | 10.4 |
| `verdigris` | `#5FC6C0` | 9.2 | | |
| `tyrian` | `#BB93C9` | 7.3 | | |

`night` on `sol` 10.0; `line` on `night` 1.53 (divider only). Light: `ink` `#1B1C26` 13.0, `ink-2` `#434453` 7.4, `ink-muted` `#626170` 4.7, `bronze` `#7E5A0E` 4.8, `pompeii-dark` `#A8432C` 4.6, `laurel-dark` `#4E6B35` 4.6, `lapis-dark` `#1E6E6A` 4.6 (lowest of `dawn`, `dawn-surface`, `dawn-raised`); backgrounds `dawn` `#F3EEE2`, `dawn-surface` `#FAF8F1`, `dawn-raised` `#E8E1D0`, `dawn-line` `#D3C9B3`.

### Wallpapers per theme

Each theme names one wallpaper in its token file. All are ours, made from that theme's tokens, SVG source plus 3840 x 2160 and 5120 x 1440 PNG exports, CC BY 4.0 with Alex as author, like Sol. Every composition keeps the motif in the lower third and the top dark, so the bar and the centre of the screen stay quiet.

| Wallpaper | Theme | Composition |
|---|---|---|
| **Sol** | Dusk | As above: a low sun over a horizon. |
| **Arcade** | Porphyry | A two-tier Roman aqueduct in `basalt`, receding in perspective from the left edge to the right horizon, its round arches open onto a sky that runs from `night` at the top to deep porphyry (`#43222D`) at the horizon, with a faint `sol` glow (16%) behind the arches on the left. |
| **Selene** | Aegean | A full moon low on the right, `marble` at 88% with faint maria and a soft halo, over a flat sea in `basalt`, a dark headland on the left of the horizon, and a broken path of short horizontal strokes on the water in `sol-bright` fading from 38% to 10%. |
| **Pharos** | Alexandria | A lapis sky from `night` to `#1B2142` at the horizon, 40 sparse five-pointed stars in `sol` from 14% (high) to 34% (low) (the stars painted on Egyptian tomb ceilings), and the Pharos as a three-tier stepped silhouette on a rock on the right, with one `sol-bright` lamp, a faint beam to the left (10% fading to 0) and its reflection on the water. |

Radiate and Night are drawn from tokens (`line` rays on `night`; flat `night` with noise), so the generator renders them for whichever theme is on; they stay available to anyone who picks them in the wallpaper setting.

**Lock and login.** The lock screen uses the same composition for every theme: current wallpaper blurred, the mark in `sol`, the clock in `marble`, the date in `parchment`, the field in `basalt` with a `sol` border while typing, `pompeii` for a wrong password. One rotating quote list for all themes. The login screen (SDDM), the boot splash and the boot menu stay Dusk: they run before the user session, they need root to change, and the brand's front door should look the same on every machine. The cost: after picking Porphyry, login and lock no longer look identical. Acceptable for a first version; see Concerns in the hand-back.

### The switcher

**Key: `Super + Shift + T`** (T for theme). Checked against `config/hypr/invictus/binds.lua` on 2026-09-30: `Super + T` is Zed, nothing is bound to `Super + Shift + T`. Description for the keybinding help: `"Look: change theme"`. The picker is also in the launcher as **Change theme** (`invictus-theme.desktop`), so it can be found without remembering the key.

Keys considered and not used: `Super + C` (the usual copy key on other desktops, likely to be claimed), `Super + K` (no link to the word), `Super + Ctrl + Shift + Space` (what Omarchy uses; three modifiers is a reach).

**The picker** is rofi in `dmenu` mode with its own theme file, built from the same launcher styles:

- Opens where the launcher opens: 560 px wide, centred, 18% from the top, `basalt` at 94% with blur, 1 px `line` border, radius 12, padding 12.
- Header: `Theme` in Plex Sans 14 px weight 600 `marble`. No search field (four rows need no search) and no mode bar.
- One row per theme, 64 px tall, in the order: Dusk, then the others alphabetically, then any user themes. Each row: a 44 px swatch (radius 8, 1 px border in that theme's `line`), the name in 15 px `marble`, the concept in 12.5 px `ash` under it (one line, max 62 characters, which the concepts above keep to).
- **Swatch.** Generated from the theme's own tokens, so it is always right: that theme's `night` as the ground, the 16 px mark scaled to 26 px in that theme's `sol`, and a 10 px foot in `basalt` with a `marble` and an `ash` bar. Rendered by the generator to `swatches/<id>.png` (rofi row icon, `element-icon size 44px`).
- The current theme is preselected (`-selected-row`) and has a check glyph in `parchment` on the right. Selection is the launcher's: `stone` background and 3 px `sol` bar, in the *current* theme's colours.
- Hint line: `Enter apply   Esc close`, 12 px `ash`.
- Enter applies and closes. Esc closes and changes nothing. Picking the current theme closes and does nothing.
- No live preview while moving the selection. Re-colouring the whole desktop on every arrow press would flash every app, and the switch is fast enough that trying one and switching back costs two keypresses.

Taps and decisions: before, changing the look meant editing config files and logging out. After: one chord, arrows, Enter; one decision.

### Files

```
theme/                            # repo; installed to /usr/share/invictus/theme/
  dusk.toml porphyry.toml aegean.toml alexandria.toml
  templates/                      # one file per target, {{token}} placeholders
    hyprland-colors.lua  waybar-colors.css  rofi-colors.rasi  kitty-colors.conf
    swaync-colors.css    hyprlock-colors.conf  gtk-colors.css  qt-colors.conf
    btop.theme  cava-colors  desk-tokens.css  swatch.svg  radiate.svg  night.svg
~/.config/invictus/themes/<id>.toml   # user themes, same schema, listed after the built-ins
~/.local/state/invictus/theme/<id>/   # generated output, one folder per theme
~/.config/invictus/current -> ~/.local/state/invictus/theme/<id>/   # the only thing apps point at
```

**Token file schema** (`theme/<id>.toml`, all four follow it exactly):

- `[meta]`: `id`, `name`, `source`, `concept` (max 62 characters), `wallpaper` (a name in `assets/wallpapers/`), `lock = "standard"`, `gnome-accent` (the nearest named GNOME accent: `yellow`, `purple`, `blue`, ...), `papirus-folders = "grey"` (grey in every theme; folders are never the focus colour), `default` (true only for Dusk).
- `[dark]`: `night basalt stone line marble parchment ash sol sol-bright pompeii laurel lapis verdigris tyrian`.
- `[light]`: `dawn dawn-surface dawn-raised dawn-line ink ink-2 ink-muted bronze pompeii-dark laurel-dark lapis-dark`. `bronze` is the light-mode focus colour, whatever its hue.
- `[terminal]`: `background foreground selection-background selection-foreground cursor cursor-text url color0` to `color15`.

**Templates.** Placeholders are `{{token}}` (`#RRGGBB`), `{{token|hex}}` (`RRGGBB`, for Hyprland's `rgb()`), `{{token|rgba:0.82}}` (`rgba(r,g,b,0.82)`), and `{{meta.name}}`. Tokens are looked up in `[dark]`, then `[light]`, then `[terminal]`. An unknown token is an error and nothing is written.

**Static configs include the generated file once**, so they never change when the theme does:

| App | Line in its static config |
|---|---|
| Hyprland | `invictus/colors.lua` loads `~/.config/invictus/current/hyprland-colors.lua` with `require` and exposes `c.sol`, `c.stone`... (falls back to its built-in Dusk values for any token the file does not supply) |
| waybar | `@import url("../invictus/current/waybar-colors.css");` at the top of `style.css` |
| rofi | `@import "~/.config/invictus/current/rofi-colors.rasi"` in the launcher and picker themes |
| kitty | `include ~/.config/invictus/current/kitty-colors.conf` |
| swaync | `@import url("../invictus/current/swaync-colors.css");` |
| hyprlock | `source = ~/.config/invictus/current/hyprlock-colors.conf` (defines `$sol`, `$marble`... and the wallpaper path) |
| GTK 3 / 4 | `~/.config/gtk-3.0/gtk.css` and `gtk-4.0/gtk.css` each `@import` `gtk-colors.css` (the `@define-color` list under GTK above, from tokens) |
| Qt | qt5ct/qt6ct colour scheme path points at `~/.config/invictus/current/qt-colors.conf` |
| btop | `color_theme = "~/.config/invictus/current/btop.theme"` |
| Moneta panel, Desk | load `~/.config/invictus/current/desk-tokens.css` (CSS custom properties with the token names) |

### `invictus-theme`: generate and reload

One command, `scripts/invictus-theme` (Python 3 standard library only: `tomllib`, no template engine), installed to `/usr/bin/invictus-theme`.

| Command | Does |
|---|---|
| `invictus-theme pick` | Opens the picker (what the key and the launcher entry run) |
| `invictus-theme set <id>` | Generates and switches |
| `invictus-theme apply` | Re-generates the current theme and reloads; run once at session start before waybar, so a fresh install or an updated template is always in place. No `current` link yet means Dusk |
| `invictus-theme list` | Prints `id name` per theme, current one marked |
| `invictus-theme check [<id>]` | Validates the schema and re-measures every contrast rule above; non-zero exit on any failure. Run in the repo tests and before `set` loads a user theme |

`set <id>` in order:

1. **Load and check.** Read `theme/<id>.toml` (user folder first, then `/usr/share`). Run `check`. On failure: one critical notification, `Theme not changed: <reason>`, and stop. Nothing has been touched.
2. **Generate** every template into a temp folder beside the target (`~/.local/state/invictus/theme/.<id>.tmp/`), plus `swatch.png`, the Radiate and Night wallpapers at each monitor's resolution (`rsvg-convert`, from `librsvg`), and an `id` file. Then rename the temp folder to `<id>/`. A failure here also stops with the notification and nothing switched.
3. **Switch** the link atomically: `ln -sfn <id> current.new && mv -T current.new current` inside `~/.config/invictus/`.
4. **Reload**, in this order so the screen changes in one beat (target: everything within one second, no logout):

| Surface | How it picks up the change |
|---|---|
| Wallpaper | `hyprctl hyprpaper reload <monitor>,<path>` for each monitor, with the 5120 x 1440 export on ultrawide outputs |
| Hyprland borders, groupbar, `misc.background_color` | `hyprctl reload` (re-runs the Lua, which reads the new `hyprland-colors.lua`). If game mode is on, skip this step; leaving game mode already reloads |
| waybar | `pkill -SIGUSR2 -x waybar` (reloads config and style) |
| swaync | `swaync-client --reload-css` |
| kitty (every open window) | `pkill -SIGUSR1 -x kitty` (kitty re-reads `kitty.conf`, including the colours) |
| GTK accent in open apps | `gsettings set org.gnome.desktop.interface accent-color <gnome-accent>`; libadwaita apps that follow the portal update live. GTK 3 apps restyle when the theme name is toggled (`gtk-theme` to `Adwaita-dark` and back to `adw-gtk3-dark`). The full palette in `gtk.css` applies to each app at its next launch |
| Qt apps | Next launch |
| cava | `pkill -SIGUSR1 -x cava` |
| btop | Next launch |
| rofi, hyprlock | Read at each launch; nothing to do |
| Moneta panel, Desk | Watch `~/.config/invictus/current` with inotify and reload `desk-tokens.css` |
| Anything else | Executables in `~/.config/invictus/theme-hooks.d/` run with the theme id as the only argument (for example a Zed or browser theme). A hook failing is logged and does not undo the switch |

5. **Remember.** The `current` link is the setting; nothing else stores it. No success notification: the desktop changing is the confirmation.

Old generated folders stay (a few KB each), so switching back is as fast as switching forward; `apply` regenerates only the current one.

**Adding a theme** is one TOML file in `~/.config/invictus/themes/`. It appears in the picker on the next open, if `check` passes.


## Motion

Alex asked for some wow (2026-09-30) without losing the two rules: snappy for gaming, calm for ADHD. The answer is to split motion by how often it happens. **Everyday** changes (focus, borders, dimming, moving and resizing windows, menus) happen hundreds of times a day, so they stay as quick as before. **Moments** (a window opening, a workspace switch, a notification, the launcher) get a little shape. **Ceremonies** (log in, unlock, theme switch) happen a few times a day, so they are allowed to show off. See `docs/mockups/motion.html` (buttons switch the level and replay each moment) and the recording `docs/mockups/motion.webm`.

### Levels

One setting, `motion`, three values. **Showcase** is the default. No key: the launcher entry **Change motion** opens a three-row picker styled like the theme picker (current level preselected, Enter applies). Game mode forces Off and puts the old level back when it ends.

| | Everyday | Moments | Ceremonies | Overshoot, glint, rays, wipe |
|---|---|---|---|---|
| **Showcase** (default) | ≤ 150 ms | ≤ 300 ms | ≤ 600 ms | Yes |
| **Calm** | ≤ 120 ms | ≤ 180 ms, fades and small scales only, no slides | ≤ 300 ms, fades only | No |
| **Off** (game mode, or chosen) | none | none | none (a cut) | No |

Rules at every level:

1. **Nothing waits for an animation.** Keys and clicks go to the new target on the first frame. Hyprland already retargets a running animation when you act again; our own pieces (the veil, the SDDM rays) must do the same and never block input.
2. **Nothing loops.** Every animation runs once and stops. No `loop` style on `borderangle`, no pulsing icons, no breathing borders. The only thing that moves continuously is the push-to-talk level bar, and only while the button is held.
3. **Exits are faster than entries** (about 60%).
4. **Motion goes where your eyes already are.** Flourishes play on the thing you just acted on (the window you opened, the picker you used). Things in the corner of the eye (notifications) get the smallest motion that still says "new".
5. **Themes change the shape of an accent, never the timing or the amount of motion.** Timings are the same in all four themes.
6. Calm and Off also set `org.gnome.desktop.interface enable-animations` to false (Showcase sets it true), so GTK apps follow.
7. Kitty follows the level too (Alex, 2026-09-30, keeping his original cursor animation): Showcase is his exact blink and trail values, Calm is the shorter set, Off has no trail and no blink (Surfaces, Kitty).

**How the level is applied** (built 2026-09-30): the setting is one word in `~/.config/invictus/motion` (`showcase`, `calm` or `off`; missing or unreadable means Showcase). Hyprland reads it when the config loads (`invictus/state.lua`, `invictus/motion.lua`), so a change takes effect on `hyprctl reload`; game mode (the marker file `$XDG_RUNTIME_DIR/invictus/game-mode`) forces Off without touching the file. The per-app files are shipped as `config/<app>/motion/{showcase,calm,off}`: kitty includes the chosen one through `~/.config/invictus/motion.d/kitty.conf`; waybar and swaync have their Showcase values in `motion.css` and the switcher copies `motion/calm.css` or `motion/off.css` over `~/.config/<app>/motion.css`; swaync's `transition-time` (220 / 150 / 0) is in `config.json`. The switcher itself, `invictus-motion`, is not written yet.

### Curves

Hyprland `speed` is in tenths of a second (1 = 100 ms). Names are ours.

| Curve | Points | Used for |
|---|---|---|
| `snap` | 0.2, 0.9, 0.1, 1.0 | Everyday moves, the bar sliding in |
| `glide` | 0.25, 1.0, 0.5, 1.0 | Fades, workspace slide, dim, border colour |
| `rise` | 0.3, 1.5, 0.6, 1.0 | Window open: about 6% overshoot of the pop-in, so a big window settles by about 1% of its size (15 px on a 1440 px window) |
| `unveil` | 0.16, 1.0, 0.3, 1.0 | Ceremonies and the glint: fast start, long soft landing |
| `sink` | 0.4, 0.0, 1.0, 1.0 | Exits |
| `linear` | 0, 0, 1, 1 | Fade-outs |

```lua
hl.curve("snap",   { type = "bezier", points = { { 0.2,  0.9 }, { 0.1, 1 } } })
hl.curve("glide",  { type = "bezier", points = { { 0.25, 1 },   { 0.5, 1 } } })
hl.curve("rise",   { type = "bezier", points = { { 0.3,  1.5 }, { 0.6, 1 } } })
hl.curve("unveil", { type = "bezier", points = { { 0.16, 1 },   { 0.3, 1 } } })
hl.curve("sink",   { type = "bezier", points = { { 0.4,  0 },   { 1,   1 } } })
hl.curve("linear", { type = "bezier", points = { { 0,    0 },   { 1,   1 } } })
```

Springs (`type = "spring"`) exist in 0.56 but we do not use them: how `speed` bounds a spring's duration is not documented, and the budget needs a hard ceiling.

### Hyprland (0.56.2, Lua)

Leaf and style names checked against the v0.56.2 source (`src/config/shared/animation/AnimationTree.cpp` for leaves, `CHyprAnimationManager::styleValidInConfigVar` in `src/animation/AnimationManager.cpp` for styles, `hlAnimation` in `src/config/lua/bindings/LuaBindingsConfigRules.cpp` for the table fields). The curve field is `bezier` (or `spring`); the wiki's "Extras" examples write `curve =`, which 0.56.2 rejects with "bezier or spring is required".

| Leaf | Showcase | Calm | Tier |
|---|---|---|---|
| `global` | 1.5 `snap` | 1.2 `snap` | fallback |
| `windowsIn` | 2.6 `rise`, `popin 88%` | 1.8 `glide`, `popin 96%` | moment |
| `windowsOut` | 1.4 `sink`, `popin 92%` | 1.0 `sink`, `popin 96%` | moment |
| `windowsMove` | 1.5 `snap` | 1.2 `snap` | everyday |
| `fadeIn` | 1.6 `glide` | 1.2 `glide` | moment |
| `fadeOut` | 1.2 `linear` | 1.0 `linear` | moment |
| `fadeSwitch` | 1.2 `glide` | 1.2 `glide` | everyday |
| `fadeShadow` | 1.5 `glide` | 1.2 `glide` | everyday |
| `fadeDim` | 1.5 `glide` | 1.2 `glide` | everyday |
| `border` | 1.2 `glide` | 1.2 `glide` | everyday |
| `borderangle` | 3 `unveil`, style `once` (the glint) | off | moment |
| `layersIn` | 1.8 `snap`, `popin 94%` | 1.2 `glide`, `fade` | moment |
| `layersOut` | 1.2 `sink`, `fade` | 1.0 `linear`, `fade` | moment |
| `fadeLayersIn` | 1.6 `glide` | 1.2 `glide` | moment |
| `fadeLayersOut` | 1.0 `linear` | 1.0 `linear` | moment |
| `fadePopupsIn` | 1.0 `glide` | 1.0 `glide` | everyday |
| `fadePopupsOut` | 0.8 `linear` | 0.8 `linear` | everyday |
| `workspaces` | 2.8 `glide`, `slidefade 12%` | 1.8 `glide`, `fade` | moment |
| `specialWorkspace` | 2.6 `glide`, `slidefadevert 16%` | 1.8 `glide`, `fade` | moment (the Desk) |
| `zoomFactor` | 2.5 `glide` | 1.5 `glide` | everyday |
| `monitorAdded` | 6 `unveil` | off | ceremony |
| `fadeDpms` | 3 `glide` | 2 `glide` | ceremony (screen wakes) |

Off: `hl.config({ animations = { enabled = false } })`. That covers every leaf, including `borderangle`.

Example, Showcase window open:

```lua
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 2.6, bezier = "rise",   style = "popin 88%" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 3,   bezier = "unveil", style = "once" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 2.8, bezier = "glide",  style = "slidefade 12%" })
```

What each moment looks like:

- **Window open.** The window pops from 88% with a small overshoot and fades in over 160 ms. At the same time a brighter band (`sol-bright`) sweeps once around its gold border: the **glint**, our "sun's rays" (Hyprland rotates the border gradient 360° once on map, `borderangle` style `once`). Showcase sets `general.col.active_border` to the three-stop gradient `sol sol-bright sol` at 45°, so at rest two corners are a shade brighter and the border still reads as one gold. Calm and Off go back to solid `sol`.
- **Focus change** stays everyday: border colour 120 ms, dim 150 ms. The glint also plays on the newly focused window (Hyprland restarts `borderangle once` on focus as well as on open; they cannot be split). It is 300 ms, once, on the window you just chose, and Calm turns it off.
- **Workspace switch.** Windows slide 12% of the screen and fade, instead of a full-width slide: direction is clear, the screen does not sweep past your eyes.
- **Session start** (after the SDDM rays, below). `monitorAdded` is the only built-in that zooms the whole screen: Hyprland plays it on every monitor when it is added, which includes session start, zooming from 2x to 1x while the wallpaper fades in (`Monitor.cpp`, `Renderer.cpp`). 600 ms with `unveil` covers most of the distance in the first 150 ms. It also plays when a monitor is hot-plugged; Calm turns it off.

Layer rules (Hyprland layer rule effect `animation` sets the style per namespace; the value format is assumed to be the same as `style`, not tested):

| Namespace | Rule | Why |
|---|---|---|
| `waybar` | `animation = "slide top"` | The bar drops in from the edge at session start |
| `rofi` (launcher and pickers) | inherits `layersIn` `popin 94%` | Opens where you look |
| `moneta-panel` | `animation = "slide right"` | Matches where it lives; 180 ms as in the panel spec |
| `swaync-notification-window`, `swaync-control-center` | `no_anim = true` | swaync animates its own cards; a layer fade on top would double it |
| `invictus-veil` | `no_anim = true` | The veil animates itself (theme switch, below) |

### Ceremonies

**Log in (SDDM, QML; always Dusk).** On a correct password the field border turns `laurel` (100 ms), then the mark's nine rays light up one by one, left to right, each drawn outward from the disc in `sol-bright` over 220 ms with a 35 ms stagger (500 ms in all) while the disc brightens to `sol-bright`. Then the screen fades to `night` (250 ms) and Hyprland starts: `monitorAdded` zoom, then the bar drops in. The same gesture as the Plymouth splash, where the rays light up as boot progresses, so boot and login rhyme. Calm: laurel, then a 200 ms fade, no rays. Off: laurel, cut. Wrong password: the field turns `pompeii`; no shake (a shake is motion that reads as scolding).

**Unlock (hyprlock 0.9.6).** On a correct password the field turns `laurel` (`check_color`, leaf `inputFieldColors`), then `fadeOut`: every widget fades while the blurred wallpaper cross-fades into a live capture of your desktop, so the lock dissolves into exactly what you left. This is hyprlock's own behaviour: `CBackground::draw` mixes its texture with a screencopy during fade-in and fade-out, and it takes that screencopy only when `fadeIn` or `fadeOut` is enabled. No new code. hyprlock still uses hyprlang (`~/.config/hypr/hyprlock.conf`), and it **stores speed as a whole number** (`int64_t speed` in `ConfigManager::handleAnimation`), so 4.5 becomes 4.

```
bezier = unveil, 0.16, 1, 0.3, 1
bezier = glide, 0.25, 1, 0.5, 1
animation = fadeIn, 1, 3, glide            # lock appears: 300 ms (Calm 2)
animation = fadeOut, 1, 5, unveil          # unlock reveal: 500 ms (Calm 3)
animation = inputFieldColors, 1, 1, linear # sol to laurel or pompeii: 100 ms
animation = inputFieldWidth, 0             # the field never changes size
animation = inputFieldDots, 1, 1, linear
```

Off: `animation = global, 0`. hyprlock reads its config at launch, so the level applies from the next lock.

**Theme switch.** `invictus-theme set` gains one step before the reload and one after:

1. Before the reload: `grim` captures every output, and `invictus-veil` shows each capture full-screen as a layer surface (namespace `invictus-veil`, layer overlay, no input, no keyboard focus). It looks identical to the screen, so its appearance is invisible.
2. The reload runs underneath as specified in Themes.
3. After the reload (or after 1.5 s at most, so a slow app never holds the screen), the veil animates itself away and exits. **Showcase: sunrise wipe.** A circle opens from the centre of the picker and grows to cover the screen in 520 ms (`unveil`), with the old theme outside it and the new one inside, and a 2 px ring in the new theme's `sol-bright` riding the edge, fading to 60% as it goes. **Calm:** a 250 ms cross-fade. **Off:** the veil closes at once (a cut, as before).

`invictus-veil` is new and small: Python with `python-gobject` and `gtk4-layer-shell` (both in extra), about 80 lines: a `Gtk.Picture` per monitor, and the wipe as a clip in `do_snapshot`. It must exit on any error, on Esc, and after 2 s whatever happens, so it can never leave a frozen screen over the desktop. If `grim` is missing or fails, skip the veil and switch with a cut.

### Bar, notifications, launcher, panel

**Waybar** (GTK 3 CSS supports `transition` and `@keyframes`). A generated `motion.css` beside the colour file sets two durations as the level requires:

```css
#workspaces button { transition: box-shadow 150ms cubic-bezier(.25,1,.5,1), color 150ms; }
#workspaces button.active { box-shadow: inset 0 -2px @sol; }
#custom-swaync .dot { transition: opacity 150ms; }
```

Calm: 120 ms. Off: `transition: none`. Nothing else in the bar moves. The system alert appears without motion (it is already red).

**swaync 0.12.6** (GTK 4). Cards slide in from the right; the slide is swaync's own, and its length is `"transition-time"` in `config.json` (Showcase 220, Calm 150, Off 0). On top of the slide, a one-shot CSS accent per theme, 300 ms, on `.notification-row .notification` (GTK 4 CSS supports `@keyframes`). The accent is the only part that differs between themes:

| Theme | Accent | How (cheap: one keyframe, opacity and box-shadow only) |
|---|---|---|
| Dusk | **Sunrise bar**: the 3 px left bar rises from the bottom, and a warm light washes in from the left edge and fades | `box-shadow: inset 3px 0 @sol, inset 24px 0 32px -24px alpha(@sol,.5)` to `inset 3px 0 @sol` |
| Porphyry | **Dye**: the card border starts Tyrian and bleeds back to `line` | `border-color` from `@sol` to `@line` |
| Aegean | **Ripple**: one ring spreads from the app icon and fades | `box-shadow: 0 0 0 0 alpha(@sol,.6)` to `0 0 0 14px alpha(@sol,0)` on `.notification-default-action .image` |
| Alexandria | **Beam**: one pass of lamp light across the card, left to right | `background-position` of a faint `@sol-bright` linear gradient from -100% to 200% |

Calm and Off: no accent (`animation: none`). Critical notifications get no accent in any theme: the `pompeii` bar is already there and they must not look festive. The mockup shows Dusk's bar and Aegean's ripple. Whether GTK 4 animates `background-position` (Alexandria) is not tested; if it does not, Alexandria uses Dusk's sunrise bar.

**Rofi 2.0** (launcher and the theme and motion pickers) has no animation of its own. It opens with the Hyprland `layersIn` pop (94%, 180 ms) and closes with the 120 ms fade. The selection moves instantly, which is right for a list you drive with arrow keys.

**Moneta panel and Desk.** Panel: `slide right`, 180 ms in, 120 ms out. Desk: the special workspace `slidefadevert 16%`, 260 ms. New lines in the panel conversation fade in over 120 ms (Calm: none). The "Working on it" status never animates dots or spinners; it changes the word only.

### Timing budget, checked

| Moment | Showcase | Calm | Budget |
|---|---|---|---|
| Focus change | 120 ms (+300 ms glint on the focused window) | 120 ms | Everyday ≤ 150 ms; the glint is the one exception, on the window you just chose, and off in Calm |
| Window move, resize, menus | 150 ms / 100 ms | 120 ms / 100 ms | Everyday |
| Window open / close | 260 / 140 ms | 180 / 100 ms | Moment ≤ 300 |
| Workspace | 280 ms | 180 ms | Moment |
| Launcher, pickers | 180 / 120 ms | 120 / 100 ms | Moment |
| Notification | 220 ms slide + 300 ms accent | 150 ms | Moment |
| Unlock | 500 ms | 300 ms | Ceremony ≤ 600 |
| Log in | 500 ms rays + 250 ms fade, then 600 ms zoom | 200 ms fade | Ceremony; the two halves run in different processes (SDDM, then Hyprland) |
| Theme switch | 520 ms wipe | 250 ms | Ceremony |

Cost: none of this adds a daemon that stays running. The glint is part of the border shader Hyprland runs anyway. The only new program is `invictus-veil`, which lives for under two seconds per theme switch.

## Cut, and why

| Cut | Why |
|---|---|
| GPU, CPU and memory pills refreshing every 2 s | Moving numbers pull the eye all day. Replaced by one alert that appears only when something is hot |
| Pill-per-module bar | Nine shapes to scan; one continuous bar is one shape |
| Gradient active border, see-through windows | Gradients shimmer; transparency behind text costs legibility. Dimming unfocused windows does the same job better |
| Rofi mode switcher | Unused; `drun` is the job |
| Forever-blinking cursor | Constant motion in the corner of the eye |
| Control-centre sliders and player | The bar already has volume; the rest was rarely used |
| Lock screen avatar, battery, media, weather | Nothing to do there but type a password |
| Yellow Papirus folders | Gold is reserved for "you are here" |
| Nordic Darker GTK | Cold blue clashes, and it is from the AUR |
| Anime and Berserk wallpapers in the default set | Licensing, and it is a distro for friends and family now |
| Roman numerals on workspaces | They do not match the keys you press |

## Reused / new, and why

Reused: IBM Plex Mono and the kitty font settings, the block cursor and blink curve, the master layout and its values, `resize_on_border false`, the persistent workspace split per monitor, the updates module and its script, pavucontrol and nm-connection-editor actions, Papirus, nwg-look, the SDDM compositor setup (`d43490a`), the cursor fix (`0a579b7`), and the Desk idea from Alex's Liberalitas Desk (sections Now, Waiting on you, Threads). New: the palette, the mark, the Plymouth, SDDM and btop themes, the system-alert module (replaces three stats modules), the Now module and Moneta panel (nothing like them exists), and the wallpapers (the old ones cannot ship). No shared theming tool exists yet; the engineer should generate every app's colour file from one tokens file per theme (`theme/<id>.toml`, see Themes) so a colour change is made once.

Themes (2026-09-30). Reused: the Dusk token names and every surface spec above (the themes change values only), the launcher's rofi layout and selection style for the picker, the keybinding description convention in `binds.lua`, the existing `hyprpaper` daemon, and each app's own reload signal. New: `theme/<id>.toml` files, the templates, `invictus-theme` and the picker. Nothing in the repo generated app colours from one source before (`scripts/` has install, deploy and update scripts only; `config/` holds hand-written colours per app), so the generator is new; it replaces those hand-written colours rather than sitting beside them.

Motion and wallpapers (2026-09-30). Reused: the existing Hyprland curves `snap`, `glide`, `linear` and the old snappy timings (now the everyday tier), Hyprland's own `borderangle once`, `monitorAdded` and `popin`/`slidefade` styles, hyprlock's built-in screencopy cross-fade for the unlock, swaync's own slide (`transition-time`), rofi's existing layer pop, the mark's ray geometry for the login and the Sol rays, the wallpaper compositions already drawn in `themes.html`, and the theme picker's layout for the motion picker. New: the three levels and the `motion` setting, curves `rise`, `unveil` and `sink`, the per-theme notification accents (four CSS keyframes), `invictus-veil` for the theme switch (nothing on the system can show a still image as an overlay layer and animate it away; `hyprpaper` only changes the wallpaper), the SDDM ray sequence (the SDDM theme is new anyway), and the four wallpaper files.
