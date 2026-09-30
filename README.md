# hyprdots

A reproducible, Arch Linux–based Hyprland desktop environment with a clean separation between
system provisioning, configuration deployment, and user customization.

This repository is designed to be:
- Safe to run on fresh installs
- Explicit about destructive actions
- Re-runnable without breaking the system
- Easy to reason about and extend

---

## Philosophy

This repo intentionally separates concerns:

- **System provisioning** (packages, dependencies)
- **Configuration deployment** (copy-once defaults)
- **Advanced workflows** (optional symlink mode)

Nothing happens implicitly.  
Anything destructive is guarded and opt-in.

This structure reflects real-world infrastructure and DevOps best practices.

---
### Install Process

This repository is intended to be installed on a fresh minimimal profile archinstall
While an attempt has been made for nvidea compatibility, this system is designed for AMD
Installing this system on nvidea hardware may produce bugs and unforeseen issues
Only install on nvidea systems if you are comfortable with troubleshooting

Install with:

git clone https://github.com/turneralexander55/hyprdots.git ~/hyprdots
cd ~/hyprdots
chmod +x scripts/*.sh
chmod +x scripts/waybar/*.sh
./scripts/install.sh


#### Repository Structure
hyprdots
├── assets
│   ├── SDDM
│   │   ├── blackglass
│   │   │   ├── assets
│   │   │   │   ├── boycott.ttf
│   │   │   │   ├── buttondown.svg
│   │   │   │   ├── buttonhover.svg
│   │   │   │   ├── buttonup.svg
│   │   │   │   ├── cboxhover.svg
│   │   │   │   ├── cbox.svg
│   │   │   │   ├── comboarrow.svg
│   │   │   │   ├── DigitalSegmented.pcf.gz
│   │   │   │   ├── HelmetNeue-Regular.otf
│   │   │   │   ├── inputhi.svg
│   │   │   │   ├── input.svg
│   │   │   │   ├── logscreen.svg
│   │   │   │   ├── powerdown.svg
│   │   │   │   ├── powerhover.svg
│   │   │   │   ├── powerup.svg
│   │   │   │   ├── rebootdown.svg
│   │   │   │   ├── reboothover.svg
│   │   │   │   └── rebootup.svg
│   │   │   ├── ComboBox.qml
│   │   │   ├── LICENSE
│   │   │   ├── logscreen.svg
│   │   │   ├── Main.qml
│   │   │   ├── metadata.desktop
│   │   │   ├── preview.png
│   │   │   ├── README.md
│   │   │   ├── theme.conf
│   │   │   └── theme.conf.user
│   │   └── hyprland.desktop
│   └── wallpapers
│       ├── Berserk.jpg
│       ├── blossom.png
│       └── girl.png
├── config
│   ├── btop
│   │   ├── btop.conf
│   │   └── themes
│   ├── cava
│   │   ├── config
│   │   ├── shaders
│   │   │   ├── bar_spectrum.frag
│   │   │   ├── eye_of_phi.frag
│   │   │   ├── northern_lights.frag
│   │   │   ├── pass_through.vert
│   │   │   ├── spectrogram.frag
│   │   │   └── winamp_line_style_spectrum.frag
│   │   └── themes
│   │       ├── solarized_dark
│   │       └── tricolor
│   ├── fastfetch
│   │   └── config.jsonc
│   ├── hypr
│   │   ├── .luarc.json
│   │   ├── hyprland.lua
│   │   ├── hyprpaper.conf
│   │   └── lua
│   │       ├── autostart.lua
│   │       ├── binds.lua
│   │       ├── env.lua
│   │       ├── gaming.lua
│   │       ├── input.lua
│   │       ├── look.lua
│   │       ├── monitors.lua
│   │       ├── permissions.lua
│   │       ├── rules.lua
│   │       ├── variables.lua
│   │       └── workspaces.lua
│   ├── kitty
│   │   └── kitty.conf
│   ├── rofi
│   │   ├── config.rasi
│   │   └── themes
│   │       └── theme.rasi
│   ├── swaync
│   │   └── config.json
│   ├── waybar
│   │   ├── config.json
│   │   └── style.css
│   └── zed
│       ├── settings.json
│       └── themes
├── packages
│   ├── aur.txt
│   └── pacman.txt
├── README.md
├── scripts
│   ├── deploy-configs.sh
│   ├── deploy-shell.sh
│   ├── init-user.sh
│   ├── install-packages.sh
│   ├── install-sddm.sh
│   ├── install.sh
│   ├── nvidea.sh
│   ├── show-keybindings.sh
│   ├── symlink-configs.sh
│   ├── update.sh
│   └── waybar
│       ├── cpu.sh
│       ├── gpu.sh
│       ├── memory.sh
│       └── updates.sh
├── shell
│   └── zshrc
└── tests
    └── hyprland-lua          # run.sh: checks the Lua config without Hyprland
