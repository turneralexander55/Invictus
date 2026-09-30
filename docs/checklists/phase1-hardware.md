# Phase 1 hardware checks

For Alex, on his own PC, after `docs/checklists/adopt.md` step 7 (you have
logged out and back in on the new desktop). About 15 minutes. These are the
things only your monitors, GPU and keyboard can show. Tick Pass or Fail on
each line; for any Fail, note what you saw instead. If the desktop does not
come up at all, press Ctrl+Alt+F3, log in and run
`~/src/invictus/scripts/dev/adopt.sh --undo --apply`.

`Super` is the Windows key.

## Screen and layout (3 minutes)

| # | Do this | You should see | Pass | Fail |
|---|---|---|---|---|
| 1 | Look at all three monitors after login. | The Sol (sun) wallpaper on every monitor, the bar on your main monitor only, no error banner at the top of any screen. | [ ] | [ ] |
| 2 | In a terminal (Super+Return): `hyprctl monitors`. | Each monitor with the resolution and refresh rate you had before, at the same position. Compare with the pre-adopt layout in `~/.local/state/invictus/adopt/latest/config/hypr/config/monitors.conf`. | [ ] | [ ] |
| 3 | Press Super+1, Super+4, Super+7 in turn. | Each one goes to a different monitor, and the bar shows workspaces 1-3, 4-6 and 7-9 on their monitors as before. If they all land on one monitor, your old workspace-to-monitor lines were not carried over: note it. | [ ] | [ ] |
| 4 | Move the mouse across all three monitors. | The cursor crosses every edge in the order you expect; no black screen or flicker on any monitor. | [ ] | [ ] |

## Keys (4 minutes)

| # | Do this | You should see | Pass | Fail |
|---|---|---|---|---|
| 5 | Super+/ | A key list opens. Escape closes it. | [ ] | [ ] |
| 6 | Super+Shift+T, pick another theme, Enter. | The bar, kitty and the borders change colour without logging out. Do it once more to switch back. | [ ] | [ ] |
| 7 | Super+minus | Your tmux dashboard opens in kitty (this is your own bind, now in `~/.config/hypr/user.lua`). | [ ] | [ ] |
| 8 | Super+Delete, then choose No. Then Super+Alt+Ctrl+Escape, then choose No. Do NOT choose Yes. | Each one asks first ("Log out?", "Power off?"); No or Escape leaves everything running. | [ ] | [ ] |
| 9 | Print, then select an area; Shift+Print, then click a window; Ctrl+Print. | Three screenshots saved (default folder `~/Pictures`) and a notification each time. | [ ] | [ ] |
| 10 | Play a sound. Press volume up, down, mute and the media keys. | The volume changes with the on-screen change, mute works, play/pause and next control the player. | [ ] | [ ] |
| 11 | Super+L, then unlock. | The lock screen appears on all monitors and your password unlocks it. | [ ] | [ ] |

## Screen sharing (3 minutes)

| # | Do this | You should see | Pass | Fail |
|---|---|---|---|---|
| 12 | In Discord (Super+D) start a call or test share and share a window. | Discord lists your windows, and the other side (or the preview) shows the window's content, not black. | [ ] | [ ] |
| 13 | In a browser call (for example a Google Meet test) share your screen. | The desktop-portal picker opens, you pick a monitor, and the preview shows it. | [ ] | [ ] |

## Games (3 minutes)

| # | Do this | You should see | Pass | Fail |
|---|---|---|---|---|
| 14 | Super+G, start a game you know well in fullscreen. | Steam opens and the game runs at its usual frame rate on your AMD GPU, no black screen, sound works. | [ ] | [ ] |
| 15 | While the game runs, in another terminal or over SSH: `hyprctl monitors \| grep -i vrr`. | The monitor the game is on shows VRR active. If your monitor has FreeSync off in its own menu, note that instead of failing. | [ ] | [ ] |
| 16 | Start a game with gamescope or MangoHud as you normally do (for example the launch option `mangohud %command%`). | The overlay shows, or gamescope opens, as it did before. | [ ] | [ ] |
| 17 | Switch to another workspace with Super+number, then back to the game. | The game returns to fullscreen without a stuck cursor or a black monitor. | [ ] | [ ] |

## Updates and health (2 minutes)

| # | Do this | You should see | Pass | Fail |
|---|---|---|---|---|
| 18 | Click the updates number on the bar. | A terminal runs `invictus-update`, asks for your sudo password, and ends with `==> Update complete.` | [ ] | [ ] |
| 19 | In a terminal: `invictus-doctor`. | No FAIL lines. Send the whole output to the team either way. | [ ] | [ ] |

## Good to know

Packages you installed yourself from the AUR (Zen, Claude Code, Proton GE and
so on) are no longer updated by the bar button. Run `invictus-update --aur`
now and then until the team publishes them.

## When you are done

Send the team: the ticked table, the output of `invictus-doctor`, and one line
on anything that felt slower, uglier or different from before.
