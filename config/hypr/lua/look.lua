--------------------------------------------------------------------------------
--                                                                            --
--                               AESTHETICS                                   --
--                                                                            --
--------------------------------------------------------------------------------
-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
--------------------------------------------------------------------------------


-- ─────────────────────────────────────────────────────────────────────────────
-- GENERAL  (Layout, gaps, borders)
-- ─────────────────────────────────────────────────────────────────────────────
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,

        -- Slightly heavier border to match block cursor weight
        border_size = 3,

        -- Monochrome manga-style borders
        col = {
            active_border   = { colors = { "rgba(f7f7f7ff)", "rgba(d6d6d6ff)" }, angle = 45 },
            inactive_border = "rgba(1a1a1acc)",
        },

        -- Do not allow accidental border dragging
        resize_on_border = false,

        -- general.allow_tearing lives in lua/gaming.lua (tearing for games only)

        -- Intentional layout choice
        layout = "master",
    },
})


-- ─────────────────────────────────────────────────────────────────────────────
-- MASTER LAYOUT
-- https://wiki.hypr.land/Configuring/Layouts/Master-Layout/
-- ─────────────────────────────────────────────────────────────────────────────
hl.config({
    master = {
        allow_small_split    = true,
        special_scale_factor = 0.95,
        mfact                = 0.65,
        new_on_top           = false,
        new_on_active        = "none",
        new_status           = "slave",
        orientation          = "left",
    },
})


-- ─────────────────────────────────────────────────────────────────────────────
-- DECORATION  (Corners, opacity, shadows, blur)
-- ─────────────────────────────────────────────────────────────────────────────
hl.config({
    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Focused / unfocused transparency
        active_opacity   = 0.9,
        inactive_opacity = 0.8,

        shadow = {
            enabled      = true,
            range        = 30,
            render_power = 5,
            color        = "rgba(00000055)",
        },

        blur = {
            enabled  = true,
            size     = 5,
            passes   = 2,
            vibrancy = 0,
        },
    },
})


-- ─────────────────────────────────────────────────────────────────────────────
-- ANIMATIONS (Timing curves & motion)
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
-- ─────────────────────────────────────────────────────────────────────────────
hl.config({
    animations = {
        enabled = true, -- yes, please :)
    },
})

-- Curves
hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1 },    { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear",         { type = "bezier", points = { { 0, 0 },       { 1, 1 } } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 } } })

-- Animations
hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })


-- ─────────────────────────────────────────────────────────────────────────────
-- WORKSPACE RULES (Optional smart gaps)
-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- ─────────────────────────────────────────────────────────────────────────────
-- "Smart gaps" / "No gaps when only"
-- Uncomment all if you wish to use that.
--
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
--
-- hl.window_rule({
--     name        = "no-gaps-wtv1",
--     match       = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
--
-- hl.window_rule({
--     name        = "no-gaps-f1",
--     match       = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })


-- ─────────────────────────────────────────────────────────────────────────────
-- DWINDLE
-- https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/
-- ─────────────────────────────────────────────────────────────────────────────
-- dwindle.pseudotile was removed in 0.55 ("it wasn't doing anything").
-- Pseudotiling is now only the per-window hl.dsp.window.pseudo() dispatcher.
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})


-- ─────────────────────────────────────────────────────────────────────────────
-- MISC
-- ─────────────────────────────────────────────────────────────────────────────
-- misc.vrr lives in lua/gaming.lua
hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable anime mascot wallpapers
        disable_hyprland_logo   = false, -- :(
    },
})
