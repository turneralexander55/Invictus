--------------------------------------------------------------------------------
--                                                                            --
--                               PERMISSIONS                                  --
--                                                                            --
--------------------------------------------------------------------------------
-- Explicit permission rules for Hyprland components.
--
-- Permission changes made here are NOT applied dynamically.
-- A full Hyprland restart is required for security reasons.
--
-- Use this file to control access for:
--   • Screenshot and screencopy utilities
--   • Hyprland plugins
--   • Desktop portal integrations
--
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
--------------------------------------------------------------------------------


-- ─────────────────────────────────────────────────────────────────────────────
-- Ecosystem Permissions
-- Global permission enforcement controls.
-- ─────────────────────────────────────────────────────────────────────────────
-- hl.config({
--     ecosystem = {
--         enforce_permissions = true,
--     },
-- })


-- ─────────────────────────────────────────────────────────────────────────────
-- Explicit Permission Rules (Examples)
-- Uncomment only if explicit permission control is required.
-- ─────────────────────────────────────────────────────────────────────────────
-- hl.permission({ binary = "/usr/(bin|local/bin)/grim", type = "screencopy", mode = "allow" })
-- hl.permission({ binary = "/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", type = "screencopy", mode = "allow" })
-- hl.permission({ binary = "/usr/(bin|local/bin)/hyprpm", type = "plugin", mode = "allow" })
