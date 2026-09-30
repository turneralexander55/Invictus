-- luacheck: read globals hl
-- Invictus live session only: open the installer when the desktop starts.
-- (The live user's home is deleted by the installer.)
hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/lib/invictus/live/invictus-install --auto")
end)
