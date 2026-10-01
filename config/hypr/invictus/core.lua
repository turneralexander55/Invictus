--------------------------------------------------------------------------------
--                                                                            --
--                               INVICTUS CORE                                --
--                                                                            --
--------------------------------------------------------------------------------
-- The shipped Hyprland config. Installed by invictus-desktop under
-- /usr/share/invictus/hypr/invictus/ and replaced on every update, so do not
-- edit it on a machine: put changes in ~/.config/hypr/user.lua, which
-- hyprland.lua loads after this file (later settings win).
--
-- Written against the Hyprland 0.56.2 Lua API.
-- https://wiki.hypr.land/Configuring/Start/
--
-- Each require() runs in its own protected scope, so an error in one module
-- is reported and the others still load. Modules share values through return
-- tables (see invictus/variables.lua). Monitor layout is not here: it lives
-- in ~/.config/hypr/monitors.lua.
--------------------------------------------------------------------------------

require("invictus.look")
require("invictus.motion")
require("invictus.variables")
require("invictus.autostart")
require("invictus.env")
require("invictus.input")
require("invictus.permissions")
require("invictus.binds")
require("invictus.rules")
require("invictus.workspaces")
require("invictus.gaming")

-- The Moneta panel comes with the AI set (invictus-tribune). With No AI the
-- module is not on disk, and "module not found" is the only error require
-- raises (any other error in a module is reported and require returns {}).
pcall(require, "invictus.moneta")
