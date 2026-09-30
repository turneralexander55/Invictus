# A home set up by the old hyprdots scripts

Files copied from `main` (the branch Alex's machine runs) at 0a579b7, laid
out the way `legacy/deploy-configs.sh` copies them into `~/.config`. The
other `hypr/config/*.conf` files are the same as
`tests/hyprland-lua/fixtures/*.conf` (checked byte for byte when this was
made), so `tests/pkgs/lib/legacy-home.sh` takes them from there.

Used by `tests/pkgs/run.sh` (the hyprlang porter) and
`tests/pkgs/e2e-adopt.sh` (adopt, undo).
