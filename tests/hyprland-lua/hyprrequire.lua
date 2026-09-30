-- Hyprland's require(), emulated for the tests and for invictus-doctor
-- (installed as /usr/lib/invictus/doctor/hyprrequire.lua by invictus-tools).
--
-- Hyprland 0.56.2 (src/config/lua/ConfigManager.cpp):
--   * a name starting with "/", "./", "../" or "~/" is a file path, tried as
--     given, with ".lua" added, then as <path>/init.lua;
--   * a module that is not found raises an error the caller can pcall;
--   * any other error in a module is reported and require returns {}.
--
-- make(realRequire, onRequire, onError) returns a require function.

local M = {}

function M.explicitPath(name)
    if name:match("^/") or name:match("^%.%.?/") or name:match("^~/") then
        local base = name:gsub("^~/", (os.getenv("HOME") or "") .. "/")
        for _, c in ipairs({ base, base .. ".lua", base .. "/init.lua" }) do
            local f = io.open(c)
            if f then f:close(); return c end
        end
    end
end

function M.make(realRequire, onRequire, onError)
    return function(name)
        if package.loaded[name] ~= nil then return package.loaded[name] end
        local file = M.explicitPath(name)
        local ok, res
        if file then
            onRequire(name)
            local chunk, e = loadfile(file)
            if chunk then ok, res = pcall(chunk, name, file) else ok, res = false, e end
        elseif package.preload[name] or package.searchpath(name, package.path) then
            onRequire(name)
            ok, res = pcall(realRequire, name)
            if ok then return res end
        else
            error("module '" .. name .. "' not found", 2)
        end
        if not ok then
            onError("require(\"" .. name .. "\"): " .. tostring(res))
            package.loaded[name] = {}
            return {}
        end
        if res == nil then res = true end
        package.loaded[name] = res
        return res
    end
end

return M
