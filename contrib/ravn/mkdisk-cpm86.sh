#!/bin/sh
# ---------------------------------------------------------------------------
# mkdisk-cpm86.sh - pack CP/M-86 .CMD programs into a bootable-disk *image*
# that a full-machine emulator (86Box, PCem, QEMU, MAME) can mount, so the
# programs can be run under a REAL Digital Research CP/M-86, not just the
# instruction-level cpm86run_unicorn.py test harness.
#
# Our .CMD programs call the BDOS through software interrupt 224 (INT 0E0h)
# with the standard CP/M-86 function numbers, i.e. they use the genuine
# CP/M-86 ABI -- so the console demos (HELLO, DHRY) run unmodified on real
# CP/M-86. (BIGDATA uses a hard-coded far segment and is only guaranteed to
# work under the bundled emulator; see README.)
#
# Requires cpmtools (mkfs.cpm, cpmcp, cpmls). Install e.g. with:
#     brew install cpmtools        (macOS)
#     apt-get install cpmtools     (Debian/Ubuntu)
#
# Usage:  ./mkdisk-cpm86.sh [IMAGE.img] [FILE.CMD ...]
#   IMAGE.img   output image (default: cpm86.img)
#   FILE.CMD    programs to add (default: all *.CMD in this directory)
#
# The image uses the "ibmpc-514ds" format (IBM PC 5.25" 320K DS, the classic
# DR CP/M-86-for-the-IBM-PC layout) which plain cpmtools handles without the
# optional libdsk driver. Override with FORMAT=... if your emulator/OS build
# expects another geometry (e.g. FORMAT=cpm86-144feat needs libdsk-enabled
# cpmtools for 1.44M).
# ---------------------------------------------------------------------------
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
FORMAT=${FORMAT:-ibmpc-514ds}
IMG=${1:-cpm86.img}
[ $# -gt 0 ] && shift

if ! command -v mkfs.cpm >/dev/null 2>&1 || ! command -v cpmcp >/dev/null 2>&1; then
    echo "mkdisk-cpm86.sh: cpmtools not found (need mkfs.cpm and cpmcp)." >&2
    echo "  install with 'brew install cpmtools' or 'apt-get install cpmtools'." >&2
    exit 1
fi

# Default file set: every .CMD in the script directory.
if [ $# -gt 0 ]; then
    FILES=$*
else
    FILES=$(ls "$HERE"/*.CMD 2>/dev/null || true)
fi
if [ -z "$FILES" ]; then
    echo "mkdisk-cpm86.sh: no .CMD files to add." >&2
    exit 1
fi

rm -f "$IMG"
mkfs.cpm -f "$FORMAT" "$IMG"
# shellcheck disable=SC2086
cpmcp -f "$FORMAT" "$IMG" $FILES 0:

echo "Wrote $IMG ($FORMAT):"
cpmls -f "$FORMAT" "$IMG"
echo
echo "Mount $IMG as a floppy/hard-disk image in a full-machine emulator running"
echo "Digital Research CP/M-86 (86Box, PCem, QEMU qemu-system-i386, or MAME)."
