#!/usr/bin/bash
# ------------------------------------------------------------
# pre-admin-snapshot: a safety copy of / before every admin action (G2,
# design-simple-mode.md 1.4, SM17). Installed as
# /usr/lib/invictus/pre-admin-snapshot by invictus-guardrails.
#
# Run as root by pam_exec, in the auth stacks of /etc/pam.d/polkit-1
# (shipped by invictus-guardrails) and /etc/pam.d/sudo (line added by
# `guardrails apply`), after `auth include system-auth`: system-auth ends a
# wrong password with [default=die], so this only runs after a good one.
#
# Makes "Before: <service>, <user>" (important, number cleanup, so the last
# 10 are kept), at most one per 10 minutes, and writes it to Acta. A net:
# under Libertas, `pre-admin-snapshot = off` in /etc/invictus/nets turns it
# off; under Custodia it is always on. Never fails the authentication: it
# always exits 0, and gives snapper 8 seconds at most. A failed snapper
# (full disk, broken config, lock held) is stamped too and not tried again
# for 2 minutes, so a full disk costs one wait, not one per password
# (Janus M1, 2026-10-01).
# Env from pam_exec: PAM_SERVICE, PAM_USER, PAM_TYPE.
# Env (tests, from a checkout only): INVICTUS_SYS_ROOT, INVICTUS_LIB,
# INVICTUS_SNAPPER, ACTA_LOGGER
# ------------------------------------------------------------
set -uo pipefail
# The installed copy honours no overrides: pam_exec runs it as root for
# whoever authenticates, including auth_self prompts.
case "$(readlink -f -- "$0")" in
    /usr/*) export PATH=/usr/bin
            while read -r v; do unset "$v"; done < <(compgen -v | grep -E '^(INVICTUS_|ACTA_)' || true) ;;
esac

LIB="${INVICTUS_LIB:-/usr/lib/invictus}"
# shellcheck source=scripts/lib/guardrails-state.sh
. "$LIB/lib/guardrails-state.sh" || exit 0
# shellcheck source=scripts/lib/acta.sh
. "$LIB/lib/acta.sh" || exit 0
read -ra SNAPPER <<< "${INVICTUS_SNAPPER:-snapper}"
STAMP="${INVICTUS_SYS_ROOT:-}/run/invictus/pre-admin-snapshot.stamp"
FAILED="${INVICTUS_SYS_ROOT:-}/run/invictus/pre-admin-snapshot.failed"

[[ "${PAM_TYPE:-auth}" == auth ]] || exit 0
gr_net_on pre-admin-snapshot || exit 0

# One per 10 minutes, and after a failure none for 2 minutes: stamps on
# tmpfs (gone at boot, and removed by every switch to Custodia so the first
# admin action after it is copied).
fresh() { [[ -f "$1" ]] && (( $(date +%s) - $(stat -c %Y "$1") < $2 )); }
if fresh "$STAMP" 600 || fresh "$FAILED" 120; then exit 0; fi

clean() { local v="${1//[^A-Za-z0-9@._-]/}"; printf '%s' "${v:0:32}"; }
service="$(clean "${PAM_SERVICE:-unknown}")"
user="$(clean "${PAM_USER:-unknown}")"
desc="Before: $service, $user"

mkdir -p "$(dirname "$STAMP")"
if id="$(timeout 8 "${SNAPPER[@]}" -c root create --type single --print-number --cleanup-algorithm number \
        --userdata important=yes --description "$desc" 2>/dev/null)" && [[ "$id" =~ ^[0-9]+$ ]]; then
    touch "$STAMP"; rm -f "$FAILED"
    acta "safety copy $id: $desc" VERB=pre-admin-snapshot ARGS="$service $user" SNAPSHOT="$id" RESULT=ok \
        PAM_SERVICE="$service" PAM_USER="$user"
else
    touch "$FAILED"
    acta "no safety copy before admin action ($desc): snapper failed; next try in 2 minutes" VERB=pre-admin-snapshot \
        ARGS="$service $user" RESULT=failed PAM_SERVICE="$service" PAM_USER="$user"
fi
exit 0
