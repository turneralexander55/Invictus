-- Tests for the Lua Hyprland config: the loader (config/hypr/hyprland.lua),
-- the shipped modules (config/hypr/invictus/*.lua) and the user templates
-- (config/hypr/monitors.lua, user.lua).
--
-- Loads the real config against a mock `hl` that checks every call against
-- the Hyprland 0.56.2 API, then compares what it set with the old hyprlang
-- config kept in fixtures/. Run through run.sh.
--
-- usage: lua run.lua <repo root> <stubs> [keysyms.h] [fake-binds-out]

local repo, stubsPath, keysymsPath, fakeBindsOut = ...
assert(repo and stubsPath, "usage: lua run.lua <repo root> <stubs> [keysyms.h] [fake-binds-out]")
if keysymsPath == "" then keysymsPath = nil end

local here = repo .. "/tests/hyprland-lua"
local hyprDir = repo .. "/config/hypr"
-- The loader adds SHARED (where invictus-desktop installs the modules) in
-- front of package.path unless it is already there. Listing it after the
-- repo keeps the loader from moving it, so the repo's modules are tested
-- even on a machine that has the package installed.
local SHARED = "/usr/share/invictus/hypr/?.lua"
local basePath = package.path
package.path = here .. "/?.lua;" .. hyprDir .. "/?.lua;" .. SHARED .. ";" .. basePath

local api      = require("api")
local mock     = require("mock_hl")
local hyprlang = require("hyprlang")

-- ─── tiny test runner ───────────────────────────────────────────────────────

local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
    local problems = {}
    local function check(cond, msg)
        if not cond then table.insert(problems, msg) end
    end
    local ok, e = pcall(fn, check)
    if not ok then table.insert(problems, "error: " .. tostring(e)) end
    if #problems == 0 then
        passed = passed + 1
        print("ok    " .. name)
    else
        failed = failed + 1
        print("FAIL  " .. name)
        for _, p in ipairs(problems) do print("        " .. p) end
        table.insert(failures, name)
    end
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function deepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then
        if type(a) == "number" then return math.abs(a - b) < 1e-9 end
        return a == b
    end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function show(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for k, x in pairs(v) do table.insert(parts, tostring(k) .. "=" .. show(x)) end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- ─── load the config the way Hyprland does ─────────────────────────────────

local hl, state = mock.new({ stubs = stubsPath, keysyms = keysymsPath })
_G.hl = hl

-- Hyprland's require(), emulated (hyprrequire.lua, shared with invictus-doctor).
local realRequire = require
local hyprrequire = require("hyprrequire")
local function makeRequire(onRequire, onError)
    return hyprrequire.make(realRequire, onRequire, onError)
end

local requiredModules = {}
local moduleErrors = {}
_G.require = makeRequire(function(name) requiredModules[name] = true end,
                         function(e) table.insert(moduleErrors, e) end)

local mainChunk, loadErr = loadfile(hyprDir .. "/hyprland.lua")
local mainOk, mainErr = false, loadErr
if mainChunk then mainOk, mainErr = pcall(mainChunk) end
_G.require = realRequire

-- Run the autostart handlers, as Hyprland does once at start.
for _, cb in ipairs(state.events["hyprland.start"] or {}) do
    local ok, e = pcall(cb)
    if not ok then table.insert(moduleErrors, "hyprland.start handler: " .. tostring(e)) end
end

-- ─── old config (fixtures) ──────────────────────────────────────────────────

local fx = here .. "/fixtures/"
local old = {
    look     = hyprlang.parse(fx .. "aesthetics.conf"),
    input    = hyprlang.parse(fx .. "input-rules.conf"),
    env      = hyprlang.parse(fx .. "environment.conf"),
    auto     = hyprlang.parse(fx .. "autostart.conf"),
    vars     = hyprlang.parse(fx .. "variables.conf"),
    binds    = hyprlang.parse(fx .. "keybindings.conf"),
    rules    = hyprlang.parse(fx .. "window-rules.conf"),
}

local oldVars = {}
for k, v in pairs(old.vars.vars) do oldVars[k] = v end
for k, v in pairs(old.binds.vars) do oldVars[k] = trim(v) end

local function resolve(s)
    return (s:gsub("%$(%a[%w_]*)", function(name)
        if name == "HOME" then return "$HOME" end
        return oldVars[name] or ("$" .. name)
    end))
end

-- hyprlang value -> Lua value, shaped like the new value it is compared with
local BOOL = { ["true"] = true, yes = true, on = true, ["1"] = true,
               ["false"] = false, no = false, off = false, ["0"] = false }

local function parseGradient(s)
    local colors, angle = {}, nil
    for tok in s:gmatch("%S+") do
        local deg = tok:match("^(%-?[%d%.]+)deg$")
        if deg then angle = tonumber(deg) else table.insert(colors, tok) end
    end
    if #colors == 1 and not angle then return colors[1] end
    return { colors = colors, angle = angle }
end

local function convert(oldValue, like)
    local t = type(like)
    if t == "boolean" then
        local first = oldValue:match("^(%S+)")
        return BOOL[first:gsub(",$", "")]
    elseif t == "number" then
        return tonumber(oldValue)
    elseif t == "table" then
        if like.colors then return parseGradient(oldValue) end
        local a, b = oldValue:match("^(%S+)%s+(%S+)$")
        return { tonumber(a) or a, tonumber(b) or b }
    end
    return oldValue
end

-- ─── tests ──────────────────────────────────────────────────────────────────

test("config loads with no Lua errors", function(check)
    check(mainChunk ~= nil, "hyprland.lua does not compile: " .. tostring(loadErr))
    check(mainOk, "hyprland.lua raised: " .. tostring(mainErr))
    for _, e in ipairs(moduleErrors) do check(false, e) end
end)

test("every hl.* call is valid for the 0.56.2 API", function(check)
    for _, e in ipairs(state.errors) do check(false, e) end
end)

test("no API warnings", function(check)
    for _, w in ipairs(state.warnings) do check(false, w) end
end)

test("every module in invictus/ is loaded (core.lua requires the rest)", function(check)
    local p = io.popen('ls "' .. hyprDir .. '/invictus"')
    for file in p:lines() do
        local mod = file:match("^(.*)%.lua$")
        if mod then check(requiredModules["invictus." .. mod], "invictus/" .. file .. " is never required") end
    end
    p:close()
    check(requiredModules[hyprDir .. "/monitors.lua"], "monitors.lua next to hyprland.lua was not loaded")
    check(requiredModules[hyprDir .. "/user.lua"], "user.lua next to hyprland.lua was not loaded")
end)

-- The loader, run on its own in a scratch config dir with a stand-in core.
local function runLoader(dir, files)
    os.execute('rm -rf "' .. dir .. '" && mkdir -p "' .. dir .. '"')
    local src = assert(io.open(hyprDir .. "/hyprland.lua")):read("a")
    assert(io.open(dir .. "/hyprland.lua", "w")):write(src):close()
    for name, body in pairs(files) do assert(io.open(dir .. "/" .. name, "w")):write(body):close() end
    _G.LOADER_LOG = {}
    local errors = {}
    local savedPath, savedRequire = package.path, _G.require
    package.path = basePath
    _G.require = makeRequire(function() end, function(e) table.insert(errors, e) end)
    package.preload["invictus.core"] = function() table.insert(LOADER_LOG, "core"); return true end
    local results = {}
    for run = 1, 2 do -- a config reload runs the file again in the same Lua state
        for name in pairs(package.loaded) do
            if name == "invictus.core" or name:sub(1, #dir) == dir then package.loaded[name] = nil end
        end
        local ok, e = pcall(assert(loadfile(dir .. "/hyprland.lua")))
        results[run] = { ok = ok, err = e, path = package.path, log = LOADER_LOG }
        _G.LOADER_LOG = {}
    end
    package.preload["invictus.core"] = nil
    package.loaded["invictus.core"] = nil
    package.path, _G.require = savedPath, savedRequire
    os.execute('rm -rf "' .. dir .. '"')
    return results, errors
end

local scratch = os.tmpname()
os.remove(scratch)

test("loader: shared module path goes first, once, even after reloads", function(check)
    local r = runLoader(scratch, {})
    for run = 1, 2 do
        check(r[run].ok, "run " .. run .. " raised: " .. tostring(r[run].err))
        check(r[run].path:sub(1, #SHARED + 1) == SHARED .. ";", "run " .. run .. ": package.path starts " .. r[run].path:sub(1, 40))
        local _, n = r[run].path:gsub(SHARED:gsub("%p", "%%%0"), "")
        check(n == 1, "run " .. run .. ": shared path listed " .. n .. " times")
    end
end)

test("loader: loads core, then monitors.lua, then user.lua (user wins)", function(check)
    local r, errs = runLoader(scratch, {
        ["monitors.lua"] = 'table.insert(LOADER_LOG, "monitors")',
        ["user.lua"]     = 'table.insert(LOADER_LOG, "user")',
    })
    for run = 1, 2 do
        check(r[run].ok, "run " .. run .. " raised: " .. tostring(r[run].err))
        check(deepEqual(r[run].log, { "core", "monitors", "user" }), "run " .. run .. " order " .. show(r[run].log))
    end
    for _, e in ipairs(errs) do check(false, e) end
end)

test("loader: runs with no monitors.lua or user.lua", function(check)
    local r, errs = runLoader(scratch, {})
    check(r[1].ok, "raised: " .. tostring(r[1].err))
    check(deepEqual(r[1].log, { "core" }), "order " .. show(r[1].log))
    for _, e in ipairs(errs) do check(false, e) end
end)

test("loader: an error in user.lua is reported and does not stop the config", function(check)
    local r, errs = runLoader(scratch, { ["user.lua"] = 'error("boom")' })
    check(r[1].ok, "raised: " .. tostring(r[1].err))
    check(deepEqual(r[1].log, { "core" }), "order " .. show(r[1].log))
    check(#errs >= 1 and errs[1]:match("boom"), "error not reported: " .. show(errs))
end)

test("loader: five lines, as the design says", function(check)
    local n = 0
    for _ in io.lines(hyprDir .. "/hyprland.lua") do n = n + 1 end
    check(n == 5, "hyprland.lua has " .. n .. " lines")
end)

test("keysym names checked against xkbcommon (skipped names count as fail)", function(check)
    check(state.keysymsChecked, "xkbcommon-keysyms.h not found; key names only checked for ESC/Enter")
end)

-- Old dispatcher + arg -> the dispatcher the Lua config should use.
local function expectedDispatcher(name, arg)
    arg = arg and trim(arg) or ""
    local dir = { l = "left", r = "right", u = "up", d = "down" }
    local function num(s) return tonumber(s) or s end
    if name == "exec" then return { "exec_cmd", resolve(arg) } end
    if name == "killactive" then return { "window.close" } end
    if name == "togglefloating" then return { "window.float", { action = "toggle" } } end
    if name == "fullscreen" then return { "window.fullscreen" } end
    if name == "togglesplit" then return { "layout", "togglesplit" } end
    if name == "movefocus" then return { "focus", { direction = dir[arg] } } end
    if name == "workspace" then return { "focus", { workspace = num(arg) } } end
    if name == "movetoworkspace" then return { "window.move", { workspace = num(arg) } } end
    if name == "movewindow" and arg ~= "" then return { "window.move", { direction = dir[arg] } } end
    if name == "movewindow" then return { "window.drag" } end
    if name == "resizewindow" then return { "window.resize" } end
    if name == "togglespecialworkspace" then return { "workspace.toggle_special", arg } end
    return { "UNMAPPED:" .. name }
end

local function actualDispatcher(d)
    if type(d) == "function" then return { "<lua function>" } end
    local out = { d.__dispatcher }
    for i = 1, d.args.n do out[i + 1] = d.args[i] end
    return out
end

local FLAGS = { bind = {}, bindl = { locked = true }, bindel = { locked = true, repeating = true },
                binde = { repeating = true }, bindm = { mouse = true } }

-- Deliberate changes, each listed in the hand-back report.
local EXCEPTIONS = {
    -- hyprctl dispatch takes Lua now
    ["64+delete"] = function(exp)
        exp[2] = exp[2]:gsub("hyprctl dispatch exit", "hyprctl dispatch 'hl.dsp.exit()'")
        return exp
    end,
    -- hyprctl keyword is gone; the layout toggle is a Lua function
    ["72+space"] = function() return { "<lua function>" } end,
    -- the repo is called invictus now; the deployed copy is rewritten for other clone paths
    ["64+slash"] = function() return { "exec_cmd", "$HOME/invictus/scripts/show-keybindings.sh" } end,
    ["64+f1"] = function() return { "exec_cmd", "$HOME/invictus/scripts/show-keybindings.sh" } end,
    -- power off now asks first: the bind runs scripts/confirm-poweroff.sh (rofi yes/no, default No)
    ["76+escape"] = function() return { "exec_cmd", "$HOME/invictus/scripts/confirm-poweroff.sh" } end,
}
local KEY_RENAMES = { ESC = "Escape" } -- ESC is not an xkb keysym; the old bind never fired
-- Old binds deliberately left out of the port. Empty now: the power-off bind is back
-- (Alex, 2026-09-30) with a confirm step, so it is an EXCEPTION above instead.
local DISABLED = {}

test("every old keybind exists with the same keys, action and flags", function(check)
    local byCombo = {}
    for _, b in ipairs(state.binds) do
        local combo = b.modmask .. "+" .. b.key:lower()
        check(byCombo[combo] == nil, "two binds on " .. b.keys)
        byCombo[combo] = b
    end

    local seen = {}
    local oldCount = 0
    for _, kw in ipairs(old.binds.keywords) do
        if kw.kind:match("^bind") then
            oldCount = oldCount + 1
            local p = hyprlang.split(kw.value, 4)
            local mask = 0
            for m in resolve(p[1]):gmatch("%S+") do mask = mask | (api.modifiers[m] or 0) end
            local key = KEY_RENAMES[p[2]] or p[2]
            local combo = mask .. "+" .. key:lower()
            local b = byCombo[combo]
            if DISABLED[p[4] or ""] then
                check(b == nil, "disabled bind is active: " .. kw.value)
            elseif not b then
                check(false, "missing bind: " .. kw.kind .. " = " .. kw.value)
            else
                seen[combo] = true
                local exp = expectedDispatcher(p[3], p[4])
                if EXCEPTIONS[combo] then exp = EXCEPTIONS[combo](exp) end
                local got = actualDispatcher(b.dispatcher)
                check(deepEqual(exp, got), b.keys .. ": expected " .. show(exp) .. ", got " .. show(got))
                local flags = {}
                for k, v in pairs(b.opts) do if k ~= "description" and v then flags[k] = true end end
                check(deepEqual(FLAGS[kw.kind], flags),
                    b.keys .. ": flags " .. show(flags) .. ", old " .. kw.kind .. " wants " .. show(FLAGS[kw.kind]))
            end
        end
    end
    check(oldCount == 67, "expected 67 binds in the old keybindings.conf, found " .. oldCount)
    for combo, b in pairs(byCombo) do
        check(seen[combo], "new bind not in the old config: " .. b.keys)
    end
end)

test("every bind has a 'Section: action' description", function(check)
    for _, b in ipairs(state.binds) do
        local d = b.opts.description
        check(type(d) == "string" and d:match("^[%w &/]+: %S"), b.keys .. ": description " .. tostring(d))
    end
end)

test("layout toggle bind switches master <-> dwindle", function(check)
    local toggle
    for _, b in ipairs(state.binds) do
        if b.keys == "SUPER + ALT + SPACE" then toggle = b.dispatcher end
    end
    check(type(toggle) == "function", "SUPER + ALT + SPACE is not a Lua function")
    if type(toggle) ~= "function" then return end
    check(state.config["general.layout"] == "master", "starts on master")
    local before = #state.errors
    toggle()
    check(state.config["general.layout"] == "dwindle", "first press gives dwindle, got " .. tostring(state.config["general.layout"]))
    toggle()
    check(state.config["general.layout"] == "master", "second press gives master, got " .. tostring(state.config["general.layout"]))
    check(#state.errors == before, "toggle raised API errors")
end)

-- Config keys whose old value intentionally differs or is gone.
local KEY_CHANGES = {
    ["dwindle.pseudotile"]    = "removed", -- removed in 0.55
    ["general.allow_tearing"] = true,      -- gaming addition (invictus/gaming.lua)
}

local function compareSections(check, parsed, label)
    for key, oldValue in pairs(parsed.config) do
        local change = KEY_CHANGES[key]
        local newValue = state.config[key]
        if change == "removed" then
            check(newValue == nil, key .. " was removed in 0.55 but is still set")
            check(state.stubs.configTypes[key] == nil, key .. " exists in 0.56.2 after all")
        elseif change ~= nil then
            check(deepEqual(newValue, change), key .. ": expected changed value " .. show(change) .. ", got " .. show(newValue))
        else
            check(newValue ~= nil, label .. ": " .. key .. " (= " .. oldValue .. ") not set in Lua")
            if newValue ~= nil then
                local want = convert(oldValue, newValue)
                check(deepEqual(want, newValue), key .. ": old " .. oldValue .. " -> want " .. show(want) .. ", got " .. show(newValue))
            end
        end
    end
end

test("look: general, master, decoration, dwindle, misc match aesthetics.conf", function(check)
    compareSections(check, old.look, "aesthetics.conf")
end)

test("input and cursor settings match input-rules.conf / environment.conf", function(check)
    local inputOnly = { config = {} }
    for k, v in pairs(old.input.config) do inputOnly.config[k] = v end
    compareSections(check, inputOnly, "input-rules.conf")
    compareSections(check, old.env, "environment.conf")
end)

test("curves and animations match aesthetics.conf", function(check)
    local oldCurves, oldAnims = 0, 0
    for _, kw in ipairs(old.look.keywords) do
        if kw.kind == "bezier" then
            oldCurves = oldCurves + 1
            local p = hyprlang.split(kw.value)
            local c = state.curves[p[1]]
            local want = { type = "bezier", points = { { tonumber(p[2]), tonumber(p[3]) }, { tonumber(p[4]), tonumber(p[5]) } } }
            check(deepEqual(c, want), "curve " .. p[1] .. ": want " .. show(want) .. ", got " .. show(c))
        elseif kw.kind == "animation" then
            oldAnims = oldAnims + 1
            local p = hyprlang.split(kw.value)
            local found
            for _, a in ipairs(state.animations) do if a.leaf == p[1] then found = a end end
            local want = { leaf = p[1], enabled = p[2] == "1", speed = tonumber(p[3]), bezier = p[4], style = p[5] }
            check(deepEqual(found, want), "animation " .. p[1] .. ": want " .. show(want) .. ", got " .. show(found))
        end
    end
    check(oldCurves == 5 and oldAnims == 17, "fixture counts changed: " .. oldCurves .. " curves, " .. oldAnims .. " animations")
    check(#state.animations == oldAnims, "animation count " .. #state.animations .. " vs old " .. oldAnims)
end)

test("gesture and per-device settings match input-rules.conf", function(check)
    local g
    for _, kw in ipairs(old.input.keywords) do if kw.kind == "gesture" then g = hyprlang.split(kw.value) end end
    check(#state.gestures == 1, "expected one gesture, got " .. #state.gestures)
    check(deepEqual(state.gestures[1], { fingers = tonumber(g[1]), direction = g[2], action = g[3] }),
        "gesture: " .. show(state.gestures[1]))
    local d = old.input.devices[1]
    check(#state.devices == 1 and state.devices[1].name == d.name and state.devices[1].sensitivity == tonumber(d.sensitivity),
        "device: " .. show(state.devices[1]))
end)

test("environment variables match environment.conf", function(check)
    local n = 0
    for _, kw in ipairs(old.env.keywords) do
        if kw.kind == "env" then
            n = n + 1
            local name, value = kw.value:match("^([^,]+),(.*)$")
            check(state.env[trim(name)] == trim(value), "env " .. name .. ": got " .. tostring(state.env[trim(name)]))
        end
    end
    local m = 0
    for _ in pairs(state.env) do m = m + 1 end
    check(n == m, "env count " .. m .. " vs old " .. n)
end)

-- Old autostart commands deliberately dropped (design 1.2).
local REMOVED_EXECS = {
    mako = true, -- second notification daemon; swaync stays
}

test("autostart runs the same commands as autostart.conf, once at start", function(check)
    local want = {}
    for _, kw in ipairs(old.auto.keywords) do
        local cmd = trim((kw.value:gsub("%s*&%s*$", "")))
        if kw.kind == "exec-once" and not REMOVED_EXECS[cmd] then table.insert(want, cmd) end
    end
    for cmd in pairs(REMOVED_EXECS) do
        for _, got in ipairs(state.execs) do check(got ~= cmd, cmd .. " is still autostarted") end
    end
    check(deepEqual(want, state.execs), "want " .. show(want) .. ", got " .. show(state.execs))
    local handlers = 0
    for ev, list in pairs(state.events) do
        check(ev == "hyprland.start", "unexpected event handler: " .. ev)
        handlers = handlers + #list
    end
    check(handlers == 1, "expected one hyprland.start handler, got " .. handlers)
end)

-- windowrule/layerrule block -> the Lua spec it should become
local function oldRuleToSpec(block)
    local spec = { match = {} }
    for k, v in pairs(block) do
        if k ~= "__kind" then
            local m = k:match("^match:(.+)$")
            if m then
                if BOOL[v] ~= nil and (v == "true" or v == "false") then spec.match[m] = BOOL[v] else spec.match[m] = v end
            elseif k == "name" then
                spec.name = v
            else
                spec[k] = v
            end
        end
    end
    return spec
end

local function compareRules(check, oldBlocks, newRules, kind)
    local byName = {}
    for _, r in ipairs(newRules) do if r.name then byName[r.name] = r end end
    for _, block in ipairs(oldBlocks) do
        local want = oldRuleToSpec(block)
        local got = byName[want.name]
        check(got ~= nil, kind .. " '" .. tostring(want.name) .. "' missing")
        if got then
            check(deepEqual(want.match, got.match), want.name .. ": match " .. show(got.match) .. " vs old " .. show(want.match))
            for k, v in pairs(want) do
                if k ~= "match" and k ~= "name" then
                    local conv = convert(v, got[k] ~= nil and got[k] or "")
                    check(got[k] ~= nil and deepEqual(conv, got[k]), want.name .. "." .. k .. ": old " .. v .. ", got " .. show(got[k]))
                end
            end
            for k in pairs(got) do
                check(k == "match" or k == "name" or want[k] ~= nil, want.name .. ": extra effect " .. k)
            end
        end
    end
end

test("window rules match window-rules.conf", function(check)
    local gamingRule = {}
    for _, r in ipairs(state.windowRules) do
        if r.name and (r.name:match("^game%-") or r.name:match("^steam%-toasts")) then gamingRule[r.name] = true end
    end
    local plain = {}
    for _, r in ipairs(state.windowRules) do if not gamingRule[r.name] then table.insert(plain, r) end end
    check(#plain == #old.rules.windowRules, "rule count " .. #plain .. " vs old " .. #old.rules.windowRules)
    compareRules(check, old.rules.windowRules, plain, "windowrule")
end)

test("layer rules match window-rules.conf", function(check)
    check(#state.layerRules == #old.rules.layerRules, "layer rule count")
    compareRules(check, old.rules.layerRules, state.layerRules, "layerrule")
end)

test("gaming: VRR for fullscreen games, tearing allowed, direct scanout auto", function(check)
    check(state.config["misc.vrr"] == 3, "misc.vrr = " .. tostring(state.config["misc.vrr"]))
    check(state.config["general.allow_tearing"] == true, "general.allow_tearing not true")
    check(state.config["render.direct_scanout"] == 2, "render.direct_scanout = " .. tostring(state.config["render.direct_scanout"]))
    check(state.config["cursor.no_break_fs_vrr"] == nil, "no_break_fs_vrr should stay at its default (2)")
end)

test("gaming: Steam games and gamescope are marked as games and may tear", function(check)
    -- The small RE2 subset the rules use, as a Lua pattern
    local function luaPattern(re)
        local out = re:gsub("[%(%)]", "")
        out = out:gsub("%-", "%%-"):gsub("\\d", "%%d")
        return out
    end
    -- Effects a window of this class ends up with: every rule whose class
    -- matches contributes, later rules win (other match props ignored).
    local function ruleFor(class)
        local merged, any = {}, false
        for _, r in ipairs(state.windowRules) do
            local pat = r.match.class
            if pat and class:match(luaPattern(pat)) then
                any = true
                for k, v in pairs(r) do
                    if k ~= "match" and k ~= "name" then merged[k] = v end
                end
            end
        end
        return any and merged or nil
    end
    for _, class in ipairs({ "steam_app_1091500", "gamescope" }) do
        local r = ruleFor(class)
        check(r ~= nil, "no rule matches " .. class)
        if r then
            check(r.content == "game", class .. ": content " .. tostring(r.content))
            check(r.immediate == true, class .. ": immediate not set")
            check(r.opaque == true, class .. ": opaque not set")
            check(r.idle_inhibit == "fullscreen", class .. ": idle_inhibit " .. tostring(r.idle_inhibit))
        end
    end
    local steamClient = ruleFor("steam")
    check(steamClient and steamClient.immediate == nil and steamClient.content == nil,
        "the Steam client itself must not be marked as a game")
    local byContent
    for _, r in ipairs(state.windowRules) do if r.match.content == "game" then byContent = r end end
    check(byContent and byContent.immediate == true, "no rule for self-declared game content")
end)

-- ─── every command the config runs is installed by a meta package ──────────

-- Executable -> package that provides it. false = not packaged yet, with why.
local COMMAND_PACKAGES = {
    kitty = "kitty", yazi = "yazi", rofi = "rofi", ["zen-browser"] = "zen-browser-bin",
    hyprlock = "hyprlock", zeditor = "zed", thunar = "thunar", discord = "discord",
    steam = "steam", hyprshot = "hyprshot", wpctl = "wireplumber",
    brightnessctl = "brightnessctl", playerctl = "playerctl",
    xwaylandvideobridge = "xwaylandvideobridge", systemctl = "systemd",
    hyprpolkitagent = "hyprpolkitagent", ["wl-paste"] = "wl-clipboard", cliphist = "cliphist",
    ["/usr/lib/xdg-desktop-portal-hyprland"] = "xdg-desktop-portal-hyprland",
    ["/usr/lib/xdg-desktop-portal"] = "xdg-desktop-portal",
    swaync = "swaync", hyprpaper = "hyprpaper", hypridle = "hypridle", waybar = "waybar",
    hyprctl = "hyprland",
    hyprshutdown = false,  -- optional: the bind checks `command -v` first
    ["$HOME/invictus/scripts/show-keybindings.sh"] = false, -- repo script; invictus-tools in Phase 1
    ["$HOME/invictus/scripts/confirm-poweroff.sh"] = false, -- same
    ["~/.local/bin/dashboard-tmux"] = false, -- Alex's own script, not in the repo
    ["/usr/lib/invictus/show-keybindings"] = "invictus-tools",
    ["/usr/lib/invictus/confirm-poweroff"] = "invictus-tools",
}
-- Pulled in by every Arch install, so no meta lists them.
local BASE_SYSTEM = { systemd = true }

local function executables(cmd)
    local out = {}
    cmd = cmd:gsub("%d*>&%d+", ""):gsub("%d*>%s*%S+", "") -- drop redirections (2>&1, >/dev/null)
    for seg in (cmd .. ";"):gmatch("(.-)%s*[;|&]+%s*") do
        local words = {}
        for w in seg:gmatch("%S+") do table.insert(words, w) end
        if words[1] == "command" and words[2] == "-v" then
            table.insert(out, words[3])
        elseif words[1] then
            table.insert(out, words[1])
            for i, w in ipairs(words) do
                if w == "-e" and words[i + 1] then table.insert(out, words[i + 1]) end
                if w == "start" and words[1] == "systemctl" and words[i + 1] then table.insert(out, words[i + 1]) end
            end
        end
    end
    return out
end

test("every command the config runs comes from a meta package in pkgs/meta", function(check)
    local provided = {}
    local p = io.popen('for f in "' .. repo .. '"/pkgs/meta/*/PKGBUILD; do '
        .. 'bash -c \'source "$1"; printf "%s\\n" "${depends[@]}"\' _ "$f"; done')
    for dep in p:lines() do provided[dep] = true end
    p:close()
    check(next(provided) ~= nil, "no depends read from pkgs/meta/*/PKGBUILD")
    local cmds = {}
    for _, c in ipairs(state.execs) do table.insert(cmds, c) end
    for _, b in ipairs(state.binds) do
        local d = b.dispatcher
        if type(d) == "table" and d.__dispatcher == "exec_cmd" then table.insert(cmds, d.args[1]) end
    end
    local seen = 0
    for _, c in ipairs(cmds) do
        for _, exe in ipairs(executables(c)) do
            seen = seen + 1
            local pkg = COMMAND_PACKAGES[exe]
            if pkg == nil then
                check(false, "'" .. exe .. "' (from: " .. c .. ") has no entry in COMMAND_PACKAGES")
            elseif pkg and not provided[pkg] and not BASE_SYSTEM[pkg] then
                check(false, "'" .. exe .. "' needs package " .. pkg .. ", which no meta depends on")
            end
        end
    end
    check(seen > 30, "only " .. seen .. " commands found; parsing broke?")
end)

-- ─── fake `hyprctl binds` output for the show-keybindings test ──────────────

if fakeBindsOut and fakeBindsOut ~= "" then
    local f = assert(io.open(fakeBindsOut, "w"))
    local ref = 10
    for _, b in ipairs(state.binds) do
        ref = ref + 1
        local flags = ""
        if b.opts.locked then flags = flags .. "l" end
        if b.opts.repeating then flags = flags .. "e" end
        if b.opts.description then flags = flags .. "d" end
        f:write(string.format("bind%s\n\tmodmask: %d\n\tsubmap: \n\tkey: %s\n\tkeycode: 0\n\tcatchall: false\n\tdescription: %s\n\tdispatcher: __lua\n\targ: %d\n\n",
            flags, b.modmask, b.key, b.opts.description or "", ref))
    end
    f:close()
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
