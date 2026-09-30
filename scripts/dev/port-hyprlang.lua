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
--                 * every window rule in your deployed config that pins a
--                   window to a monitor (monitor = ...), such as Discord on
--                   HDMI-A-2, unless the shipped rules.lua (next to binds.lua)
--                   already has a rule of that name;
--                 * every `workspace = N, monitor:X` line (and its default:,
--                   persistent: ... options) as hl.workspace_rule{};
--                 * every other line you added, as a comment to port by hand.
--                 Files scanned: config/*.conf, hyprland.conf and every file
--                 they `source` (also outside config/; globs and ~ or $HOME
--                 paths are followed). Anything it cannot port is listed as
--                 "not ported: FILE:LINE: ..." on stdout and in user.lua:
--                 monitorv2 blocks, workspace options with no Lua form, a
--                 sourced file that is missing or has an unresolvable path.
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

-- ─── which files to read ───────────────────────────────────────────────────
-- config/*.conf, hyprland.conf, then every file they `source` (recursively).
local notPorted = {} -- { where = "file:line", what = "..." , extra = { commented lines } }
local function notePort(where, what, extra)
    table.insert(notPorted, { where = where, what = what, extra = extra })
end

local function shortName(path)
    return path:sub(1, #deployed + 1) == deployed .. "/" and path:sub(#deployed + 2) or path
end

local function scanFile(path)
    local info = { monitorv2 = {}, workspaces = {}, sources = {}, blockLines = {} }
    local depth, cur = 0, nil
    for i, raw in ipairs(lines(path)) do
        local l = trim((raw:gsub("#.*$", "")))
        if cur then
            info.blockLines[i] = true
            table.insert(cur.text, raw)
            if l:match("{$") then depth = depth + 1 elseif l == "}" then depth = depth - 1 end
            if depth == 0 then cur = nil end
        elseif l:match("^monitorv2%s*{$") then
            cur = { line = i, text = { raw } }
            depth = 1
            info.blockLines[i] = true
            table.insert(info.monitorv2, cur)
        else
            local ws = l:match("^workspace%s*=%s*(.*)$")
            if ws then table.insert(info.workspaces, { line = i, value = ws }) end
            local src = l:match("^source%s*=%s*(.*)$")
            if src then table.insert(info.sources, { line = i, value = src }) end
        end
    end
    return info
end

local home = os.getenv("HOME") or ""
local function resolveSource(value, fromFile)
    local v = value:gsub("%$HOME", home):gsub("^~", home)
    local xdg = os.getenv("XDG_CONFIG_HOME")
    if xdg and xdg ~= "" then v = v:gsub("%$XDG_CONFIG_HOME", xdg) end
    -- the deployed folder is what the old source lines meant by ~/.config/hypr
    for _, root in ipairs({ home .. "/.config/hypr/", (xdg and xdg ~= "" and xdg .. "/hypr/") or false }) do
        if root and v:sub(1, #root) == root then v = deployed .. "/" .. v:sub(#root + 1) end
    end
    if v:find("%$") then return nil end
    if v:sub(1, 1) ~= "/" then v = fromFile:match("^(.*)/[^/]*$") .. "/" .. v end
    return v
end

local function globFiles(pattern)
    if not pattern:find("[%*%?%[]") then
        return readAll(pattern) and { pattern } or {}
    end
    local out = {}
    local p = io.popen('ls -d ' .. pattern:gsub("([^%w%*%?%[%]/%._%-])", "\\%1") .. ' 2>/dev/null')
    if p then for f in p:lines() do table.insert(out, f) end; p:close() end
    return out
end

local fileList, fileInfo, seenFile = {}, {}, {}
local function addFile(path, fromWhere)
    if seenFile[path] then return end
    if not readAll(path) then
        if fromWhere then notePort(fromWhere, "sourced file not found: " .. path) end
        return
    end
    seenFile[path] = true
    table.insert(fileList, path)
    fileInfo[path] = scanFile(path)
end
do
    local p = io.popen('ls "' .. deployed .. '/config/"*.conf 2>/dev/null')
    if p then for f in p:lines() do addFile(f) end; p:close() end
    addFile(deployed .. "/hyprland.conf")
    local i = 1
    while i <= #fileList do -- the list grows as sourced files are found
        local path = fileList[i]
        for _, src in ipairs(fileInfo[path].sources) do
            local where = shortName(path) .. ":" .. src.line
            local target = resolveSource(src.value, path)
            if not target then
                notePort(where, "source = " .. src.value .. " (path uses a variable; file not read)")
            else
                local found = globFiles(target)
                if #found == 0 then notePort(where, "sourced file not found: " .. target) end
                for _, f in ipairs(found) do addFile(f, where) end
            end
        end
        i = i + 1
    end
end

-- ─── monitors ───────────────────────────────────────────────────────────────
local MON_FIELDS = { transform = "int", vrr = "int", bitdepth = "int", mirror = "str", cm = "str",
                     sdrbrightness = "num", sdrsaturation = "num" }
local monitorsOut, monitorNotes = {}, {}
local seenMon = {}
for _, monPath in ipairs(fileList) do
    for _, kw in ipairs(hyprlang.parse(monPath).keywords) do
        if kw.kind == "monitor" and not seenMon[kw.value] then
            seenMon[kw.value] = true
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
                        notePort(shortName(monPath), "monitor option " .. key .. " (monitor = " .. kw.value .. ")")
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
    -- the same exec_cmd("...") call, not just the same words somewhere
    if shipped:find("exec_cmd(" .. q(cmd) .. ")", 1, true) then
        table.insert(skipped, cmd)
        return
    end
    local opts = { "description = " .. q("Personal: " .. (label ~= "" and label or cmd:match("^%S+"))) }
    for _, o in ipairs(FLAG_OPTS[kind]) do table.insert(opts, o) end
    table.insert(binds, string.format("-- %s\nhl.bind(%s, hl.dsp.exec_cmd(%s), { %s })",
        why, q(keysOf(mods, key)), q(cmd), table.concat(opts, ", ")))
end

local unscannedBinds = 0 -- binds we could not tell were yours (no old clone to compare)
for _, path in ipairs(fileList) do
    local rel = shortName(path)
    do
        local inClone = {}
        if clone ~= "" then
            for _, l in ipairs(lines(clone .. "/" .. rel)) do inClone[trim(l)] = true end
        end
        local lastComment = ""
        local blockLines = fileInfo[path].blockLines
        for lineNo, raw in ipairs(lines(path)) do
            local l = trim(raw)
            if blockLines[lineNo] then l = "" end
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
                if kind and clone == "" and not fromHome then unscannedBinds = unscannedBinds + 1 end
                -- workspace and monitor lines are ported by their own sections
                local other = not (code:match("^workspace%s*=") or code:match("^monitor%s*="))
                if other and kind and (fromHome or added) then
                    addBind(kind, value, fromHome and "runs a program from your home (" .. rel .. ")"
                        or "you added this bind (" .. rel .. ")", fromHome and lastComment or "", rel)
                elseif other and added and not code:match("^source%s*=") then
                    table.insert(comments, "-- (" .. rel .. ") " .. code)
                end
                lastComment = ""
            end
        end
    end
end

-- ─── window rules that pin a window to a monitor ────────────────────────────
-- Monitor names are machine-specific, so the shipped rules.lua has none; a
-- pin in the old config is yours and goes to user.lua.
local shippedRules = readAll((shippedBinds or ""):gsub("[^/]*$", "") .. "rules.lua") or ""
local windowRules, seenRule = {}, {}
for _, path in ipairs(fileList) do
    for _, block in ipairs(hyprlang.parse(path).windowRules) do
        local name = block.name
        if block.monitor and name and not seenRule[name]
            and not shippedRules:find("name%s*=%s*" .. q(name):gsub("%p", "%%%0")) then
            seenRule[name] = true
            local match = {}
            for k, v in pairs(block) do
                local m = k:match("^match:(.+)$")
                if m then table.insert(match, string.format("%s = %s", m, (v == "true" or v == "false") and v or q(v))) end
            end
            table.sort(match)
            table.insert(windowRules, string.format(
                "-- pins %s to a monitor (%s)\nhl.window_rule({\n    name    = %s,\n    match   = { %s },\n    monitor = %s,\n})",
                name, shortName(path), q(name), table.concat(match, ", "), q(block.monitor)))
        end
    end
end


-- ─── workspace rules (workspace = N, monitor:X) ─────────────────────────────
local WS_BOOL = { default = "default", persistent = "persistent", decorate = "decorate" }
local WS_NEG = { border = "no_border", rounding = "no_rounding", shadow = "no_shadow" }
local WS_NUM = { bordersize = "border_size", gapsin = "gaps_in", gapsout = "gaps_out" }
local WS_STR = { monitor = "monitor", animation = "animation", layout = "layout",
                 defaultName = "default_name", ["on-created-empty"] = "on_created_empty" }
local workspaceRules, seenWs = {}, {}
for _, path in ipairs(fileList) do
    for _, ws in ipairs(fileInfo[path].workspaces) do
        local where = shortName(path) .. ":" .. ws.line
        if not seenWs[ws.value] then
            seenWs[ws.value] = true
            local p = hyprlang.split(ws.value)
            local fields, bad = { "    workspace = " .. q(p[1]) }, {}
            for i = 2, #p do
                local k, v = p[i]:match("^([^:]+):%s*(.*)$")
                local isBool = v == "true" or v == "false" or v == "1" or v == "0"
                local b = (v == "true" or v == "1") and "true" or "false"
                if k and WS_STR[k] and v ~= "" then
                    table.insert(fields, string.format("    %s = %s", WS_STR[k], q(v)))
                elseif k and WS_BOOL[k] and isBool then
                    table.insert(fields, string.format("    %s = %s", WS_BOOL[k], b))
                elseif k and WS_NEG[k] and isBool then
                    table.insert(fields, string.format("    %s = %s", WS_NEG[k], b == "true" and "false" or "true"))
                elseif k and WS_NUM[k] and tonumber(v) then
                    table.insert(fields, string.format("    %s = %s", WS_NUM[k], v))
                else
                    table.insert(bad, p[i])
                end
            end
            for _, b in ipairs(bad) do notePort(where, "workspace option " .. b .. " (workspace = " .. ws.value .. ")") end
            if #fields > 1 then
                table.insert(workspaceRules, string.format("-- from %s\nhl.workspace_rule({\n%s,\n})", where, table.concat(fields, ",\n")))
            end
        end
    end
end

-- ─── monitorv2 blocks: not scanned ─────────────────────────────────────────
for _, path in ipairs(fileList) do
    for _, blk in ipairs(fileInfo[path].monitorv2) do
        local commented = {}
        for _, t in ipairs(blk.text) do table.insert(commented, "-- " .. t) end
        notePort(shortName(path) .. ":" .. blk.line, "monitorv2 block (write it as hl.monitor{} in monitors.lua)", commented)
    end
end
if unscannedBinds > 0 then
    notePort("(all files)", unscannedBinds .. " bind line(s) that do not run a program from your home are not ported: "
        .. "there is no old clone to tell which of them you added")
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
if #binds > 0 or #comments > 0 or #windowRules > 0 or #workspaceRules > 0 or #notPorted > 0 then
    user = user .. "\n-- ─── Ported from your old hyprlang config by adopt.sh on " .. date .. " ───\n"
    if #binds > 0 then user = user .. "\n" .. table.concat(binds, "\n\n") .. "\n" end
    if #windowRules > 0 then user = user .. "\n" .. table.concat(windowRules, "\n\n") .. "\n" end
    if #workspaceRules > 0 then user = user .. "\n" .. table.concat(workspaceRules, "\n\n") .. "\n" end
    if #notPorted > 0 then
        user = user .. "\n-- NOT PORTED: adopt.sh could not turn these into Lua. Rewrite any you still want.\n"
        for _, n in ipairs(notPorted) do
            user = user .. "-- not ported (" .. n.where .. "): " .. n.what .. "\n"
            if n.extra then user = user .. table.concat(n.extra, "\n") .. "\n" end
        end
    end
    if #comments > 0 then
        user = user .. "\n-- Lines in your old config that are not in the old repo copy. They are\n"
            .. "-- not ported; rewrite any you still want in Lua (see the examples above).\n"
            .. table.concat(comments, "\n") .. "\n"
    end
end
write(outUser, user)

print(string.format("monitors: %d ported, %d not ported", #monitorsOut, #monitorNotes))
print(string.format("window rules pinned to a monitor: %d ported", #windowRules))
print(string.format("workspace rules: %d ported", #workspaceRules))
print(string.format("personal binds: %d ported, %d already shipped, %d other lines left as comments", #binds, #skipped, #comments))
for _, c in ipairs(skipped) do print("  already in the shipped binds: " .. c) end
for _, n in ipairs(notPorted) do print("  not ported: " .. n.where .. ": " .. n.what) end
