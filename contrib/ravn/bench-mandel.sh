#!/usr/bin/env bash
#
# bench-mandel.sh -- build the fixed-point Mandelbrot kernel several ways with
# Open Watcom C (against the Digital Research C run-time) and compare each
# against the genuine DR C build, which is the correctness ORACLE and the
# size/speed BASELINE.
#
# This is the compute-bound sibling of bench.sh (Dhrystone).  The SAME source
# (owc-drc/mandel.c: 80x25 ASCII Mandelbrot, fixed-point 8.8, ported verbatim
# from the llvm-z80 test-gen example) is built in the SAME small/8080 memory
# model DR C uses; only the Open Watcom code-generator settings change:
#
#   O0     -ecc -od     cdecl (stack) calls, optimiser disabled   (~ -O0)
#   O3     -ecc -ox     cdecl (stack) calls, full optimisation    (~ -O2/-O3)
#   mixed       -ox     register calls user<->user, cdecl to libc (llvm-z80
#                       trick: -fi=compat-mixed.h, NO -ecc), full optimisation
#
# Output is deterministic (25 lines x 80 columns, no timing, no input), so
# every build must reproduce the DR C oracle byte-for-byte.  A single shared
# putchar.asm (BDOS function 2, C_WRITE) is the only I/O primitive, identical
# in all four builds -- so the measured work is the fixed-point compute loop,
# not two different libc stdout paths.  Unlike Dhrystone, mandel.c makes NO
# user<->user calls (everything is inlined in main), so O3 and mixed are
# expected to be near-identical: the register-calling trick has almost nothing
# to optimise in a compute-bound kernel -- exactly the case bench.sh's writeup
# predicted would "see even less".
#
# Speed is reported as INSTRUCTIONS and estimated iAPX 186 CLOCK CYCLES
# (contrib/ravn/cycles186.py) and, at --mhz (default 6, the RC759 Piccoline),
# as an estimated wall-clock time.  The clock figure is an estimate: Unicorn is
# a functional emulator with no timing; cycles186.py layers an 80186 clock
# table on a capstone decode and does NOT model the prefetch queue or memory
# wait-states.  Treat it as "cirka-ish"; use MAME/PCE for cycle-exact timing.
#
# The DR C oracle (owc-drc/MANDEL-DRC.CMD) needs the DRI copyright toolchain,
# so it is not committed.  If DRC_HOME (with drc.cmd/link86.cmd/clears.l86 --
# see pure-drc/build-pure-drc.sh) is present this script rebuilds and compares
# against it directly; otherwise it falls back to the persisted numbers in
# baseline.json ("mandel").
#
# Usage:  ./bench-mandel.sh [--mhz N]
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
XDEV="$HERE/cpm86-crossdev"
BIN="$REPO/build/binbuild"
EMU2="$XDEV/bin/emu2"
LINK86="$XDEV/share/pcdev/linkcmd.exe"
OWC="$HERE/owc-drc"
MHZ=6

while [ $# -gt 0 ]; do
    case "$1" in
        --mhz) MHZ="$2"; shift 2;;
        --mhz=*) MHZ="${1#*=}"; shift;;
        *) echo "usage: $0 [--mhz N]" >&2; exit 2;;
    esac
done

for t in "$BIN/bwcc" "$BIN/bwasm" "$EMU2" "$LINK86"; do
    [ -e "$t" ] || { echo "error: missing prerequisite: $t" >&2; exit 1; }
done
[ -f "$OWC/drc/clears.l86" ] || { echo "error: owc-drc/drc/clears.l86 missing; run owc-drc/fetch-drc.sh first" >&2; exit 1; }

# build_variant <label> <cflags...>  -> writes owc-drc/MANDEL-<label>.CMD
build_variant() {
    local label="$1"; shift
    local cflags="$*"
    local W; W="$(mktemp -d /tmp/benchm.XXXXXX)"
    cp "$OWC"/compat.h "$OWC"/compat-mixed.h "$OWC"/owcrt.asm "$OWC"/putchar.asm \
       "$OWC"/mandel.c "$OWC"/drc/clears.l86 "$OWC"/stdcbench/owmath.asm "$W/"
    cp "$OWC"/drc/*.h "$W/" 2>/dev/null || true
    cp "$LINK86" "$W/LINKCMD.EXE"
    (
        cd "$W"
        "$BIN/bwasm" -0 -ms owcrt.asm   -fo=OWCRT.OBJ   >/dev/null
        "$BIN/bwasm" -0 -ms putchar.asm -fo=PUTCHAR.OBJ >/dev/null
        # owmath.asm supplies Watcom's 32-bit long helpers (__U4M/__I4M/...) that
        # DR C's library lacks; FP_MUL does a (long)a*b>>8, so the link needs them.
        "$BIN/bwasm" -0 -ms owmath.asm  -fo=OWMATH.OBJ  >/dev/null
        cp mandel.c MAND.C
        "$BIN/bwcc" $cflags -Dmain=cmain MAND.C -fo=MAND.OBJ >/dev/null 2>&1 \
            || { echo "error: compile failed for '$label'" >&2; exit 1; }
        EMU2_DRIVE_D="$W" EMU2_PROGNAME='d:\LINKCMD.EXE' \
            "$EMU2" "$W/LINKCMD.EXE" "MAND=OWCRT,MAND,PUTCHAR,OWMATH,CLEARS.L86[S]" >link.log 2>&1 || true
        [ -f MAND.CMD ] || { echo "error: link produced no MAND.CMD for '$label'" >&2; cat link.log >&2; exit 1; }
        cp MAND.CMD "$OWC/MANDEL-$label.CMD"
    )
    rm -rf "$W"
}

echo "Building Watcom variants of the Mandelbrot kernel from owc-drc/mandel.c..."
build_variant O0    -0 -ms -s -zl -ecc -fpi87 -nt=CODE -fi=compat.h       -od
build_variant O3    -0 -ms -s -zl -ecc -fpi87 -nt=CODE -fi=compat.h       -ox
build_variant mixed -0 -ms -s -zl      -fpi87 -nt=CODE -fi=compat-mixed.h -ox

# OW-specific IMUL variant (owc-drc/mandel-ow.c): FP_MUL is a #pragma aux 16x16
# IMUL + byte-extract, so it needs NO owmath (__I4M) at link time.  Output stays
# byte-identical to the oracle; ~4.6x fewer clocks than portable O3.
build_ow_imul() {
    local W; W="$(mktemp -d /tmp/benchm.XXXXXX)"
    cp "$OWC"/compat.h "$OWC"/owcrt.asm "$OWC"/putchar.asm \
       "$OWC"/mandel-ow.c "$OWC"/drc/clears.l86 "$W/"
    cp "$LINK86" "$W/LINKCMD.EXE"
    (
        cd "$W"
        "$BIN/bwasm" -0 -ms owcrt.asm   -fo=OWCRT.OBJ   >/dev/null
        "$BIN/bwasm" -0 -ms putchar.asm -fo=PUTCHAR.OBJ >/dev/null
        cp mandel-ow.c MOW.C
        "$BIN/bwcc" -0 -ms -s -zl -ecc -fpi87 -nt=CODE -fi=compat.h -ox \
            -Dmain=cmain MOW.C -fo=MOW.OBJ >/dev/null 2>&1 \
            || { echo "error: compile failed for 'OWIMUL'" >&2; exit 1; }
        EMU2_DRIVE_D="$W" EMU2_PROGNAME='d:\LINKCMD.EXE' \
            "$EMU2" "$W/LINKCMD.EXE" "MOW=OWCRT,MOW,PUTCHAR,CLEARS.L86[S]" >link.log 2>&1 || true
        [ -f MOW.CMD ] || { echo "error: link produced no MOW.CMD for 'OWIMUL'" >&2; cat link.log >&2; exit 1; }
        cp MOW.CMD "$OWC/MANDEL-OWIMUL.CMD"
    )
    rm -rf "$W"
}
build_ow_imul
echo

# Rebuild the DR C oracle if DRC_HOME is available, else use baseline.json.
ORACLE="$OWC/MANDEL-DRC.CMD"
if [ -n "${DRC_HOME:-}" ] && [ -f "${DRC_HOME}/drc.cmd" ]; then
    echo "DRC_HOME set -- rebuilding the genuine DR C oracle ..."
    ( cd "$HERE/pure-drc" && ./build-pure-drc.sh mandel >/dev/null 2>&1 ) || true
    [ -f "$HERE/pure-drc/mandel.cmd" ] && cp "$HERE/pure-drc/mandel.cmd" "$ORACLE"
fi

if [ -f "$ORACLE" ]; then
    for v in O0 O3 mixed OWIMUL; do
        echo "### DR C (oracle) vs Watcom $v ###"
        python3 "$HERE/bench.py" compare "$ORACLE" "$OWC/MANDEL-$v.CMD" \
            --mhz "$MHZ" --label-candidate "Watcom $v"
        echo
    done
else
    echo "(DR C oracle owc-drc/MANDEL-DRC.CMD not present -- checking against baseline.json)"
    echo
    for v in O0 O3 mixed OWIMUL; do
        echo "### baseline mandel (DR C) vs Watcom $v ###"
        python3 "$HERE/bench.py" baseline check mandel "$OWC/MANDEL-$v.CMD" --mhz "$MHZ" \
            || true
        echo
    done
fi
