#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-doctor: read-only health checks (design 1.4, 1.5).
# Installed as /usr/bin/invictus-doctor by invictus-tools.
#
#   invictus-doctor                 all checks
#   invictus-doctor --post-update   all checks, plus what to do if one fails
#   invictus-doctor --hypr          only the Hyprland config check
#   invictus-doctor --diff PATH     show how your copy of a shipped default
#                                   differs from the one installed now
#                                   (PATH as listed, e.g. waybar/config.json)
#
# Checks:
#   hypr      your Hyprland config loads: Hyprland --verify-config when
#             Hyprland is installed, and the stub check (the test mock of
#             `hl` against the API stubs Hyprland ships) for hyprland.lua
#   pinned    installed hypr* versions match the tested set
#   repo      [invictus-testing]/[invictus] comes before [extra]
#   snapshots btrfs root: snapper has a root config and snap-pac is there
#   guardrails Custodia or Libertas (since, until), nets that are off, and
#             whether the derived files match the setting
#   kernel    each installed kernel has its image, initramfs and a boot
#             entry; the running kernel's modules still exist
#   defaults  your copies of the shipped defaults: which changed upstream
#             since first login (never overwritten, only listed)
#
# Changes nothing. Exit 0 when nothing FAILs, 1 otherwise.
# Lines: "ok    ", "note  ", "warn  ", "FAIL  " then check: message.
# ------------------------------------------------------------
set -uo pipefail

LIB="${INVICTUS_LIB:-/usr/lib/invictus}"
# shellcheck source=scripts/lib/defaults.sh
. "${INVICTUS_DEFAULTS_SH:-$LIB/lib/defaults.sh}"

HYPRLAND="${INVICTUS_HYPRLAND:-Hyprland}"
STUBS="${HL_STUBS:-/usr/share/hypr/stubs/hl.meta.lua}"
KEYSYMS="${XKB_KEYSYMS_H:-/usr/include/xkbcommon/xkbcommon-keysyms.h}"
BOOT="${INVICTUS_BOOT:-/boot}"
MODULES="${INVICTUS_MODULES:-/usr/lib/modules}"
PACMAN_CONF="${INVICTUS_PACMAN_CONF:-/etc/pacman.conf}"
GUARDRAILS="${INVICTUS_GUARDRAILS:-/usr/lib/invictus/guardrails}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

MODE=all
DIFF_PATH=""
case "${1:-}" in
    "") ;;
    --post-update) MODE="post" ;;
    --hypr) MODE="hypr" ;;
    --diff) MODE="diff"; DIFF_PATH="${2:?--diff needs a path}" ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "invictus-doctor: unknown argument $1" >&2; exit 2 ;;
esac

fails=0 warns=0
ok()   { printf 'ok    %s\n' "$*"; }
note() { printf 'note  %s\n' "$*"; }
warn() { printf 'warn  %s\n' "$*"; warns=$((warns + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

pick_lua() {
    local c
    for c in "${LUA:-}" lua5.5 lua5.4 lua; do
        [[ -n "$c" ]] && command -v "$c" >/dev/null && { command -v "$c"; return 0; }
    done
    return 1
}

# ---- hypr ----------------------------------------------------------------------
check_hypr() {
    local conf lua out rc tmp
    if [[ -f "$CFG/hypr/hyprland.lua" ]]; then conf="$CFG/hypr/hyprland.lua"
    elif [[ -f "$CFG/hypr/hyprland.conf" ]]; then conf="$CFG/hypr/hyprland.conf"
    else fail "hypr: no ~/.config/hypr/hyprland.lua or hyprland.conf"; return; fi

    if command -v "$HYPRLAND" >/dev/null; then
        # --verify-config parses without starting a session. It logs into its
        # working folder, so give it a throwaway one.
        tmp="$(mktemp -d)"
        out="$(cd "$tmp" && XDG_RUNTIME_DIR="$tmp" timeout 60 "$HYPRLAND" --verify-config -c "$conf" 2>&1)"; rc=$?
        rm -rf "$tmp"
        if [[ $rc -eq 0 ]]; then
            ok "hypr: $("$HYPRLAND" --version 2>/dev/null | head -1 | cut -c1-40) accepts $conf"
        else
            fail "hypr: Hyprland --verify-config rejects $conf:"
            sed -n '/Config parsing result/,$p' <<< "$out" | grep -v '^=*$\|Config parsing result' | sed 's/^/        /' | head -20
        fi
    else
        note "hypr: Hyprland is not installed here; stub check only"
    fi

    [[ "$conf" == *.lua ]] || { note "hypr: hyprland.conf (hyprlang) is in use; the stub check is for hyprland.lua"; return; }
    if ! lua="$(pick_lua)"; then warn "hypr: no Lua interpreter for the stub check"; return; fi
    if [[ ! -f "$STUBS" ]]; then warn "hypr: no API stubs at $STUBS; stub check skipped"; return; fi
    [[ -f "$KEYSYMS" ]] || KEYSYMS=""
    out="$("$lua" "$LIB/doctor/hypr-check.lua" "$conf" "$STUBS" "$KEYSYMS" 2>&1)"; rc=$?
    case $rc in
        0) ok "hypr: stub check passes ($(grep -c '^warning' <<< "$out") warnings)" ;;
        1) fail "hypr: stub check found errors:"; grep '^error' <<< "$out" | sed 's/^/        /' | head -20 ;;
        *) warn "hypr: stub check could not run: $out" ;;
    esac
}

# ---- pinned --------------------------------------------------------------------
check_pinned() {
    local list="$INVICTUS_SHARE/pinned-hypr.txt" name want have diff=0
    [[ -f "$list" ]] || { note "pinned: no $list (invictus-desktop not installed)"; return; }
    command -v pacman >/dev/null || { note "pinned: pacman not found"; return; }
    while read -r name want; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        have="$(pacman -Q "$name" 2>/dev/null | cut -d' ' -f2)"
        if [[ -z "$have" ]]; then continue
        elif [[ "$have" != "$want" ]]; then
            warn "pinned: $name $have installed, Invictus tested $want"; diff=1
        fi
    done < "$list"
    [[ $diff == 0 ]] && ok "pinned: hypr* versions match the tested set"
    # Other hypr* apps link the same libraries; if Arch moves them past the
    # pinned set, pacman -Syu stops with a dependency error.
    local extra
    extra="$(pacman -Qq 2>/dev/null | grep -E '^hypr' | grep -vxF -f <(cut -d' ' -f1 "$list") | grep -vx 'hyprshot' | tr '\n' ' ')"
    [[ -z "$extra" ]] || note "pinned: installed hypr* apps outside the pinned set (can block an update if Arch moves them first): $extra"
}

# ---- repo order ----------------------------------------------------------------
check_repo() {
    [[ -f "$PACMAN_CONF" ]] || { note "repo: no $PACMAN_CONF"; return; }
    local sections ours extra
    sections="$(grep -E '^\[[^]]+\]' "$PACMAN_CONF" | tr -d '[]' | grep -vx options)"
    ours="$(grep -nxE 'invictus(-testing)?' <<< "$sections" | head -1 | cut -d: -f1)"
    extra="$(grep -nx extra <<< "$sections" | head -1 | cut -d: -f1)"
    if [[ -z "$ours" ]]; then warn "repo: no [invictus] or [invictus-testing] in $PACMAN_CONF"
    elif [[ -n "$extra" && "$ours" -gt "$extra" ]]; then fail "repo: our repo comes after [extra], so the hypr* pin does not hold"
    else ok "repo: $(sed -n "${ours}p" <<< "$sections") comes before [extra]"; fi
}

# ---- snapshots -----------------------------------------------------------------
check_snapshots() {
    local fstype
    fstype="${INVICTUS_ROOT_FSTYPE:-$(findmnt -no FSTYPE / 2>/dev/null)}"
    if [[ "$fstype" != btrfs ]]; then
        note "snapshots: / is ${fstype:-unknown}, not btrfs: no snapshots (they come with the Phase 3 install)"
        return
    fi
    if ! command -v snapper >/dev/null; then warn "snapshots: / is btrfs but snapper is not installed"; return; fi
    if [[ ! -f /etc/snapper/configs/root ]]; then warn "snapshots: snapper has no 'root' config"; return; fi
    if pacman -Q snap-pac >/dev/null 2>&1; then ok "snapshots: snapper root config and snap-pac present"
    else warn "snapshots: snap-pac is not installed, so updates take no snapshots"; fi
    local n
    if n="$(snapper -c root --no-headers list 2>/dev/null | wc -l)"; then
        if [[ "$n" -gt 1 ]]; then ok "snapshots: $((n - 1)) root snapshots"; else warn "snapshots: no root snapshots yet"; fi
    else
        note "snapshots: cannot list snapshots as $(id -un) (sudo invictus-doctor shows them)"
    fi
}

# ---- kernel --------------------------------------------------------------------
check_kernel() {
    local k found=0 entries
    for k in linux linux-lts linux-zen linux-hardened linux-cachyos; do
        pacman -Q "$k" >/dev/null 2>&1 || continue
        found=1
        [[ -f "$BOOT/vmlinuz-$k" ]] || { fail "kernel: $k is installed but $BOOT/vmlinuz-$k is missing"; continue; }
        [[ -f "$BOOT/initramfs-$k.img" ]] || { fail "kernel: $BOOT/initramfs-$k.img is missing"; continue; }
        entries="$( { cat "$BOOT"/limine.conf "$BOOT"/limine/limine.conf "$BOOT"/EFI/limine/limine.conf \
            "$BOOT"/loader/entries/*.conf "$BOOT"/grub/grub.cfg; } 2>/dev/null)"
        if [[ -z "$entries" ]]; then note "kernel: $k image and initramfs present; no limine, systemd-boot or grub config found to check"
        elif grep -q "vmlinuz-$k\b" <<< "$entries"; then ok "kernel: $k has image, initramfs and a boot entry"
        else fail "kernel: no boot entry names vmlinuz-$k"; fi
    done
    [[ $found == 1 ]] || note "kernel: no Arch kernel package found"
    local running
    running="$(uname -r)"
    [[ -d "$MODULES/$running" ]] || warn "kernel: modules for the running kernel $running are gone (updated): reboot soon"
}

# ---- guard rails -----------------------------------------------------------------
# design-simple-mode TS11, SM24: say which guard rails are on, since when and
# until when, which nets are off, and whether the derived files match.
check_guardrails() {
    local st rails until by n
    [[ -x "$GUARDRAILS" ]] || { note "guard rails: invictus-guardrails is not installed"; return; }
    st="$("$GUARDRAILS" status 2>/dev/null)" || { warn "guard rails: could not read the state"; return; }
    val() { sed -n "s/^$1=//p" <<< "$st"; }
    rails="$(val effective)"; until="$(val until)"; by="$(val by)"
    if [[ "$rails" == custodia ]]; then ok "guard rails: Custodia"
    elif [[ -n "$until" ]]; then note "guard rails: Libertas until $until${by:+ (by $by)}"
    else note "guard rails: Libertas"; fi
    for n in pre-admin-snapshot auto-update boot-guard home-snapshots; do
        [[ "$(val "net.$n")" == off ]] && note "guard rails: safety net $n is off"
    done
    [[ "$(val full-access)" == on ]] && note "guard rails: Moneta has full access (terminal and every tool)"
    if "$GUARDRAILS" apply --check >/dev/null 2>&1; then ok "guard rails: the derived files match"
    else warn "guard rails: the derived files do not match (sudo invictus-sys guardrails apply)"; fi
}

# ---- defaults ------------------------------------------------------------------
check_defaults() {
    local rel user shipped rec u s n=0 changed=() both=() missing=()
    [[ -d "$INVICTUS_SHARE/config" ]] || { note "defaults: $INVICTUS_SHARE/config not installed"; return; }
    while IFS= read -r rel; do
        user="$(default_user_path "$rel")"
        shipped="$INVICTUS_SHARE/config/$rel"
        n=$((n + 1))
        if [[ ! -e "$user" ]]; then
            default_user_owned "$rel" || missing+=("$rel")
            continue
        fi
        default_user_owned "$rel" && continue
        cmp -s "$user" "$shipped" && continue
        rec="$(recorded_default "$rel")"
        u="$(file_sha "$user")"; s="$(file_sha "$shipped")"
        if [[ -z "$rec" ]]; then both+=("$rel")          # we cannot tell who changed it
        elif [[ "$u" == "$rec" ]]; then changed+=("$rel") # untouched by you; the default moved on
        elif [[ "$s" != "$rec" ]]; then both+=("$rel")    # you and the default both changed it
        fi                                                # else: yours, the default is unchanged
    done < <(default_files)
    ok "defaults: $n shipped defaults compared with your copies"
    local r
    for r in "${changed[@]}"; do note "defaults: new version of $r (you never edited yours): invictus-doctor --diff $r"; done
    for r in "${both[@]}"; do note "defaults: $r differs from the shipped one: invictus-doctor --diff $r"; done
    [[ ${#missing[@]} -eq 0 ]] || note "defaults: not in your home: ${missing[*]}"
}

show_diff() {
    local rel="${1#/}" user shipped
    shipped="$INVICTUS_SHARE/config/$rel"
    [[ "$rel" != *..* && -f "$shipped" ]] || { echo "No shipped default called $rel" >&2; exit 2; }
    user="$(default_user_path "$rel")"
    [[ -f "$user" ]] || { echo "You have no $user; the shipped one is $shipped"; exit 0; }
    diff -u --label "yours: $user" --label "shipped: $shipped" "$user" "$shipped"
    exit 0
}

case "$MODE" in
    diff) show_diff "$DIFF_PATH" ;;
    hypr) check_hypr ;;
    *) check_hypr; check_pinned; check_repo; check_snapshots; check_guardrails; check_kernel; check_defaults ;;
esac

echo
echo "invictus-doctor: $fails failed, $warns warnings"
if [[ "$MODE" == post && $fails -gt 0 ]]; then
    echo
    echo "Something above failed after the update. Nothing was changed by this check."
    echo "If the desktop does not start, reboot and pick the snapshot taken before"
    echo "this update from the boot menu's Snapshots entry (if this machine has one),"
    echo "or log in on a text console (Ctrl+Alt+F3) and fix the file named above."
fi
[[ $fails -eq 0 ]]
