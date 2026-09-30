-- Minimal reader for the old hyprlang config files kept in fixtures/.
-- Handles what those files use: nested sections, key = value, keyword lines
-- (bind*, bezier, animation, env, exec-once, gesture, $var) and the 0.53
-- windowrule { } / layerrule { } / device { } blocks.

local M = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local KEYWORDS = {
    bind = true, binde = true, bindl = true, bindel = true, bindle = true, bindm = true,
    bezier = true, animation = true, env = true, ["exec-once"] = true, gesture = true,
    monitor = true, workspace = true,
}
local BLOCKS = { windowrule = "windowRules", layerrule = "layerRules", device = "devices" }

function M.parse(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local out = { config = {}, keywords = {}, vars = {}, windowRules = {}, layerRules = {}, devices = {} }
    local stack = {}
    local block -- current windowrule/layerrule/device table

    for raw in f:lines() do
        local line = trim((raw:gsub("#.*$", "")))
        if line ~= "" then
            local open = line:match("^([%w_%.%-]+)%s*{$")
            if open then
                if BLOCKS[open] and #stack == 0 then
                    block = { __kind = open }
                    table.insert(out[BLOCKS[open]], block)
                end
                table.insert(stack, open)
            elseif line == "}" then
                table.remove(stack)
                if #stack == 0 then block = nil end
            else
                local key, value = line:match("^([^=]-)%s*=%s*(.*)$")
                if key then
                    key = trim(key)
                    value = trim(value)
                    if block then
                        block[key] = value
                    elseif key:sub(1, 1) == "$" and #stack == 0 then
                        out.vars[key:sub(2)] = value
                    elseif KEYWORDS[key] and #stack <= 1 then
                        table.insert(out.keywords, { kind = key, value = value, section = stack[1] })
                    else
                        local full = table.concat(stack, ".")
                        full = (full == "" and key) or (full .. "." .. key)
                        out.config[full] = value
                    end
                end
            end
        end
    end
    f:close()
    return out
end

-- Split "a, b, c" on commas, trimming. `max` keeps the tail together.
function M.split(value, max)
    local parts = {}
    local rest = value
    while true do
        if max and #parts == max - 1 then
            table.insert(parts, trim(rest))
            break
        end
        local i = rest:find(",", 1, true)
        if not i then
            table.insert(parts, trim(rest))
            break
        end
        table.insert(parts, trim(rest:sub(1, i - 1)))
        rest = rest:sub(i + 1)
    end
    return parts
end

return M
