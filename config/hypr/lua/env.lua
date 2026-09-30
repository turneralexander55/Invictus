--------------------------------------------------------------------------------
--                                                                            --
--                         ENVIRONMENT VARIABLES                              --
--                                                                            --
--------------------------------------------------------------------------------
-- Environment variables Hyprland exports to the Wayland session at startup.
--
-- Use this file to configure:
--   • Cursor sizes
--   • Toolkit behavior (GTK, Qt, Electron, etc.)
--   • Environment-level overrides required by specific applications
--
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
--------------------------------------------------------------------------------


-- ─────────────────────────────────────────────────────────────────────────────
-- GTK / Qt theming (Wayland)
-- ─────────────────────────────────────────────────────────────────────────────
hl.env("GTK_THEME", "Nordic-Darker")
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")


-- ─────────────────────────────────────────────────────────────────────────────
-- Cursor
-- Hardware cursors off: fixes the cursor issue seen on this machine.
-- 0 = use hw cursors if possible, 1 = never, 2 = auto (off while tearing)
-- ─────────────────────────────────────────────────────────────────────────────
hl.config({
    cursor = {
        no_hardware_cursors = 1,
    },
})
