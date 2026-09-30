-- Invictus loader (~/.config/hypr/hyprland.lua). Make changes in user.lua, not here.
local shared = "/usr/share/invictus/hypr/?.lua"; if not package.path:find(shared, 1, true) then package.path = shared .. ";" .. package.path end
require("invictus.core")
local dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
for _, name in ipairs({ "monitors", "user" }) do local f = io.open(dir .. name .. ".lua") if f then f:close(); require(dir .. name .. ".lua") end end
