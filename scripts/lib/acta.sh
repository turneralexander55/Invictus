# shellcheck shell=bash
# ------------------------------------------------------------
# Acta, the record of every root action (design 4.6, MUST A11).
# Installed as /usr/lib/invictus/lib/acta.sh by invictus-tools.
#
#   acta "MESSAGE" VERB=... ARGS=... SNAPSHOT=... RESULT=... [KEY=value...]
#
# Writes one structured journal entry under the tag invictus-sys, every
# KEY as the field INVICTUS_KEY, so `journalctl -t invictus-sys -o json`
# (and the Desk's Acta card) reads verb, args, snapshot id, the requesting
# session and the result as fields, not by parsing text. Values are made
# single-line and cut at 1000 bytes; keys must be [A-Z0-9_].
#
# ACTA_LOGGER (tests) replaces `logger --journald`; it gets the entry on
# stdin, one FIELD=value per line.
# ------------------------------------------------------------

acta_clean() {
    local v="${1//[$'\001'-$'\037'$'\177']/ }"
    printf '%s' "${v:0:1000}"
}

acta() {
    local msg="$1" kv k v; shift
    local -a logger
    read -ra logger <<< "${ACTA_LOGGER:-logger --journald}"
    {
        printf 'SYSLOG_IDENTIFIER=invictus-sys\n'
        printf 'PRIORITY=6\n'
        printf 'MESSAGE=%s\n' "$(acta_clean "$msg")"
        for kv in "$@"; do
            k="${kv%%=*}"; v="${kv#*=}"
            [[ "$k" =~ ^[A-Z0-9_]+$ ]] || continue
            printf 'INVICTUS_%s=%s\n' "$k" "$(acta_clean "$v")"
        done
    } | "${logger[@]}" 2>/dev/null || true
}
