--------------------------------------------------------------------------------
--                                                                            --
--                               MONETA PANEL                                 --
--                                                                            --
--------------------------------------------------------------------------------
-- Super+A shows and hides the Moneta panel (code name tribune, design 4.2): a
-- kitty on the special workspace "moneta" running /usr/bin/tribune, which
-- starts whoever answers (Claude Code, another agent or a chat service).
--
-- Installed by invictus-tribune (the AI set), not invictus-desktop: on a No AI
-- computer this file is absent, core.lua's protected require finds nothing,
-- and there is no Super+A (no-ai.md: "no Moneta panel, no Super+A").
--------------------------------------------------------------------------------

local apps = require("invictus.variables")

local M = {
    workspace = "special:moneta",
    class     = "invictus-moneta",
    command   = "kitty --class invictus-moneta --title Moneta /usr/bin/tribune",
}

-- The first Super+A shows the empty special workspace, which starts the
-- panel; later presses show and hide it. When the panel ends (AI turned off,
-- or the window closed), the next press starts a fresh one.
hl.workspace_rule({ workspace = M.workspace, on_created_empty = M.command })

hl.window_rule({
    name  = "moneta-panel-workspace",
    match = { class = "^invictus-moneta$" },

    workspace = M.workspace .. " silent",
})

hl.bind(apps.mainMod .. " + A", hl.dsp.workspace.toggle_special("moneta"),
        { description = "Moneta: show/hide the Moneta panel" })

return M
