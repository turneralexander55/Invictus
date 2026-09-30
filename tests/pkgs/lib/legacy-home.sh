# shellcheck shell=bash
# make_legacy_home REPO HOME: a home as the old hyprdots scripts left it.
#   HOME/hyprdots        a git clone with main's config layout and the old
#                        wallpaper (the clone Alex's machine pulls)
#   HOME/.config/...     the deployed copies (deploy-configs.sh), plus two
#                        things Alex added himself: a bind and a look tweak,
#                        and a monitor line
#   HOME/.local/bin/dashboard-tmux   his own script
make_legacy_home() {
    local repo="$1" home="$2" fx="$1/tests/pkgs/fixtures/legacy-home" clone="$2/hyprdots"
    mkdir -p "$clone/config/hypr/config" "$clone/assets/wallpapers" "$home/.config" "$home/.local/bin"
    cp -r "$fx/hypr" "$fx/waybar" "$fx/kitty" "$clone/config/"
    cp "$repo"/tests/hyprland-lua/fixtures/*.conf "$clone/config/hypr/config/"
    printf 'not really a jpeg\n' > "$clone/assets/wallpapers/Berserk.jpg"
    git -C "$clone" init -q
    git -C "$clone" -c user.email=t@t -c user.name=t add -A
    git -C "$clone" -c user.email=t@t -c user.name=t commit -qm "main as deployed"

    local d
    for d in hypr waybar kitty; do cp -a "$clone/config/$d" "$home/.config/$d"; done
    # shellcheck disable=SC2016 # a literal hyprlang variable
    printf 'bind = $mainMod SHIFT, B, exec, firefox --private-window\n' >> "$home/.config/hypr/config/keybindings.conf"
    printf 'misc {\n    vfr = false\n}\n' >> "$home/.config/hypr/config/aesthetics.conf"
    printf 'monitor = DP-1, 2560x1440@165, 0x0, 1\n' >> "$home/.config/hypr/config/monitors.conf"
    printf '#!/bin/sh\nexec tmux new -A -s dashboard\n' > "$home/.local/bin/dashboard-tmux"
    chmod +x "$home/.local/bin/dashboard-tmux"
    mkdir -p "$home/.local/state"
    touch "$home/.local/state/hyprdots-initialized"
}
