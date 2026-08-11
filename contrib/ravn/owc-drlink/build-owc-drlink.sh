#!/bin/sh
# ---------------------------------------------------------------------------
# build-owc-drlink.sh - build a CP/M-86 .CMD from Open Watcom C by linking the
# Watcom OMF output with Digital Research's native CP/M-86 linker (LINK86).
#
# Unlike contrib/ravn/build-cpm86.sh (which links to a flat raw binary with wl
# and wraps it with bin2cmd.py), this path proves that Open Watcom's OMF object
# output is directly consumable by a *real CP/M-86 linker*. DR LINK86 reads the
# Watcom .obj files and emits a proper .CMD with correct group descriptors.
#
# KEY FACTS (verified, see README.md):
#   * Open Watcom emits Intel/MS OMF; DR LINK86 (LINK86 2.02) accepts it as-is.
#   * Compile C with -ecc so Watcom uses cdecl (stack args, leading underscore),
#     matching a classic C-runtime ABI.
#   * Do NOT name the C entry `main` (that pulls Watcom's _cstart_ and exports
#     main_). Use a plain name (here: cmain) so it links against crt.asm.
#
# Prerequisites:
#   1. Built Open Watcom cross-tools (bwcc/bwasm or wcc/wasm) - run ./build.sh.
#   2. The cpm86-crossdev submodule populated with DR tools + emu2:
#        cd contrib/ravn/cpm86-crossdev
#        ./fetch_tools           # or the individual src/fetch/* + buildemu2
#      This provides bin/emu2, bin/pcdev_linkcmd and (for running) bin/cpm86.
#
# Usage: ./build-owc-drlink.sh [hello.c]
# ---------------------------------------------------------------------------
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:-"$HERE/hello.c"}
STEM=$(basename "$SRC" | sed 's/\.[^.]*$//')
CMD=$(echo "$STEM" | tr '[:lower:]' '[:upper:]').CMD

CPU=${CPU:-0}

# Tools: prefer released names, fall back to bootstrap b-prefixed cross-tools.
REPO=$(cd "$HERE/../../.." && pwd)
BINB="$REPO/build/binbuild"
pick() { for t in "$@"; do command -v "$t" >/dev/null 2>&1 && { echo "$t"; return; }; done; echo "$2"; }
WCC=$(pick wcc "$BINB/bwcc")
WASM=$(pick wasm "$BINB/bwasm")

XDEV="$HERE/../cpm86-crossdev"
EMU2="$XDEV/bin/emu2"
LINK86="$XDEV/share/pcdev/linkcmd.exe"

[ -x "$WCC" ]  || { echo "ERR: Watcom C compiler not found ($WCC). Run ./build.sh." >&2; exit 1; }
[ -x "$EMU2" ] || { echo "ERR: emu2 not built. Run cpm86-crossdev/src/fetch/buildemu2." >&2; exit 1; }
[ -f "$LINK86" ] || { echo "ERR: DR linkcmd.exe missing. Run cpm86-crossdev/src/fetch/drtools." >&2; exit 1; }

WORK=$(mktemp -d /tmp/owcdr.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# DR LINK86 has a short limit on the OMF THEADR (module-name) string, which the
# Watcom compiler fills with the *absolute* source path. Compile from a
# short-pathed work dir with bare filenames so THEADR stays within the limit.
cp "$SRC" "$WORK/HELLO.C"
cp "$HERE/crt.asm" "$WORK/CRT.ASM"
cp "$LINK86" "$WORK/LINKCMD.EXE"

# 1. Compile C to OMF: 8086 (-$CPU), small model (-ms), no stack checks (-s),
#    no default library refs (-zl), force cdecl ABI (-ecc).
( cd "$WORK" && "$WCC" "-$CPU" -ms -s -zl -ecc HELLO.C -fo=HELLO.OBJ )

# 2. Assemble the tiny OMF runtime.
( cd "$WORK" && "$WASM" "-$CPU" CRT.ASM -fo=CRT.OBJ )

# 3. Link both OMF objects with DR LINK86 -> .CMD (runtime first = entry).
#    LINK86 syntax: OUTPUT=INPUT1,INPUT2  (drops .OBJ / .CMD extensions).
( cd "$WORK" && EMU2_DRIVE_D="$WORK" EMU2_PROGNAME='d:\LINKCMD.EXE' \
    "$EMU2" "$WORK/LINKCMD.EXE" "HELLO=CRT,HELLO" -- PATH=D:\\ LIB=D:\\ ) \
    2>&1 | grep -iE 'undefined|no file|error|CODE|DATA' || true

cp "$WORK/HELLO.CMD" "$HERE/$CMD"
echo "OK: $HERE/$CMD"

# 4. Optional: run it if the cpm86 emulator is available.
if [ -x "$XDEV/bin/cpm86" ] && [ -f "$XDEV/share/emu/cpm86.exe" ]; then
    echo "--- run on CP/M-86 emulator ---"
    ( cd "$HERE" && PATH="$XDEV/bin:$PATH" cpm86 "$CMD" ) 2>&1 | grep -v 'Copyright\|emulator for DOS'
fi
