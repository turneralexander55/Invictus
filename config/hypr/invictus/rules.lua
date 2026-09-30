--------------------------------------------------------------------------------
--                                                                            --
--                               WINDOW RULES                                 --
--                                                                            --
--------------------------------------------------------------------------------
-- Window- and layer-specific behavior rules.
--
-- Use this file to control:
--   • Window placement and sizing
--   • Floating behavior
--   • Focus handling
--   • Monitor assignment
--   • Layer rules (launchers, overlays, etc.)
--
-- Workspace assignment logic belongs in:
--   → invictus/workspaces.lua
-- Game rules (VRR, tearing, Steam games, gamescope) are in:
--   → invictus/gaming.lua
--
-- Rules run top to bottom, named rules before anonymous ones. Match values are
-- RE2 regexes; in Lua strings a regex backslash is written "\\".
--
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
--     https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
--------------------------------------------------------------------------------


-- ─────────────────────────────────────────────────────────────────────────────
-- Global Behavior Fixes
-- ─────────────────────────────────────────────────────────────────────────────

hl.window_rule({
    -- Ignore maximize requests from all applications
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix dragging issues with certain XWayland clients
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})


-- ─────────────────────────────────────────────────────────────────────────────
-- Hyprland Utilities
-- ─────────────────────────────────────────────────────────────────────────────

hl.window_rule({
    -- Position hyprland-run consistently
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})


-- ─────────────────────────────────────────────────────────────────────────────
-- Application-Specific Rules
-- ─────────────────────────────────────────────────────────────────────────────

-- Steam
hl.window_rule({
    name  = "steam-size",
    match = { class = "^(steam)$", title = "^(Steam)$" },

    float  = true,
    size   = { 1800, 1200 },
    center = true,
})

hl.window_rule({
    name  = "steam-settings",
    match = { class = "^(steam)$", title = "^(Steam Settings)$" },

    float  = true,
    size   = { 800, 800 },
    center = true,
})


-- Discord
hl.window_rule({
    name  = "discord-assign",
    match = { class = "^(discord)$" },

    monitor = "HDMI-A-2",
})


-- Zen Browser
hl.window_rule({
    name  = "zen-assign",
    match = { class = "^(zen)$" },

    monitor = "DP-2",
})


-- ─────────────────────────────────────────────────────────────────────────────
-- Layer Rules
-- ─────────────────────────────────────────────────────────────────────────────

-- Rofi launcher
hl.layer_rule({
    name  = "rofi",
    match = { namespace = "rofi" },

    blur       = true,
    dim_around = true,
})


-- ─────────────────────────────────────────────────────────────────────────────
-- Custom Utilities
-- ─────────────────────────────────────────────────────────────────────────────
