# shellcheck shell=bash
# Group 20 of tests/pkgs/run.sh (sourced; uses REPO, TMP, ok, bad):
# scripts/dev/pacman-sandbox-hotfix.sh (build note 63) with pacman and
# pacman-conf faked. FAKE_RESOLVES lists the steps whose names resolve
# ("full" = the sandbox in full, or a --disable-sandbox* flag).
# shellcheck disable=SC2153 # REPO and TMP come from run.sh
if [[ "${BASH_SOURCE[0]}" == "$0" ]] || ! declare -F ok bad >/dev/null || [[ -z "${REPO:-}" || -z "${TMP:-}" ]]; then
    echo "tests/pkgs/hotfix.sh is group 20 of tests/pkgs/run.sh: run that" >&2
    # shellcheck disable=SC2317 # exit is reached when run, not sourced
    return 2 2>/dev/null || exit 2
fi

echo "== pacman sandbox hotfix"
HF="$REPO/scripts/dev/pacman-sandbox-hotfix.sh"
HFT="$TMP/hotfix"
mkdir -p "$HFT"
cat >"$HFT/pacman" <<'EOF'
#!/usr/bin/env bash
# Fake pacman -Sy: logs its arguments; resolves when its step is in FAKE_RESOLVES.
echo "$*" >>"$FAKE_CALLS"
step=full
for a in "$@"; do [[ "$a" == --disable-sandbox* ]] && step="$a"; done
[[ "$*" == *--dbpath* && "$*" == *-Sy* ]] || { echo "fake pacman: unexpected call: $*" >&2; exit 9; }
[[ "$step" == full ]] && echo "debug: filesystem access has been restricted to /x/, Landlock ABI is 10"
if [[ " ${FAKE_RESOLVES:-} " == *" $step "* ]]; then
    [[ -n "${FAKE_OTHER_ERROR:-}" ]] && { echo "error: failed retrieving file 'core.db' from geo.mirror.pkgbuild.com : The requested URL returned error: 503"; exit 1; }
    exit 0
fi
echo "error: failed retrieving file 'core.db' from geo.mirror.pkgbuild.com : Resolving timed out after 10000 milliseconds"
exit 1
EOF
cat >"$HFT/pacman-conf" <<'EOF'
#!/usr/bin/env bash
# Fake pacman-conf --config FILE: the option lines, DisableSandbox as its two parts.
conf="$2"
sed -n '/^\[options\]/,/^\[/p' "$conf" | grep -E '^(DownloadUser|DisableSandbox)' | sed 's/^DisableSandbox$/DisableSandboxFilesystem\nDisableSandboxSyscalls/'
EOF
chmod +x "$HFT/pacman" "$HFT/pacman-conf"
HF_CONF_ORIG="$(printf '[options]\nHoldPkg = pacman glibc\nDownloadUser = alpm\nSigLevel = Required DatabaseOptional\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n')"

# hf CASE RESOLVES [ARGS...]: run the hotfix on a fresh pacman.conf; sets hf_rc, hf_out.
hf() {
    local case="$1" resolves="$2"; shift 2
    hf_dir="$HFT/$case"; mkdir -p "$hf_dir"
    [[ -f "$hf_dir/pacman.conf" ]] || printf '%s\n' "$HF_CONF_ORIG" >"$hf_dir/pacman.conf"
    : >"$hf_dir/calls"
    hf_rc=0
    hf_out="$(FAKE_CALLS="$hf_dir/calls" FAKE_RESOLVES="$resolves" FAKE_OTHER_ERROR="${FAKE_OTHER_ERROR:-}" \
        INVICTUS_PACMAN="$HFT/pacman" INVICTUS_PACMAN_CONF_CMD="$HFT/pacman-conf" \
        INVICTUS_PACMAN_CONF="$hf_dir/pacman.conf" INVICTUS_REPORT="$hf_dir/report.txt" \
        bash "$HF" "$@" 2>&1)" || hf_rc=$?
}
opt_after_download_user() { sed -n '/^DownloadUser/{n;n;p}' "$1"; }

hf works full
if [[ $hf_rc -eq 0 && "$hf_out" == *"nothing to change"* ]] && [[ "$(cat "$hf_dir/pacman.conf")" == "$HF_CONF_ORIG" ]] \
    && [[ "$(wc -l <"$hf_dir/calls")" -eq 1 ]]; then
    ok "hotfix: a sandbox that resolves changes nothing (one pacman run)"
else bad "hotfix: a sandbox that resolves changes nothing: rc=$hf_rc $hf_out"; fi

hf syscalls "--disable-sandbox-syscalls --disable-sandbox-filesystem --disable-sandbox"
if [[ $hf_rc -eq 0 && "$(opt_after_download_user "$hf_dir/pacman.conf")" == DisableSandboxSyscalls ]] \
    && grep -qx '# invictus hotfix (build note 63).*' "$hf_dir/pacman.conf" && [[ -f "$hf_dir/pacman.conf.invictus-hotfix.bak" ]] \
    && [[ "$(cat "$hf_dir/pacman.conf.invictus-hotfix.bak")" == "$HF_CONF_ORIG" ]]; then
    ok "hotfix: the syscall filter alone is turned off when that is enough, under [options], with a backup"
else bad "hotfix: syscall filter step: rc=$hf_rc $hf_out $(cat "$hf_dir/pacman.conf")"; fi
if [[ "$(sed -n 's/.*\(--disable-sandbox[a-z-]*\).*/\1/p; /--disable-sandbox/!s/.*/full/p' "$hf_dir/calls" | tr '\n' ' ')" == "full --disable-sandbox-syscalls " ]]; then
    ok "hotfix: tries the sandbox in full first, then stops at the first step that works"
else bad "hotfix: step order: $(cat "$hf_dir/calls")"; fi
grep -q -- '--logfile /dev/null' "$hf_dir/calls" && ! grep -q -- '--dbpath /var/lib/pacman' "$hf_dir/calls" \
    && ok "hotfix: test runs use a throwaway database folder and no pacman.log lines" \
    || bad "hotfix: test runs touch the real database or log: $(cat "$hf_dir/calls")"
hf syscalls "--disable-sandbox-syscalls"
if [[ $hf_rc -eq 0 && "$hf_out" == *"already has the hotfix line (DisableSandboxSyscalls)"* ]] && [[ ! -s "$hf_dir/calls" ]] \
    && [[ "$(grep -c DisableSandbox "$hf_dir/pacman.conf")" -eq 1 ]]; then
    ok "hotfix: a second run sees its line, adds nothing and runs no pacman"
else bad "hotfix: second run: rc=$hf_rc $hf_out"; fi

hf filesystem "--disable-sandbox-filesystem --disable-sandbox"
[[ $hf_rc -eq 0 && "$(opt_after_download_user "$hf_dir/pacman.conf")" == DisableSandboxFilesystem ]] \
    && ok "hotfix: the file-system rules alone when the syscall filter is not the cause" \
    || bad "hotfix: file-system step: rc=$hf_rc $hf_out"

hf whole "--disable-sandbox"
[[ $hf_rc -eq 0 && "$(opt_after_download_user "$hf_dir/pacman.conf")" == DisableSandbox ]] \
    && ok "hotfix: DisableSandbox only when neither part alone is enough" \
    || bad "hotfix: whole step: rc=$hf_rc $hf_out"

hf nothing ""
[[ $hf_rc -eq 1 && "$hf_out" == *"the network, not the sandbox"* && "$(cat "$hf_dir/pacman.conf")" == "$HF_CONF_ORIG" ]] \
    && ok "hotfix: no resolution even without the sandbox: exit 1, pacman.conf untouched" \
    || bad "hotfix: no resolution at all: rc=$hf_rc $hf_out"

hf check "--disable-sandbox-syscalls" --check
[[ $hf_rc -eq 0 && "$hf_out" == *"--check: "*"DisableSandboxSyscalls"* && "$(cat "$hf_dir/pacman.conf")" == "$HF_CONF_ORIG" ]] \
    && ok "hotfix: --check names the step and changes nothing" \
    || bad "hotfix: --check: rc=$hf_rc $hf_out"

FAKE_OTHER_ERROR=1 hf mirror503 "full --disable-sandbox-syscalls --disable-sandbox-filesystem --disable-sandbox"
[[ $hf_rc -eq 0 && "$hf_out" == *"nothing to change"* && "$(cat "$hf_dir/pacman.conf")" == "$HF_CONF_ORIG" ]] \
    && ok "hotfix: a mirror's 503 is not a resolve failure: the sandbox stays on" \
    || bad "hotfix: 503: rc=$hf_rc $hf_out"

grep -q 'Resolving timed out' "$HFT/syscalls/report.txt" 2>/dev/null || grep -q 'Resolving timed out' "$HFT/whole/report.txt" \
    && ok "hotfix: the report keeps pacman's resolve error lines" \
    || bad "hotfix: report lacks the error lines"

hf bad "" --apply-everything
[[ $hf_rc -eq 2 ]] && ok "hotfix: an unknown argument is refused (exit 2)" || bad "hotfix: unknown argument: rc=$hf_rc"
