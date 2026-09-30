-- Ports the personal parts of an old hyprlang Hyprland config (deployed by
-- the legacy scripts) to the Lua layout, for scripts/dev/adopt.sh.
--
-- usage: lua port-hyprlang.lua <deployed hypr dir> <clone hypr dir or "">
--            <shipped binds.lua or ""> <monitors template> <user template>
--            <out monitors.lua> <out user.lua>
--
--   monitors.lua  the template, plus one hl.monitor{} per `monitor =` line
--                 in the deployed config/monitors.conf
--   user.lua      the template, plus
--                 * every exec bind that runs something from your home
--                   (~/ or $HOME/, not the old clone), such as dashboard-tmux;
--                 * every exec bind that is in your deployed config but not in
--                   the clone (a bind you added yourself);
--                 * every other line you added, as a comment to port by hand.
--                 A bind whose command the shipped binds.lua already runs is
--                 left out, so nothing fires twice.
-- Prints a summary on stdout. Reuses the hyprlang reader from the tests.

local deployed, clone, shippedBinds, monTpl, userTpl, outMon, outUser = ...
assert(outUser, "usage: lua port-hyprlang.lua <deployed> <clone> <binds.lua> <monitors tpl> <user tpl> <out monitors> <out user>")

local here = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
package.path = here .. "../../tests/hyprland-lua/?.lua;" .. package.path
local hyprlang = require("hyprlang")

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function readAll(path)
    local f = path and path ~= "" and io.open(path, "r")
    if not f then return nil end
    local s = f:read("a"); f:close(); return s
end
local function lines(path)
    local out = {}
    local s = readAll(path)
    if s then for l in (s .. "\n"):gmatch("(.-)\n") do table.insert(out, l) end end
    return out
end
local function q(s) return string.format("%q", s) end

-- ─── variables ($mainMod, $terminal, ...) from the deployed files ──────────
local vars = {}
for _, name in ipairs({ "variables.conf", "keybindings.conf" }) do
    local path = deployed .. "/config/" .. name
    if readAll(path) then
        for k, v in pairs(hyprlang.parse(path).vars) do vars[k] = trim(v) end
    end
end
local function resolve(s)
    return (s:gsub("%$([%a_][%w_]*)", function(n)
        if n == "HOME" then return "$HOME" end
        return vars[n] or ("$" .. n)
    end))
end

-- ─── monitors ───────────────────────────────────────────────────────────────
local MON_FIELDS = { transform = "int", vrr = "int", bitdepth = "int", mirror = "str", cm = "str",
                     sdrbrightness = "num", sdrsaturation = "num" }
local monitorsOut, monitorNotes = {}, {}
local monPath = deployed .. "/config/monitors.conf"
if readAll(monPath) then
    for _, kw in ipairs(hyprlang.parse(monPath).keywords) do
        if kw.kind == "monitor" then
            local p = hyprlang.split(kw.value)
            local spec = { "    output   = " .. q(p[1] or "") }
            if p[2] == "disable" or p[2] == "disabled" then
                table.insert(spec, "    disabled = true")
            else
                if p[2] and p[2] ~= "" then table.insert(spec, "    mode     = " .. q(p[2])) end
                if p[3] and p[3] ~= "" then table.insert(spec, "    position = " .. q(p[3])) end
                if p[4] and p[4] ~= "" then
                    table.insert(spec, "    scale    = " .. (tonumber(p[4]) and p[4] or q(p[4])))
                end
                local i = 5
                while p[i] do
                    local key, val = p[i], p[i + 1]
                    local kind = MON_FIELDS[key]
                    if kind and val then
                        if kind == "str" then val = q(val) end
                        table.insert(spec, string.format("    %-8s = %s", key, val))
                    else
                        table.insert(monitorNotes, "-- not ported (" .. key .. "): monitor = " .. kw.value)
                    end
                    i = i + 2
                end
            end
            table.insert(monitorsOut, "hl.monitor({\n" .. table.concat(spec, ",\n") .. ",\n})")
        end
    end
end

-- ─── personal lines ─────────────────────────────────────────────────────────
local shipped = readAll(shippedBinds) or ""
local FLAG_OPTS = { bind = {}, bindl = { "locked = true" }, binde = { "repeating = true" },
                    bindel = { "locked = true", "repeating = true" }, bindle = { "locked = true", "repeating = true" } }

local function keysOf(mods, key)
    local parts = {}
    for m in resolve(mods):gmatch("[^%s_]+") do table.insert(parts, m:upper()) end
    table.insert(parts, key)
    return table.concat(parts, " + ")
end

local binds, comments, skipped = {}, {}, {}
local seenCmd = {}

local function addBind(kind, value, why, label, file)
    local p = hyprlang.split(value, 4)
    local mods, key, disp, arg = p[1] or "", p[2] or "", trim(p[3] or ""), p[4] or ""
    if disp ~= "exec" or not FLAG_OPTS[kind] or key == "" then
        table.insert(comments, "-- (" .. file .. ") " .. kind .. " = " .. value)
        return
    end
    local cmd = trim(resolve(arg))
    if seenCmd[kind .. mods .. key .. cmd] then return end
    seenCmd[kind .. mods .. key .. cmd] = true
    if shipped:find(cmd, 1, true) then
        table.insert(skipped, cmd)
        return
    end
    local opts = { "description = " .. q("Personal: " .. (label ~= "" and label or cmd:match("^%S+"))) }
    for _, o in ipairs(FLAG_OPTS[kind]) do table.insert(opts, o) end
    table.insert(binds, string.format("-- %s\nhl.bind(%s, hl.dsp.exec_cmd(%s), { %s })",
        why, q(keysOf(mods, key)), q(cmd), table.concat(opts, ", ")))
end

local function confFiles(dir)
    local out = {}
    local p = io.popen('ls "' .. dir .. '/config/"*.conf 2>/dev/null')
    if p then for f in p:lines() do table.insert(out, f) end; p:close() end
    table.insert(out, dir .. "/hyprland.conf")
    return out
end

for _, path in ipairs(confFiles(deployed)) do
    local rel = path:sub(#deployed + 2)
    if rel ~= "config/monitors.conf" then
        local inClone = {}
        if clone ~= "" then
            for _, l in ipairs(lines(clone .. "/" .. rel)) do inClone[trim(l)] = true end
        end
        local lastComment = ""
        for _, raw in ipairs(lines(path)) do
            local l = trim(raw)
            local comment = l:match("^#%s*(.-)%s*$")
            -- a blank line keeps lastComment (a group heading covers its binds)
            if comment then
                if comment:match("%w") and not comment:match("^[─=%-#%s]+$") then lastComment = comment end
            elseif l ~= "" then
                local code = trim((l:gsub("%s+#.*$", "")))
                local kind, value = code:match("^(bind%a*)%s*=%s*(.*)$")
                local added = clone ~= "" and not inClone[l]
                local fromHome = kind and (value:find("~/", 1, true) or value:find("$HOME/", 1, true))
                    and not value:find("hyprdots/", 1, true)
                    and not value:find("invictus/scripts/", 1, true)
                if kind and (fromHome or added) then
                    addBind(kind, value, fromHome and "runs a program from your home (" .. rel .. ")"
                        or "you added this bind (" .. rel .. ")", fromHome and lastComment or "", rel)
                elseif added and not code:match("^source%s*=") then
                    table.insert(comments, "-- (" .. rel .. ") " .. code)
                end
                lastComment = ""
            end
        end
    end
end

-- ─── write ──────────────────────────────────────────────────────────────────
local function write(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text); f:close()
end

local date = os.date("%Y-%m-%d")
local mon = readAll(monTpl) or ""
if #monitorsOut > 0 or #monitorNotes > 0 then
    mon = mon .. "\n-- Ported from ~/.config/hypr/config/monitors.conf by adopt.sh on " .. date .. ".\n"
        .. table.concat(monitorsOut, "\n") .. "\n" .. table.concat(monitorNotes, "\n") .. (#monitorNotes > 0 and "\n" or "")
end
write(outMon, mon)

local user = readAll(userTpl) or ""
if #binds > 0 or #comments > 0 then
    user = user .. "\n-- ─── Ported from your old hyprlang config by adopt.sh on " .. date .. " ───\n"
    if #binds > 0 then user = user .. "\n" .. table.concat(binds, "\n\n") .. "\n" end
    if #comments > 0 then
        user = user .. "\n-- Lines in your old config that are not in the old repo copy. They are\n"
            .. "-- not ported; rewrite any you still want in Lua (see the examples above).\n"
            .. table.concat(comments, "\n") .. "\n"
    end
end
write(outUser, user)

print(string.format("monitors: %d ported, %d not ported", #monitorsOut, #monitorNotes))
print(string.format("personal binds: %d ported, %d already shipped, %d other lines left as comments", #binds, #skipped, #comments))
for _, c in ipairs(skipped) do print("  already in the shipped binds: " .. c) end
