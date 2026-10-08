#!/usr/bin/env bash
# ------------------------------------------------------------
# ISO profile sanity (iso/): boot entries, names, live-only files, secrets,
# os-release, pacman config, package list, the staged build
# (scripts/build-iso.sh --prepare-only), the Plymouth theme and the pinned
# PKGBUILDs. No container or network needed.
#
#   tests/iso/profile.sh     ok/FAIL lines, exit 1 on any failure
# ------------------------------------------------------------
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
ISO="$REPO/iso"

pass=0 fail=0
ok()  { echo "ok    $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ---- 1. profiledef ------------------------------------------------------------------
check "profiledef.sh parses" bash -n "$ISO/profiledef.sh"
# shellcheck disable=SC2034,SC2154  # the variables come from profiledef.sh
(
    declare -A file_permissions  # mkarchiso declares it before sourcing
    # shellcheck disable=SC1091
    . "$ISO/profiledef.sh"
    printf '%s\n' "$iso_name" "${bootmodes[*]}" "$install_dir" "$iso_label" "$iso_publisher" "$iso_application" "${airootfs_image_tool_options[*]}"
) >"$T/pd"
mapfile -t pd <"$T/pd"
check "profiledef: iso_name is invictus" test "${pd[0]}" = invictus
check "profiledef: UEFI only, systemd-boot (D5)" test "${pd[1]}" = uefi.systemd-boot
check "profiledef: install_dir stays arch (archiso and Ventoy defaults)" test "${pd[2]}" = arch
check "profiledef: label INVICTUS_YYYYMM, at most 32 characters" bash -c "[[ '${pd[3]}' =~ ^INVICTUS_[0-9]{6}$ && \${#pd} -le 32 ]]"
check "profiledef: publisher and application do not use the Arch name" bash -c "! grep -qi 'arch' <<<'${pd[4]} ${pd[5]}'"
# Compression (2026-10-08): zstd, fast to read at random; xz in 1 MiB
# blocks was the likely cause of the ten-minute first boot.
check "profiledef: zstd squashfs by default (fast random reads)" grep -q -- '^-comp zstd ' <<<"${pd[6]}"
check "profiledef: never xz for the squashfs" bash -c "! grep -Eq \"'xz'|-comp xz\" '$ISO/profiledef.sh'"
check "profiledef: zstd level 19 for release builds" grep -q -- '-Xcompression-level 19 ' <<<"${pd[6]}"
check "profiledef: 256 KiB blocks (measured: fastest cold reads; 128 KiB is bigger and slower to read through)" grep -q -- '-b 256K$' <<<"${pd[6]}"
pdz="$(INVICTUS_COMPRESSION=zstd-fast bash -c "declare -A file_permissions; . '$ISO/profiledef.sh'; echo \"\${airootfs_image_tool_options[*]}\"")"
check "profiledef: --fast is zstd at a low level, same block size" grep -q -- '^-comp zstd -Xcompression-level 3 -b 256K$' <<<"$pdz"
check "build-iso: zstd by default, zstd-fast with --fast" bash -c "grep -qx 'COMPRESSION=zstd' '$REPO/scripts/build-iso.sh' && grep -q -- '--fast) COMPRESSION=zstd-fast' '$REPO/scripts/build-iso.sh'"
check "live initramfs: zstd, not xz" grep -qx 'COMPRESSION="zstd"' "$ISO/airootfs/etc/mkinitcpio.conf.d/archiso.conf"

# ---- 2. boot entries ----------------------------------------------------------------
entries=("$ISO"/efiboot/loader/entries/*.conf)
for e in "${entries[@]}"; do
    n="$(basename "$e")"
    check "boot entry $n: title without the Arch name" bash -c "! grep -i '^title.*arch' '$e'"
    if grep -q '^linux' "$e"; then
        check "boot entry $n: archiso's standard parameters (Ventoy, dd)" \
            grep -Eq '^options +archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% %KERNEL_PARAMS%' "$e"
        check "boot entry $n: no hard-coded device path" bash -c "! grep -Eq '/dev/|root=|archisodevice=' '$e'"
    fi
done
default="$(awk '$1 == "default" { print $2 }' "$ISO/efiboot/loader/loader.conf")"
check "loader.conf default entry exists" test -f "$ISO/efiboot/loader/entries/$default"
check "the default entry is the plain install with the splash" grep -q 'quiet splash$' "$ISO/efiboot/loader/entries/$default"
check "an Advanced entry passes invictus.install=advanced" grep -q 'invictus.install=advanced' "$ISO/efiboot/loader/entries/02-invictus-advanced.conf"
check "a safe-graphics entry passes invictus.safe=1" grep -q 'invictus.safe=1' "$ISO/efiboot/loader/entries/03-invictus-safe.conf"
check "loopback.cfg keeps img_dev/img_loop for GRUB loopback boots" bash -c "grep -c 'img_dev=UUID=\${archiso_img_dev_uuid} img_loop=\"\${iso_path}\"' '$ISO/grub/loopback.cfg' | grep -qx 3"
check "loopback.cfg without the Arch name in entries" bash -c "! grep -i 'menuentry.*arch' '$ISO/grub/loopback.cfg'"



# The live initramfs keeps archiso's own boot hooks (Ventoy hooks archiso's
# mount handler) plus plymouth; memdisk and PXE hooks are out because their
# tools (syslinux, nbd, nfs utils) are not on the image and mkinitcpio fails.
want='HOOKS=(base udev microcode modconf kms plymouth archiso archiso_loop_mnt block filesystems keyboard)'
check "live initramfs: archiso hooks plus plymouth, no memdisk or PXE" grep -qxF "$want" "$ISO/airootfs/etc/mkinitcpio.conf.d/archiso.conf"

# ---- 3. live-only and keep lists ---------------------------------------------------------
list_entries() { grep -v '^[[:space:]]*\(#\|$\)' "$1"; }
covered() {
    local f="$1" e
    while IFS= read -r e; do
        [[ "$f" == "$e" || "$f" == "$e"/* ]] && return 0
    done < <(list_entries "$ISO/live-only.txt"; list_entries "$ISO/keep.txt")
    return 1
}
while IFS= read -r f; do
    rel="/${f#"$ISO/airootfs/"}"
    check "airootfs$rel is live-only or kept" covered "$rel"
done < <(find "$ISO/airootfs" \( -type f -o -type l \) | sort)
while IFS= read -r e; do
    if [[ "$e" == /etc/invictus/iso-release ]]; then
        check "live-only $e is written by build-iso.sh" grep -q 'etc/invictus/iso-release' "$REPO/scripts/build-iso.sh"
    else
        check "live-only $e exists in airootfs" test -e "$ISO/airootfs$e" -o -L "$ISO/airootfs$e"
    fi
done < <(list_entries "$ISO/live-only.txt")
check "no file is both live-only and kept" bash -c "! comm -12 <(grep -v '^#' '$ISO/live-only.txt' | sort) <(grep -v '^#' '$ISO/keep.txt' | sort) | grep -q ."
check "the live user's NOPASSWD rule is live-only" grep -qx '/etc/sudoers.d/liber' "$ISO/live-only.txt"

# Boot waits (first hardware boot, 2026-10-08). The live image's
# /etc/machine-id is "uninitialized" (mkarchiso), so systemd-firstboot runs;
# with no /etc/vconsole.conf it asks for a keymap on a VT console and holds
# sysinit.target until someone answers, under the Plymouth splash.
fb="$ISO/airootfs/etc/systemd/system/systemd-firstboot.service"
check "boot wait: systemd-firstboot is masked on the live image" bash -c "[[ -L '$fb' && \"\$(readlink '$fb')\" == /dev/null ]]"
check "boot wait: the firstboot mask is live-only (the installed system has a machine id)" \
    grep -qx /etc/systemd/system/systemd-firstboot.service "$ISO/live-only.txt"
check "boot wait: no boot entry names a serial console (serial-getty would wait on its device)" \
    bash -c "! grep -Eq 'console=tty[A-Z]' '$ISO'/efiboot/loader/entries/*.conf '$ISO/grub/loopback.cfg'"
check "boot wait: the live image enables no time-sync or network-online waiter" \
    bash -c "! find '$ISO/airootfs' -path '*.wants/*' | grep -Eq 'time-wait-sync|wait-online'"
# sshd off (design-simple-mode 1.3, 2026-10-08): systemd-ssh-generator binds
# sshd to /run/ssh-unix-local/socket whenever openssh is installed. The mask
# is invictus-sys's file (Janus I-2), so the live image and every install
# get it from the package: invictus-base (in the live image's package list)
# brings invictus-guardrails, which brings invictus-sys. A copy in airootfs
# would make pacstrap refuse invictus-sys ("exists in filesystem").
gm=/etc/systemd/system-generators/systemd-ssh-generator
check "sshd off: the generator mask is not in airootfs, keep.txt or live-only.txt (invictus-sys owns it)" \
    bash -c "[[ ! -e '$ISO/airootfs$gm' && ! -L '$ISO/airootfs$gm' ]] && ! grep -qx '$gm' '$ISO/keep.txt' '$ISO/live-only.txt'"
check "sshd off: invictus-sys ships the mask, and the live image installs invictus-sys (invictus-base -> invictus-guardrails -> invictus-sys)" \
    bash -c "grep -qF 'ln -s /dev/null \"\$pkgdir$gm\"' '$REPO/pkgs/own/invictus-sys/PKGBUILD' && grep -qx invictus-base '$ISO/packages.x86_64' \
             && grep -q \"'invictus-guardrails'\" '$REPO/pkgs/meta/invictus-base/PKGBUILD' && grep -q \"'invictus-sys\" '$REPO/pkgs/own/invictus-guardrails/PKGBUILD'"

# ---- 4. secrets ---------------------------------------------------------------------------
SCAN="$ISO/secrets-scan.sh"
check "secrets scan: airootfs is clean" bash "$SCAN" "$ISO/airootfs"
plant() {  # plant NAME PATH CONTENT: a clean copy of airootfs with one secret; the scan must fail
    local d="$T/plant-$1"
    cp -a "$ISO/airootfs" "$d"
    mkdir -p "$(dirname "$d/$2")"
    printf '%s\n' "$3" >"$d/$2"
    if bash "$SCAN" "$d" >"$T/scan.out" 2>&1; then bad "secrets scan catches $1"; else ok "secrets scan catches $1"; fi
}
body="$(printf 'A%.0s' {1..64})"
plant "a PGP private key block" "usr/share/invictus/key.asc" "$(printf -- '-----BEGIN PGP PRIVATE KEY BLOCK-----\nComment: x\n\n%s\n' "$body")"
plant "an OpenSSH private key" "etc/skel/notes.txt" "$(printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n%s\n' "$body")"
plant "a PEM key with CRLF line ends" "etc/k.pem" "$(printf -- '-----BEGIN PRIVATE KEY-----\r\n%s\r\n' "$body")"
plant "a GitHub token" "etc/profile.d/gh.sh" "export GH_TOKEN=ghp_$(printf 'a%.0s' {1..36})"
plant "a fine-grained GitHub token" "etc/x.conf" "token=github_pat_$(printf 'b%.0s' {1..70})"
plant "an Anthropic API key" "etc/environment" "ANTHROPIC_API_KEY=sk-ant-api03-$(printf 'c%.0s' {1..40})"
plant "Claude Code credentials" "home/liber/.claude/.credentials.json" "{}"
plant "a filled pacman keyring" "etc/pacman.d/gnupg/pubring.gpg" "x"
plant "a GnuPG private key store" "root/.gnupg/private-keys-v1.d/ABC.key" "x"
plant "an SSH host key" "etc/ssh/ssh_host_ed25519_key" "x"
plant "an AWS key" "etc/aws" "AKIA$(printf 'Q%.0s' {1..16})"
plant "a home other than the live user's" "home/alex/.bashrc" "x"
d="$T/allow"; cp -a "$ISO/airootfs" "$d"; mkdir -p "$d/usr/lib/python3.14/test/certdata"
printf -- '-----BEGIN RSA PRIVATE KEY-----\n%s\n' "$body" >"$d/usr/lib/python3.14/test/certdata/keycert.pem"
mkdir -p "$d/usr/share/mime/packages"
printf '<match value="-----BEGIN PGP PRIVATE KEY BLOCK-----" type="string" offset="0"/>\n' >"$d/usr/share/mime/packages/freedesktop.org.xml"
check "secrets scan: upstream test keys and MIME tables quoting key headers are allowed" bash "$SCAN" "$d"
printf -- '-----BEGIN PGP PRIVATE KEY BLOCK-----\n\n%s\n' "$body" >"$d/usr/lib/python3.14/test/certdata/pgp.asc"
if bash "$SCAN" "$d" >/dev/null 2>&1; then bad "secrets scan: a PGP private key is caught even in test data"; else ok "secrets scan: a PGP private key is caught even in test data"; fi

# ---- 5. os-release and names ----------------------------------------------------------------
osr="$ISO/boot-branding/os-release"
check "os-release: NAME Invictus" grep -qx 'NAME="Invictus"' "$osr"
check "os-release: ID invictus, ID_LIKE arch" bash -c "grep -qx 'ID=invictus' '$osr' && grep -qx 'ID_LIKE=arch' '$osr'"
check "os-release: no 'Arch Linux'" bash -c "! grep -qi 'arch linux' '$osr'"
check "os-release hook re-applies after filesystem upgrades" bash -c "grep -qx 'Target = filesystem' '$ISO/boot-branding/invictus-os-release.hook' && grep -q '/usr/lib/os-release' '$ISO/boot-branding/invictus-os-release.hook'"

# ---- support identity (no personal names in product text, Alex 2026-09-30)
# shellcheck disable=SC1091
. "$ISO/support.env"
check "os-release support contact is the support identity" grep -qx "SUPPORT_URL=\"mailto:$SUPPORT_EMAIL\"" "$osr"
check "installer branding points at the support identity" grep -q "productUrl: \"mailto:$SUPPORT_EMAIL\"" "$REPO/installer/branding/invictus/branding.desc"
check "ISO publisher is the support identity" grep -qF "iso_publisher=\"$SUPPORT_NAME <$SUPPORT_EMAIL>\"" "$ISO/profiledef.sh"
# Everything a person sees: no personal name (the repo server URL in
# pacman.conf is an address, not text, and is allowed).
seen=("$osr" "$REPO/installer/branding/invictus/branding.desc" "$REPO/installer/branding/invictus/show.qml"
      "$REPO/installer/diskcheck/DiskCheckViewStep.cpp" "$REPO"/installer/live/*.desktop
      "$REPO"/installer/calamares/*/modules/*.conf "$ISO"/efiboot/loader/entries/*.conf "$ISO/grub/loopback.cfg"
      "$ISO/boot-branding/plymouth/invictus.plymouth" "$REPO/installer/data/limine-header.conf")
check "no 'Alex' in anything the installer, live session or boot shows (comments aside)" bash -c "! grep -iH 'alex' ${seen[*]} | grep -Ev '^[^:]+:[[:space:]]*(#|//|/?\\*|--)' | grep -q ."

# ---- 6. pacman configuration ------------------------------------------------------------------
bc="$ISO/pacman.conf"
check "build pacman.conf: our repo before core" bash -c "[[ \$(grep -n '^\[@BUILD_REPO_NAME@\]' '$bc' | cut -d: -f1) -lt \$(grep -n '^\[core\]' '$bc' | cut -d: -f1) ]]"
ic="$ISO/airootfs/etc/pacman.conf"
check "installed pacman.conf: our repo first" bash -c "grep '^\[' '$ic' | sed -n 2p | grep -qx '\[@REPO_NAME@\]'"
check "installed pacman.conf: our repo requires signatures" bash -c "sed -n '/^\[@REPO_NAME@\]/,/^\[/p' '$ic' | grep -qx 'SigLevel = Required DatabaseRequired'"
check "installed pacman.conf: multilib for Steam" grep -qx '\[multilib\]' "$ic"
check "installed pacman.conf: no local file:// server" bash -c "! grep -q 'file://' '$ic'"
check "mirrorlist has working servers" bash -c "grep -c '^Server = https://' '$ISO/airootfs/etc/pacman.d/mirrorlist' | grep -qv '^0$'"

# ---- 7. package list ---------------------------------------------------------------------------
pkgs="$(grep -v '^[[:space:]]*\(#\|$\)' "$ISO/packages.x86_64")"
have_pkgbuild() { compgen -G "$REPO/pkgs/*/$1/PKGBUILD" >/dev/null || test -f "$ISO/own-needed/$1/PKGBUILD"; }
while IFS= read -r p; do
    check "package $p has a PKGBUILD" have_pkgbuild "$p"
done < <(grep '^invictus-' <<<"$pkgs")
# AUR packages the ISO's sets need (pkgs/meta/sources.txt says aur or aur-paru).
for p in calamares limine-mkinitcpio-hook limine-snapper-sync zen-browser-bin spaceship-prompt xwaylandvideobridge; do
    check "AUR package $p is pinned in pkgs/aur" test -f "$REPO/pkgs/aur/$p/PKGBUILD"
done
# Our calamares must build our page and packagechooser, or the installer breaks.
cal="$REPO/pkgs/aur/calamares/PKGBUILD"
check "the calamares PKGBUILD used builds our diskcheck page" grep -q 'installer/diskcheck' "$cal"
check "the calamares PKGBUILD used builds packagechooser" bash -c "! sed -n '/_skip_modules=(/,/)/p' '$cal' | grep -qx '[[:space:]]*packagechooser'"
check "the ISO installs the four sets and pipewire-jack (docs/packages.md)" bash -c "for p in invictus-base invictus-desktop invictus-tessera invictus-atrium pipewire-jack; do grep -qx \$p <<<'$pkgs' || exit 1; done"
check "no NVIDIA packages (AMD only)" bash -c "! grep -qi nvidia <<<'$pkgs'"
check "no BIOS loaders (syslinux, grub)" bash -c "! grep -Eqx 'syslinux|grub' <<<'$pkgs'"
# One kernel, linux-cachyos (Alex, 2026-09-30); rollback is the snapshot
# entries, not a second kernel.
basepb="$REPO/pkgs/meta/invictus-base/PKGBUILD"
check "kernel: invictus-base depends on linux-cachyos, not linux or linux-lts" bash -c "grep -q \"'linux-cachyos'\" '$basepb' && ! grep -Eq \"'linux(-lts)?'\" '$basepb'"
check "kernel: every live boot entry starts linux-cachyos" bash -c "for f in '$ISO'/efiboot/loader/entries/0[123]-*.conf; do grep -qx 'linux    /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux-cachyos' \"\$f\" && grep -qx 'initrd   /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux-cachyos.img' \"\$f\" || exit 1; done; ! grep -q 'vmlinuz-linux ' '$ISO/grub/loopback.cfg'"
check "kernel: the live initramfs is built for linux-cachyos" grep -q 'grep -lx linux-cachyos /usr/lib/modules/\*/pkgbase' "$ISO/airootfs/root/customize_airootfs.sh"
check "firmware: no NVIDIA firmware on the ISO (the linux-firmware meta pulls it)" bash -c "! grep -Eq \"'linux-firmware(-nvidia)?'\" '$basepb'"
for fw in amdgpu intel atheros mediatek broadcom realtek; do
    check "firmware: linux-firmware-$fw stays (graphics or Wi-Fi)" grep -q "'linux-firmware-$fw'" "$basepb"
done
check "no duplicate package lines" bash -c "[[ -z \$(sort <<<'$pkgs' | uniq -d) ]]"

# ---- 8. staged build (build-iso.sh --prepare-only) -------------------------------------------------
W="$T/stage"
if bash "$REPO/scripts/build-iso.sh" --prepare-only "$W" --version 2026.09.30 >"$T/prep.out" 2>&1; then
    ok "build-iso --prepare-only runs"
    check "staged: no @...@ left in the pacman configs" bash -c "! grep -rq '@[A-Z_]*@' '$W/profile/pacman.conf' '$W/profile/airootfs/etc/pacman.conf'"
    check "staged: dev build reads the local [invictus-testing] repo unsigned" bash -c "sed -n '/^\[invictus-testing\]/,/^\[/p' '$W/profile/pacman.conf' | grep -qx 'SigLevel = Never'"
    check "staged: installed system uses [invictus-testing] on GitHub" grep -qx 'Server = https://github.com/turneralexander55/invictus/releases/download/invictus-testing' "$W/profile/airootfs/etc/pacman.conf"
    check "staged: release file says dev, testing, the version" bash -c "grep -qx build=dev '$W/profile/airootfs/etc/invictus/iso-release' && grep -qx channel=testing '$W/profile/airootfs/etc/invictus/iso-release' && grep -qx version=2026.09.30 '$W/profile/airootfs/etc/invictus/iso-release'"
    check "staged: the installer package is added under pkgs/own" test -f "$W/src/pkgs/own/invictus-installer/PKGBUILD"
    check "staged: the real checkout's pkgs/ is untouched" test ! -e "$REPO/pkgs/own/invictus-installer"
    # Regression, test-cmd-not-found (2026-09-30): this check read
    # `! -e ...` without a test command, so bash ran "-e", failed, and the
    # "!" made it pass whatever the profile held.
    check "staged: the build-only folders are not in the profile" test ! -e "$W/profile/own-needed" -a ! -e "$W/profile/secrets-scan.sh" -a ! -e "$W/profile/live-only.txt"
    kf="$W/src/pkgs/own/invictus-keyring/invictus.gpg"
    if grep -q INVICTUS-PLACEHOLDER "$REPO/pkgs/own/invictus-keyring/invictus.gpg"; then
        check "staged: dev keyring holds only a public key" bash -c "grep -q 'BEGIN PGP PUBLIC KEY BLOCK' '$kf' && ! grep -q PRIVATE '$kf'"
        check "staged: release file says keyring=dev-throwaway" grep -qx keyring=dev-throwaway "$W/profile/airootfs/etc/invictus/iso-release"
        check "staged: no private key in the staged packages or profile" bash -c "! grep -rlq 'BEGIN PGP PRIVATE KEY BLOCK' '$W/src/pkgs' '$W/profile'"
    fi
    check "staged: the secrets scan passes on the staged airootfs" bash "$ISO/secrets-scan.sh" "$W/profile/airootfs"
else
    bad "build-iso --prepare-only runs"; cat "$T/prep.out"
fi
bash "$REPO/scripts/build-iso.sh" --prepare-only "$T/stage-stable" --channel stable >/dev/null 2>&1
check "staged --channel stable: installed system uses [invictus]" grep -qx '\[invictus\]' "$T/stage-stable/profile/airootfs/etc/pacman.conf"
bash "$REPO/scripts/build-iso.sh" --prepare-only "$T/stage-rel" --release --repo "$T/empty-repo" >"$T/rel.out" 2>&1; rc=$?
check "--release without a signed repo refuses" bash -c "[[ $rc -ne 0 ]] && grep -q 'needs a signed invictus-testing repo' '$T/rel.out'"
bash "$REPO/scripts/build-iso.sh" --prepare-only "$T/stage-rel2" --release --fast >/dev/null 2>&1
check "--release --fast refuses" test $? -ne 0
mkdir -p "$T/signed-repo"; touch "$T/signed-repo/invictus-testing.db" "$T/signed-repo/invictus-testing.db.sig"
if grep -q INVICTUS-PLACEHOLDER "$REPO/pkgs/own/invictus-keyring/invictus.gpg"; then
    bash "$REPO/scripts/build-iso.sh" --prepare-only "$T/stage-rel3" --release --repo "$T/signed-repo" >"$T/rel3.out" 2>&1; rc=$?
    check "--release with the placeholder keyring refuses" bash -c "[[ $rc -ne 0 ]] && grep -q 'real public key' '$T/rel3.out'"
fi
check "build-iso never takes a private signing key" bash -c "! grep -Eq 'INVICTUS_SIGN(ING)?_KEY' '$REPO/scripts/build-iso.sh'"
bash "$REPO/scripts/build-iso.sh" --prepare-only "$T/stage-bad" --channel beta >/dev/null 2>&1
check "an unknown channel refuses" test $? -ne 0

# Size gate (Alex, 2026-10-08: "we can keep it less compressed and find a
# different way to host it"): 2 GiB warns (no GitHub release asset), 4 GiB
# fails (a runaway build). Sparse files, so no disk is used.
size_check() { truncate -s "$1" "$T/invictus-size.iso"; bash "$REPO/scripts/build-iso.sh" --check-size "$T/invictus-size.iso" >"$T/size.out" 2>&1; }
size_check 2147483648; rc=$?
check "size: exactly 2 GiB passes, with the hosting warning" bash -c "[[ $rc -eq 0 ]] && grep -q 'too big for a GitHub release asset. It is hosted elsewhere (team decision 2026-10-08)' '$T/size.out'"
size_check 3000000000; rc=$?
check "size: 3 GB passes, with the hosting warning" bash -c "[[ $rc -eq 0 ]] && grep -q 'too big for a GitHub release asset' '$T/size.out'"
size_check 4294967296; rc=$?
check "size: 4 GiB fails the build (runaway bound)" bash -c "[[ $rc -ne 0 ]] && grep -q 'at or over the 4 GiB bound' '$T/size.out'"
size_check 4294967295; rc=$?
check "size: one byte under 4 GiB passes" test "$rc" -eq 0
size_check 2147483647; rc=$?
check "size: one byte under 2 GiB passes without a warning" bash -c "[[ $rc -eq 0 ]] && ! grep -q WARNING '$T/size.out'"
rm -f "$T/invictus-size.iso"
check "size: the build checks every ISO it makes (dev and release)" bash -c "tail -n 3 '$REPO/scripts/build-iso.sh' | grep -qx 'check_iso_size \"\$iso\"'"

# iso.yml's publish step (2026-10-08): an ISO of 2 GiB or more stays a
# workflow artifact; the step refuses before it touches any release. The
# step's own script runs here with fake gh and sha256sum.
pub="$T/publish"; mkdir -p "$pub/bin" "$pub/out/iso"
python3 -c 'import sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
print(next(st["run"] for st in w["jobs"]["publish"]["steps"] if st.get("name", "").startswith("Attach")))' \
    "$REPO/.github/workflows/iso.yml" >"$pub/step.sh" 2>"$pub/py.err"
check "iso.yml: the publish job's attach step is found" test -s "$pub/step.sh"
printf '#!/bin/sh\necho "gh $*" >>"%s/gh.log"\n' "$pub" >"$pub/bin/gh"
printf '#!/bin/sh\nexit 0\n' >"$pub/bin/sha256sum"
chmod +x "$pub/bin/gh" "$pub/bin/sha256sum"
publish() {  # publish BYTES: run the step on a sparse ISO of that size
    rm -f "$pub/gh.log" "$pub/out/iso/invictus-t-x86_64.iso"; : >"$pub/gh.log"
    truncate -s "$1" "$pub/out/iso/invictus-t-x86_64.iso"
    (cd "$pub" && PATH="$pub/bin:$PATH" ISO=invictus-t-x86_64.iso VERSION=t bash --noprofile --norc -eo pipefail step.sh) >"$pub/out.txt" 2>&1
}
publish 2147483648; rc=$?
check "iso.yml publish: an ISO of 2 GiB is refused" test "$rc" -ne 0
check "iso.yml publish: ... with a message naming the hosting decision" grep -q '::error::invictus-t-x86_64.iso is 2147483648 bytes, 2 GiB or more: GitHub does not take release assets that big.*team decision 2026-10-08' "$pub/out.txt"
check "iso.yml publish: ... before any release is created or uploaded to" test ! -s "$pub/gh.log"
publish 2147483647; rc=$?
check "iso.yml publish: an ISO under 2 GiB is attached" bash -c "[[ $rc -eq 0 ]] && grep -q '^gh release upload iso-t invictus-t-x86_64.iso' '$pub/gh.log'"
rm -f "$pub/out/iso/invictus-t-x86_64.iso"
python3 -c 'import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["build"]["steps"]
smoke = next(i for i, st in enumerate(steps) if "tests/iso/boot-smoke.sh" in st.get("run", ""))
upload = next(i for i, st in enumerate(steps) if "upload-artifact" in st.get("uses", ""))
assert upload < smoke, "boot smoke before the upload"
assert "/dev/kvm" in steps[smoke]["run"]' "$REPO/.github/workflows/iso.yml" 2>"$T/smoke-step.err"
check "iso.yml: the build boots the ISO with boot-smoke.sh after uploading it, and needs KVM" test $? -eq 0
python3 -c 'import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["build"]["steps"]
at = lambda s: next(i for i, st in enumerate(steps) if s in st.get("run", ""))
build, e2e, disk = at("scripts/build-iso.sh"), at("tests/iso/e2e-jobs.sh"), at("tests/iso/disk-boot.sh")
assert build < e2e < disk, "order: build, e2e (install), disk boot"
assert "if" not in steps[e2e], "the install runs for every kind of build"
assert "--keep" in steps[e2e]["run"] and "--iso" in steps[e2e]["run"], "e2e installs the ISO and keeps the disk"
assert "/dev/kvm" in steps[disk]["run"], "disk boot needs KVM"
logs = [st for st in steps[disk:] if "upload-artifact" in st.get("uses", "") and st.get("if") == "failure()"]
assert logs and "out/disk-boot" in logs[0]["with"]["path"], "disk-boot logs uploaded on failure"
assert "disk.img" not in logs[0]["with"]["path"] and "out/disk\n" not in logs[0]["with"]["path"] + "\n", "not the image"
' "$REPO/.github/workflows/iso.yml" 2>"$T/disk-step.err"
check "iso.yml: the ISO is installed onto a kept disk (e2e-jobs --keep) that disk-boot.sh then boots with KVM, logs uploaded on failure" test $? -eq 0
check "iso.yml: the build no longer claims a 2 GiB failure" bash -c "! grep -q 'so an ISO that gets here is under it' '$REPO/.github/workflows/iso.yml'"

# ---- 9. Plymouth theme --------------------------------------------------------------------------
PL="$ISO/boot-branding/plymouth"
# shellcheck disable=SC2013  # names without spaces
for img in $(grep -o '"[a-z-]*\.png"' "$PL/invictus.script" | tr -d '"' | sort -u) ray-{1..9}.png; do
    [[ "$img" == ray-.png || "$img" == .png ]] && continue
    check "plymouth: $img has a source SVG" test -f "$PL/${img%.png}.svg"
done
check "plymouth: script theme pointing at the installed paths" bash -c "grep -qx 'ModuleName=script' '$PL/invictus.plymouth' && grep -qx 'ScriptFile=/usr/share/plymouth/themes/invictus/invictus.script' '$PL/invictus.plymouth'"
check "plymouth: rays light left to right" bash -c "grep -o 'x2=\"[0-9.]*\"' '$PL'/ray-{1..9}.svg | cut -d'\"' -f2 | sort -c -n"
check "plymouth: background is night #14120F" grep -q 'SetBackgroundTopColor(0.078, 0.071, 0.059)' "$PL/invictus.script"

check "art: every PNG is rendered from its SVG (iso/render-art.sh --check)" bash "$ISO/render-art.sh" --check
for img in logo icon welcome; do
    check "art: installer branding $img.png exists" test -s "$REPO/installer/branding/invictus/$img.png"
done

# ---- 10. the installer package installs what the configs call ----------------------------------------
IP="$ISO/own-needed/invictus-installer/PKGBUILD"
for j in "$REPO"/installer/jobs/*.sh; do
    n="$(basename "$j" .sh)"
    [[ "$n" == lib ]] && continue
    check "installer package installs job $n" grep -q "for j in .*\b$n\b" "$IP"
done
# shellcheck disable=SC2016  # a literal $pkgdir
check "installer package installs lib.sh next to the jobs" grep -q 'installer/jobs/lib.sh" "$pkgdir/usr/lib/invictus/installer/lib.sh"' "$IP"
check "installer package ships the live-only list" grep -q 'iso/live-only.txt' "$IP"
check "installer package installs the invictusextras module where Calamares looks (local)" \
    grep -q 'usr/lib/calamares/modules/invictusextras' "$IP"

echo
echo "profile: $pass passed, $fail failed"
((fail == 0))
