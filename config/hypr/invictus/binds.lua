--------------------------------------------------------------------------------
--                                                                            --
--                               KEYBINDINGS                                  --
--                                                                            --
--------------------------------------------------------------------------------
-- All global keyboard and mouse bindings.
--
-- Use this file to configure:
--   • Application launch shortcuts
--   • Window management and layout controls
--   • Workspace navigation and movement
--   • Screenshots, media keys, and hardware controls
--
-- Every bind carries a description "Section: action". `hyprctl binds` shows
-- it, and scripts/show-keybindings.sh (SUPER + / or SUPER + F1) reads it, so
-- keep the "Section: " prefix when adding binds.
--
-- Old flag letters map to options: e = repeating, l = locked, m = mouse.
-- See https://wiki.hypr.land/Configuring/Basics/Binds/
--------------------------------------------------------------------------------

local apps    = require("invictus.variables")
local mainMod = apps.mainMod

local dsp     = hl.dsp

-- bind("SUPER + Q", dispatcher, "Section: what it does", { flags })
local function bind(keys, dispatcher, description, flags)
    local opts = { description = description }
    for k, v in pairs(flags or {}) do
        opts[k] = v
    end
    return hl.bind(keys, dispatcher, opts)
end

local function mod(...)
    return table.concat({ mainMod, ... }, " + ")
end


-- ─────────────────────────────────────────────────────────────────────────────
-- Show Keybindings Reference
-- ─────────────────────────────────────────────────────────────────────────────
local S = "Help: "
bind(mod("slash"), dsp.exec_cmd("$HOME/invictus/scripts/show-keybindings.sh"), S .. "show keybindings")
bind(mod("F1"),    dsp.exec_cmd("$HOME/invictus/scripts/show-keybindings.sh"), S .. "show keybindings")


-- ─────────────────────────────────────────────────────────────────────────────
-- Core Application & Window Controls
-- ─────────────────────────────────────────────────────────────────────────────
S = "Apps & windows: "

-- Switch the tiling layout between master and dwindle. Replaces the old
-- `hyprctl keyword` + jq one-liner (hyprctl keyword is gone with Lua configs).
local function toggleLayout()
    local current = hl.get_config("general.layout")
    hl.config({ general = { layout = (current == "dwindle") and "master" or "dwindle" } })
end

bind(mod("Return"), dsp.exec_cmd(apps.terminal),            S .. "terminal")
bind(mod("Q"),      dsp.window.close(),                     S .. "close window")
bind(mod("DELETE"), dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"),
                                                            S .. "exit Hyprland")
bind(mod("Y"),      dsp.exec_cmd(apps.terminal .. " -e yazi"), S .. "yazi file manager")
bind(mod("F"),      dsp.window.float({ action = "toggle" }), S .. "toggle floating")
bind(mod("SPACE"),  dsp.exec_cmd(apps.menu),                S .. "app launcher")
bind(mod("J"),      dsp.layout("togglesplit"),              S .. "toggle split (dwindle)")
bind(mod("W"),      dsp.exec_cmd(apps.browser),             S .. "browser")
bind(mod("L"),      dsp.exec_cmd("hyprlock"),               S .. "lock screen")
bind("ALT + F",     dsp.window.fullscreen(),                S .. "toggle fullscreen")
bind(mod("T"),      dsp.exec_cmd("zeditor"),                S .. "Zed editor")
bind(mod("E"),      dsp.exec_cmd(apps.fileManager),         S .. "file manager")
bind(mod("D"),      dsp.exec_cmd("discord"),                S .. "Discord")
bind(mod("ALT", "SPACE"), toggleLayout,                     S .. "switch layout master/dwindle")
bind(mod("G"),      dsp.exec_cmd("steam"),                  S .. "Steam")
-- Asks yes/no first (default No, Escape cancels), then runs systemctl poweroff.
bind(mod("ALT", "CTRL", "Escape"), dsp.exec_cmd("$HOME/invictus/scripts/confirm-poweroff.sh"), S .. "power off with confirm")

-- Opens the theme picker (rofi); Enter applies and reloads the desktop, no logout.
-- invictus-theme is installed to /usr/bin, so it is on PATH.
bind(mod("SHIFT", "T"), dsp.exec_cmd("invictus-theme pick"), "Look: change theme")

-- Toggle dashboard terminal (tmux)
bind(mod("minus"),  dsp.exec_cmd("kitty --title dashboard -e ~/.local/bin/dashboard-tmux"), S .. "dashboard (tmux)")


-- ─────────────────────────────────────────────────────────────────────────────
-- Focus Navigation
-- ─────────────────────────────────────────────────────────────────────────────
S = "Focus: "
bind(mod("left"),  dsp.focus({ direction = "left" }),  S .. "left")
bind(mod("right"), dsp.focus({ direction = "right" }), S .. "right")
bind(mod("up"),    dsp.focus({ direction = "up" }),    S .. "up")
bind(mod("down"),  dsp.focus({ direction = "down" }),  S .. "down")


-- ─────────────────────────────────────────────────────────────────────────────
-- Screenshots (hyprshot)
-- ─────────────────────────────────────────────────────────────────────────────
S = "Screenshots: "
bind("Print",         dsp.exec_cmd("hyprshot -m region"),                  S .. "region")
bind("SHIFT + Print", dsp.exec_cmd("hyprshot -m window"),                  S .. "window")
bind("CTRL + Print",  dsp.exec_cmd("hyprshot -m output"),                  S .. "monitor")
bind(mod("P"),        dsp.exec_cmd("hyprshot -m region --clipboard-only"), S .. "region to clipboard")


-- ─────────────────────────────────────────────────────────────────────────────
-- Workspace Switching           mainMod + [0–9]
-- Move Window to Workspace      mainMod + SHIFT + [0–9]
-- ─────────────────────────────────────────────────────────────────────────────
for i = 1, 10 do
    local key = tostring(i % 10) -- workspace 10 is on key 0
    bind(mod(key),          dsp.focus({ workspace = i }),       "Workspaces: go to " .. i)
    bind(mod("SHIFT", key), dsp.window.move({ workspace = i }), "Move window: to workspace " .. i)
end


-- ─────────────────────────────────────────────────────────────────────────────
-- Move Active Window
-- ─────────────────────────────────────────────────────────────────────────────
S = "Move window: "
bind(mod("SHIFT", "left"),  dsp.window.move({ direction = "left" }),  S .. "left")
bind(mod("SHIFT", "right"), dsp.window.move({ direction = "right" }), S .. "right")
bind(mod("SHIFT", "up"),    dsp.window.move({ direction = "up" }),    S .. "up")
bind(mod("SHIFT", "down"),  dsp.window.move({ direction = "down" }),  S .. "down")


-- ─────────────────────────────────────────────────────────────────────────────
-- Special Workspace (Scratchpad)
-- ─────────────────────────────────────────────────────────────────────────────
S = "Scratchpad: "
bind(mod("S"),          dsp.workspace.toggle_special("magic"),             S .. "show/hide")
bind(mod("SHIFT", "S"), dsp.window.move({ workspace = "special:magic" }), S .. "move window there")


-- ─────────────────────────────────────────────────────────────────────────────
-- Workspace Scrolling
-- ─────────────────────────────────────────────────────────────────────────────
S = "Workspaces: "
bind(mod("mouse_down"), dsp.focus({ workspace = "e+1" }), S .. "next (scroll)")
bind(mod("mouse_up"),   dsp.focus({ workspace = "e-1" }), S .. "previous (scroll)")


-- ─────────────────────────────────────────────────────────────────────────────
-- Mouse Window Controls
-- ─────────────────────────────────────────────────────────────────────────────
S = "Mouse: "
bind(mod("mouse:272"), dsp.window.drag(),   S .. "drag to move window",   { mouse = true })
bind(mod("mouse:273"), dsp.window.resize(), S .. "drag to resize window", { mouse = true })


-- ─────────────────────────────────────────────────────────────────────────────
-- Hardware & Media Keys
-- ─────────────────────────────────────────────────────────────────────────────
S = "Media: "
-- locked + repeating was bindel
bind("XF86AudioRaiseVolume",  dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), S .. "volume up",       { locked = true, repeating = true })
bind("XF86AudioLowerVolume",  dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      S .. "volume down",     { locked = true, repeating = true })
bind("XF86AudioMute",         dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     S .. "mute",            { locked = true, repeating = true })
bind("XF86AudioMicMute",      dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   S .. "mute mic",        { locked = true, repeating = true })
bind("XF86MonBrightnessUp",   dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  S .. "brightness up",   { locked = true, repeating = true })
bind("XF86MonBrightnessDown", dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  S .. "brightness down", { locked = true, repeating = true })

-- Requires playerctl (was bindl)
bind("XF86AudioNext",  dsp.exec_cmd("playerctl next"),       S .. "next track",     { locked = true })
bind("XF86AudioPause", dsp.exec_cmd("playerctl play-pause"), S .. "play/pause",     { locked = true })
bind("XF86AudioPlay",  dsp.exec_cmd("playerctl play-pause"), S .. "play/pause",     { locked = true })
bind("XF86AudioPrev",  dsp.exec_cmd("playerctl previous"),   S .. "previous track", { locked = true })
