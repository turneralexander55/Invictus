#!/usr/bin/env bash
# ------------------------------------------------------------
# adopt.sh: move a machine set up by the old hyprdots scripts (a clone
# at ~/hyprdots, configs copied into ~/.config, hyprland.conf) onto the
# Invictus packages and the Lua config. Run it as yourself, from a
# checkout of this repo that is NOT the old clone (for example
# ~/src/invictus), so the old clone keeps working until you are done.
#
#   adopt.sh                      print the plan; change nothing
#   adopt.sh --apply              do it
#   adopt.sh --undo               print what undo would do (latest adopt)
#   adopt.sh --undo --apply       put the machine back as it was
#   adopt.sh --undo STAMP --apply undo a specific run (see ~/.local/state/invictus/adopt/)
#
# Options:
#   --legacy DIR          the old clone (default: ~/hyprdots, else ~/invictus)
#   --server URL          [invictus-testing] server (default: the GitHub release)
#   --key FILE            the repo's public key (default: pkgs/own/invictus-keyring/invictus.gpg)
#   --unsigned-local DIR  dry-run/test mode: use a local repo folder built by
#                         scripts/build-repo.sh without a key. pacman trusts it
#                         with "SigLevel = Optional TrustAll", so this only
#                         accepts a local folder, never a URL.
#   --skip gaming|dev     leave out invictus-gaming or invictus-dev (repeatable)
#   --yes                 no pacman questions
#
# What it does (each step is printed with its command before it runs):
#   1. checks: Arch, the old config is there, not adopted already, [multilib]
#      for gaming, the key (signed mode), which packages would come from where
#   2. backs up ~/.config/{hypr,waybar,rofi,kitty,swaync}, /etc/pacman.conf,
#      the package list and the first-login state into
#      ~/.local/state/invictus/adopt/<STAMP>/, plus any wallpaper the old
#      hyprpaper.conf takes from the old clone
#   3. adds [invictus-testing] to /etc/pacman.conf ahead of the Arch repos
#      (between "# BEGIN invictus" and "# END invictus"), imports and
#      locally signs the key (signed mode)
#   4. sudo pacman -Syu --needed invictus-keyring invictus-desktop
#      invictus-tessera invictus-gaming invictus-dev (never invictus-base:
#      no limine or snap-pac on this machine; never a partial upgrade)
#   5. writes ~/.config/hypr/monitors.lua (from monitors.conf) and
#      ~/.config/hypr/user.lua (your own binds such as dashboard-tmux, and
#      every other line you added, as comments; workspace = N, monitor:X lines
#      become hl.workspace_rule; anything it cannot port, such as monitorv2
#      blocks, is listed as "not ported" with file and line), then runs
#      invictus-first-login --adopt: hyprland.lua (the loader) is added, the
#      hypr/waybar/rofi/kitty/swaync defaults replace the old copies. Your
#      hyprland.conf and config/*.conf stay where they are, unused
#      (Hyprland prefers hyprland.lua).
#   6. invictus-doctor --hypr; if the new config does not load, the config
#      folders are put back at once and it stops.
# Then log out and back in.
#
# Undo reverses whichever of these steps ran: config folders back exactly
# as they were, the packages adopt installed removed (pacman -Rn), the key
# deleted, the pacman.conf block removed. Packages that -Syu upgraded stay
# upgraded, and the GTK settings the theme set (gsettings accent-color,
# gtk-theme) stay; reset them with gsettings reset if you want.
# ------------------------------------------------------------
# -E: the ERR trap below must also fire for a failure inside cmd() (a function).
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/lib/defaults.sh
. "$ROOT/scripts/lib/defaults.sh"

REPO_NAME="invictus-testing"
SERVER="https://github.com/turneralexander55/invictus/releases/download/invictus-testing"
KEY_FILE="$ROOT/pkgs/own/invictus-keyring/invictus.gpg"
PACMAN_CONF="/etc/pacman.conf"
SUDO="${ADOPT_SUDO:-sudo}"
# Backed up before, put back by undo: every ~/.config folder the shipped
# defaults touch (first-login --adopt replaces hypr, waybar, rofi, kitty and
# swaync, and adds any default that is missing), plus invictus/ (theme and
# motion level). ~/.zshrc is handled the same way below.
DIRS=(hypr waybar rofi kitty swaync btop cava fastfetch zed invictus)
# The same for ~/.local/state/invictus (first-login and theme state).
STATE_ITEMS=(first-login.done defaults.sha256 theme swatches backup)
BEGIN_MARK="# BEGIN invictus (added by scripts/dev/adopt.sh; remove with adopt.sh --undo)"
END_MARK="# END invictus"

APPLY=false UNDO=false UNDO_STAMP="" LEGACY="" LOCAL_REPO="" YES=false
SKIP=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply) APPLY=true; shift ;;
        --undo) UNDO=true; shift
                if [[ $# -gt 0 && "$1" != --* ]]; then UNDO_STAMP="$1"; shift; fi ;;
        --legacy) LEGACY="${2:?--legacy needs a folder}"; shift 2 ;;
        --server) SERVER="${2:?--server needs a URL}"; shift 2 ;;
        --key) KEY_FILE="${2:?--key needs a file}"; shift 2 ;;
        --unsigned-local) LOCAL_REPO="${2:?--unsigned-local needs a folder}"; shift 2 ;;
        --skip) case "${2:-}" in gaming|dev) SKIP+=("$2") ;; *) echo "--skip takes gaming or dev" >&2; exit 2 ;; esac; shift 2 ;;
        --yes) YES=true; shift ;;
        -h|--help) sed -n '2,62p' "$0"; exit 0 ;;
        *) echo "adopt.sh: unknown argument $1" >&2; exit 2 ;;
    esac
done

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="$(invictus_state_dir)"
ADOPT_ROOT="$STATE/adopt"
CONFIRM=()
$YES && CONFIRM=(--noconfirm)

# Put the config folders and first-login state back from backup folder $1.
restore_config() {
    local b="$1" d f
    for d in "${DIRS[@]}"; do
        if [[ -d "$b/config/$d" ]]; then
            cmd rm -rf "${CFG:?}/$d"
            cmd cp -a "$b/config/$d" "$CFG/$d"
        elif grep -qx "$d" "$b/absent-config.txt" 2>/dev/null; then
            cmd rm -rf "${CFG:?}/$d"
        fi
    done
    if [[ -f "$b/zshrc" ]]; then cmd cp -a "$b/zshrc" "$HOME/.zshrc"
    elif [[ -f "$b/absent-zshrc" ]]; then cmd rm -f "$HOME/.zshrc"; fi
    for f in "${STATE_ITEMS[@]}"; do
        cmd rm -rf "${STATE:?}/$f"
        if [[ -e "$b/state/$f" ]]; then cmd cp -a "$b/state/$f" "$STATE/$f"; fi
    done
    return 0
}

n=0
problems=()
step()    { n=$((n + 1)); echo; echo "[$n] $*"; }
info()    { echo "    $*"; }
problem() { echo "    PROBLEM: $*"; problems+=("$*"); }
# Print a command; run it only with --apply.
cmd() {
    printf '    $'; printf ' %q' "$@"; echo
    if $APPLY; then "$@"; fi
}
mark_step() { $APPLY && echo "$1" >> "$B/steps"; return 0; }
die() { echo "adopt.sh: $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run this as yourself, not root (it uses sudo for the system steps)"

if $APPLY; then echo "==> adopt.sh: APPLYING"; else echo "==> adopt.sh: dry run (nothing changes; add --apply to do it)"; fi

# ============================================================================
# undo
# ============================================================================
if $UNDO; then
    if [[ -z "$UNDO_STAMP" ]]; then
        [[ -L "$ADOPT_ROOT/latest" ]] || die "no adopt run to undo in $ADOPT_ROOT"
        UNDO_STAMP="$(basename "$(readlink "$ADOPT_ROOT/latest")")"
    fi
    B="$ADOPT_ROOT/$UNDO_STAMP"
    [[ -d "$B" ]] || die "no adopt run $UNDO_STAMP in $ADOPT_ROOT"
    [[ ! -f "$B/undone" ]] || die "$UNDO_STAMP was already undone on $(cat "$B/undone")"
    done_step() { grep -qx "$1" "$B/steps" 2>/dev/null; }
    echo "==> Undoing adopt run $UNDO_STAMP (steps done: $(tr '\n' ' ' < "$B/steps" 2>/dev/null))"

    # Cached copies of what came from our repo carry our signature; with the
    # key gone pacman would refuse them on a later reinstall. The list comes
    # from pacman's copy of our database, so read it now, while the repo and
    # its key are still there.
    cached=()
    if done_step pacman-conf; then
        mapfile -t cached < <(pacman -Sl "$REPO_NAME" 2>/dev/null | awk '{ print $2 "-" $3 }' | tr ':' '.' \
            | while read -r nv; do compgen -G "/var/cache/pacman/pkg/$nv-*.pkg.tar.zst*" || true; done)
    fi

    if done_step config; then
        step "Put the config folders back exactly as they were"
        info "(what is there now is kept in $B/before-undo first)"
        cmd mkdir -p "$B/before-undo"
        for d in "${DIRS[@]}"; do
            [[ -e "$CFG/$d" ]] && cmd cp -a "$CFG/$d" "$B/before-undo/$d"
        done
        restore_config "$B"
    fi
    if done_step backup; then
        if [[ -f "$B/created-files.txt" ]]; then
            while IFS= read -r f; do [[ -n "$f" ]] && cmd rm -f "$f"; done < "$B/created-files.txt"
        fi
    fi

    if done_step packages; then
        step "Remove the packages adopt installed"
        mapfile -t still < <(comm -12 <(sort -u "$B/packages-installed.txt") <(pacman -Qq | sort -u))
        if [[ ${#still[@]} -gt 0 ]]; then
            info "${#still[@]} packages: ${still[*]}"
            cmd "$SUDO" pacman -Rn "${CONFIRM[@]}" -- "${still[@]}"
        else
            info "none of them are installed any more"
        fi
    fi

    if done_step key && [[ -s "$B/key-fingerprint" ]]; then
        step "Delete the Invictus key from pacman's keyring"
        cmd "$SUDO" pacman-key --delete "$(cat "$B/key-fingerprint")"
    fi

    if done_step pacman-conf; then
        step "Remove the [$REPO_NAME] block from $PACMAN_CONF"
        tmp="$(mktemp)"
        # the block and the blank line adopt put after it
        awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
            $0 == b { skip = 1; next }
            skip && $0 == e { skip = 0; after = 1; next }
            after && $0 == "" { after = 0; next }
            { after = 0 }
            !skip' "$PACMAN_CONF" > "$tmp"
        diff -u --label "$PACMAN_CONF" --label "$PACMAN_CONF (after)" "$PACMAN_CONF" "$tmp" | sed 's/^/    /' || true
        cmd "$SUDO" install -m644 "$tmp" "$PACMAN_CONF"
        rm -f "$tmp"
        # pacman's copy of our database (and its signature) would otherwise
        # stay behind and confuse a later adopt.
        if [[ ${#cached[@]} -gt 0 ]]; then cmd "$SUDO" rm -f -- "${cached[@]}"; fi
        cmd "$SUDO" rm -f "/var/lib/pacman/sync/$REPO_NAME.db" "/var/lib/pacman/sync/$REPO_NAME.db.sig" \
            "/var/lib/pacman/sync/$REPO_NAME.files" "/var/lib/pacman/sync/$REPO_NAME.files.sig"
    fi

    if $APPLY; then
        date -Is > "$B/undone"
        [[ "$(readlink "$ADOPT_ROOT/latest" 2>/dev/null)" == "$UNDO_STAMP" ]] && rm -f "$ADOPT_ROOT/latest"
        echo
        echo "==> Undone. Log out and back in: Hyprland reads hyprland.conf again."
    else
        echo
        echo "==> Dry run. Run again with --apply to undo."
    fi
    exit 0
fi

# ============================================================================
# adopt
# ============================================================================
STAMP="$(date +%Y%m%d-%H%M%S)"
B="$ADOPT_ROOT/$STAMP"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SIGNED=true
[[ -n "$LOCAL_REPO" ]] && SIGNED=false

METAS=()
for m in desktop tessera gaming dev; do
    [[ " ${SKIP[*]} " == *" $m "* ]] || METAS+=("invictus-$m")
done
TARGETS=("${METAS[@]}")
$SIGNED && TARGETS=(invictus-keyring "${TARGETS[@]}")

# ---- 1. checks -------------------------------------------------------------
step "Checks"
if [[ -f /etc/arch-release ]]; then info "Arch Linux: yes"; else problem "this is not Arch Linux"; fi

if [[ -z "$LEGACY" ]]; then
    for c in "$HOME/hyprdots" "$HOME/invictus"; do
        [[ -d "$c/.git" || -f "$c/.git" ]] && { LEGACY="$c"; break; }
    done
fi
if [[ -n "$LEGACY" ]]; then
    LEGACY="$(cd "$LEGACY" && pwd)"
    info "old clone: $LEGACY ($(git -C "$LEGACY" log -1 --format='%h %cs' 2>/dev/null || echo 'not a git clone'))"
    [[ "$LEGACY" != "$ROOT" ]] || problem "run adopt.sh from a separate checkout, not from the old clone $LEGACY"
else
    info "old clone: none found (~/hyprdots, ~/invictus); only binds that run programs from your home are ported"
fi

if [[ -f "$CFG/hypr/hyprland.lua" ]] && ! is_autogenerated_hypr "$CFG/hypr/hyprland.lua"; then
    problem "$CFG/hypr/hyprland.lua exists: this home already uses a Lua config (adopted before? see $ADOPT_ROOT)"
elif [[ -f "$CFG/hypr/hyprland.conf" ]]; then
    info "old config: $CFG/hypr/hyprland.conf"
else
    problem "no $CFG/hypr/hyprland.conf: nothing to adopt (a new home gets its config at first login)"
fi
if [[ -L "$ADOPT_ROOT/latest" ]]; then
    problem "adopt already ran ($(basename "$(readlink "$ADOPT_ROOT/latest")")); undo it first: adopt.sh --undo"
fi

if grep -qxF "$BEGIN_MARK" "$PACMAN_CONF"; then
    problem "$PACMAN_CONF already has an adopt block"
elif grep -qE "^\[(invictus|invictus-testing)\]" "$PACMAN_CONF"; then
    problem "$PACMAN_CONF already lists an Invictus repo (added by hand?); remove it first"
fi

if [[ " ${METAS[*]} " == *" invictus-gaming "* ]] && ! grep -qx '\[multilib\]' "$PACMAN_CONF"; then
    problem "invictus-gaming needs [multilib] enabled in $PACMAN_CONF (or use --skip gaming)"
fi

FPR=""
if $SIGNED; then
    info "repo: $SERVER (signed)"
    if [[ ! -f "$KEY_FILE" ]]; then problem "no key file $KEY_FILE"
    elif grep -q INVICTUS-PLACEHOLDER "$KEY_FILE"; then
        problem "the repo key is still the placeholder (docs/checklists/signing-key.md); for a test, use --unsigned-local"
    else
        FPR="$(gpg --batch --with-colons --show-keys "$KEY_FILE" 2>/dev/null | awk -F: '/^fpr:/ { print $10; exit }')"
        if [[ -n "$FPR" ]]; then info "key fingerprint: $FPR (compare it with the one you made)"
        else problem "no public key in $KEY_FILE"; fi
        if grep -q 'PRIVATE KEY' "$KEY_FILE"; then problem "$KEY_FILE holds a PRIVATE key"; fi
    fi
    OUR_SIGLEVEL="Required DatabaseRequired"
    OUR_SERVER="$SERVER"
else
    [[ "$LOCAL_REPO" != *://* ]] || die "--unsigned-local takes a local folder, not a URL (an unsigned remote repo is never allowed)"
    LOCAL_REPO="$(cd "$LOCAL_REPO" 2>/dev/null && pwd)" || die "--unsigned-local: no such folder"
    [[ -f "$LOCAL_REPO/$REPO_NAME.db" ]] || problem "$LOCAL_REPO has no $REPO_NAME.db (build it with scripts/build-repo.sh)"
    info "repo: file://$LOCAL_REPO (UNSIGNED local test mode: SigLevel = Optional TrustAll)"
    OUR_SIGLEVEL="Optional TrustAll"
    OUR_SERVER="file://$LOCAL_REPO"
fi

if pacman -Q hyprland >/dev/null 2>&1; then
    have="$(pacman -Q hyprland | cut -d' ' -f2)"
    want="$(awk '$1 == "hyprland" { print $2 }' "$ROOT/pkgs/pinned/hypr.lock")"
    if [[ "$have" == "$want" ]]; then info "hyprland $have: the pinned version"
    else info "hyprland $have installed, pinned $want: pacman keeps a newer local one; the pin holds from the next Arch release on"; fi
fi
extra_hypr="$(pacman -Qq 2>/dev/null | grep -E '^hypr' | grep -vxF -f <(grep -v '^#' "$ROOT/pkgs/pinned/hypr.lock" | cut -d' ' -f1) | grep -vx hyprshot | tr '\n' ' ' || true)"
[[ -z "$extra_hypr" ]] || info "note: hypr* apps outside the pinned set ($extra_hypr) can block pacman -Syu if Arch moves them before we move the pin"

command -v lua >/dev/null || problem "lua is not installed (Hyprland 0.55+ pulls it in; pacman -S lua)"

# The new pacman.conf, and a preview of what pacman would install, from a
# throwaway copy of the sync databases (the real ones are not touched).
awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v r="$REPO_NAME" -v sl="$OUR_SIGLEVEL" -v sv="$OUR_SERVER" '
    !done && /^\[/ && $0 != "[options]" {
        print b; print "[" r "]"; print "SigLevel = " sl; print "Server = " sv; print e; print ""; done = 1
    }
    { print }
    END { if (!done) { print ""; print b; print "[" r "]"; print "SigLevel = " sl; print "Server = " sv; print e } }
' "$PACMAN_CONF" > "$TMP/pacman.conf"

preview() {
    local db="$TMP/db" conf="$TMP/preview.conf"
    install -dm755 "$TMP" "$db" "$db/sync"
    chmod 755 "$TMP"
    ln -sfn /var/lib/pacman/local "$db/local"
    # Display only: our database is read without checking its signature
    # here (the key is not imported yet, and pacman's keyring is root's).
    # The real install below checks signatures.
    sed "/^\[$REPO_NAME\]/,/^Server/ s/^SigLevel = .*/SigLevel = Never/" "$TMP/pacman.conf" > "$conf"
    command -v fakeroot >/dev/null || { info "preview skipped: fakeroot is not installed"; return 0; }
    if ! fakeroot -- pacman --config "$conf" --dbpath "$db" --logfile /dev/null -Sy >"$TMP/sync.log" 2>&1; then
        info "preview skipped: could not read the repos ($(tail -1 "$TMP/sync.log"))"; return 0
    fi
    if pacman --config "$conf" --dbpath "$db" -Sup --needed --print-format '%n %v %r' "${TARGETS[@]}" > "$TMP/plan.txt" 2>"$TMP/plan.err"; then
        local new ours
        new="$(awk '{ print $1 }' "$TMP/plan.txt" | grep -cvxF -f <(pacman -Qq) || true)"
        ours="$(awk -v r="$REPO_NAME" '$3 == r' "$TMP/plan.txt" | wc -l)"
        info "pacman -Syu would handle $(wc -l < "$TMP/plan.txt") packages: $new new, $ours from [$REPO_NAME]:"
        awk -v r="$REPO_NAME" '$3 == r { print "      " $0 }' "$TMP/plan.txt"
        info "(the rest are Arch packages and upgrades; full list in the backup folder after --apply)"
        # pacman -Sp does not check conflicts. An installed package that one
        # of ours conflicts with (code vs visual-studio-code-bin) makes pacman
        # ask to remove it; with --yes (--noconfirm) the answer is No and the
        # whole update stops (the adopt-jack2-conflict lesson).
        local ours_names conflicts line pkg c
        mapfile -t ours_names < <(awk -v r="$REPO_NAME" '$3 == r { print $1 }' "$TMP/plan.txt")
        if [[ ${#ours_names[@]} -gt 0 ]]; then
            conflicts="$(pacman --config "$conf" --dbpath "$db" -Si "${ours_names[@]}" 2>/dev/null \
                | awk -F' *: ' '/^Name/ { n = $2 } /^Conflicts With/ { if ($2 != "None") print n, $2 }' || true)"
            while read -r pkg line; do
                [[ -n "$pkg" ]] || continue
                for c in $line; do
                    c="${c%%[<>=]*}"
                    pacman -Q "$c" >/dev/null 2>&1 || continue
                    if $YES; then
                        problem "$pkg replaces $c, which is installed; with --yes pacman would refuse. Run without --yes and answer y to remove $c, or remove it first (sudo pacman -R $c)"
                    else
                        info "pacman will ask to remove $c for $pkg (they conflict): answer y"
                    fi
                done
            done <<< "$conflicts"
        fi
    else
        problem "pacman cannot resolve the packages: $(grep -v '^$' "$TMP/plan.err" | head -5 | tr '\n' ' ')"
        info "An AUR package our repo does not carry yet must be installed first (for example: paru -S <name>)."
    fi
}
preview

if [[ ${#problems[@]} -gt 0 ]]; then
    echo
    echo "==> ${#problems[@]} problem(s); nothing was changed:"
    printf '    - %s\n' "${problems[@]}"
    exit 1
fi

if $APPLY; then
    trap 'echo; echo "==> adopt.sh stopped at step $n. What ran so far is recorded in $B;"; echo "    to put it all back: $0 --undo --apply"' ERR
fi

# ---- 2. backup ------------------------------------------------------------------
step "Back up into $B"
cmd mkdir -p "$B/config" "$B/state"
for d in "${DIRS[@]}"; do
    if [[ -e "$CFG/$d" ]]; then cmd cp -a "$CFG/$d" "$B/config/$d"
    else info "$CFG/$d does not exist (undo will remove it)"; $APPLY && echo "$d" >> "$B/absent-config.txt"; fi
done
if [[ -f "$HOME/.zshrc" ]]; then cmd cp -a "$HOME/.zshrc" "$B/zshrc"
elif $APPLY; then touch "$B/absent-zshrc"; fi
for f in "${STATE_ITEMS[@]}"; do
    if [[ -e "$STATE/$f" ]]; then cmd cp -a "$STATE/$f" "$B/state/$f"; fi
done
cmd cp -a "$PACMAN_CONF" "$B/pacman.conf"
info "\$ pacman -Qq > $B/packages-before.txt"
$APPLY && pacman -Qq > "$B/packages-before.txt"
if [[ -n "$LEGACY" && -f "$CFG/hypr/hyprpaper.conf" ]]; then
    while IFS= read -r wp; do
        wp="${wp/#\~/$HOME}"; wp="${wp//\$HOME/$HOME}"
        [[ "$wp" == "$LEGACY"/* && -f "$wp" ]] || continue
        info "your wallpaper $wp comes from the old clone (a git pull there deletes it): keeping a copy"
        cmd mkdir -p "$B/wallpapers" "$HOME/Pictures/Wallpapers"
        cmd cp -a "$wp" "$B/wallpapers/"
        if [[ ! -e "$HOME/Pictures/Wallpapers/$(basename "$wp")" ]]; then
            cmd cp -a "$wp" "$HOME/Pictures/Wallpapers/"
            $APPLY && echo "$HOME/Pictures/Wallpapers/$(basename "$wp")" >> "$B/created-files.txt"
        fi
    done < <(sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$CFG/hypr/hyprpaper.conf")
fi
if $APPLY; then
    ln -sfn "$STAMP" "$ADOPT_ROOT/latest"
    mark_step backup
fi

# ---- 3. repo and key ------------------------------------------------------------
step "Add [$REPO_NAME] to $PACMAN_CONF, ahead of the Arch repos"
diff -u --label "$PACMAN_CONF" --label "$PACMAN_CONF (new)" "$PACMAN_CONF" "$TMP/pacman.conf" | sed 's/^/    /' || true
cmd "$SUDO" install -m644 "$TMP/pacman.conf" "$PACMAN_CONF"
mark_step pacman-conf
if $SIGNED; then
    step "Trust the Invictus key ($FPR)"
    cmd "$SUDO" pacman-key --add "$KEY_FILE"
    cmd "$SUDO" pacman-key --lsign-key "$FPR"
    $APPLY && echo "$FPR" > "$B/key-fingerprint"
    mark_step key
fi

# ---- 4. packages ----------------------------------------------------------------
step "Install the Invictus packages with a full upgrade"
cmd "$SUDO" pacman -Syu --needed "${CONFIRM[@]}" "${TARGETS[@]}"
if $APPLY; then
    pacman -Qq > "$B/packages-after.txt"
    comm -13 <(sort "$B/packages-before.txt") <(sort "$B/packages-after.txt") > "$B/packages-installed.txt"
    [[ -s "$TMP/plan.txt" ]] && cp "$TMP/plan.txt" "$B/pacman-plan.txt"
    info "$(wc -l < "$B/packages-installed.txt") new packages (list: $B/packages-installed.txt)"
    mark_step packages
fi

# ---- 5. config ------------------------------------------------------------------
step "Switch Hyprland to the Lua config, keeping your own binds"
if $APPLY; then SHARE="$INVICTUS_SHARE"; FIRST_LOGIN=/usr/lib/invictus/first-login
else
    # Before the packages exist, preview with the repo's own files laid out
    # the way invictus-desktop installs them.
    SHARE="$TMP/share"
    mkdir -p "$SHARE/config" "$SHARE/hypr"
    (cd "$ROOT/config" && tar --exclude=./hypr/invictus -cf - .) | tar -C "$SHARE/config" -xf -
    cp -r "$ROOT/config/hypr/invictus" "$SHARE/hypr/"
    FIRST_LOGIN="$ROOT/scripts/first-login.sh"
fi
mark_step config
mkdir -p "$TMP/port"
clone_hypr=""
[[ -n "$LEGACY" && -d "$LEGACY/config/hypr" ]] && clone_hypr="$LEGACY/config/hypr"
lua "$ROOT/scripts/dev/port-hyprlang.lua" "$CFG/hypr" "$clone_hypr" "$SHARE/hypr/invictus/binds.lua" \
    "$SHARE/config/hypr/monitors.lua" "$SHARE/config/hypr/user.lua" \
    "$TMP/port/monitors.lua" "$TMP/port/user.lua" | sed 's/^/    /'
for f in monitors user; do
    if [[ -e "$CFG/hypr/$f.lua" ]]; then info "keeping your existing $CFG/hypr/$f.lua"; continue; fi
    cmd install -m644 "$TMP/port/$f.lua" "$CFG/hypr/$f.lua"
done
if ! $APPLY && [[ -s "$TMP/port/user.lua" ]]; then
    info "user.lua would end with:"
    sed -n '/Ported from your old hyprlang config/,$p' "$TMP/port/user.lua" | sed 's/^/      | /'
fi
info "\$ $FIRST_LOGIN --adopt $B/replaced"
if $APPLY; then
    "$FIRST_LOGIN" --adopt "$B/replaced" | sed 's/^/    /'
else
    INVICTUS_SHARE="$SHARE" INVICTUS_DEFAULTS_SH="$ROOT/scripts/lib/defaults.sh" INVICTUS_STATE="$TMP/state" \
        bash "$FIRST_LOGIN" --dry-run --adopt "$B/replaced" | sed 's/^/    /'
fi

# ---- 6. check -------------------------------------------------------------------
step "Check that Hyprland accepts the new config"
info "\$ invictus-doctor --hypr"
if $APPLY; then
    if ! invictus-doctor --hypr | sed 's/^/    /'; then
        echo
        echo "==> The new config did not load. Putting the config folders back now."
        restore_config "$B"
        if [[ -f "$B/created-files.txt" ]]; then
            while IFS= read -r f; do [[ -n "$f" ]] && cmd rm -f "$f"; done < "$B/created-files.txt"
            : > "$B/created-files.txt"
        fi
        sed -i '/^config$/d' "$B/steps"
        echo "==> Your old config is back. The packages and repo are still installed:"
        echo "    to remove them too: $0 --undo --apply"
        exit 1
    fi
    date -Is > "$B/complete"
    echo
    echo "==> Adopted. Log out and back in to start the new desktop."
    echo "    Backup and record: $B"
    echo "    Undo everything:   $0 --undo --apply"
else
    echo
    echo "==> Dry run finished. Nothing was changed. To do it: $0 --apply"
fi
