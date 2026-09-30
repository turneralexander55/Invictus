#!/usr/bin/env python3
"""Checks on the shipped app configs in config/ (called by run.sh).

Prints "ok <what>" or "FAIL <what>" per check and exits non-zero if any failed.

usage: config_checks.py <repo root> <generated Dusk folder>
"""
import json
import re
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
dusk = Path(sys.argv[2])
config = repo / "config"
failures = 0


def ok(what):
    print(f"ok   {what}")


def fail(what, detail=""):
    global failures
    failures += 1
    print(f"FAIL {what}")
    if detail:
        print(f"       {detail}")


def check(cond, what, detail=""):
    ok(what) if cond else fail(what, detail)


def files(pattern="*"):
    return sorted(p for p in config.rglob(pattern) if p.is_file())


# ---------------------------------------------------------------- 1. colours

# Files that are entirely fallback, and GLSL shaders (code, not app colours).
def exempt(p):
    rel = p.relative_to(config).as_posix()
    return ("fallback" in p.name or rel == "hypr/invictus/colors.lua" or rel == "cava/themes/invictus"
            or p.suffix in (".frag", ".vert", ".png", ".svg", ".jpg"))


def strip_comments(p, text):
    if p.suffix in (".css", ".rasi"):
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    lines = []
    for line in text.split("\n"):
        s = line.strip()
        if p.suffix == ".lua":
            line = re.sub(r"--.*$", "", line)
        elif p.suffix in (".json", ".jsonc"):
            line = re.sub(r"^\s*//.*$", "", line)
        elif p.suffix in (".css", ".rasi"):
            pass
        elif s.startswith("#") or s.startswith(";"):
            line = ""
        lines.append(line)
    return "\n".join(lines)


HEX = re.compile(r"#[0-9a-fA-F]{3,8}\b|\b0x[0-9a-fA-F]{6,8}\b|\brgba?\(|\bhsla?\(|(?:foreground|background|color)=['\"]")
NAMED = re.compile(r"(?<![\w-])(white|black|red|green|blue|yellow|orange|purple|cyan|magenta|gray|grey|pink|brown)(?![\w-])")
hard = []
for p in files():
    if exempt(p):
        continue
    text = strip_comments(p, p.read_text(errors="replace"))
    for n, line in enumerate(text.split("\n"), 1):
        if HEX.search(line):
            hard.append(f"{p.relative_to(repo)}:{n}: {line.strip()}")
        elif p.suffix in (".css", ".rasi") and NAMED.search(line):
            hard.append(f"{p.relative_to(repo)}:{n}: named colour: {line.strip()}")
check(not hard, "no colour is written by hand in config/ outside the fallback files", "\n       ".join(hard[:8]))

# The exempt files are the only place a colour may live: name them so a new one is noticed.
fallbacks = sorted(p.relative_to(config).as_posix() for p in files() if exempt(p) and p.suffix not in (".frag", ".vert", ".png", ".svg", ".jpg"))
check(fallbacks == sorted([
    "cava/themes/invictus", "hypr/invictus/colors.lua", "kitty/colors-fallback.conf",
    "rofi/themes/colors-fallback.rasi", "swaync/colors-fallback.css", "waybar/colors-fallback.css",
]), "the fallback files are exactly the expected six", str(fallbacks))

# ------------------------------------------------- 2. fallbacks are Dusk, as generated
pairs = [
    ("waybar/colors-fallback.css", "waybar-colors.css"),
    ("swaync/colors-fallback.css", "swaync-colors.css"),
    ("rofi/themes/colors-fallback.rasi", "rofi-colors.rasi"),
    ("kitty/colors-fallback.conf", "kitty-colors.conf"),
    ("cava/themes/invictus", "cava-colors"),
]
for fb, gen in pairs:
    a = (config / fb).read_text().split("\n")[1:]
    b = (dusk / gen).read_text().split("\n")[1:]
    check(a == b, f"{fb} equals the generated Dusk {gen} (after the header line)")
    check((config / fb).read_text().split("\n")[0].lstrip("/*# ").startswith("Dusk"), f"{fb} says it is the Dusk fallback")

# colors.lua fallback = generated Dusk hyprland-colors.lua
def lua_table(text):
    return dict(re.findall(r'(\w+)\s*=\s*"([^"]*)"', text))

gen_lua = lua_table((dusk / "hyprland-colors.lua").read_text())
fb_lua = lua_table((config / "hypr/invictus/colors.lua").read_text().split("local GENERATED")[0])
diff = {k: (fb_lua.get(k), v) for k, v in gen_lua.items() if fb_lua.get(k) != v}
check(not diff, "hypr colors.lua fallback equals the generated Dusk hyprland-colors.lua", str(diff))

# ------------------------------------------------- 3. every app loads the generated file
def has(path, needle):
    return needle in (config / path).read_text()

check(has("waybar/style.css", '@import url("../invictus/current/waybar-colors.css");'), "waybar style.css imports waybar-colors.css")
check(has("swaync/style.css", '@import url("../invictus/current/swaync-colors.css");'), "swaync style.css imports swaync-colors.css")
check(has("rofi/themes/theme.rasi", '@import "~/.config/invictus/current/rofi-colors.rasi"'), "rofi theme imports rofi-colors.rasi")
check(has("kitty/kitty.conf", "~/.config/invictus/current/kitty-colors.conf"), "kitty.conf includes kitty-colors.conf")
check(has("btop/btop.conf", 'color_theme = "~/.config/invictus/current/btop.theme"'), "btop.conf points at btop.theme")
check(has("cava/config", "theme = 'invictus'"), "cava config uses the invictus theme")
check(has("hypr/invictus/colors.lua", "pcall(require, GENERATED)") and has("hypr/invictus/colors.lua", "current/hyprland-colors.lua"),
      "Hyprland colors.lua requires hyprland-colors.lua")
for app, f in (("waybar", "waybar/style.css"), ("swaync", "swaync/style.css")):
    t = (config / f).read_text()
    check(t.index("colors-fallback.css") < t.index("current/"), f"{app}: fallback is imported before the theme file (theme wins)")
for f in ("rofi/themes/theme.rasi",):
    t = (config / f).read_text()
    check(t.index("colors-fallback.rasi") < t.index("current/"), "rofi: fallback is imported before the theme file (theme wins)")
t = (config / "kitty/kitty.conf").read_text()
check(t.index("colors-fallback.conf") < t.index("current/"), "kitty: fallback is included before the theme file (theme wins)")

# every colour name the apps use is defined by the generated file
def defined(path, pattern):
    return set(re.findall(pattern, (dusk / path).read_text(), flags=re.M))

for app, style, gen, pat in (
        ("waybar", "waybar/style.css", "waybar-colors.css", r"@define-color ([\w-]+)"),
        ("swaync", "swaync/style.css", "swaync-colors.css", r"@define-color ([\w-]+)")):
    text = "\n".join(p.read_text() for p in (config / app).rglob("*.css") if "fallback" not in p.name)
    used = set(re.findall(r"@([\w-]+)", text)) - {"import", "keyframes"}
    missing = used - defined(gen, pat)
    check(not missing, f"{app}: every @colour the CSS uses is defined by {gen}", str(sorted(missing)))
rofi_text = (config / "rofi/themes/theme.rasi").read_text()
used = set(re.findall(r"@([\w-]+)", rofi_text)) - {"import"}
missing = used - defined("rofi-colors.rasi", r"^\s*([\w-]+):")
check(not missing, "rofi: every @colour the theme uses is defined by rofi-colors.rasi", str(sorted(missing)))

# ------------------------------------------------- 4. file formats
def load_jsonc(path):
    text = re.sub(r"^\s*//.*$", "", (config / path).read_text(), flags=re.M)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)

waybar = load_jsonc("waybar/config.json")
swaync = load_jsonc("swaync/config.json")
fastfetch = load_jsonc("fastfetch/config.jsonc")
ok("waybar, swaync and fastfetch configs parse as JSON")

for f in files():
    if f.suffix in (".css", ".rasi"):
        t = re.sub(r"/\*.*?\*/", "", f.read_text(), flags=re.S)
        check(t.count("{") == t.count("}"), f"braces balance in {f.relative_to(repo)}")

# ------------------------------------------------- 5. waybar
check(isinstance(waybar, list) and len(waybar) == 2, "waybar config is two bars: primary and the others")
prim, sec = waybar[0], waybar[1]
check(prim["output"] == "DP-1" and sec["output"] == ["!DP-1"], "primary is DP-1, the other bar takes every other output")
for bar in waybar:
    check(bar["position"] == "top" and bar["height"] == 32 and bar["layer"] == "top" and bar["exclusive"] is True
          and not any(k.startswith("margin") for k in bar), "bar: top, height 32, layer top, exclusive, attached (no margins)")
    for zone in ("modules-left", "modules-center", "modules-right"):
        for m in bar[zone]:
            check(m in bar, f"module {m} has its configuration ({bar['name']} bar)")
check(prim["modules-left"] == ["custom/mark", "hyprland/workspaces", "hyprland/window"], "primary left: mark, workspaces, window title")
check(prim["modules-center"] == ["clock"], "primary centre: clock")
check(prim["modules-right"] == ["custom/now", "tray", "custom/updates", "custom/alert", "pulseaudio", "network", "custom/swaync"],
      "primary right: Now, tray, updates, alert, volume, network, notifications", str(prim["modules-right"]))
check(sec["modules-right"] == [] and sec["modules-left"] == ["hyprland/workspaces", "hyprland/window"] and sec["modules-center"] == ["clock"],
      "other monitors: workspaces and window title, clock, nothing on the right")
allmods = {m for bar in waybar for z in ("modules-left", "modules-center", "modules-right") for m in bar[z]}
check(not ({"custom/gpu", "custom/cpu", "custom/memory"} & allmods), "the GPU, CPU and memory pills are gone")
check(prim["custom/alert"]["interval"] == 5 and "alert.sh" in prim["custom/alert"]["exec"], "alert module polls every 5 s and runs alert.sh")
check(prim["hyprland/window"]["max-length"] == 60 and prim["hyprland/window"]["separate-outputs"] is True, "window title: max 60, separate outputs")
check(prim["tray"]["icon-size"] == 16, "tray icon size 16")
check(prim["pulseaudio"]["scroll-step"] == 5 and prim["pulseaudio"]["on-click"] == "pavucontrol", "volume: scroll 5, click opens pavucontrol")
check(prim["clock"]["format"] == "{:%H:%M}" and "%A %d %B %Y" in prim["clock"]["tooltip-format"], "clock: HH:MM, tooltip has the long date")
check(prim["custom/swaync"]["exec"] == "swaync-client -swb" and prim["custom/swaync"]["on-click"] == "swaync-client -t -sw", "notifications: swaync-client -swb, click toggles")
check((config / "waybar/alert.sh").exists(), "alert.sh ships")
persist = prim["hyprland/workspaces"]["persistent-workspaces"]
check(persist == {"DP-1": [1, 2, 3], "DP-2": [4, 5, 6], "HDMI-A-2": [7, 8, 9]} and sec["hyprland/workspaces"]["persistent-workspaces"] == persist,
      "workspaces keep the persistent 1-3 / 4-6 / 7-9 split")
css = (config / "waybar/style.css").read_text()
check("box-shadow: inset 0 -2px @sol" in css, "active workspace has the 2 px sol bar")
check("color: @pompeii" in css.split("#custom-alert.hot")[1][:60], "hot alert is pompeii")
check("transition" in (config / "waybar/motion.css").read_text() and "none" in (config / "waybar/motion/off.css").read_text()
      and "120ms" in (config / "waybar/motion/calm.css").read_text() and "150ms" in (config / "waybar/motion.css").read_text(),
      "waybar motion: Showcase 150 ms, Calm 120 ms, Off none")

# ------------------------------------------------- 6. swaync
check(swaync["transition-time"] == 220 and swaync["timeout"] == 5 and swaync["timeout-low"] == 3 and swaync["timeout-critical"] == 0,
      "swaync: slide 220 ms (Showcase), normal 5 s, low 3 s, critical stays")
check(swaync["notification-window-width"] == 380 and swaync["control-center-width"] == 400, "swaync: cards 380 px, control centre 400 px")
check(swaync["positionX"] == "right" and swaync["positionY"] == "top", "swaync: top right")
check("mpris" not in swaync["widgets"] and "volume" not in swaync["widgets"] and "backlight" not in swaync["widgets"],
      "control centre has no player or sliders")
check(swaync["widgets"][0] == "dnd" and swaync["widgets"][1] == "notifications", "control centre: Do not disturb, then the list")
acc = (config / "swaync/accent.css").read_text()
check("@keyframes sunrise" in acc and "300ms" in acc and "inset 3px 0 @sol" in acc and acc.count("animation: none") >= 1,
      "swaync: Dusk's sunrise accent, 300 ms, none on critical")
for name, needle in (("dye", "border-color"), ("ripple", "0 0 0 14px"), ("beam", "background-position")):
    t = (config / f"swaync/accents/{name}.css").read_text()
    check(f"@keyframes {name}" in t and needle in t and "300ms" in t and "animation: none" in t, f"swaync accent {name} ships, 300 ms, none on critical")
for level in ("calm", "off"):
    check("animation: none" in (config / f"swaync/motion/{level}.css").read_text(), f"swaync motion/{level}.css turns the accent off")
check("border-radius: 12px" in (config / "swaync/style.css").read_text() and "box-shadow: inset 3px 0 @pompeii" in (config / "swaync/style.css").read_text(),
      "swaync: radius 12, critical has a 3 px pompeii bar")

# ------------------------------------------------- 7. rofi, kitty, btop, cava, fastfetch
rasi = (config / "rofi/themes/theme.rasi").read_text()
rc = (config / "rofi/config.rasi").read_text()
check('modi: "drun";' in rc and re.search(r'modi: "([^"]*)"', rc).group(1).split(",") == ["drun"], "rofi: drun only")
for needle in ("width: 560px;", "y-offset: 18%;", "border-radius: 12px;", "padding: 12px;", "lines: 8;", "size: 24px;",
               "scrollbar: false;", 'placeholder: "Search apps";', "border-color: @sol;", "Enter open   Ctrl+Enter run as typed"):
    check(needle in rasi, f"rofi theme has {needle}")

kc = (config / "kitty/kitty.conf").read_text()
for needle in ("font_family      IBM Plex Mono", "font_size        12.5", "modify_font cell_height 110%", "background_opacity 1.0",
               "window_padding_width 10 14", "cursor_shape block", "tab_bar_style separator", 'tab_separator " · "',
               "tab_bar_edge top", "tab_bar_min_tabs 2", "url_style single"):
    check(needle in kc, f"kitty.conf has {needle}")
check(not re.search(r"^(cursor_trail|cursor_blink|cursor_stop)", kc, re.M), "kitty.conf leaves cursor motion to the motion files")

def kitty_opts(name):
    out = {}
    for line in (config / f"kitty/motion/{name}.conf").read_text().split("\n"):
        if line.strip() and not line.startswith("#"):
            k, _, v = line.partition(" ")
            out[k] = v.strip()
    return out

check(kitty_opts("showcase") == {"cursor_blink_interval": "0.5 ease-in-out", "cursor_stop_blinking_after": "0", "cursor_trail": "50",
      "cursor_trail_decay": "0.12 0.45", "cursor_trail_start_threshold": "2", "cursor_trail_color": "none"},
      "kitty Showcase = Alex's original cursor values", str(kitty_opts("showcase")))
c = kitty_opts("calm")
check(c["cursor_trail"] == "3" and c["cursor_trail_decay"] == "0.08 0.3" and c["cursor_stop_blinking_after"] == "15", "kitty Calm = Venus's shorter values", str(c))
o = kitty_opts("off")
check(o["cursor_trail"] == "0" and o["cursor_blink_interval"] == "0", "kitty Off: no trail, no blink", str(o))
check("include motion/showcase.conf" in kc and "globinclude ~/.config/invictus/motion.d/kitty.conf" in kc
      and kc.index("include motion/showcase.conf") < kc.index("globinclude ~/.config/invictus/motion.d/kitty.conf"),
      "kitty: Showcase is the default, the motion.d link overrides it")

btop = (config / "btop/btop.conf").read_text()
check("rounded_corners = true" in btop, "btop: rounded corners")
cava_cfg = (config / "cava/config").read_text()
check(not re.search(r"^shader", cava_cfg, re.M) and (config / "cava/shaders").is_dir(), "cava: no shader by default, shaders still shipped")
ff_logo = (config / "fastfetch/logo.txt").read_text().rstrip("\n").split("\n")
check(len(ff_logo) == 9 and all(l.startswith("$1") for l in ff_logo), "fastfetch logo is 9 lines in colour 1")
check(fastfetch["logo"]["color"] == {"1": "yellow"} and fastfetch["logo"]["type"] == "file", "fastfetch logo coloured with the terminal's yellow (sol in Dusk)")
mods = [m if isinstance(m, str) else m["type"] for m in fastfetch["modules"]]
check(mods == ["title", "separator", "os", "kernel", "uptime", "packages", "wm", "terminal", "shell", "cpu", "gpu", "memory", "disk"],
      "fastfetch modules: title, OS, kernel, uptime, packages, WM, terminal, shell, CPU, GPU, memory, disk", str(mods))
osm = [m for m in fastfetch["modules"] if isinstance(m, dict) and m["type"] == "os"][0]
check(osm["format"] == "Invictus (based on Arch Linux)", "fastfetch OS line says Invictus (based on Arch Linux)")
disk = [m for m in fastfetch["modules"] if isinstance(m, dict) and m["type"] == "disk"][0]
check(disk["folders"] == "/", "fastfetch disk is /")
zsh = (config / "shell/zshrc").read_text()
check("alias cmatrix='cmatrix -C white -a -b -u 6'" in zsh and re.search(r"^\[\[ \$- == \*i\* \]\] && fastfetch$", zsh, re.M),
      "zshrc keeps the cmatrix alias and runs fastfetch at start (no forced colours)")

# ------------------------------------------------- 8. launcher entries
for name, exe, entry in (("invictus-theme", "invictus-theme pick", "Change theme"), ("invictus-motion", "invictus-motion pick", "Change motion")):
    text = (config / f"applications/{name}.desktop").read_text()
    kv = dict(l.split("=", 1) for l in text.split("\n") if "=" in l and not l.startswith("#"))
    check(kv.get("Type") == "Application" and kv.get("Name") == entry and kv.get("Exec") == exe and kv.get("Terminal") == "false"
          and kv.get("Icon") and kv.get("Categories", "").endswith(";"), f"{name}.desktop is valid and runs '{exe}'")
check("NoDisplay=true" in (config / "applications/invictus-motion.desktop").read_text(), "the motion entry stays hidden until invictus-motion exists")
check("NoDisplay" not in (config / "applications/invictus-theme.desktop").read_text(), "the theme entry shows in the launcher")

# ------------------------------------------------- 9. the "Now" module and alert.sh
import os
import tempfile

with tempfile.TemporaryDirectory() as home:
    now_cmd = prim["custom/now"]["exec"]
    env = dict(os.environ, HOME=home)
    def run_now():
        return subprocess.run(["sh", "-c", now_cmd], env=env, capture_output=True, text=True).stdout
    check(run_now() == "", "Now: nothing when the state file is missing (the module hides)")
    state = Path(home, ".local/state/invictus")
    state.mkdir(parents=True)
    (state / "now").write_text("Port waybar to Lua\nsecond line\n")
    check(run_now().strip() == "Port waybar to Lua", "Now: first line of ~/.local/state/invictus/now", run_now())
    (state / "now").write_text("x" * 100 + "\n")
    check(len(run_now().strip()) == 40, "Now: cut to 40 characters", str(len(run_now().strip())))
    (state / "now").write_text("")
    check(run_now() == "", "Now: empty file hides it")

def alert(**kw):
    with tempfile.TemporaryDirectory() as d:
        env = dict(os.environ, ALERT_CPU_WAIT="0", ALERT_MEMINFO=f"{d}/mem", ALERT_PROC_STAT=f"{d}/stat", ALERT_DF="echo 40%",
                   ALERT_GPU_TEMP=f"{d}/gpu")
        Path(d, "stat").write_text("cpu  100 0 100 800 0 0 0 0 0 0\n")
        Path(d, "mem").write_text(f"MemTotal: 1000 kB\nMemAvailable: {kw.get('avail', 800)} kB\n")
        Path(d, "gpu").write_text(f"{kw.get('gpu', 50)}000\n")
        env["ALERT_DF"] = f"echo {kw.get('disk', 40)}%"
        if "cpu" in kw:
            # CPU is the busy share between two samples of /proc/stat: start at zero, and
            # let the stub `sleep` between the samples write the second reading
            Path(d, "stat").write_text("cpu  0 0 0 0 0 0 0 0 0 0\n")
            second = f"cpu  {kw['cpu']} 0 0 {100 - kw['cpu']} 0 0 0 0 0 0\n"
            env["PATH"] = f"{d}:{env['PATH']}"
            Path(d, "sleep").write_text(f"#!/bin/sh\nprintf '%s' '{second}' > '{d}/stat'\n")
            Path(d, "sleep").chmod(0o755)
        r = subprocess.run(["bash", str(config / "waybar/alert.sh")], env=env, capture_output=True, text=True)
        return json.loads(r.stdout)

quiet = alert()
check(quiet["text"] == "" and quiet["class"] == "" and "GPU 50 °C" in quiet["tooltip"] and "RAM 20%" in quiet["tooltip"]
      and "CPU" in quiet["tooltip"] and "Disk / 40%" in quiet["tooltip"], "alert.sh: hidden while everything is under 90, tooltip lists all four", str(quiet))
hot = alert(gpu=94)
check(hot["text"] == "󰢮 94 °C" and hot["class"] == "hot", "alert.sh: GPU at 94 °C shows that reading, hot", str(hot))
hot = alert(avail=50)
check(hot["text"] == "󰘚 95%" and hot["class"] == "hot", "alert.sh: RAM at 95% shows that reading", str(hot))
hot = alert(disk=93)
check(hot["text"] == "󰋊 93%" and hot["class"] == "hot", "alert.sh: root disk at 93% shows that reading", str(hot))
hot = alert(cpu=97)
check(hot["text"] == "󰻠 97%" and hot["class"] == "hot", "alert.sh: CPU at 97% shows that reading", str(hot))
edge = alert(gpu=89)
check(edge["text"] == "", "alert.sh: 89 °C is still quiet", str(edge))

sys.exit(1 if failures else 0)
