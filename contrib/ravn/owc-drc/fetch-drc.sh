#!/usr/bin/env bash
#
# fetch-drc.sh -- obtain the Digital Research C (CP/M-86) run-time library and
# headers from a Datamuseum.dk (DDHF) floppy image, into ./drc/.
#
# We link Open Watcom C against DR C's clears.l86 because Open Watcom ships no
# CP/M-86 target run-time of its own.  The image is the original DR C release
# preserved by DDHF; only clears.l86 (small-model run-time) and the C headers
# are extracted.  Extraction uses cpmtools with the bundled ./diskdefs.
#
# Requirements: curl, shasum (or sha256sum), cpmtools (cpmls, cpmcp).
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# DDHF Bits:30002664 -- Digital-Research-C-May84.bin (raw 77c 2h 8s 1024b).
IMG_URL="https://datamuseum.dk/bits/30002664"
IMG="Digital-Research-C-May84.bin"
IMG_SHA="b85731168298db9fcc95f11a09b44e911fe33f75656b9b3da0ab373584ab3999"
FMT="drc-rc759"          # defined in ./diskdefs
OUT="drc"

sha256() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
    else sha256sum "$1" | awk '{print $1}'; fi
}

command -v cpmls >/dev/null 2>&1 || { echo "error: cpmtools (cpmls) not found" >&2; exit 1; }
command -v cpmcp >/dev/null 2>&1 || { echo "error: cpmtools (cpmcp) not found" >&2; exit 1; }

if [ ! -f "$IMG" ]; then
    echo ">> downloading $IMG"
    curl -fsSL -o "$IMG" "$IMG_URL"
fi
got="$(sha256 "$IMG")"
if [ "$got" != "$IMG_SHA" ]; then
    echo "error: sha256 mismatch for $IMG" >&2
    echo "  expected $IMG_SHA" >&2
    echo "  got      $got" >&2
    exit 1
fi
echo ">> sha256 ok: $IMG"

echo ">> extracting run-time + headers into $OUT/"
rm -rf "$OUT"; mkdir -p "$OUT"
# cpmtools reads the format from a 'diskdefs' file in the current directory.
for f in clears.l86 clearl.l86 stdio.h portab.h ctype.h errno.h setjmp.h; do
    cpmcp -f "$FMT" "$IMG" "0:$f" "$OUT/$f"
done

echo ">> cleaning CP/M text padding (^Z / CR) from headers"
for h in "$OUT"/*.h; do
    tr -d '\032\r' < "$h" > "$h.tmp" && mv "$h.tmp" "$h"
done

echo ">> done:"
ls -l "$OUT"
