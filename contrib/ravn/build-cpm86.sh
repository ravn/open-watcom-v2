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

# Tool names. A full Open Watcom install provides wasm/wcc/wl; a fresh
# bootstrap build (./build.sh preboot + builder boot, or ci/buildx.sh with
# OWBUILD_STAGE=boot) only provides the b-prefixed bootstrap cross-tools in
# build/binbuild (bwasm/bwcc/bwlink). Prefer the released names, fall back to
# the bootstrap ones so this script works straight after a boot build.
pick() { for t in "$@"; do command -v "$t" >/dev/null 2>&1 && { echo "$t"; return; }; done; echo "$1"; }
WASM=$(pick wasm bwasm)
WCC=$(pick wcc bwcc)
WLINK=$(pick wl wlink bwlink)

# Assembler/linker/wrapper differ slightly between the asm and C paths:
#
#   * asm source uses 'org 100h', so wl already emits the 100H base-page
#     padding in the raw image and 'end start_' fixes the entry point. We wrap
#     with --no-basepage (padding is already there).
#   * C source has no 'org'; wcc names the entry symbol with a trailing '_'
#     (default __watcall), so the C function start_() is the object symbol
#     start__. We link with 'option offset=0x100' so all addresses assume a
#     load at 0100H, and let bin2cmd.py reserve the 100H base page (do NOT pass
#     --no-basepage) so the code lands at 0100H to match.
#
# 1. Assemble or compile to an OMF object; 2. link to a flat binary image;
# 3. wrap in the CP/M-86 .CMD header. The "stack segment not found" warning is
# expected and harmless for a freestanding CP/M-86 image.
case "$EXT" in
    asm)
        "$WASM" "-$CPU" "$SRC" -fo="$STEM.obj"
        "$WLINK" format raw bin \
           option quiet \
           name "$STEM.bin" \
           file "$STEM.obj"
        python3 "$HERE/bin2cmd.py" "$STEM.bin" "$CMD" --no-basepage
        ;;
    c)
        # 16-bit x86 (-$CPU), small model (-ms; OW has no separate tiny model),
        # no stack checks (-s), intrinsics on (-oi), no default library refs
        # (-zl). The C entry point is cpmmain(); a startup stub (cpmstart.asm),
        # linked FIRST so it lands at the start of the code group, calls it and
        # terminates -- `wl format raw` does not reorder _TEXT to put the entry
        # symbol first, so the first linked object must be the entry.
        "$WCC" "-$CPU" -ms -s -oi -zl "$SRC" -fo="$STEM.obj"
        "$WASM" "-$CPU" "$HERE/cpmstart.asm" -fo="$HERE/cpmstart.obj"
        "$WLINK" format raw bin \
           option quiet, offset=0x100 \
           name "$STEM.bin" \
           file "$HERE/cpmstart.obj" file "$STEM.obj"
        python3 "$HERE/bin2cmd.py" "$STEM.bin" "$CMD"
        ;;
    *)
        echo "build-cpm86.sh: unknown source type: .$EXT" >&2
        exit 1
        ;;
esac

echo "Built $CMD"
