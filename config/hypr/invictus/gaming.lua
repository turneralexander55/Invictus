--------------------------------------------------------------------------------
--                                                                            --
--                                 GAMING                                     --
--                                                                            --
--------------------------------------------------------------------------------
-- Invictus gaming baseline (new in the Lua port; not in the old hyprland.conf).
-- Loaded by invictus/core.lua. Override any value here in ~/.config/hypr/user.lua.
--
-- How it fits together: the rules below mark game windows with the "game"
-- content type. Three settings key off that type, so they only kick in for
-- games, never for a fullscreen browser or terminal:
--   • misc.vrr = 3             adaptive sync (FreeSync) for fullscreen games/video
--   • render.direct_scanout = 2 skip compositing for a fullscreen game
--   • cursor.no_break_fs_vrr   default 2: cursor moves don't break VRR in games
-- Tearing is separate: general.allow_tearing is the master switch, and only
-- windows with the `immediate` rule effect tear.
--
-- Add a game that isn't matched (Lutris, Heroic, native launchers): find its
-- class with `hyprctl clients` and add it to extraGameClasses below.
--------------------------------------------------------------------------------


-- ─────────────────────────────────────────────────────────────────────────────
-- Global switches                                              [ADDED: gaming]
-- ─────────────────────────────────────────────────────────────────────────────
hl.config({
    misc = {
        -- 0 off, 1 always, 2 any fullscreen window, 3 fullscreen game/video.
        -- 3, not 2: VRR on a fullscreen desktop app (browser, terminal, idle
        -- video player UI) makes some panels flicker in brightness as the
        -- refresh rate swings. 3 limits it to windows marked game or video.
        -- If a fullscreen game never gets FreeSync, add its class below, or
        -- use 2 as the blunt fallback.
        vrr = 3,
    },

    general = {
        -- Master switch only. Nothing tears unless a rule sets `immediate`.
        -- Tearing needs the game to be fullscreen and alone on its monitor.
        allow_tearing = true,
    },

    render = {
        -- 0 off, 1 on, 2 auto (only for the "game" content type).
        -- Lower latency for fullscreen games. Set 0 if a game shows glitches.
        direct_scanout = 2,
    },
})


-- ─────────────────────────────────────────────────────────────────────────────
-- Game windows                                                 [ADDED: gaming]
-- ─────────────────────────────────────────────────────────────────────────────
-- Effects every game window gets:
--   content      = "game"        drives vrr = 3, direct_scanout = 2
--   immediate    = true          allow tearing (lower input latency)
--   opaque       = true          ignore the 0.9 / 0.8 desktop transparency
--   idle_inhibit = "fullscreen"  no idle lock while playing fullscreen on a pad
local function gameRule(name, match)
    return hl.window_rule({
        name         = name,
        match        = match,

        content      = "game",
        immediate    = true,
        opaque       = true,
        idle_inhibit = "fullscreen",
    })
end

-- Steam games through Proton/XWayland get the class steam_app_<appid>
gameRule("game-steam-proton", { class = "^steam_app_\\d+$" })

-- gamescope (Steam launch option `gamescope -- %command%`, or run directly)
gameRule("game-gamescope", { class = "^gamescope$" })

-- Anything that tags itself as a game through the content-type protocol
gameRule("game-content-type", { content = "game" })

-- Other games by class. Example: { "^Minecraft.*$", "^heroic$" }
local extraGameClasses = {}
for i, class in ipairs(extraGameClasses) do
    gameRule("game-extra-" .. i, { class = class })
end


-- ─────────────────────────────────────────────────────────────────────────────
-- Steam client                                                 [ADDED: gaming]
-- ─────────────────────────────────────────────────────────────────────────────
-- Steam's friend and download toasts are separate windows; stop them taking
-- focus away from a running game.
hl.window_rule({
    name  = "steam-toasts-no-focus",
    match = { class = "^steam$", title = "^notificationtoasts_\\d+_desktop$" },

    no_initial_focus = true,
})
