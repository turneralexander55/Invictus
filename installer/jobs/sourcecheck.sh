#!/usr/bin/env bash
# ------------------------------------------------------------
# invictus-sourcecheck SFS: the first job of the install, before the
# partition job writes anything. Stops the install while the disks are
# still untouched if the image unpackfs copies from is not there (design
# note 60: archiso's copytoram had unmounted the boot medium, and the
# install failed only after partitioning had erased the disk).
# ------------------------------------------------------------
set -euo pipefail

sfs="${1:?usage: sourcecheck.sh /path/to/airootfs.sfs}"
if [[ ! -f "$sfs" ]]; then
    echo "The installer cannot find the system image ($sfs). Nothing on your disks was changed. Restart from the USB stick and try again." >&2
    exit 1
fi
echo "sourcecheck: $sfs present"
