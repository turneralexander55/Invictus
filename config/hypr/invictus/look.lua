--------------------------------------------------------------------------------
--                                                                            --
--                                  LOOK                                      --
--                                                                            --
--------------------------------------------------------------------------------
-- The look from docs/look.md: gaps, borders, rounding, dimming, shadows, blur.
-- Colours come from invictus/colors.lua (the current theme, with Dusk as the
-- fallback), never typed here. Animations are in invictus/motion.lua.
-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
--------------------------------------------------------------------------------

local c      = require("invictus.colors")
local state  = require("invictus.state")

-- Game mode (marker file, see state.lua): no gaps, borders, shadows, blur or
-- dim, so nothing sits between the game and the screen.
local game   = state.gameMode()

-- Showcase draws the focus border as a gradient of two focus tones (the glint
-- sweeps it once when a window opens, see motion.lua); Calm and Off use solid
-- focus colour.
local activeBorder = c.sol
if state.motionLevel() == "showcase" then
    activeBorder = { colors = { c.sol, c.sol_bright, c.sol }, angle = 45 }
end


-- ─────────────────────────────────────────────────────────────────────────────
-- GENERAL  (Layout, gaps, borders)
-- ─────────────────────────────────────────────────────────────────────────────
hl.config({
    general = {
        gaps_in  = game and 0 or 4,
        gaps_out = game and 0 or 8,

        -- Thin and precise; 3 read as heavy
        border_size = game and 0 or 2,

        -- Gold means "you are here": the focused window and nothing else
        col = {
            active_border   = activeBorder,
            inactive_border = c.stone,
        },

        -- Do not allow accidental border dragging
        resize_on_border = false,

        -- general.allow_tearing lives in invictus/gaming.lua (tearing for games only)

        -- Intentional layout choice
        layout = "master",
    },

    group = {
        col = {
            border_active   = c.sol,
            border_inactive = c.stone,
        },
        groupbar = {
            font_family = "IBM Plex Sans",
            font_size   = 12,
            text_color  = c.marble,
            col = {
                active   = c.sol,
                inactive = c.line,
            },
        },
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
        rounding       = 8,
        rounding_power = 2,

        -- Text stays fully legible: unfocused windows are dimmed, not see-through
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        dim_inactive     = not game,
        dim_strength     = 0.12,

        -- The focused window lifts a little; unfocused ones get no shadow
        shadow = {
            enabled        = not game,
            range          = 16,
            render_power   = 3,
            color          = c.shadow,
            color_inactive = c.shadow_none,
        },

        -- Only visible on layers (bar, launcher, notifications): windows are opaque
        blur = {
            enabled            = not game,
            size               = 6,
            passes             = 3,
            noise              = 0.015,
            vibrancy           = 0.1,
            new_optimizations  = true,
            xray               = false,
        },
    },
})


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
-- misc.vrr lives in invictus/gaming.lua
hl.config({
    misc = {
        force_default_wallpaper  = 0,     -- no Hyprland mascot wallpapers
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = c.night, -- no flash of another colour before the wallpaper loads
        focus_on_activate        = false,   -- apps cannot steal focus
        -- misc.vfr (in the look spec) does not exist in 0.56.2; variable frame rate is always on
    },
})
