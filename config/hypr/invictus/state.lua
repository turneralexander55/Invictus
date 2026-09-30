--------------------------------------------------------------------------------
--                                                                            --
--                                  STATE                                     --
--------------------------------------------------------------------------------
-- Small runtime settings the shipped modules read when the config loads:
--
--   motion level   ~/.config/invictus/motion holds one word: showcase, calm or
--                  off (Showcase is the default). Change it, then `hyprctl reload`.
--   game mode      the marker file $XDG_RUNTIME_DIR/invictus/game-mode exists
--                  while game mode is on (the same file invictus-theme checks).
--                  It forces the motion level to off; the state file is left
--                  alone, so the old level comes back when game mode ends.
--
-- INVICTUS_MOTION_FILE and INVICTUS_GAMEMODE_FILE override the two paths
-- (the tests use them).
--------------------------------------------------------------------------------

local M = {}

local LEVELS = { showcase = true, calm = true, off = true }

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end

function M.motionFile()
    return os.getenv("INVICTUS_MOTION_FILE") or ((os.getenv("HOME") or "") .. "/.config/invictus/motion")
end

function M.gameModeFile()
    return os.getenv("INVICTUS_GAMEMODE_FILE") or ((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/invictus/game-mode")
end

function M.gameMode()
    return exists(M.gameModeFile())
end

-- The level the user chose. Anything unreadable or unknown means showcase.
function M.chosenLevel()
    local f = io.open(M.motionFile(), "r")
    if not f then return "showcase" end
    local word = (f:read("l") or ""):match("^%s*(%a+)%s*$")
    f:close()
    word = word and word:lower()
    return LEVELS[word or ""] and word or "showcase"
end

-- The level in force: off while game mode is on.
function M.motionLevel()
    if M.gameMode() then return "off" end
    return M.chosenLevel()
end

return M
