#!/bin/bash
# ===========================================================================
# build.sh -- regenerate the CP/M-86 C-runtime artifacts that the Open Watcom
# "owcc -bcpm86" one-command build depends on, entirely FROM SOURCE IN GIT.
#
# Produces (into $WATCOM/lib286/cpm86/, a .gitignored install dir):
#     cstartcpm.obj   CP/M-86 startup   (from ./cstartcpm.asm)
#     clibs.lib       CP/M-86 C library (from ./putchar.c + Watcom clib source)
#
# These two files are the pieces wlink's `system begin cpm86` block references
# (`libfile cstartcpm.obj` + auto-fetch of `clibs.lib` from `%WATCOM%/lib286/
# cpm86`).  They are build OUTPUT, git-ignored by .gitignore's `/*/` rule, so
# they vanish on `clean.sh`.  Everything needed to rebuild them, however, is in
# git: this script, cstartcpm.asm, putchar.c, and the stock Watcom clib sources
# under bld/clib/.  Re-run this after any clean.
#
# Once built, a single command links a CP/M-86 .CMD:
#     WLINK_LNK=$OW/bld/wl/lnk/osxa64/wlink.lnk \
#     owcc -bcpm86 -mcmodel=s prog.c -o PROG.CMD
# (WLINK_LNK points wlink at the config that defines `system cpm86`; source
#  env.sh from this directory to set WATCOM/WLINK_LNK/PATH in one step.)
# ===========================================================================
set -e
cd "$(dirname "$0")"
HERE="$(pwd)"
OW="${OW:-$(cd ../../.. && pwd)}"
B="$OW/bld"

# --- native tools (owcc drives children by bare name; expose unsuffixed) ---
BIN="$(mktemp -d)"
ln -sf "$B/cc/i86/osxa64/binbuild/wcc.exe" "$BIN/wcc"
ln -sf "$B/wasm/osxa64/wasm.exe"           "$BIN/wasm"
ln -sf "$B/wl/osxa64/wlink.exe"            "$BIN/wlink"
ln -sf "$B/nwlib/osxa64/wlib.exe"          "$BIN/wlib"
ln -sf "$B/wcl/owcc/osxa64/owcc.exe"       "$BIN/owcc"
cp     "$B/wcl/owcc/osxa64/specs.owc"      "$BIN/specs.owc"
export PATH="$BIN:$PATH" WATCOM="$OW" OWROOT="$OW"
export WLINK_LNK="$B/wl/lnk/osxa64/wlink.lnk"
trap 'rm -rf "$BIN"' EXIT

DEST="$OW/lib286/cpm86"
mkdir -p "$DEST"
WORK="$(mktemp -d)"

# Include path for building stock Watcom clib source (mirrors the port build).
INC="-i=$B/lib_misc/h -i=$B/clib/h -i=$B/clib/intel/h -i=$B/watcom/h -i=$B/hdr/dos/h"
# Compile Watcom clib modules the same way the DOS 16-bit small-model library
# does: -bt=dos picks the 16-bit host, -ms small model, -0 8086, -zl suppress
# the auto-lib record inside the members, -x no default includes.
CLIB="-bt=dos -0 -ms -zl -zastd=c99 -x"

echo "==> startup: cstartcpm.obj"
wasm -ms -0 "$HERE/cstartcpm.asm" -fo="$WORK/cstartcpm.obj"

echo "==> clib members"
# console seam (our CP/M-86 BDOS putchar)
owcc -bcpm86 -mcmodel=s -O2 -c "$HERE/putchar.c" -o "$WORK/putchar.obj"
# 32-bit long multiply / divide helpers (stock Watcom cgsupp)
wasm -ms -0 -i="$B/watcom/h" "$B/clib/cgsupp/a/i4m.asm" -fo="$WORK/i4m.obj"
wasm -ms -0 -i="$B/watcom/h" "$B/clib/cgsupp/a/i4d.asm" -fo="$WORK/i4d.obj"
# a genuine stock Watcom clib module, to prove auto-fetch of real clib code
wcc $CLIB $INC "$B/clib/string/c/strlen.c" -fo="$WORK/strlen.obj"

echo "==> archive clibs.lib"
rm -f "$WORK/clibs.lib"
wlib -q -b "$WORK/clibs.lib" \
    +"$WORK/putchar.obj" +"$WORK/i4m.obj" +"$WORK/i4d.obj" +"$WORK/strlen.obj"

echo "==> install into $DEST"
cp "$WORK/cstartcpm.obj" "$DEST/cstartcpm.obj"
cp "$WORK/clibs.lib"     "$DEST/clibs.lib"
rm -rf "$WORK"
ls -l "$DEST"

# --- self-test: single-command owcc -bcpm86 build + emu2 oracle -------------
EMU2="${EMU2:-/Users/ravn/z80/scratch/cpm86-tools/emu2-cpm86/emu2}"
MSRC="$OW/contrib/ravn/owc-drc/mandel.c"
DRC="$OW/contrib/ravn/owc-drc/MANDEL-DRC.CMD"     # independent DR C oracle
if [ -f "$MSRC" ]; then
    T="$(mktemp -d)"
    echo "==> self-test: owcc -bcpm86 mandel.c -o MANDEL.CMD  (single command)"
    # mandel.c hits wcc ICE 97 at -O1+ on its ternary/string-index line, so -O0.
    ( cd "$T" && owcc -bcpm86 -mcmodel=s -O0 "$MSRC" -o MANDEL.CMD )
    ls -l "$T/MANDEL.CMD"
    if [ -x "$EMU2" ] && [ -f "$DRC" ]; then
        ( cd "$T" && EMU2_DRIVE_A=. EMU2_DEFAULT_DRIVE=A "$EMU2" MANDEL.CMD 2>/dev/null | tr -d '\r' >ours.txt
          cp "$DRC" MANDEL-DRC.CMD
          EMU2_DRIVE_A=. EMU2_DEFAULT_DRIVE=A "$EMU2" MANDEL-DRC.CMD 2>/dev/null | tr -d '\r' >drc.txt )
        if diff -q "$T/ours.txt" "$T/drc.txt" >/dev/null; then
            echo "PASS: owcc build byte-identical to independent DR C oracle"
        else
            echo "FAIL: mandel output differs from DR C oracle"; diff "$T/ours.txt" "$T/drc.txt" | head; rm -rf "$T"; exit 1
        fi
    else
        echo "(skipped emu2 oracle: emu2 or DR C reference not found)"
    fi
    rm -rf "$T"
fi
echo "DONE."
