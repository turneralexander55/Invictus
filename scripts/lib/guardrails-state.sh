# shellcheck shell=bash
# ------------------------------------------------------------
# Reading the guard-rails state (installed as
# /usr/lib/invictus/lib/guardrails-state.sh by invictus-tools).
# design-simple-mode.md 1.6, 6.2, 12.1, 12.3; design-no-ai.md N1.
#
# Every guard reads the state through these functions, so they agree on
# the defaults: a missing or garbled guardrails file reads as custodia
# (the safe side), a missing nets key reads as on, a missing assistant or
# ai file reads as off. Nothing here writes; invictus-sys and
# /usr/lib/invictus/guardrails are the only writers.
#
#   gr_rails             custodia | libertas, as the file says
#   gr_effective_rails   the same, but a timed Libertas whose end has
#                        passed reads as custodia (12.1 step 3)
#   gr_until_epoch       the end of a timed Libertas (epoch seconds), or
#                        nothing when there is none
#   gr_net_on KEY        exit 0 if the net KEY is on; under Custodia every
#                        net is on whatever the nets file says
#   gr_full_access       on | off  (/etc/invictus/assistant, full-access)
#   gr_ai                on | off  (/etc/invictus/ai)
#
# INVICTUS_SYS_ROOT (tests) is put in front of every path.
# ------------------------------------------------------------

GR_ETC="${INVICTUS_SYS_ROOT:-}/etc/invictus"
GR_NETS="pre-admin-snapshot auto-update boot-guard home-snapshots"

# kv_get FILE KEY: the value of "KEY = value" (last one wins), or nothing.
kv_get() {
    [[ -r "$1" ]] || return 0
    awk -v k="$2" '
        /^[[:space:]]*#/ { next }
        { line = $0; sub(/^[[:space:]]+/, "", line) }
        index(line, k) == 1 {
            rest = substr(line, length(k) + 1)
            if (rest ~ /^[[:space:]]*=/) { sub(/^[[:space:]]*=[[:space:]]*/, "", rest); sub(/[[:space:]]+$/, "", rest); v = rest }
        }
        END { if (v != "") print v }' "$1"
}

gr_rails() {
    local w=""
    [[ -r "$GR_ETC/guardrails" ]] && read -r w < "$GR_ETC/guardrails"
    if [[ "$w" == libertas ]]; then echo libertas; else echo custodia; fi
}

gr_until_epoch() {
    local u e
    u="$(kv_get "$GR_ETC/guardrails-until" until)"
    [[ -n "$u" ]] || return 0
    e="$(date -d "$u" +%s 2>/dev/null)" || return 0
    echo "$e"
}

gr_effective_rails() {
    local r u
    r="$(gr_rails)"
    if [[ "$r" == libertas ]]; then
        u="$(gr_until_epoch)"
        if [[ -n "$u" ]] && (( $(date +%s) >= u )); then r=custodia; fi
    fi
    echo "$r"
}

gr_net_on() {
    [[ " $GR_NETS " == *" $1 "* ]] || return 1
    [[ "$(gr_effective_rails)" == custodia ]] && return 0
    [[ "$(kv_get "$GR_ETC/nets" "$1")" != off ]]
}

gr_full_access() {
    if [[ "$(kv_get "$GR_ETC/assistant" full-access)" == on ]]; then echo on; else echo off; fi
}

gr_ai() {
    local w=""
    [[ -r "$GR_ETC/ai" ]] && read -r w < "$GR_ETC/ai"
    if [[ "$w" == on ]]; then echo on; else echo off; fi
}
