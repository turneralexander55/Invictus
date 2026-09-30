--------------------------------------------------------------------------------
--                                                                            --
--                                  MOTION                                    --
--                                                                            --
--------------------------------------------------------------------------------
-- Animation curves, animation leaves and layer animations for the three motion
-- levels in docs/look.md ("Motion"):
--
--   showcase  (default) everyday <= 150 ms, moments <= 300 ms, overshoot and
--             the border glint
--   calm      shorter, fades and small scales only, no slides, no glint
--   off       no animation at all (also forced while game mode is on)
--
-- The level comes from invictus/state.lua (~/.config/invictus/motion). Hyprland
-- `speed` is in tenths of a second (1 = 100 ms). Every leaf name and style was
-- checked against the v0.56.2 source; the curve field is `bezier`, not the
-- wiki's `curve`. Nothing loops: no leaf uses the `loop` style.
--------------------------------------------------------------------------------

local state = require("invictus.state")

local level = state.motionLevel()

-- Curves (all levels; names are ours).
hl.curve("snap",   { type = "bezier", points = { { 0.2,  0.9 }, { 0.1, 1 } } }) -- everyday moves, the bar
hl.curve("glide",  { type = "bezier", points = { { 0.25, 1 },   { 0.5, 1 } } }) -- fades, workspaces, dim, border colour
hl.curve("rise",   { type = "bezier", points = { { 0.3,  1.5 }, { 0.6, 1 } } }) -- window open, about 6% overshoot
hl.curve("unveil", { type = "bezier", points = { { 0.16, 1 },   { 0.3, 1 } } }) -- ceremonies and the glint
hl.curve("sink",   { type = "bezier", points = { { 0.4,  0 },   { 1,   1 } } }) -- exits
hl.curve("linear", { type = "bezier", points = { { 0,    0 },   { 1,   1 } } }) -- fade-outs

-- One row per leaf: { leaf, showcase, calm }. A level entry is
-- { speed, curve [, style] }; false means the leaf is off at that level.
local LEAVES = {
    { "global",          { 1.5, "snap" },                          { 1.2, "snap" } },
    { "windowsIn",       { 2.6, "rise",   "popin 88%" },           { 1.8, "glide", "popin 96%" } },
    { "windowsOut",      { 1.4, "sink",   "popin 92%" },           { 1.0, "sink",  "popin 96%" } },
    { "windowsMove",     { 1.5, "snap" },                          { 1.2, "snap" } },
    { "fadeIn",          { 1.6, "glide" },                         { 1.2, "glide" } },
    { "fadeOut",         { 1.2, "linear" },                        { 1.0, "linear" } },
    { "fadeSwitch",      { 1.2, "glide" },                         { 1.2, "glide" } },
    { "fadeShadow",      { 1.5, "glide" },                         { 1.2, "glide" } },
    { "fadeDim",         { 1.5, "glide" },                         { 1.2, "glide" } },
    { "border",          { 1.2, "glide" },                         { 1.2, "glide" } },
    { "borderangle",     { 3,   "unveil", "once" },                false },  -- the glint
    { "layersIn",        { 1.8, "snap",   "popin 94%" },           { 1.2, "glide", "fade" } },
    { "layersOut",       { 1.2, "sink",   "fade" },                { 1.0, "linear", "fade" } },
    { "fadeLayersIn",    { 1.6, "glide" },                         { 1.2, "glide" } },
    { "fadeLayersOut",   { 1.0, "linear" },                        { 1.0, "linear" } },
    { "fadePopupsIn",    { 1.0, "glide" },                         { 1.0, "glide" } },
    { "fadePopupsOut",   { 0.8, "linear" },                        { 0.8, "linear" } },
    { "workspaces",      { 2.8, "glide",  "slidefade 12%" },       { 1.8, "glide", "fade" } },
    { "specialWorkspace", { 2.6, "glide", "slidefadevert 16%" },   { 1.8, "glide", "fade" } }, -- the Desk
    { "zoomFactor",      { 2.5, "glide" },                         { 1.5, "glide" } },
    { "monitorAdded",    { 6,   "unveil" },                        false },  -- session start zoom
    { "fadeDpms",        { 3,   "glide" },                         { 2,   "glide" } },
}

if level == "off" then
    -- Covers every leaf, including borderangle.
    hl.config({ animations = { enabled = false } })
else
    hl.config({ animations = { enabled = true } })
    local column = (level == "showcase") and 2 or 3
    for _, row in ipairs(LEAVES) do
        local spec = row[column]
        if spec then
            hl.animation({ leaf = row[1], enabled = true, speed = spec[1], bezier = spec[2], style = spec[3] })
        else
            hl.animation({ leaf = row[1], enabled = false })
        end
    end
end

-- Layer animations by namespace (rofi and the pickers inherit layersIn;
-- swaync and the veil animate themselves, see rules.lua). The `animation`
-- value format is assumed to match a leaf `style`; not tested on a real
-- Hyprland yet. Slides are for Showcase only: Calm has no slides.
if level == "showcase" then
    hl.layer_rule({ name = "motion-waybar",       match = { namespace = "waybar" },       animation = "slide top" })
    hl.layer_rule({ name = "motion-moneta-panel", match = { namespace = "moneta-panel" }, animation = "slide right" })
end

return { level = level, leaves = LEAVES }
