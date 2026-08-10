#!/bin/sh
# ---------------------------------------------------------------------------
# build-cpm86.sh - build a freestanding CP/M-86 .CMD program with Open Watcom
#
# Open Watcom cannot emit CP/M-86 .CMD files natively (its linker only knows
# DOS .EXE/.COM, OS/2, Windows, ELF, Phar Lap, QNX, RDOS and raw binary -- see
# bld/wl/h/_formats.h). We therefore:
#
#   1. assemble/compile 16-bit x86 (no runtime)
#   2. link to a flat raw binary with wl (format raw)
#   3. wrap the raw image in a 128-byte CP/M-86 .CMD header with bin2cmd.py
#
# Requires a built Open Watcom toolchain on PATH (wasm/wcc, wl) -- i.e. run the
# top-level ./build.sh first and source setvars.sh. Validate the resulting
# .CMD in a CP/M-86 emulator (86Box, PCem, ...).
#
# Usage: ./build-cpm86.sh hello.asm      (or hello.c)
# ---------------------------------------------------------------------------
set -e

SRC=${1:-hello.asm}
STEM=$(basename "$SRC" | sed 's/\.[^.]*$//')
EXT=$(echo "$SRC" | sed 's/.*\.//')
HERE=$(cd "$(dirname "$0")" && pwd)
CMD=$(echo "$STEM" | tr '[:lower:]' '[:upper:]').CMD

# Target CPU instruction level (wcc/wasm -<n>): 0=8086 (default), 1=80186,
# 2=80286, 3=80386... Only the instruction set matters here; CP/M-86 is
# real-mode and we run the result at instruction level (Unicorn/QEMU handles
# 80186+ opcodes fine). Override with e.g.  CPU=1 ./build-cpm86.sh hello.asm
CPU=${CPU:-0}

# 1. Assemble or compile to an OMF object.
case "$EXT" in
    asm)
        wasm "-$CPU" "$SRC" -fo="$STEM.obj"
        ;;
    c)
        # 16-bit x86 (-$CPU), tiny model (-mt), no stack checks (-s).
        wcc "-$CPU" -mt -s -oi -zl "$SRC" -fo="$STEM.obj"
        ;;
    *)
        echo "build-cpm86.sh: unknown source type: .$EXT" >&2
        exit 1
        ;;
esac

# 2. Link to a flat binary image. Code is assembled at org 100h (after the
#    100H-byte base page); for the 8080 model CP/M-86 enters at CS:0100H.
wl format raw bin \
   option quiet, start=start_ \
   name "$STEM.bin" \
   file "$STEM.obj"

# 3. Prepend the CP/M-86 .CMD header and reserve the 100H-byte base page
#    (8080 / single-group model). If wl already emits the 100H org padding in
#    the raw image, add --no-basepage here to avoid reserving it twice.
python3 "$HERE/bin2cmd.py" "$STEM.bin" "$CMD"

echo "Built $CMD"
