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

-- Hyprland's require(), emulated (hyprrequire.lua, shared with invictus-doctor).
local realRequire = require
local realGetenv = os.getenv
local hyprrequire = require("hyprrequire")
local function makeRequire(onRequire, onError)
    return hyprrequire.make(realRequire, onRequire, onError)
end

-- The environment the config sees. The suite never touches the real HOME:
-- every load runs with a scratch HOME, and the motion and game-mode files
-- point into it, so a machine that has a theme or a motion level set gives
-- the same results as a fresh one.
local SCRATCH_HOME = os.tmpname()
os.remove(SCRATCH_HOME)
os.execute('mkdir -p "' .. SCRATCH_HOME .. '/.config/invictus" "' .. SCRATCH_HOME .. '/run/invictus"')
local function writeFile(path, body)
    os.execute('mkdir -p "$(dirname "' .. path .. '")"')
    local f = assert(io.open(path, "w"))
    f:write(body)
    f:close()
end
local function removeFile(path) os.remove(path) end

-- Load the whole config the way Hyprland does, in a fresh mock, with some
-- environment variables overridden (a false value means unset). Returns the
-- mock's recorded state and how the load went.
local function loadConfig(over)
    over = over or {}
    local env = { HOME = SCRATCH_HOME, XDG_RUNTIME_DIR = SCRATCH_HOME .. "/run",
                  INVICTUS_MOTION_FILE = false, INVICTUS_GAMEMODE_FILE = false }
    for k, v in pairs(over) do env[k] = v end
    os.getenv = function(name)
        local v = env[name]
        if v == nil then return realGetenv(name) end
        return v or nil
    end
    -- Hyprland clears package.loaded on every reload
    for name in pairs(package.loaded) do
        if name:match("^invictus%.") or name:match("^/") or name:match("^~/") then package.loaded[name] = nil end
    end
    local L = { requiredModules = {}, moduleErrors = {} }
    local hlNew, st = mock.new({ stubs = stubsPath, keysyms = keysymsPath })
    L.hl, L.state = hlNew, st
    _G.hl = hlNew
    _G.require = makeRequire(function(name) L.requiredModules[name] = true end,
                             function(e) table.insert(L.moduleErrors, e) end)
    local chunk, loadErr = loadfile(hyprDir .. "/hyprland.lua")
    L.mainChunk, L.loadErr = chunk, loadErr
    L.mainOk, L.mainErr = false, loadErr
    if chunk then L.mainOk, L.mainErr = pcall(chunk) end
    -- Run the autostart handlers, as Hyprland does once at start.
    for _, cb in ipairs(st.events["hyprland.start"] or {}) do
        local ok, e = pcall(cb)
        if not ok then table.insert(L.moduleErrors, "hyprland.start handler: " .. tostring(e)) end
    end
    _G.require = realRequire
    os.getenv = realGetenv
    return L
end

local L0 = loadConfig({})
local state = L0.state
local requiredModules, moduleErrors = L0.requiredModules, L0.moduleErrors
local mainChunk, loadErr, mainOk, mainErr = L0.mainChunk, L0.loadErr, L0.mainOk, L0.mainErr

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
    -- log out now asks first: confirm.sh (rofi yes/no, default No) wraps the hyprshutdown-or-exit command
    ["64+delete"] = function()
        return { "exec_cmd", "/usr/lib/invictus/confirm \"Log out?\" -- sh -c \"command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'\"" }
    end,
    -- hyprctl keyword is gone; the layout toggle is a Lua function
    ["72+space"] = function() return { "<lua function>" } end,
    -- the cheatsheet is installed by invictus-tools now, not run from the clone
    ["64+slash"] = function() return { "exec_cmd", "/usr/lib/invictus/show-keybindings" } end,
    ["64+f1"] = function() return { "exec_cmd", "/usr/lib/invictus/show-keybindings" } end,
    -- power off now asks first: the bind runs confirm.sh (installed as /usr/lib/invictus/confirm)
    ["76+escape"] = function() return { "exec_cmd", "/usr/lib/invictus/confirm \"Power off?\" -- systemctl poweroff" } end,
}
-- Binds added since the hyprlang config, each with the dispatcher it must run.
-- Keyed like EXCEPTIONS: modmask + key (SUPER+SHIFT = 65).
local NEW_BINDS = {
    ["65+t"] = { "exec_cmd", "invictus-theme pick" }, -- Look: change theme (docs/look.md, The switcher)
    ["64+a"] = { "workspace.toggle_special", "cicero" }, -- Cicero: the panel (design 4.2; invictus/cicero.lua, AI set only)
}
local KEY_RENAMES = { ESC = "Escape" } -- ESC is not an xkb keysym; the old bind never fired
-- Old binds deliberately left out of the shipped config: Alex's own, not a friend's.
-- adopt.sh ports them into his user.lua (tests/pkgs/runtime.sh, hyprlang porter).
local DISABLED = { ["kitty --title dashboard -e ~/.local/bin/dashboard-tmux"] = true }
-- Old window rules left out for the same reason: they pin apps to Alex's monitors.
local PERSONAL_RULES = { ["discord-assign"] = true, ["zen-assign"] = true }

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
        local added = NEW_BINDS[combo]
        if added then
            check(deepEqual(actualDispatcher(b.dispatcher), added),
                b.keys .. ": expected " .. show(added) .. ", got " .. show(actualDispatcher(b.dispatcher)))
        else
            check(seen[combo], "new bind not in the old config or NEW_BINDS: " .. b.keys)
        end
    end
    for combo in pairs(NEW_BINDS) do check(byCombo[combo], "NEW_BINDS entry " .. combo .. " is not bound") end
end)

test("theme picker bind: Super+Shift+T, described 'Look: change theme'", function(check)
    local found
    for _, b in ipairs(state.binds) do if b.keys == "SUPER + SHIFT + T" then found = b end end
    check(found ~= nil, "SUPER + SHIFT + T is not bound")
    if found then check(found.opts.description == "Look: change theme", "description " .. tostring(found.opts.description)) end
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
-- A value here is the exact new value. The look ones come from docs/look.md
-- (Hyprland table); the colours are the Dusk fallbacks, Showcase level.
local KEY_CHANGES = {
    ["dwindle.pseudotile"]    = "removed", -- removed in 0.55
    ["general.allow_tearing"] = true,      -- gaming addition (invictus/gaming.lua)
    -- the look (docs/look.md, Surfaces > Hyprland)
    ["general.gaps_in"]                = 4,
    ["general.gaps_out"]               = 8,
    ["general.border_size"]            = 2,
    ["general.col.active_border"]      = { colors = { "rgb(E0A64B)", "rgb(F0C274)", "rgb(E0A64B)" }, angle = 45 },
    ["general.col.inactive_border"]    = "rgb(27241F)",
    ["decoration.rounding"]            = 8,
    ["decoration.active_opacity"]      = 1.0,
    ["decoration.inactive_opacity"]    = 1.0,
    ["decoration.shadow.range"]        = 16,
    ["decoration.shadow.render_power"] = 3,
    ["decoration.shadow.color"]        = "rgba(00000073)",
    ["decoration.blur.size"]           = 6,
    ["decoration.blur.passes"]         = 3,
    ["decoration.blur.vibrancy"]       = 0.1,
    ["misc.force_default_wallpaper"]   = 0,
    ["misc.disable_hyprland_logo"]     = true,
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

-- Old environment.conf values changed on purpose (docs/look.md, GTK, Qt, icons, cursor):
-- false = dropped (the theme tool sets the GTK look), a string = the new value.
local CHANGED_ENV = {
    GTK_THEME = false,
    XCURSOR_THEME = "capitaine-cursors",
    QT_QPA_PLATFORMTHEME = "qt6ct",
}

test("environment variables match environment.conf (except the look.md changes)", function(check)
    local n = 0
    for _, kw in ipairs(old.env.keywords) do
        if kw.kind == "env" then
            local name, value = kw.value:match("^([^,]+),(.*)$")
            name, value = trim(name), trim(value)
            local want = CHANGED_ENV[name]
            if want == nil then want = value end
            if want ~= false then n = n + 1 end
            check(state.env[name] == (want or nil), "env " .. name .. ": got " .. tostring(state.env[name]))
        end
    end
    local m = 0
    for _ in pairs(state.env) do m = m + 1 end
    check(n == m, "env count " .. m .. " vs expected " .. n)
end)

-- Old autostart commands deliberately dropped (design 1.2).
local REMOVED_EXECS = {
    mako = true, -- second notification daemon; swaync stays
}
-- Old autostart commands that now run behind another step (docs/look.md, Themes:
-- `invictus-theme apply` runs once at session start, before waybar).
local WRAPPED_EXECS = {
    waybar = "invictus-theme apply; waybar",
}
-- New at the end of the start handler, in this order (each with its reason).
local ADDED_EXECS = {
    "invictus-first-boot start --if-pending", -- first start (design.md 2.3), once per person
}

test("autostart runs the same commands as autostart.conf (plus first start), once at start", function(check)
    local want = {}
    for _, kw in ipairs(old.auto.keywords) do
        local cmd = trim((kw.value:gsub("%s*&%s*$", "")))
        if kw.kind == "exec-once" and not REMOVED_EXECS[cmd] then table.insert(want, WRAPPED_EXECS[cmd] or cmd) end
    end
    for _, cmd in ipairs(ADDED_EXECS) do table.insert(want, cmd) end
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
        if r.name and (r.name:match("^game%-") or r.name:match("^steam%-toasts") or r.name:match("^cicero%-")) then gamingRule[r.name] = true end
    end
    local plain = {}
    for _, r in ipairs(state.windowRules) do if not gamingRule[r.name] then table.insert(plain, r) end end
    local shipped = {}
    for _, block in ipairs(old.rules.windowRules) do
        if PERSONAL_RULES[block.name] then
            for _, r in ipairs(plain) do check(r.name ~= block.name, block.name .. " is machine-specific and must not ship") end
        else
            table.insert(shipped, block)
        end
    end
    for _, r in ipairs(plain) do check(r.monitor == nil, "rule " .. tostring(r.name) .. " pins a monitor") end
    check(#plain == #shipped, "rule count " .. #plain .. " vs old " .. #shipped)
    compareRules(check, shipped, plain, "windowrule")
end)

-- The old config had one layer rule, "rofi" (blur, dim_around). The look adds
-- blur + ignore_alpha 0.3 for every panel on the wallpaper (docs/look.md),
-- no_anim for swaync (it animates itself) and the theme-switch veil, and the
-- Showcase-only layer animations from motion.lua. Kept exact: any other layer
-- rule, or any other effect, fails.
local function layerRule(L, name)
    for _, r in ipairs(L.state.layerRules) do if r.name == name then return r end end
end

test("layer rules: the old rofi rule, plus the look's blur and no_anim rules", function(check)
    local want = {
        waybar                        = { blur = true, ignore_alpha = 0.3 },
        rofi                          = { blur = true, ignore_alpha = 0.3, dim_around = true },
        ["swaync-notification-window"] = { blur = true, ignore_alpha = 0.3, no_anim = true },
        ["swaync-control-center"]     = { blur = true, ignore_alpha = 0.3, no_anim = true },
        ["cicero-panel"]              = { blur = true, ignore_alpha = 0.3 },
        ["invictus-veil"]             = { no_anim = true },
        ["motion-waybar"]             = { animation = "slide top" },
        ["motion-cicero-panel"]       = { animation = "slide right" },
    }
    local n = 0
    for name, effects in pairs(want) do
        n = n + 1
        local r = layerRule(L0, name)
        check(r ~= nil, "layer rule '" .. name .. "' missing")
        if r then
            local ns = name:gsub("^motion%-", "")
            check(deepEqual(r.match, { namespace = ns }), name .. ": match " .. show(r.match))
            local got = {}
            for k, v in pairs(r) do if k ~= "name" and k ~= "match" then got[k] = v end end
            check(deepEqual(got, effects), name .. ": effects " .. show(got) .. ", want " .. show(effects))
        end
    end
    check(#state.layerRules == n, "layer rule count " .. #state.layerRules .. ", expected " .. n)
    -- the old rofi rule is still there with its old effects
    local oldRofi = old.rules.layerRules[1]
    check(oldRofi and oldRofi.blur == "on" and oldRofi.dim_around == "on" and oldRofi.name == "rofi", "fixture changed")
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
    ["invictus-theme"] = "invictus-tools",
    ["invictus-first-boot"] = "invictus-tools",
    hyprshutdown = "hyprshutdown", -- optional at runtime: the bind checks `command -v` first
    ["/usr/lib/invictus/show-keybindings"] = "invictus-tools",
    ["/usr/lib/invictus/confirm"] = "invictus-tools",
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

-- ─── the look: values from docs/look.md ─────────────────────────────────────

local function configOf(L) return L.state.config end
local function noProblems(L, check)
    check(L.mainOk, "config raised: " .. tostring(L.mainErr))
    for _, e in ipairs(L.moduleErrors) do check(false, e) end
    for _, e in ipairs(L.state.errors) do check(false, e) end
    for _, w in ipairs(L.state.warnings) do check(false, w) end
end

local DUSK = { night = "rgb(14120F)", stone = "rgb(27241F)", line = "rgb(3A352D)", marble = "rgb(ECE6DA)",
               sol = "rgb(E0A64B)", sol_bright = "rgb(F0C274)" }

test("look (Dusk fallback, Showcase): every value in the Hyprland table of docs/look.md", function(check)
    local cfg = configOf(L0)
    local want = {
        ["general.gaps_in"] = 4, ["general.gaps_out"] = 8, ["general.border_size"] = 2,
        ["general.col.active_border"] = { colors = { DUSK.sol, DUSK.sol_bright, DUSK.sol }, angle = 45 },
        ["general.col.inactive_border"] = DUSK.stone,
        ["general.layout"] = "master", ["general.resize_on_border"] = false,
        ["decoration.rounding"] = 8, ["decoration.rounding_power"] = 2,
        ["decoration.active_opacity"] = 1.0, ["decoration.inactive_opacity"] = 1.0,
        ["decoration.dim_inactive"] = true, ["decoration.dim_strength"] = 0.12,
        ["decoration.shadow.enabled"] = true, ["decoration.shadow.range"] = 16,
        ["decoration.shadow.render_power"] = 3, ["decoration.shadow.color"] = "rgba(00000073)",
        ["decoration.shadow.color_inactive"] = "rgba(00000000)",
        ["decoration.blur.enabled"] = true, ["decoration.blur.size"] = 6, ["decoration.blur.passes"] = 3,
        ["decoration.blur.noise"] = 0.015, ["decoration.blur.vibrancy"] = 0.1,
        ["decoration.blur.new_optimizations"] = true, ["decoration.blur.xray"] = false,
        ["group.col.border_active"] = DUSK.sol, ["group.col.border_inactive"] = DUSK.stone,
        ["group.groupbar.font_family"] = "IBM Plex Sans", ["group.groupbar.font_size"] = 12,
        ["group.groupbar.col.active"] = DUSK.sol, ["group.groupbar.col.inactive"] = DUSK.line,
        ["group.groupbar.text_color"] = DUSK.marble,
        ["misc.disable_hyprland_logo"] = true, ["misc.disable_splash_rendering"] = true,
        ["misc.force_default_wallpaper"] = 0, ["misc.background_color"] = DUSK.night,
        ["misc.focus_on_activate"] = false,
    }
    for key, v in pairs(want) do
        check(deepEqual(cfg[key], v), key .. ": want " .. show(v) .. ", got " .. show(cfg[key]))
    end
    -- unchanged: the cursor fix from 0a579b7 is not touched by the look
    check(cfg["cursor.no_hardware_cursors"] == 0 or cfg["cursor.no_hardware_cursors"] == nil
        or type(cfg["cursor.no_hardware_cursors"]) ~= "table", "cursor.no_hardware_cursors changed shape")
end)

-- Motion levels are picked by a one-word state file.
local function withLevel(word, extra)
    local file = SCRATCH_HOME .. "/level"
    if word then writeFile(file, word) else removeFile(file) end
    local env = { INVICTUS_MOTION_FILE = file }
    for k, v in pairs(extra or {}) do env[k] = v end
    local L = loadConfig(env)
    removeFile(file)
    return L
end

test("motion: no state file, and unreadable ones, mean Showcase", function(check)
    for _, word in ipairs({ false, "", "\n", "garbage", "showcase extra words", "ON" }) do
        local L = withLevel(word)
        noProblems(L, check)
        check(configOf(L)["animations.enabled"] == true and #L.state.animations > 10,
            "level file " .. show(word) .. ": not Showcase")
        local bo = L.state.config["general.col.active_border"]
        check(type(bo) == "table", "level file " .. show(word) .. ": no glint gradient")
    end
end)

-- The Motion table of docs/look.md, typed here on its own so the config is
-- checked against the spec and not against itself. { speed, curve, style }; false = off.
local SPEC = {
    showcase = {
        global = { 1.5, "snap" }, windowsIn = { 2.6, "rise", "popin 88%" }, windowsOut = { 1.4, "sink", "popin 92%" },
        windowsMove = { 1.5, "snap" }, fadeIn = { 1.6, "glide" }, fadeOut = { 1.2, "linear" },
        fadeSwitch = { 1.2, "glide" }, fadeShadow = { 1.5, "glide" }, fadeDim = { 1.5, "glide" },
        border = { 1.2, "glide" }, borderangle = { 3, "unveil", "once" },
        layersIn = { 1.8, "snap", "popin 94%" }, layersOut = { 1.2, "sink", "fade" },
        fadeLayersIn = { 1.6, "glide" }, fadeLayersOut = { 1.0, "linear" },
        fadePopupsIn = { 1.0, "glide" }, fadePopupsOut = { 0.8, "linear" },
        workspaces = { 2.8, "glide", "slidefade 12%" }, specialWorkspace = { 2.6, "glide", "slidefadevert 16%" },
        zoomFactor = { 2.5, "glide" }, monitorAdded = { 6, "unveil" }, fadeDpms = { 3, "glide" },
    },
    calm = {
        global = { 1.2, "snap" }, windowsIn = { 1.8, "glide", "popin 96%" }, windowsOut = { 1.0, "sink", "popin 96%" },
        windowsMove = { 1.2, "snap" }, fadeIn = { 1.2, "glide" }, fadeOut = { 1.0, "linear" },
        fadeSwitch = { 1.2, "glide" }, fadeShadow = { 1.2, "glide" }, fadeDim = { 1.2, "glide" },
        border = { 1.2, "glide" }, borderangle = false,
        layersIn = { 1.2, "glide", "fade" }, layersOut = { 1.0, "linear", "fade" },
        fadeLayersIn = { 1.2, "glide" }, fadeLayersOut = { 1.0, "linear" },
        fadePopupsIn = { 1.0, "glide" }, fadePopupsOut = { 0.8, "linear" },
        workspaces = { 1.8, "glide", "fade" }, specialWorkspace = { 1.8, "glide", "fade" },
        zoomFactor = { 1.5, "glide" }, monitorAdded = false, fadeDpms = { 2, "glide" },
    },
}
local CURVES = {
    snap = { { 0.2, 0.9 }, { 0.1, 1 } }, glide = { { 0.25, 1 }, { 0.5, 1 } }, rise = { { 0.3, 1.5 }, { 0.6, 1 } },
    unveil = { { 0.16, 1 }, { 0.3, 1 } }, sink = { { 0.4, 0 }, { 1, 1 } }, linear = { { 0, 0 }, { 1, 1 } },
}

for _, level in ipairs({ "showcase", "calm" }) do
    test("motion " .. level .. ": every leaf, speed, curve and style matches the spec table", function(check)
        local L = withLevel(level)
        noProblems(L, check)
        check(configOf(L)["animations.enabled"] == true, "animations.enabled is not true")
        local got, n = {}, 0
        for _, a in ipairs(L.state.animations) do
            check(got[a.leaf] == nil, "leaf " .. a.leaf .. " set twice")
            got[a.leaf] = a
            n = n + 1
        end
        local want = 0
        for leaf, spec in pairs(SPEC[level]) do
            want = want + 1
            local a = got[leaf]
            check(a ~= nil, "leaf " .. leaf .. " missing")
            if a then
                if spec then
                    check(a.enabled == true and a.speed == spec[1] and a.bezier == spec[2] and a.style == spec[3],
                        leaf .. ": " .. show(a) .. ", want " .. show(spec))
                else
                    check(a.enabled == false, leaf .. " should be off in " .. level .. ", got " .. show(a))
                end
                check(a.spring == nil, leaf .. ": springs are not used")
            end
        end
        check(n == want, n .. " leaves set, spec has " .. want)
        for name, pts in pairs(CURVES) do
            local c = L.state.curves[name]
            check(deepEqual(c, { type = "bezier", points = pts }), "curve " .. name .. ": " .. show(c))
        end
        -- Rule 2: nothing loops. Rule 1 (retargeting) is Hyprland's own.
        for _, a in ipairs(L.state.animations) do
            check(not tostring(a.style):match("loop"), a.leaf .. " uses a looping style")
        end
    end)
end

test("motion: the timing budget (Showcase everyday <= 150 ms, moments <= 300 ms; Calm 120 / 180)", function(check)
    -- tiers from the spec's leaf table. zoomFactor is listed as everyday there
    -- but is 250 ms (Calm 150 ms), over that tier; left out and reported.
    local everyday = { "windowsMove", "fadeSwitch", "fadeShadow", "fadeDim", "border", "fadePopupsIn", "fadePopupsOut", "global" }
    local moments = { "windowsIn", "windowsOut", "fadeIn", "fadeOut", "layersIn", "layersOut", "fadeLayersIn",
                      "fadeLayersOut", "workspaces", "specialWorkspace" }
    local caps = { showcase = { 1.5, 3.0 }, calm = { 1.2, 1.8 } }
    for level, cap in pairs(caps) do
        local L = withLevel(level)
        local byLeaf = {}
        for _, a in ipairs(L.state.animations) do byLeaf[a.leaf] = a end
        for _, leaf in ipairs(everyday) do
            check(byLeaf[leaf] and byLeaf[leaf].speed <= cap[1], level .. " " .. leaf .. " over the everyday budget")
        end
        for _, leaf in ipairs(moments) do
            check(byLeaf[leaf] and byLeaf[leaf].speed <= cap[2], level .. " " .. leaf .. " over the moment budget")
        end
    end
end)

test("motion off: animations.enabled = false, no animation leaf, no glint gradient", function(check)
    local L = withLevel("off")
    noProblems(L, check)
    check(configOf(L)["animations.enabled"] == false, "animations.enabled = " .. show(configOf(L)["animations.enabled"]))
    check(#L.state.animations == 0, #L.state.animations .. " animation leaves still set")
    check(configOf(L)["general.col.active_border"] == DUSK.sol, "Off should use the solid focus border")
    for _, name in ipairs({ "motion-waybar", "motion-cicero-panel" }) do
        check(layerRule(L, name) == nil, "layer animation " .. name .. " set in Off")
    end
    check(layerRule(L, "invictus-veil") and layerRule(L, "invictus-veil").no_anim == true, "veil no_anim missing")
end)

test("motion calm: solid border, no glint leaf, no slides, layer animations absent", function(check)
    local L = withLevel("calm")
    check(configOf(L)["general.col.active_border"] == DUSK.sol, "Calm border should be solid focus colour")
    for _, a in ipairs(L.state.animations) do
        check(not (a.style or ""):match("^slide") or (a.style or ""):match("^slidefade"), a.leaf .. ": slide style in Calm")
        check(not (a.style or ""):match("^slidefade"), a.leaf .. ": slidefade in Calm (no slides)")
    end
    check(layerRule(L, "motion-waybar") == nil and layerRule(L, "motion-cicero-panel") == nil, "layer slides set in Calm")
end)

test("motion showcase: gradient glint border and the layer slides", function(check)
    local L = withLevel("showcase")
    check(deepEqual(configOf(L)["general.col.active_border"], { colors = { DUSK.sol, DUSK.sol_bright, DUSK.sol }, angle = 45 }),
        "border " .. show(configOf(L)["general.col.active_border"]))
    check(layerRule(L, "motion-waybar").animation == "slide top", "waybar slide")
    check(layerRule(L, "motion-cicero-panel").animation == "slide right", "panel slide")
end)

test("motion: level names are case-insensitive and the file may end with a newline", function(check)
    local L = withLevel("Calm\n")
    check(#L.state.animations > 0 and configOf(L)["animations.enabled"] == true and configOf(L)["general.col.active_border"] == DUSK.sol,
        "'Calm' not read as calm")
    L = withLevel("  OFF  \n")
    check(configOf(L)["animations.enabled"] == false, "'  OFF' not read as off")
end)

test("game mode forces motion Off whatever the state file says, and the level returns afterwards", function(check)
    local marker = SCRATCH_HOME .. "/run/invictus/game-mode"
    writeFile(marker, "")
    for _, word in ipairs({ "showcase", "calm", "off", false }) do
        local L = withLevel(word)
        check(configOf(L)["animations.enabled"] == false and #L.state.animations == 0,
            "game mode on, level " .. show(word) .. ": animations still on")
    end
    -- the look: no gaps, border, shadow, blur or dim while gaming
    local L = withLevel("showcase")
    local cfg = configOf(L)
    check(cfg["general.gaps_in"] == 0 and cfg["general.gaps_out"] == 0 and cfg["general.border_size"] == 0, "game mode: gaps or border")
    check(cfg["decoration.shadow.enabled"] == false and cfg["decoration.blur.enabled"] == false
        and cfg["decoration.dim_inactive"] == false, "game mode: shadow, blur or dim still on")
    removeFile(marker)
    L = withLevel("calm")
    check(configOf(L)["animations.enabled"] == true, "Calm did not come back after game mode")
    L = withLevel("showcase")
    check(configOf(L)["general.gaps_in"] == 4 and configOf(L)["decoration.blur.enabled"] == true, "look did not come back")
end)

-- ─── colours come from the theme system ─────────────────────────────────────

local GENERATED = SCRATCH_HOME .. "/.config/invictus/current/hyprland-colors.lua"
local TOOL = repo .. "/theme/invictus-theme"

-- Run the real generator for a theme and put its output where the config looks.
local function installTheme(id)
    local dir = SCRATCH_HOME .. "/gen-" .. id
    os.execute('rm -rf "' .. dir .. '" "' .. SCRATCH_HOME .. '/.config/invictus/current"')
    local ok = os.execute('python3 "' .. TOOL .. '" generate ' .. id .. ' "' .. dir .. '" >/dev/null 2>&1')
    os.execute('mkdir -p "' .. SCRATCH_HOME .. '/.config/invictus" && ln -sfn "' .. dir .. '" "' .. SCRATCH_HOME .. '/.config/invictus/current"')
    return ok, dir
end
local function uninstallTheme() os.execute('rm -rf "' .. SCRATCH_HOME .. '/.config/invictus/current" "' .. SCRATCH_HOME .. '"/gen-*') end

local function readTokens(path)
    local t = dofile(path)
    return t
end

for _, id in ipairs({ "dusk", "porphyry", "aegean", "alexandria" }) do
    test("colours: theme " .. id .. " (real generator output) reaches borders, groups and background", function(check)
        local ok, dir = installTheme(id)
        check(ok, "invictus-theme generate " .. id .. " failed (needs python3 >= 3.11)")
        if not ok then return end
        local t = readTokens(dir .. "/hyprland-colors.lua")
        local L = withLevel("showcase")
        noProblems(L, check)
        local cfg = configOf(L)
        check(deepEqual(cfg["general.col.active_border"], { colors = { t.sol, t.sol_bright, t.sol }, angle = 45 }),
            "active_border " .. show(cfg["general.col.active_border"]))
        check(cfg["general.col.inactive_border"] == t.stone, "inactive_border " .. show(cfg["general.col.inactive_border"]))
        check(cfg["group.col.border_active"] == t.sol and cfg["group.groupbar.col.active"] == t.sol, "group focus colour")
        check(cfg["group.groupbar.col.inactive"] == t.line and cfg["group.groupbar.text_color"] == t.marble, "groupbar colours")
        check(cfg["misc.background_color"] == t.night, "background_color " .. show(cfg["misc.background_color"]))
        L = withLevel("calm")
        check(configOf(L)["general.col.active_border"] == t.sol, "Calm border is not the theme's sol")
        -- every token the config reads exists in the generated file (contract with the generator)
        local colorsModule = dofile(hyprDir .. "/invictus/colors.lua")
        for k in pairs(colorsModule) do
            if k ~= "shadow" and k ~= "shadow_none" then check(t[k] ~= nil, "generator output lacks token " .. k) end
        end
        uninstallTheme()
    end)
end

test("colours: switching theme and reloading changes the borders (Dusk to Porphyry)", function(check)
    local ok1 = installTheme("dusk")
    local a = configOf(withLevel("calm"))["general.col.active_border"]
    local ok2 = installTheme("porphyry")
    local b = configOf(withLevel("calm"))["general.col.active_border"]
    check(ok1 and ok2, "generate failed")
    check(a == "rgb(E0A64B)" and b == "rgb(CE93C8)", "dusk " .. show(a) .. ", porphyry " .. show(b))
    uninstallTheme()
end)

test("colours: a missing, broken, partial or hostile generated file falls back to Dusk", function(check)
    local cases = {
        { "missing", nil },
        { "syntax error", "return {{{" },
        { "runtime error", "error('boom')" },
        { "not a table", "return 42" },
        { "empty table", "return {}" },
        { "hostile values", 'return { sol = "rgb(zz)", stone = 5, night = "red; os.exit()", sol_bright = "rgb(1,2,3)" }' },
        { "partial", 'return { sol = "rgb(112233)" }' },
    }
    for _, case in ipairs(cases) do
        local name, body = case[1], case[2]
        os.execute('rm -rf "' .. SCRATCH_HOME .. '/.config/invictus/current"')
        if body then writeFile(GENERATED, body) end
        local L = withLevel("calm")
        check(L.mainOk, name .. ": config raised " .. tostring(L.mainErr))
        for _, e in ipairs(L.state.errors) do check(false, name .. ": " .. e) end
        local cfg = configOf(L)
        local wantSol = (name == "partial") and "rgb(112233)" or DUSK.sol
        check(cfg["general.col.active_border"] == wantSol, name .. ": active_border " .. show(cfg["general.col.active_border"]))
        check(cfg["general.col.inactive_border"] == DUSK.stone, name .. ": inactive_border " .. show(cfg["general.col.inactive_border"]))
        check(cfg["misc.background_color"] == DUSK.night, name .. ": background " .. show(cfg["misc.background_color"]))
        check(cfg["decoration.blur.size"] == 6, name .. ": rest of the config did not load")
        os.execute('rm -rf "' .. SCRATCH_HOME .. '/.config/invictus/current"')
    end
end)

test("colours: look.lua and motion.lua type no colour of their own", function(check)
    for _, f in ipairs({ "look.lua", "motion.lua", "rules.lua", "binds.lua" }) do
        local n = 0
        for line in io.lines(hyprDir .. "/invictus/" .. f) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            check(not code:match("#%x%x%x%x%x%x") and not code:match("rgba?%(") and not code:match('"0x%x%x%x%x%x%x'),
                f .. ":" .. n .. ": hardcoded colour: " .. line)
        end
    end
end)

test("the config requires the generated file (not dofile), so Hyprland sees it as part of the config", function(check)
    local src = assert(io.open(hyprDir .. "/invictus/colors.lua")):read("a"):gsub("%-%-[^\n]*", "")
    check(src:find('require, GENERATED', 1, true) or src:find('pcall(require', 1, true), "colors.lua does not require the file")
    check(not src:find("dofile", 1, true) and not src:find("loadfile", 1, true), "colors.lua uses dofile or loadfile")
    check(src:find(".config/invictus/current/hyprland-colors.lua", 1, true), "colors.lua does not read the generated path")
end)

-- ─── the Cicero panel (design 4.2; no-ai.md: no Super+A with No AI) ────────

test("Cicero panel: Super+A toggles special:cicero, whose first show starts tribune in kitty", function(check)
    local L = loadConfig({})
    noProblems(L, check)
    check(L.requiredModules["invictus.cicero"], "core.lua did not load invictus.cicero")
    local rule
    for _, r in ipairs(L.state.workspaceRules) do if r.workspace == "special:cicero" then rule = r end end
    check(rule and rule.on_created_empty == "kitty --class invictus-cicero --title Cicero /usr/bin/tribune",
        "special:cicero needs on_created_empty running /usr/bin/tribune in kitty, got " .. show(rule))
    local win
    for _, r in ipairs(L.state.windowRules) do if r.name == "cicero-panel-workspace" then win = r end end
    check(win and win.match.class == "^invictus-cicero$" and win.workspace == "special:cicero silent",
        "the panel's kitty must land on special:cicero: " .. show(win))
    local n = 0
    for _, b in ipairs(L.state.binds) do
        if deepEqual(actualDispatcher(b.dispatcher), { "workspace.toggle_special", "cicero" }) then
            n = n + 1
            check(b.keys == "SUPER + A", "Cicero bind on " .. b.keys)
            check(b.opts.description == "Cicero: show/hide the Cicero panel", "description " .. tostring(b.opts.description))
        end
    end
    check(n == 1, n .. " binds toggle special:cicero")
    -- kitty and tribune must come from packages: kitty from invictus-desktop,
    -- tribune from invictus-tribune, which the AI meta (invictus-cicero) pulls.
    local f = io.open(repo .. "/pkgs/meta/invictus-cicero/PKGBUILD")
    local meta = f and f:read("a") or ""
    if f then f:close() end
    check(meta:find("'invictus-tribune'", 1, true), "invictus-cicero must depend on invictus-tribune")
end)

test("Cicero panel: with No AI (module absent) the config loads cleanly and nothing binds Super+A", function(check)
    local realSearch = package.searchpath
    package.searchpath = function(name, path, ...)
        if name == "invictus.cicero" then return nil, "hidden by the test" end
        return realSearch(name, path, ...)
    end
    local L = loadConfig({})
    package.searchpath = realSearch
    noProblems(L, check)
    check(not L.requiredModules["invictus.cicero"], "invictus.cicero loaded although absent")
    for _, b in ipairs(L.state.binds) do check(b.keys ~= "SUPER + A", "Super+A bound with No AI") end
    for _, r in ipairs(L.state.workspaceRules) do check(r.workspace ~= "special:cicero", "special:cicero rule with No AI") end
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

os.execute('rm -rf "' .. SCRATCH_HOME .. '"')
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
