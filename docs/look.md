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
| `desk.html` | The Desk home dashboard |
| `brand-sheet.html` | Mark, palette and type on one page |

Sample content in the mockups (thread names, commit messages, and the Lua in the editor, which is not the real Hyprland API) is made up.

## Concept

**Dusk in the stoa.** Warm dark stone, marble-white text, and one gold: the sun. Gold means one thing on this desktop: *you are here*. It marks the focused window, the active workspace, the selected launcher row and the field you are typing in. On a screen with a single job (the ISO's Install card) it also marks the one next step. Nothing else is gold, so the eye always finds its place in one glance.

Everything else is quiet: no live graphs in the bar, no gradients that move, no transparency behind text you read. Roman touches are in the names, the mark, the display type on the login and lock screens, and one line of Marcus Aurelius on the lock screen. They stay out of the working surfaces.

What changed from hyprdots: the old look was black pills on a busy bar, a white gradient border, see-through windows and anime wallpapers. Invictus keeps what worked (IBM Plex Mono, master layout, the block cursor, Papirus) and replaces the rest.

## Palette

Tokens are the contract. Every surface below uses these names; engineers should never type a hex that is not in this table.

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

**The radiate sun.** Sol Invictus on Roman coins wears a crown of rays. The mark is a solid disc with seven short rays over it and a horizon line under it: a sun that has already risen. Seven rays, for the seven days. Files: `docs/brand/invictus-mark.svg` (64 px grid, 3.5 px strokes, round caps) and `docs/brand/invictus-mark-small.svg` (16 px cut with three rays, for the bar and favicons).

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
| `general.col.active_border` | `rgb(E0A64B)` (solid `sol`, no gradient) | The single "you are here" signal |
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

**Animations.** Snappy: nothing over 250 ms, exits faster than entries. Hyprland speed is in units of 100 ms.

| Bezier | x0, y0, x1, y1 |
|---|---|
| `snap` | 0.2, 0.9, 0.1, 1.0 |
| `glide` | 0.25, 1.0, 0.5, 1.0 |
| `linear` | 0, 0, 1, 1 |

| Animation | On | Speed | Curve | Style |
|---|---|---|---|---|
| `global` | 1 | 2 | `snap` | |
| `windowsIn` | 1 | 2.2 | `snap` | `popin 92%` |
| `windowsOut` | 1 | 1.4 | `linear` | `popin 92%` |
| `windowsMove` | 1 | 2.2 | `snap` | `slide` |
| `border` | 1 | 2.5 | `glide` | |
| `borderangle` | 0 | | | (no rotating gradients) |
| `fadeIn` | 1 | 1.8 | `glide` | |
| `fadeOut` | 1 | 1.2 | `linear` | |
| `fadeDim` | 1 | 2 | `glide` | |
| `layersIn` | 1 | 1.8 | `snap` | `fade` |
| `layersOut` | 1 | 1.2 | `linear` | `fade` |
| `workspaces` | 1 | 2.2 | `snap` | `slide` |
| `specialWorkspace` | 1 | 2.2 | `snap` | `slidevert` |
| `zoomFactor` | 1 | 3 | `snap` | |

**Game mode.** A keybind (`Super + G`) and an automatic rule when a Steam/gamescope window goes fullscreen: turn off animations, blur, shadows and dim, set gaps to 0 and border to 0, and turn DND on in swaync. The same key restores. The bar hides on fullscreen as normal. For frame stats in game use MangoHud with its own config coloured `marble` text on `night` at 70%, top-left, not the bar.

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
- **Now** (custom module, depends on the assistant's architecture): the one thing Moneta says you are doing, for example `Now · Port waybar to Lua`, `parchment`, max 40 characters. Click opens the Moneta panel on the threads list. Hidden when nothing is set. This is the ADHD anchor: one line, always in the same place.
- **Updates**: `󰮯 12` in `parchment`; hidden at 0. Click opens the update terminal as now.
- **System alert** (replaces the GPU, CPU and memory pills): hidden while CPU < 90%, GPU temp < 90 °C, RAM < 90% and root disk < 90%. When one is over, shows that one reading in `pompeii`, e.g. `󰢮 94 °C`. Tooltip always lists all four. Poll every 5 s, not 2.
- **Volume** (`pulseaudio`): icon + number, muted shows the muted icon in `ash`. Scroll 5%. Click opens `pavucontrol`.
- **Network**: icon only; tooltip has the details. Disconnected: icon in `pompeii`.
- **Notifications** (`custom/swaync`, from `swaync-client -swb`): bell icon, `sol` dot when there are unread ones, crossed bell in `ash` when DND is on. Click toggles the control centre.
- **Moneta button**: the Moneta coin glyph (a circle with an `M`, drawn in the icon set as `moneta-symbolic`) in `parchment`. States: idle `parchment`; has something for you: small `sol` dot; listening (push-to-talk held): glyph in `lapis` with a 1 px `lapis` ring. Click toggles the Moneta panel.

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
- Blink: `cursor_blink_interval 0.5 ease-in-out` (unchanged), `cursor_stop_blinking_after 15` (was 0, blink forever; a cursor that never stops moving pulls the eye).
- Trail: keep, shorter: `cursor_trail 3`, `cursor_trail_decay 0.08 0.3`.
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

The default set is made by us from the palette, as SVG sources plus 3840 x 2160 and 5120 x 1440 PNG exports, licensed CC BY 4.0 (Alex as author):

1. **Sol** (default): a low sun just above a horizon, `sol` fading through `#5A3F1E` into `night`; the sun sits in the lower third so the bar and the centre stay dark. Mockups use this one.
2. **Stoa**: a row of column silhouettes in `basalt` against a `night` to `stone` sky; very low contrast.
3. **Radiate**: the mark's seven rays at huge scale, `line` on `night`, off to one side.
4. **Night**: flat `night` with 1.5% noise, for anyone who wants nothing.

Optional extras, public domain only: photographs from the Met Open Access and Rijksmuseum collections (both CC0), for example Roman coins of Aurelian showing Sol, or Roman architecture. Each file gets its source URL and licence in `assets/wallpapers/SOURCES.md`. Wikimedia Commons only for files marked public domain or CC0.

### Boot splash (Plymouth) and ISO

- Plymouth `script` theme `invictus`: `night` background, the mark 96 px centred in `line` colour. As boot progresses the seven rays light up one by one in `sol`, then the disc. No spinner, no text. On the LUKS prompt: the same 300 x 48 field as hyprlock under the mark, label `Disk password` in `ash`.
- Boot loader (limine on the ISO and installed system): background `14120F`, text `ECE6DA`, selected entry `E0A64B`, branding `Invictus`, no wallpaper, 3 s timeout.
- ISO desktop: the Sol wallpaper, the bar, and one centred card (`basalt`, radius 16, 440 px): the mark, `INVICTUS` wordmark, one line `Try it, or install it on this computer.`, and a single gold button `Install Invictus` (`night` text on `sol`, 48 px tall, radius 10). A text link under it, `Open a terminal`, in `ash`. Nothing else on screen.
- Installer (Calamares or our own, per Minerva's architecture): sidebar `night`, sidebar text `parchment`, current step `sol` text with a 3 px `sol` left bar, content on `basalt`, primary button `sol`. Product name `Invictus`, the mark as the product logo, the Sol wallpaper as the welcome image.

### The Moneta panel

A layer-shell panel (namespace `moneta-panel`) that slides in from the right edge. It is a helper beside your work, not a window in the tiling.

- 440 px wide, full height under the bar, 8 px gap to the right edge. `basalt` at 96% with blur, 1 px `line` border, radius 12.
- Slide in `layersIn` (180 ms); `Super + A` or the bar button toggles; `Esc` closes. Opening does not steal focus from the game or the window under it until you click or start typing into it.
- Header (48 px): Moneta glyph, `Moneta` in Plex Sans 15 px weight 600, status word in `ash` (`Ready`, `Listening`, `Thinking`, `Working on it`). Right: a collapse button.
- **Now** strip under the header: the current thread in one line, `parchment`, with a `sol` 3 px left bar. `Threads (4)` collapsed row under it; opening it shows the open threads, one line each, click to switch.
- Conversation: Moneta's messages on no background, `marble` text, 14 px, line height 1.5. Alex's messages right-aligned on `stone`, radius 12. Code blocks in Plex Mono 13 px on `night`. Tool actions she takes appear as one collapsed line (`Ran 2 commands`) with the details behind it.
- Input: 48 px min, `stone`, radius 12, placeholder `Ask Moneta` in `ash`, `sol` border on focus. A mic glyph at the right shows push-to-talk: `ash` idle, `lapis` with a level bar while the pen button is held, `pompeii` if the mic fails.
- Anything that needs approval (running a command with system access) shows as a card with a 1 px `sol` border (it is where your attention is needed), the exact command in mono, and two buttons of equal weight, `Allow once` and `Deny`, both `marble` on `stone`. Neither is styled as the default, so a habit click does not approve. While the card waits, the input loses its focus border. Never pre-approved, never auto-dismissed.

### The Desk (home dashboard)

See `docs/mockups/desk.html`. One job: **what matters now.** It opens on login on the primary monitor and on `Super + D` (a special workspace, so it slides over whatever is there and slides away). Uses the same tokens as everything else and follows light/dark (Dawn) as apps do.

Layout at 1920 x 1080, 1200 px centred column, 32 px gutters:

1. **Greeting line**: `Good evening, Alex` in Cormorant Garamond 36 px `marble`, date under it in Plex Sans 14 px `ash`.
2. **Now** card, full width: the one current focus, 22 px `marble`, with who is on it and since when in `ash`, a `sol` 3 px left bar, and two text buttons: `Done` and `Switch`. If nothing is set: `Nothing set. What are you working on?` with an input.
3. Two columns under it:
   - **Open threads** (left, 60%): up to 5, one line each with how long ago it was touched, in `ash`. `Show all (n)` link if more. Click opens it in the Moneta panel.
   - **Waiting on you** (right, 40%): items the team needs from Alex, from the team repo, up to 4, each with one action button.
4. **System** row, small, bottom: updates available, last snapshot time (`laurel` if under 24 h, `pompeii` if older than 7 days), disk free on `/`, and the team repo sync state. Plain text, one line.
5. **Ask Moneta** input, bottom, full width.
6. A line from the Stoics, 14 px Cormorant Garamond italic `ash`, bottom right. Same rotating list as the lock screen.

Cut from the Desk: weather, news, calendar grid, app shortcuts (that is the launcher's job), system graphs (that is btop's job). If Alex wants a calendar later, it replaces "Waiting on you" only when there is an event in the next 2 hours.

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

Reused: IBM Plex Mono and the kitty font settings, the block cursor and blink curve, the master layout and its values, `resize_on_border false`, the persistent workspace split per monitor, the updates module and its script, pavucontrol and nm-connection-editor actions, Papirus, nwg-look, the SDDM compositor setup (`d43490a`), the cursor fix (`0a579b7`), and the Desk idea from Alex's Liberalitas Desk (sections Now, Waiting on you, Threads). New: the palette, the mark, the Plymouth, SDDM and btop themes, the system-alert module (replaces three stats modules), the Now module and Moneta panel (nothing like them exists), and the wallpapers (the old ones cannot ship). No shared theming tool exists yet; the engineer should generate every app's colour file from one tokens file (`theme/tokens.toml`) so a colour change is made once.
