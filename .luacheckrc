-- luacheck config (CI: .github/workflows/checks.yml). Hyprland embeds Lua 5.5;
-- lua54 is the newest standard luacheck knows and covers everything we use.
std = "lua54"
max_line_length = false -- the config aligns long bind and rule lines on purpose
exclude_files = { "tests/hyprland-lua/stubs/*" }

-- Hyprland provides the `hl` table to config files.
files["config/hypr"] = { read_globals = { "hl" } }

-- The test harness installs a mock `hl`, replaces require() the way
-- Hyprland does, and logs loader order through LOADER_LOG.
files["tests/hyprland-lua"] = {
    -- os.getenv is swapped to give each config load its own environment;
    -- package.searchpath to hide a module (No AI: no cicero.lua on disk)
    globals = { "hl", "require", "LOADER_LOG", "os", "package" },
    ignore = {
        "542", -- empty if branch: used as a "this case is fine" arm in key parsing
        "432", -- shadowing an upvalue argument: opts in nested helpers
    },
}
