#!/usr/bin/bash
# ------------------------------------------------------------
# ai-pending: finish `invictus-sys ai on` when it ran with no connection
# (design-no-ai.md N1). Installed as /usr/lib/invictus/ai-pending by
# invictus-sys; run as root by invictus-ai-pending.service, which `ai on`
# enables when the install fails and which retries after the network is
# up, like invictus-extras.service.
#
# Installs AI_ON_INSTALL (scripts/lib/ai-set.sh) with pacman -Syu --needed
# only while /var/lib/invictus/ai-install-pending exists AND
# /etc/invictus/ai reads on: the person's password at the time of the
# choice is the consent, and `ai off` since then cancels it. On success
# (or when cancelled) the marker goes and the service is disabled.
# Exit: 0 done or nothing to do; 1 the download failed (no connection
# yet: the unit tries again); 2 pacman failed for another reason (a
# conflict, a bad signature): trying again will not help, so the unit's
# RestartPreventExitStatus=2 stops the retries until the next start.
# Env (tests, from a checkout only): INVICTUS_SYS_ROOT, INVICTUS_LIB,
#   INVICTUS_PACMAN, INVICTUS_SYSTEMCTL, INVICTUS_INHIBIT, ACTA_LOGGER
# ------------------------------------------------------------
set -euo pipefail
umask 022
export LC_ALL=C
case "$(readlink -f -- "$0")" in
    /usr/*) export PATH=/usr/bin
            while read -r v; do unset "$v"; done < <(compgen -v | grep -E '^(INVICTUS_|ACTA_)' || true) ;;
esac

LIB="${INVICTUS_LIB:-/usr/lib/invictus}"
# shellcheck source=scripts/lib/pacman.sh
. "$LIB/lib/pacman.sh"
# shellcheck source=scripts/lib/guardrails-state.sh
. "$LIB/lib/guardrails-state.sh"
# shellcheck source=scripts/lib/acta.sh
. "$LIB/lib/acta.sh"
# shellcheck source=scripts/lib/ai-set.sh
. "$LIB/lib/ai-set.sh"

PENDING="${INVICTUS_SYS_ROOT:-}/var/lib/invictus/ai-install-pending"
PACMAN="${INVICTUS_PACMAN:-pacman}"
SYSTEMCTL="${INVICTUS_SYSTEMCTL:-systemctl}"
if [[ -n "${INVICTUS_INHIBIT+x}" ]]; then read -ra INHIBIT <<< "$INVICTUS_INHIBIT"
else INHIBIT=(systemd-inhibit --what=shutdown:sleep --who="Invictus" --why="Adding the AI assistant" --mode=block); fi

say() { echo "ai-pending: $*"; }
done_pending() { rm -f "$PENDING"; "$SYSTEMCTL" disable invictus-ai-pending.service >/dev/null 2>&1 || true; }

[[ -e "$PENDING" ]] || { say "nothing pending"; exit 0; }
if [[ "$(gr_ai)" != on ]]; then
    done_pending
    say "AI was turned off since; nothing installed"
    exit 0
fi
read -ra names <<< "$AI_ON_INSTALL"
say "installing: ${names[*]}"
rc=0
pacman_install_classified "${names[@]}" || rc=$?
if ((rc != 0)); then
    if [[ "$PACMAN_FAILURE" == download ]]; then
        say "could not download (exit $rc); trying again later"
        exit 1
    fi
    acta "AI packages could not be installed (pacman exit $rc, not a download failure): update first, then turn AI on again" \
        VERB=ai-on ARGS=pending RESULT=failed UID=0 USER=root
    say "pacman stopped (exit $rc), not for want of a connection; not trying again"
    exit 2
fi
done_pending
acta "AI packages installed (AI was turned on while offline): ${names[*]}" VERB=ai-on ARGS=pending RESULT=ok UID=0 USER=root
say "done"
