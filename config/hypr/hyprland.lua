--------------------------------------------------------------------------------
--                                                                            --
--                                HYPRLAND                                    --
--                                                                            --
--------------------------------------------------------------------------------
-- Hyprland 0.55+ reads this file instead of hyprland.conf.
-- Written against the Hyprland 0.56.2 Lua API.
-- https://wiki.hypr.land/Configuring/Start/
--
-- The config is split into modules under lua/. Each require() below runs in
-- its own scope, so an error in one module is reported and the others still
-- load. Modules share values through return tables (see lua/variables.lua).
--
-- Order matters only where two modules set the same thing; none do today.
-- lua/gaming.lua holds the gaming additions and can be disabled on its own
-- by commenting out its line.
--------------------------------------------------------------------------------

require("lua.look")
require("lua.monitors")
require("lua.variables")
require("lua.autostart")
require("lua.env")
require("lua.input")
require("lua.permissions")
require("lua.binds")
require("lua.rules")
require("lua.workspaces")
require("lua.gaming")
