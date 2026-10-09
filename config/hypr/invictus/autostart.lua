--------------------------------------------------------------------------------
--                                                                            --
--                                AUTOSTART                                   --
--                                                                            --
--------------------------------------------------------------------------------
-- Processes and services launched once when Hyprland starts.
--
-- Use this for:
--   • System-level user services required for Wayland functionality
--   • Desktop components such as bars, wallpaper daemons, and idle managers
--   • Notification systems and background utilities
--
-- Avoid placing application-specific launch rules here.
-- Those belong in invictus/rules.lua or invictus/workspaces.lua.
--
-- exec-once became a handler on the "hyprland.start" event. It runs once per
-- session, not on config reload. hl.exec_cmd() already runs each command in
-- the background through sh -c, so the old trailing "&" is dropped.
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
--------------------------------------------------------------------------------

-- On a brand-new account SDDM starts Hyprland while the invictus-first-login
-- user unit is still copying the defaults (Alex's first install, 2026-10-09).
-- `systemctl --user start` on a oneshot waits for it to finish, and returns at
-- once on later logins (its condition fails), so everything that reads those
-- files waits for them.
local AFTER_FIRST_LOGIN = "systemctl --user start invictus-first-login.service; "

hl.on("hyprland.start", function()
    -- ─────────────────────────────────────────────────────────────────────────
    -- System Services
    -- Core background services required for proper session behavior.
    -- ─────────────────────────────────────────────────────────────────────────
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("/usr/lib/xdg-desktop-portal-hyprland")
    hl.exec_cmd("/usr/lib/xdg-desktop-portal")

    -- ─────────────────────────────────────────────────────────────────────────
    -- Desktop Environment
    -- Visual and interaction-layer components.
    -- ─────────────────────────────────────────────────────────────────────────
    hl.exec_cmd(AFTER_FIRST_LOGIN .. "swaync")
    hl.exec_cmd(AFTER_FIRST_LOGIN .. "hyprpaper")
    hl.exec_cmd("hypridle")
    -- Generate the current theme's colour files (Dusk on a fresh install) before
    -- the bar reads them; apps have a Dusk fallback, but rofi needs the file.
    -- `;` not `&&`: a failing theme step must not leave the desktop without a bar.
    -- Waybar 0.15 reads only ~/.config/waybar/config or config.jsonc, not our
    -- config.json, so it is named here (design note 64).
    hl.exec_cmd(AFTER_FIRST_LOGIN .. "invictus-theme apply; waybar -c \"$HOME/.config/waybar/config.json\"")

    -- First start (design.md 2.3): only on a home first-login marked, once.
    hl.exec_cmd(AFTER_FIRST_LOGIN .. "invictus-first-boot start --if-pending")
end)
