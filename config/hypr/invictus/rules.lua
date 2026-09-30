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

-- Blur the panels that sit on the wallpaper (docs/look.md, Hyprland). ignore_alpha
-- keeps the blur off the fully transparent parts of a layer.
local blurred = { "waybar", "rofi", "swaync-notification-window", "swaync-control-center", "moneta-panel" }
for _, namespace in ipairs(blurred) do
    local rule = {
        name  = namespace,
        match = { namespace = namespace },

        blur         = true,
        ignore_alpha = 0.3,
    }
    -- The launcher (and the pickers, which are rofi too) dims what is behind it
    if namespace == "rofi" then rule.dim_around = true end
    -- swaync animates its own cards; a layer fade on top would double it
    if namespace:match("^swaync") then rule.no_anim = true end
    hl.layer_rule(rule)
end

-- The theme-switch veil animates itself (invictus-theme, docs/look.md, Motion)
hl.layer_rule({
    name  = "invictus-veil",
    match = { namespace = "invictus-veil" },

    no_anim = true,
})


-- ─────────────────────────────────────────────────────────────────────────────
-- Custom Utilities
-- ─────────────────────────────────────────────────────────────────────────────
