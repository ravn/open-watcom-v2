#!/bin/sh
# ---------------------------------------------------------------------------
# mkdisk-cpm86.sh - pack CP/M-86 .CMD programs into a disk *image* that a
# full-machine emulator can mount, so the programs run under a REAL Digital
# Research CP/M-86 / Concurrent CP/M-86, not just the instruction-level
# cpm86run_unicorn.py test harness.
#
# Our .CMD programs call the BDOS through software interrupt 224 (INT 0E0h)
# with the standard CP/M-86 function numbers, i.e. they use the genuine
# CP/M-86 ABI -- so the console demos (HELLO, ECHOARG, DHRY) run unmodified on
# real CP/M-86 and Concurrent CP/M-86. (BIGDATA uses a hard-coded far segment
# and is only guaranteed to work under the bundled emulator; see README.)
#
# Requires cpmtools (mkfs.cpm, cpmcp, cpmls). Install e.g. with:
#     brew install cpmtools        (macOS)
#     apt-get install cpmtools     (Debian/Ubuntu)
#
# Usage:  ./mkdisk-cpm86.sh [IMAGE.img] [FILE.CMD ...]
#   IMAGE.img   output image (default: cpm86.img)
#   FILE.CMD    programs to add (default: all *.CMD in this directory)
#
# FORMAT (env) selects the cpmtools disk geometry (default: ibmpc-514ds, the
# classic DR CP/M-86-for-the-IBM-PC 5.25" 320K layout that plain cpmtools
# handles without libdsk).  Notable alternatives:
#     FORMAT=rc75x          Regnecentralen RC759 "Piccoline" (Concurrent CP/M-86,
#                           80186; 77 cyl x 2 head x 8 x 1024-byte sectors).
#                           Build the programs with CPU=1 (80186) for this host.
#     FORMAT=cpm86-720      CP/M-86 720K 3.5" floppy
#
# The image is padded to the full geometry (tracks x sectrk x seclen, read from
# the cpmtools diskdefs) so a full-machine emulator accepts it.
#
# RC759 / PCE note: the PICCOLINE emulator (PCE by Hampa Hug, https://rc700.dk)
# uses the .pbit floppy format.  Convert this raw image with the pfdc/pbit
# tools bundled with PCE:
#     pfdc -r 0-76 0-1 1-8 -p new -e size 1024 -e mfm-hd 1 -p load cpm86.img -o cpm86.pfdc
#     pbit -p encode mfm-hd-360 cpm86.pfdc -o cpm86.pbit
# then, in the emulator monitor:  -m fdc.insert 0:cpm86.pbit
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

# Pad to the full geometry so a full-machine emulator accepts the image. Read
# tracks/sectrk/seclen for FORMAT from the cpmtools diskdefs file.
DISKDEFS=${CPMTOOLS_DISKDEFS:-}
if [ -z "$DISKDEFS" ]; then
    for d in "$HOME/.local/share/diskdefs" /usr/local/share/diskdefs \
             /opt/homebrew/share/diskdefs /usr/share/diskdefs; do
        [ -f "$d" ] && { DISKDEFS=$d; break; }
    done
fi
if [ -n "$DISKDEFS" ]; then
    FULL=$(awk -v f="$FORMAT" '
        $1=="diskdef" { indef = ($2==f) }
        indef && $1=="tracks" { t=$2 }
        indef && $1=="sectrk" { s=$2 }
        indef && $1=="seclen" { l=$2 }
        indef && $1=="end"    { if (t && s && l) print t*s*l; exit }
    ' "$DISKDEFS")
    if [ -n "$FULL" ]; then
        cur=$(wc -c < "$IMG")
        if [ "$cur" -lt "$FULL" ]; then
            dd if=/dev/zero bs=1 count=0 seek="$FULL" of="$IMG" 2>/dev/null
        fi
    fi
fi

echo "Wrote $IMG ($FORMAT, $(wc -c < "$IMG") bytes):"
cpmls -f "$FORMAT" "$IMG"
echo
echo "Mount $IMG in a full-machine emulator running (Concurrent) CP/M-86."
case "$FORMAT" in
    rc75x)
        echo "RC759/PICCOLINE (PCE): convert to .pbit first --"
        echo "  pfdc -r 0-76 0-1 1-8 -p new -e size 1024 -e mfm-hd 1 -p load $IMG -o ${IMG%.img}.pfdc"
        echo "  pbit -p encode mfm-hd-360 ${IMG%.img}.pfdc -o ${IMG%.img}.pbit"
        echo "  then in the monitor:  -m fdc.insert 0:${IMG%.img}.pbit"
        ;;
esac
