--------------------------------------------------------------------------------
--                                                                            --
--                               CICERO PANEL                                 --
--                                                                            --
--------------------------------------------------------------------------------
-- Super+A shows and hides the Cicero panel (code name tribune, design 4.2): a
-- kitty on the special workspace "cicero" running /usr/bin/tribune, which
-- starts whoever answers (Claude Code, another agent or a chat service).
--
-- Installed by invictus-tribune (the AI set), not invictus-desktop: on a No AI
-- computer this file is absent, core.lua's protected require finds nothing,
-- and there is no Super+A (no-ai.md: "no Cicero panel, no Super+A").
--------------------------------------------------------------------------------

local apps = require("invictus.variables")

local M = {
    workspace = "special:cicero",
    class     = "invictus-cicero",
    command   = "kitty --class invictus-cicero --title Cicero /usr/bin/tribune",
}

-- The first Super+A shows the empty special workspace, which starts the
-- panel; later presses show and hide it. When the panel ends (AI turned off,
-- or the window closed), the next press starts a fresh one.
hl.workspace_rule({ workspace = M.workspace, on_created_empty = M.command })

hl.window_rule({
    name  = "cicero-panel-workspace",
    match = { class = "^invictus-cicero$" },

    workspace = M.workspace .. " silent",
})

hl.bind(apps.mainMod .. " + A", hl.dsp.workspace.toggle_special("cicero"),
        { description = "Cicero: show/hide the Cicero panel" })

return M
