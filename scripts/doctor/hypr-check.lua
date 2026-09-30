-- invictus-doctor's config check without Hyprland: loads a hyprland.lua
-- against the test mock of `hl` (mock_hl.lua, api.lua), which checks every
-- call against the API stubs Hyprland ships, the way tests/hyprland-lua does.
--
-- usage: lua hypr-check.lua <hyprland.lua> <hl.meta.lua> [xkbcommon-keysyms.h]
-- Prints one line per problem ("error: ..." or "warning: ...").
-- Exit 0: no errors. 1: errors. 2: could not run.

local cfg, stubs, keysyms = ...
if not cfg or not stubs then
    io.stderr:write("usage: lua hypr-check.lua <hyprland.lua> <hl.meta.lua> [keysyms.h]\n")
    os.exit(2)
end
if keysyms == "" then keysyms = nil end

-- Installed, the mock sits next to this file; in a repo checkout it is in
-- tests/hyprland-lua.
local here = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
package.path = here .. "?.lua;" .. here .. "../../tests/hyprland-lua/?.lua;" .. package.path

local okMock, mock = pcall(require, "mock_hl")
local okReq, hyprrequire = pcall(require, "hyprrequire")
if not (okMock and okReq) then
    io.stderr:write("cannot load the checker: " .. tostring(okMock and hyprrequire or mock) .. "\n")
    os.exit(2)
end

local okNew, hl, state = pcall(mock.new, { stubs = stubs, keysyms = keysyms })
if not okNew then
    io.stderr:write("cannot load the API stubs: " .. tostring(hl) .. "\n")
    os.exit(2)
end
_G.hl = hl

local moduleErrors = {}
local realRequire = require
_G.require = hyprrequire.make(realRequire, function() end,
    function(e) table.insert(moduleErrors, e) end)

local chunk, loadErr = loadfile(cfg)
local ok, runErr = false, loadErr
if chunk then ok, runErr = pcall(chunk) end
_G.require = realRequire

if ok then
    for _, cb in ipairs(state.events["hyprland.start"] or {}) do
        local cbOk, e = pcall(cb)
        if not cbOk then table.insert(moduleErrors, "hyprland.start handler: " .. tostring(e)) end
    end
end

local errors = 0
local function out(kind, msg) print(kind .. ": " .. msg) end
if not ok then out("error", tostring(runErr)); errors = errors + 1 end
for _, e in ipairs(moduleErrors) do out("error", e); errors = errors + 1 end
for _, e in ipairs(state.errors) do out("error", e); errors = errors + 1 end
for _, w in ipairs(state.warnings) do out("warning", w) end
os.exit(errors == 0 and 0 or 1)
