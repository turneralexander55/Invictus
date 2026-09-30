-- Parts of the Hyprland 0.56.2 Lua API that the generated stubs do not list.
-- Each list is copied from the Hyprland source at tag v0.56.2; the file is
-- named next to each table so it can be refreshed on a version bump.
-- Config keys, spec fields, event names and dispatcher names come from the
-- stubs (stubs/hl.meta.lua) and are parsed at run time, not listed here.

local M = {}

local function set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

-- src/desktop/rule/Rule.cpp (matchPropStrings)
M.ruleMatchProps = set({
    "class", "title", "initial_class", "initial_title", "float", "tag", "xwayland",
    "fullscreen", "pin", "focus", "group", "modal", "fullscreen_state_internal",
    "fullscreen_state_client", "workspace", "content", "xdg_tag", "namespace",
})

-- src/config/lua/bindings/LuaBindingsInternal.hpp (WINDOW_RULE_EFFECT_DESCS)
-- value kind: bool, int, float, string, vec2 (expression vec2), gradient
M.windowEffects = {
    float = "bool", tile = "bool", fullscreen = "bool", maximize = "bool",
    center = "bool", pseudo = "bool", no_initial_focus = "bool", pin = "bool",
    fullscreen_state = "string", move = "vec2", size = "vec2", monitor = "string",
    workspace = "string", group = "string", suppress_event = "string",
    content = "string", no_close_for = "int", scrolling_width = "float",
    rounding = "int", border_size = "int", rounding_power = "float",
    scroll_mouse = "float", scroll_touchpad = "float", animation = "string",
    idle_inhibit = "string", opacity = "string", tag = "string", max_size = "vec2",
    min_size = "vec2", border_color = "gradient", persistent_size = "bool",
    allows_input = "bool", dim_around = "bool", decorate = "bool",
    focus_on_activate = "bool", keep_aspect_ratio = "bool", nearest_neighbor = "bool",
    no_anim = "bool", no_blur = "bool", no_dim = "bool", no_focus = "bool",
    no_follow_mouse = "bool", no_max_size = "bool", no_shadow = "bool",
    no_shortcuts_inhibit = "bool", opaque = "bool", force_rgbx = "bool",
    sync_fullscreen = "bool", immediate = "bool", xray = "bool",
    render_unfocused = "bool", no_screen_share = "bool", no_vrr = "bool",
    no_auto_hdr = "bool", stay_focused = "bool", confine_pointer = "bool",
    tonemap = "string",
}

-- Allowed string values for a few window rule effects (wiki: Window Rules)
M.windowEffectValues = {
    content      = set({ "none", "photo", "video", "game" }),
    idle_inhibit = set({ "none", "always", "focus", "fullscreen" }),
}
M.suppressEvents = set({
    "fullscreen", "maximize", "activate", "activatefocus", "fullscreenoutput", "x11configurerequest",
})

-- src/desktop/rule/layerRule/LayerRuleEffectContainer.cpp
M.layerEffects = {
    no_anim = "bool", blur = "bool", blur_popups = "bool", ignore_alpha = "float",
    dim_around = "bool", xray = "bool", animation = "string", order = "int",
    above_lock = "int", no_screen_share = "bool",
}

-- src/config/lua/bindings/LuaBindingsToplevel.cpp (modFromSv, isSymSpecial)
M.modifiers = {
    SHIFT = 1, CAPS = 2, CTRL = 4, CONTROL = 4, ALT = 8, MOD1 = 8, MOD2 = 16,
    MOD3 = 32, SUPER = 64, WIN = 64, LOGO = 64, MOD4 = 64, META = 64, MOD5 = 128,
}
M.specialKeys = set({ "mouse_down", "mouse_up", "mouse_left", "mouse_right" })
M.specialPrefixes = { "switch:", "mouse:" }

-- `mouse` is not read by hl.bind in 0.56.2 (drag()/resize() carry it), but the
-- official example config passes it, so it is accepted.
M.extraBindOptions = set({ "mouse" })

-- src/config/shared/animation/AnimationTree.cpp (createNode)
M.animationLeaves = set({
    "global", "windows", "layers", "fade", "border", "borderangle", "shadowangle",
    "glowangle", "workspaces", "zoomFactor", "monitorAdded", "layersIn", "layersOut",
    "windowsIn", "windowsOut", "windowsMove", "fadeIn", "fadeOut", "fadeSwitch",
    "fadeShadow", "fadeGlow", "fadeDim", "fadeLayers", "fadeLayersIn", "fadeLayersOut",
    "fadePopups", "fadePopupsIn", "fadePopupsOut", "fadeDpms", "workspacesIn",
    "workspacesOut", "specialWorkspace", "specialWorkspaceIn", "specialWorkspaceOut",
})
-- src/animation/AnimationManager.cpp (styleValidInConfigVar). "angle" styles only work on
-- the borderangle, shadowangle and glowangle leaves. Untested where noted in docs/look.md.
M.animationStyles = { slide = "any", slidevert = "any", fade = "any", slidefade = "any",
    slidefadevert = "any", popin = "any", gnome = "any", gnomed = "any", once = "angle", loop = "angle" }
M.animationFields = set({ "leaf", "enabled", "speed", "bezier", "spring", "style" })

-- src/config/lua/bindings/LuaBindingsInternal.cpp (parseDirectionStr)
M.directions = set({ "left", "l", "right", "r", "up", "u", "down", "d" })

-- Argument tables accepted by the dispatchers the config uses
-- (src/config/lua/bindings/LuaBindingsDispatchers.cpp, wiki: Dispatchers).
M.dispatcherArgs = {
    ["focus"]           = set({ "direction", "monitor", "workspace", "on_current_monitor", "window", "urgent_or_last", "last" }),
    ["window.close"]    = set({ "window" }),
    ["window.kill"]     = set({ "window" }),
    ["window.float"]    = set({ "action", "window" }),
    ["window.fullscreen"] = set({ "mode", "action", "layout_aware", "window" }),
    ["window.move"]     = set({ "direction", "group_aware", "workspace", "monitor", "follow", "x", "y", "relative", "window",
                                "into_group", "into_or_create_group", "out_of_group" }),
    ["window.drag"]     = set({}),
    ["window.resize"]   = set({ "keep_aspect_ratio", "x", "y", "relative", "window" }),
    ["window.pseudo"]   = set({ "action", "window" }),
}
-- LuaBindingsInternal.cpp parseToggleStr: anything else silently means toggle
M.floatActions = set({ "toggle", "enable", "on", "disable", "off" })

return M
