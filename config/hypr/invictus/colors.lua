--------------------------------------------------------------------------------
--                                                                            --
--                                  COLOURS                                   --
--------------------------------------------------------------------------------
-- The colours every Hyprland module uses. They come from the theme system:
-- invictus-theme writes ~/.config/invictus/current/hyprland-colors.lua for the
-- current theme, and this module loads it with require() (not dofile, so
-- Hyprland can tell the file is part of the config).
--
-- The table below is the ONLY place a colour is typed by hand: the Nox Aurea
-- values, used for any token the generated file does not supply (no file yet,
-- an unreadable file, a token missing from it). Nothing else in config/ may
-- hardcode a colour; tests/theme/run.sh checks that.
--
-- Values are Hyprland colour strings. c.sol is the focus colour.
--------------------------------------------------------------------------------

local fallback = {
    id         = "nox",
    night      = "rgb(0B0A08)",
    basalt     = "rgb(131210)",
    stone      = "rgb(1E1C18)",
    line       = "rgb(352F26)",
    marble     = "rgb(EFE6D2)",
    parchment  = "rgb(C2B8A3)",
    ash        = "rgb(9A917F)",
    sol        = "rgb(D9A441)",
    sol_bright = "rgb(F2D38A)",
    pompeii    = "rgb(E0775E)",
    laurel     = "rgb(9BB481)",
    lapis      = "rgb(84A5D8)",
    verdigris  = "rgb(76B0A6)",
    tyrian     = "rgb(B98DB6)",
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
