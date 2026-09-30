-- A stand-in for Hyprland's `hl` global. It checks every call against the
-- 0.56.2 API (stubs + api.lua) and records what the config asked for, so the
-- tests can compare it with the old hyprlang config.
--
-- Errors are collected, not thrown, the way Hyprland collects config errors.

local api = require("api")

local M = {}

-- ─── stub parsing ───────────────────────────────────────────────────────────

local function parseStubs(path)
    local f = assert(io.open(path, "r"), "cannot open stubs: " .. path)
    local text = f:read("a")
    f:close()

    local stubs = { configTypes = {}, classes = {}, events = {} }

    -- ---@field ['general.gaps_in'] integer|HL.CssGap
    for key, types in text:gmatch("%-%-%-@field %['([%w_%.]+)'%] ([^\n]+)") do
        local t = {}
        for ty in types:gmatch("[^|]+") do t[ty] = true end
        stubs.configTypes[key] = t
    end

    -- ---@class HL.Something ... ---@field name? type
    local current
    for line in text:gmatch("[^\n]+") do
        local cls = line:match("^%-%-%-@class ([%w%._]+)")
        if cls then
            current = {}
            stubs.classes[cls] = current
        elseif current then
            local field = line:match("^%-%-%-@field ([%w_]+)%??%s")
            if field then
                current[field] = true
            elseif not line:match("^%-%-%-") then
                current = nil
            end
        end
    end

    -- ---| "window.open"
    local inEvents = false
    for line in text:gmatch("[^\n]+") do
        if line:match("^%-%-%-@alias HL.EventName") then
            inEvents = true
        elseif inEvents then
            local ev = line:match('^%-%-%-| "([^"]+)"')
            if ev then stubs.events[ev] = true else inEvents = false end
        end
    end

    return stubs
end

local function parseKeysyms(path)
    if not path then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local names = {}
    for name in f:read("a"):gmatch("#define XKB_KEY_([%w_]+)") do
        names[name:lower()] = true
    end
    f:close()
    return names
end

-- ─── helpers ────────────────────────────────────────────────────────────────

local function kindOf(v)
    if type(v) == "number" then
        return math.type(v) == "integer" and "integer" or "number"
    end
    return type(v)
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Does value v fit one of the stub types for a config key?
local function fitsTypes(v, types)
    local k = kindOf(v)
    if k == "integer" then return types.integer or types.number end
    if k == "number" then return types.number end
    if k == "boolean" then return types.boolean end
    if k == "string" then return types.string or types["HL.Gradient"] or types["HL.Vec2Like"] end
    if k == "table" then return types["HL.CssGap"] or types["HL.Gradient"] or types["HL.Vec2Like"] end
    return false
end

local function isGradient(v)
    if type(v) == "string" then return true end
    if type(v) ~= "table" or type(v.colors) ~= "table" or #v.colors == 0 then return false end
    for k in pairs(v) do
        if k ~= "colors" and k ~= "angle" then return false end
    end
    return v.angle == nil or type(v.angle) == "number"
end

local function isVec2(v)
    if type(v) == "string" then return #trim(v) > 0 end
    if type(v) ~= "table" then return false end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    return n == 2 and v[1] ~= nil and v[2] ~= nil
        and (type(v[1]) == "number" or type(v[1]) == "string")
        and (type(v[2]) == "number" or type(v[2]) == "string")
end

local function fitsEffectKind(v, kind)
    if kind == "bool" then return type(v) == "boolean" end
    if kind == "int" then return math.type(v) == "integer" or type(v) == "boolean" end
    if kind == "float" then return type(v) == "number" end
    if kind == "string" then return type(v) == "string" end
    if kind == "vec2" then return isVec2(v) end
    if kind == "gradient" then return isGradient(v) end
    return false
end

-- ─── the mock ───────────────────────────────────────────────────────────────

function M.new(opts)
    local stubs = parseStubs(opts.stubs)
    local keysyms = parseKeysyms(opts.keysyms)

    local state = {
        errors = {}, warnings = {},
        config = {},        -- flat "section.key" -> value
        binds = {},         -- { keys, mods = {..}, modmask, key, dispatcher, opts, source }
        windowRules = {}, layerRules = {}, workspaceRules = {},
        env = {}, events = {}, curves = { default = true }, animations = {},
        gestures = {}, devices = {}, monitors = {}, permissions = {},
        execs = {},
        keysymsChecked = keysyms ~= nil,
        stubs = stubs,
    }

    local function where()
        -- file:line of the config line that called into hl
        for level = 3, 8 do
            local info = debug.getinfo(level, "Sl")
            if info and info.short_src and not info.short_src:match("mock_hl%.lua") then
                return info.short_src .. ":" .. (info.currentline or "?")
            end
        end
        return "?"
    end

    local function err(msg) table.insert(state.errors, where() .. ": " .. msg) end
    local function warn(msg) table.insert(state.warnings, where() .. ": " .. msg) end

    local function checkSpec(fnName, className, spec, required)
        if type(spec) ~= "table" then
            err(fnName .. ": argument must be a table")
            return false
        end
        local fields = stubs.classes[className]
        if not fields then
            err("test setup: no stub class " .. className)
            return false
        end
        for k in pairs(spec) do
            if not fields[k] then err(fnName .. ": unknown field '" .. tostring(k) .. "'") end
        end
        for _, r in ipairs(required or {}) do
            if spec[r] == nil then err(fnName .. ": missing required field '" .. r .. "'") end
        end
        return true
    end

    local hl = {}

    -- hl.config -------------------------------------------------------------
    local function walk(prefix, tbl)
        for k, v in pairs(tbl) do
            if type(k) ~= "string" then
                err("hl.config: non-string key under '" .. prefix .. "'")
            else
                local full = prefix == "" and k or (prefix .. "." .. k)
                local types = stubs.configTypes[full]
                if types then
                    if not fitsTypes(v, types) then
                        err("hl.config: bad type for '" .. full .. "': got " .. kindOf(v))
                    end
                    state.config[full] = v
                elseif type(v) == "table" then
                    walk(full, v)
                else
                    err("hl.config: unknown config key '" .. full .. "'")
                end
            end
        end
    end

    function hl.config(tbl)
        if type(tbl) ~= "table" then return err("hl.config: argument must be a table") end
        walk("", tbl)
    end

    function hl.get_config(key)
        key = key:gsub(":", ".")
        if not stubs.configTypes[key] then
            return nil, "unknown config key '" .. key .. "'"
        end
        return state.config[key]
    end

    -- hl.env ----------------------------------------------------------------
    function hl.env(name, value)
        if type(name) ~= "string" or name == "" then return err("hl.env: name must be a non-empty string") end
        if type(value) ~= "string" then return err("hl.env: value for " .. name .. " must be a string") end
        state.env[name] = value
    end

    -- hl.on / exec ----------------------------------------------------------
    function hl.on(event, cb)
        if not stubs.events[event] then err("hl.on: unknown event '" .. tostring(event) .. "'") end
        if type(cb) ~= "function" then err("hl.on: callback must be a function") end
        state.events[event] = state.events[event] or {}
        table.insert(state.events[event], cb)
        return { is_active = function() return true end, remove = function() end }
    end

    function hl.exec_cmd(cmd, rules)
        if type(cmd) ~= "string" or cmd == "" then return err("hl.exec_cmd: command must be a non-empty string") end
        table.insert(state.execs, cmd)
    end

    -- dispatchers -----------------------------------------------------------
    local function makeDsp(name, check)
        return function(...)
            local args = table.pack(...)
            if check then check(args) end
            return { __dispatcher = name, args = args }
        end
    end

    local function tableArgs(name)
        return function(args)
            local t = args[1]
            if t == nil then return end
            if type(t) ~= "table" then return err("hl.dsp." .. name .. ": argument must be a table") end
            local allowed = api.dispatcherArgs[name]
            for k in pairs(t) do
                if not allowed[k] then err("hl.dsp." .. name .. ": unknown argument '" .. tostring(k) .. "'") end
            end
            if t.direction ~= nil and not api.directions[t.direction] then
                err("hl.dsp." .. name .. ": bad direction '" .. tostring(t.direction) .. "'")
            end
            if t.action ~= nil and name == "window.float" and not api.floatActions[t.action] then
                err("hl.dsp.window.float: bad action '" .. tostring(t.action) .. "' (silently toggles)")
            end
        end
    end

    local function stringArg(name)
        return function(args)
            if type(args[1]) ~= "string" or args[1] == "" then
                err("hl.dsp." .. name .. ": argument must be a non-empty string")
            end
        end
    end

    local dsp = { window = {}, workspace = {}, group = {}, cursor = {} }
    -- Everything the stubs list exists; the ones the config uses get checked.
    for ns, cls in pairs({ [""] = "HL.DspNamespace", window = "HL.DspWindowNamespace",
                           workspace = "HL.DspWorkspaceNamespace", group = "HL.DspGroupNamespace",
                           cursor = "HL.DspCursorNamespace" }) do
        for fn in pairs(stubs.classes[cls] or {}) do
            local target = ns == "" and dsp or dsp[ns]
            local full = ns == "" and fn or (ns .. "." .. fn)
            if type(target[fn]) ~= "table" then
                local check
                if api.dispatcherArgs[full] then check = tableArgs(full) end
                if full == "exec_cmd" or full == "exec_raw" or full == "layout"
                    or full == "workspace.toggle_special" or full == "global" or full == "submap" then
                    check = stringArg(full)
                end
                target[fn] = makeDsp(full, check)
            end
        end
    end
    hl.dsp = dsp

    function hl.dispatch(d)
        if type(d) ~= "function" and not (type(d) == "table" and d.__dispatcher) then
            err("hl.dispatch: argument must be a dispatcher")
        end
    end

    -- hl.bind ---------------------------------------------------------------
    local function parseKeys(keys)
        local mods, modmask, key, special = {}, 0, nil, false
        local modsEnded = false
        for part in (keys .. "+"):gmatch("([^+]*)%+") do
            local p = trim(part)
            local mask = api.modifiers[p]
            if mask then
                if modsEnded then return nil, "modifiers must come first" end
                if modmask & mask == 0 then table.insert(mods, p) end
                modmask = modmask | mask
            else
                modsEnded = true
                if key then return nil, "more than one key in '" .. keys .. "'" end
                local isSpecial = api.specialKeys[p]
                for _, pre in ipairs(api.specialPrefixes) do
                    if p:sub(1, #pre) == pre then isSpecial = true end
                end
                if isSpecial then
                    special = true
                elseif p:match("^code:%d+$") then
                    -- keycode, fine
                elseif p == "" then
                    return nil, "empty key in '" .. keys .. "'"
                elseif keysyms then
                    if not keysyms[p:lower()] then return nil, 'Unknown keysym: "' .. p .. '"' end
                else
                    if p == "ESC" or p == "Enter" then return nil, 'Unknown keysym: "' .. p .. '"' end
                end
                key = p
            end
        end
        if not key then return nil, "no key in '" .. keys .. "'" end
        return { mods = mods, modmask = modmask, key = key, special = special }
    end

    function hl.bind(keys, dispatcher, opts)
        if type(keys) ~= "string" then return err("hl.bind: keys must be a string") end
        local parsed, perr = parseKeys(keys)
        if not parsed then return err("hl.bind: failed to parse key string: " .. perr) end
        if type(dispatcher) ~= "function" and not (type(dispatcher) == "table" and dispatcher.__dispatcher) then
            return err("hl.bind: dispatcher must be a dispatcher or a lua function")
        end
        opts = opts or {}
        local allowed = stubs.classes["HL.BindOptions"]
        for k in pairs(opts) do
            if not allowed[k] and not api.extraBindOptions[k] then
                err("hl.bind: unknown option '" .. tostring(k) .. "'")
            end
        end
        if (opts.release or opts.long_press or opts.click or opts.drag) and opts.repeating then
            err("hl.bind: long_press / release is incompatible with repeat")
        end
        if opts.click and opts.drag then err("hl.bind: click and drag are exclusive") end
        if opts.description ~= nil and type(opts.description) ~= "string" then
            err("hl.bind: description must be a string")
        end
        local b = {
            keys = keys, mods = parsed.mods, modmask = parsed.modmask, key = parsed.key,
            dispatcher = dispatcher, opts = opts, source = where(),
        }
        table.insert(state.binds, b)
        return { set_enabled = function() end, is_enabled = function() return true end }
    end

    -- rules -----------------------------------------------------------------
    local function checkMatch(fnName, match)
        if type(match) ~= "table" then
            err(fnName .. ": 'match' table is required")
            return
        end
        local n = 0
        for k, v in pairs(match) do
            n = n + 1
            if not api.ruleMatchProps[k] then err(fnName .. ": unknown match property '" .. tostring(k) .. "'") end
            local t = type(v)
            if t ~= "string" and t ~= "boolean" and t ~= "number" then
                err(fnName .. ": match value for '" .. tostring(k) .. "' must be string, bool, or number")
            end
        end
        if n == 0 then err(fnName .. ": needs at least one match property") end
    end

    local function ruleCommon(fnName, spec, effects, store)
        if type(spec) ~= "table" then return err(fnName .. ": argument must be a table") end
        checkMatch(fnName, spec.match)
        local nEffects = 0
        for k, v in pairs(spec) do
            if k ~= "name" and k ~= "enabled" and k ~= "match" then
                nEffects = nEffects + 1
                local kind = effects[k]
                if not kind then
                    err(fnName .. ": unknown field '" .. tostring(k) .. "'")
                elseif not fitsEffectKind(v, kind) then
                    err(fnName .. ": field '" .. k .. "' wants " .. kind .. ", got " .. kindOf(v))
                end
            end
        end
        if nEffects == 0 then warn(fnName .. ": rule has no effects") end
        if spec.name then
            for _, r in ipairs(store) do
                if r.name == spec.name then
                    err(fnName .. ": duplicate rule name '" .. spec.name .. "' (the later one replaces the earlier)")
                end
            end
        end
        table.insert(store, spec)
        return { set_enabled = function() end, is_enabled = function() return true end }
    end

    function hl.window_rule(spec)
        if type(spec) == "table" then
            local vals = api.windowEffectValues
            for k, allowed in pairs(vals) do
                if type(spec[k]) == "string" and not allowed[spec[k]] then
                    err("hl.window_rule: bad value '" .. spec[k] .. "' for " .. k)
                end
            end
            if type(spec.suppress_event) == "string" then
                for ev in spec.suppress_event:gmatch("%S+") do
                    if not api.suppressEvents[ev] then err("hl.window_rule: bad suppress_event '" .. ev .. "'") end
                end
            end
        end
        return ruleCommon("hl.window_rule", spec, api.windowEffects, state.windowRules)
    end

    function hl.layer_rule(spec)
        return ruleCommon("hl.layer_rule", spec, api.layerEffects, state.layerRules)
    end

    function hl.workspace_rule(spec)
        if checkSpec("hl.workspace_rule", "HL.WorkspaceRuleSpec", spec, { "workspace" }) then
            table.insert(state.workspaceRules, spec)
        end
        return { set_enabled = function() end, is_enabled = function() return true end }
    end

    -- specs -----------------------------------------------------------------
    function hl.monitor(spec)
        if checkSpec("hl.monitor", "HL.MonitorSpec", spec, { "output" }) then table.insert(state.monitors, spec) end
    end

    function hl.device(spec)
        if checkSpec("hl.device", "HL.DeviceSpec", spec, { "name" }) then table.insert(state.devices, spec) end
    end

    function hl.gesture(spec)
        if checkSpec("hl.gesture", "HL.GestureSpec", spec, { "fingers", "direction", "action" }) then
            if math.type(spec.fingers) ~= "integer" then err("hl.gesture: fingers must be an integer") end
            table.insert(state.gestures, spec)
        end
    end

    function hl.permission(spec, t, m)
        if type(spec) == "string" then spec = { binary = spec, type = t, mode = m } end
        if checkSpec("hl.permission", "HL.PermissionSpec", spec, { "binary", "type", "mode" }) then
            table.insert(state.permissions, spec)
        end
    end

    -- animations ------------------------------------------------------------
    function hl.curve(name, spec)
        if type(name) ~= "string" or name == "" then return err("hl.curve: name must be a string") end
        if type(spec) ~= "table" then return err("hl.curve: spec must be a table") end
        if spec.type == "bezier" then
            local p = spec.points
            if type(p) ~= "table" or #p ~= 2 or type(p[1]) ~= "table" or type(p[2]) ~= "table"
                or #p[1] ~= 2 or #p[2] ~= 2 then
                return err("hl.curve: bezier '" .. name .. "' needs points = { {x0, y0}, {x1, y1} }")
            end
        elseif spec.type ~= "spring" then
            return err("hl.curve: type must be 'bezier' or 'spring'")
        end
        state.curves[name] = spec
    end

    function hl.animation(spec)
        if type(spec) ~= "table" then return err("hl.animation: argument must be a table") end
        for k in pairs(spec) do
            if not api.animationFields[k] then err("hl.animation: unknown field '" .. tostring(k) .. "'") end
        end
        if not api.animationLeaves[spec.leaf] then err("hl.animation: unknown leaf '" .. tostring(spec.leaf) .. "'") end
        if spec.bezier and not state.curves[spec.bezier] then
            err("hl.animation: bezier '" .. spec.bezier .. "' is not defined (define it with hl.curve first)")
        end
        if spec.spring and not state.curves[spec.spring] then
            err("hl.animation: spring '" .. spec.spring .. "' is not defined")
        end
        if type(spec.enabled) ~= "boolean" then err("hl.animation: enabled must be a boolean") end
        if spec.enabled and type(spec.speed) ~= "number" then err("hl.animation: speed must be a number") end
        table.insert(state.animations, spec)
    end

    -- queries used at runtime -------------------------------------------------
    function hl.version() return "0.56.2" end

    -- Anything else the stubs list exists but is unused by the config.
    for fn in pairs(stubs.classes["HL.API"] or {}) do
        if hl[fn] == nil then
            hl[fn] = function() warn("hl." .. fn .. " called; not modelled by the test mock") end
        end
    end

    return hl, state
end

return M
