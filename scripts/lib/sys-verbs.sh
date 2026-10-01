# shellcheck shell=bash disable=SC2034
# (SC2034: SYS_ROOT_VERBS and SYS_CONFIG_KEYS are read by the callers.)
# ------------------------------------------------------------
# The invictus-sys verb table and argument checks (installed as
# /usr/lib/invictus/lib/sys-verbs.sh by invictus-sys). Sourced by both
# halves: /usr/bin/invictus-sys checks before the password prompt, so a
# typo never costs a password; /usr/lib/invictus/invictus-sys checks again
# as root and is the one that counts.
#
# Root verbs are the polkit action names: the root helper is always run
# as `invictus-sys <root verb> ARGS`, and each root verb has its own action
# org.invictus.sys.<root verb>, matched by pkexec on argv[1]
# (org.freedesktop.policykit.exec.argv1). So one password never covers two
# kinds of change (MUST A10), and the prompt shows the exact arguments.
#
# Needs scripts/lib/pacman.sh (valid_package_name) sourced first.
# INVICTUS_SYS_ROOT (tests) is put in front of every data path.
# ------------------------------------------------------------

SYS_SHARE="${INVICTUS_SYS_ROOT:-}/usr/share/invictus/sys"

# Every root verb, in the order `invictus-sys help` lists them.
SYS_ROOT_VERBS="update install remove snapshot rollback service set-config assistant-full-access report-collect guardrails-libertas guardrails-custodia"

# The keys set-config accepts. Anything else, and in particular the
# guard-rails, ai, assistant and helper files, has its own verb or none.
SYS_CONFIG_KEYS="nets.pre-admin-snapshot nets.auto-update nets.boot-guard nets.home-snapshots flavor.lock"

sys_err() { echo "invictus-sys: $*" >&2; }

# list_has FILE WORD: WORD is a line (first field) of FILE, comments skipped.
list_has() {
    [[ -r "$1" ]] || return 1
    awk -v w="$2" '!/^[[:space:]]*#/ && $1 == w { found = 1 } END { exit !found }' "$1"
}

# protected_packages: the names invictus-sys never removes (and the
# Custodia HoldPkg list), one per line.
protected_packages() {
    awk '!/^[[:space:]]*#/ && NF { print $1 }' "$SYS_SHARE/protected-packages" 2>/dev/null
}

# duration_seconds 1h|90m|2d: seconds, for timed Libertas (1 minute to 7 days).
duration_seconds() {
    [[ "$1" =~ ^([1-9][0-9]{0,4})([mhd])$ ]] || return 1
    local n="${BASH_REMATCH[1]}" s
    case "${BASH_REMATCH[2]}" in
        m) s=$((n * 60)) ;;
        h) s=$((n * 3600)) ;;
        d) s=$((n * 86400)) ;;
    esac
    ((s >= 60 && s <= 7 * 86400)) || return 1
    echo "$s"
}

# sys_validate ROOTVERB ARGS...: 0 if the call is well formed, else a
# reason on stderr and 2.
sys_validate() {
    local verb="${1:-}" a; shift || true
    case "$verb" in
        update|report-collect|guardrails-custodia)
            (($# == 0)) || { sys_err "$verb takes no arguments"; return 2; } ;;
        install|remove)
            (($# >= 1 && $# <= 64)) || { sys_err "$verb needs 1 to 64 package names"; return 2; }
            for a in "$@"; do
                valid_package_name "$a" || { sys_err "'$a' is not a package name"; return 2; }
                if [[ "$verb" == remove ]] && protected_packages | grep -x -- "${a#*/}" >/dev/null; then
                    sys_err "$a keeps this computer working and is never removed by invictus-sys"
                    return 2
                fi
            done ;;
        snapshot)
            (($# == 1)) && [[ -n "${1//[[:space:]]/}" ]] || { sys_err "snapshot needs one description"; return 2; } ;;
        rollback)
            (($# == 1)) && [[ "$1" =~ ^[1-9][0-9]{0,8}$ ]] || { sys_err "rollback needs a snapshot number"; return 2; } ;;
        service)
            (($# == 2)) || { sys_err "service needs enable|disable|restart and a unit"; return 2; }
            [[ "$1" =~ ^(enable|disable|restart)$ ]] || { sys_err "service: '$1' is not enable, disable or restart"; return 2; }
            if [[ ! "$2" =~ ^[A-Za-z0-9@._-]+\.(service|timer|socket)$ ]] || ! list_has "$SYS_SHARE/services.allow" "$2"; then
                sys_err "service: '$2' is not on the list invictus-sys may change ($SYS_SHARE/services.allow)"; return 2
            fi ;;
        set-config)
            (($# == 2)) || { sys_err "set-config needs a key and on|off"; return 2; }
            [[ " $SYS_CONFIG_KEYS " == *" $1 "* ]] || { sys_err "set-config: unknown key '$1' (keys: $SYS_CONFIG_KEYS)"; return 2; }
            [[ "$2" =~ ^(on|off)$ ]] || { sys_err "set-config: value must be on or off"; return 2; } ;;
        assistant-full-access)
            (($# == 1)) && [[ "$1" =~ ^(on|off)$ ]] || { sys_err "assistant.full-access must be on or off"; return 2; } ;;
        guardrails-libertas)
            if (($# == 2)) && [[ "$1" == --for ]]; then
                duration_seconds "$2" >/dev/null || { sys_err "--for takes 1m to 7d, like 1h or 30m"; return 2; }
            elif (($# != 0)); then
                sys_err "guardrails set libertas takes only --for DURATION"; return 2
            fi ;;
        *) sys_err "unknown verb '$verb'"; return 2 ;;
    esac
    return 0
}
