--------------------------------------------------------------------------------
--                                                                            --
--                                VARIABLES                                   --
--                                                                            --
--------------------------------------------------------------------------------
-- Reusable commands and applications. Other modules load this with
--     local apps = require("invictus.variables")
-- and use apps.terminal, apps.menu and so on.
--
-- In hyprlang these were $variables; in Lua they are fields of a table.
--------------------------------------------------------------------------------

return {
    -- Application defaults
    terminal    = "kitty",
    fileManager = "thunar",
    menu        = "rofi -show drun",
    browser     = "zen-browser",

    -- Main modifier ("Windows" key)
    mainMod     = "SUPER",
}
