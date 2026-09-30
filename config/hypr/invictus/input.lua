--------------------------------------------------------------------------------
--                                                                            --
--                                  INPUT                                     --
--                                                                            --
--------------------------------------------------------------------------------
-- Global input behavior for keyboards, pointers, touchpads, and gestures.
--
-- Use this file to configure:
--   • Keyboard layout and options
--   • Mouse focus and sensitivity
--   • Touchpad behavior
--   • Global gesture handling
--
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
--------------------------------------------------------------------------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        -- Pointer sensitivity
        -- Range: -1.0 to 1.0 (0 = no modification)
        sensitivity = 0,

        touchpad = {
            natural_scroll = false,
        },
    },
})


-- ─────────────────────────────────────────────────────────────────────────────
-- Gestures
-- Global gesture definitions.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- ─────────────────────────────────────────────────────────────────────────────
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})


-- ─────────────────────────────────────────────────────────────────────────────
-- Per-Device Overrides
-- Device-specific input configuration.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/
-- ─────────────────────────────────────────────────────────────────────────────
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
