--------------------------------------------------------------------------------
--                                                                            --
--                                  COLOURS                                   --
--------------------------------------------------------------------------------
-- The colours every Hyprland module uses. They come from the theme system:
-- invictus-theme writes ~/.config/invictus/current/hyprland-colors.lua for the
-- current theme, and this module loads it with require() (not dofile, so
-- Hyprland can tell the file is part of the config).
--
-- The table below is the ONLY place a colour is typed by hand: the Dusk
-- values, used for any token the generated file does not supply (no file yet,
-- an unreadable file, a token missing from it). Nothing else in config/ may
-- hardcode a colour; tests/theme/run.sh checks that.
--
-- Values are Hyprland colour strings. c.sol is the focus colour.
--------------------------------------------------------------------------------

local fallback = {
    id         = "dusk",
    night      = "rgb(14120F)",
    basalt     = "rgb(1C1A16)",
    stone      = "rgb(27241F)",
    line       = "rgb(3A352D)",
    marble     = "rgb(ECE6DA)",
    parchment  = "rgb(BDB4A3)",
    ash        = "rgb(968E7F)",
    sol        = "rgb(E0A64B)",
    sol_bright = "rgb(F0C274)",
    pompeii    = "rgb(D9725A)",
    laurel     = "rgb(94AD7B)",
    lapis      = "rgb(7C9FD4)",
    verdigris  = "rgb(72ACA3)",
    tyrian     = "rgb(B388B0)",
    -- Not theme colours: black shadow at 45%, and no shadow at all.
    shadow      = "rgba(00000073)",
    shadow_none = "rgba(00000000)",
}

local GENERATED = "~/.config/invictus/current/hyprland-colors.lua"

local ok, generated = pcall(require, GENERATED)

local colors = {}
for key, default in pairs(fallback) do
    local value = ok and type(generated) == "table" and generated[key] or nil
    if key == "id" then
        colors[key] = type(value) == "string" and value or default
    elseif key == "shadow" or key == "shadow_none" then
        colors[key] = default
    elseif type(value) == "string" and value:match("^rgba?%(%x+%)$") then
        colors[key] = value
    else
        colors[key] = default
    end
end

return colors
