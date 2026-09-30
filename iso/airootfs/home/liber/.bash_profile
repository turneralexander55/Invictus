# Invictus live session: start the desktop (or the installer kiosk) on tty1.
[[ -f ~/.bashrc ]] && . ~/.bashrc
if [[ -z "${WAYLAND_DISPLAY:-}" && "$(tty)" == /dev/tty1 ]]; then
    exec /usr/lib/invictus/live/session
fi
