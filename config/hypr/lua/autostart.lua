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
-- Those belong in lua/rules.lua or lua/workspaces.lua.
--
-- exec-once became a handler on the "hyprland.start" event. It runs once per
-- session, not on config reload. hl.exec_cmd() already runs each command in
-- the background through sh -c, so the old trailing "&" is dropped.
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
--------------------------------------------------------------------------------

hl.on("hyprland.start", function()
    -- ─────────────────────────────────────────────────────────────────────────
    -- System Services
    -- Core background services required for proper session behavior.
    -- ─────────────────────────────────────────────────────────────────────────
    hl.exec_cmd("xwaylandvideobridge")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("/usr/lib/xdg-desktop-portal-hyprland")
    hl.exec_cmd("/usr/lib/xdg-desktop-portal")

    -- ─────────────────────────────────────────────────────────────────────────
    -- Desktop Environment
    -- Visual and interaction-layer components.
    -- ─────────────────────────────────────────────────────────────────────────
    hl.exec_cmd("swaync")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
end)
