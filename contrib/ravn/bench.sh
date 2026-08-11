#!/usr/bin/env bash
#
# bench.sh -- build the Dhrystone 2.1 benchmark several ways with Open Watcom C
# (against the Digital Research C run-time) and compare each against the genuine
# DR C build, which is the correctness ORACLE and the size/speed BASELINE.
#
# The comparison is apples-to-apples: every variant is built from the SAME
# drcified, deterministic Dhrystone source (fixed run count, timing disabled ->
# identical program output), in the SAME small/8080 memory model DR C uses.
# The only thing that changes is the Open Watcom code generator settings:
#
#   O0     -ecc -od     cdecl (stack) calls, optimiser disabled   (~ -O0)
#   O3     -ecc -ox     cdecl (stack) calls, full optimisation    (~ -O2/-O3)
#   mixed       -ox     register calls user<->user, cdecl to libc (llvm-z80
#                       trick: -fi=compat-mixed.h, NO -ecc), full optimisation
#
# Speed is reported as INSTRUCTIONS and as estimated 80186 CLOCK CYCLES (the
# "ticks" metric, contrib/ravn/cycles186.py) and, at --mhz (default 6, the
# RC759 Piccoline), as an estimated wall-clock time.  The clock figure is an
# estimate: Unicorn is a functional emulator with no timing, so cycles186.py
# layers an iAPX 186 clock table on top of a capstone decode.  It does NOT
# model the prefetch queue or memory wait-states; treat it as "cirka-ish".
# For true cycle-accurate timing use MAME or PCE against the real RC759 XIOS.
#
# The DR C oracle (pure-drc/dhry.cmd) needs the DRI copyright toolchain, so it
# is not committed.  If it is present this script compares against it directly;
# otherwise it falls back to the persisted numbers in baseline.json.
#
# Usage:  ./bench.sh [--mhz N]
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
XDEV="$HERE/cpm86-crossdev"
BIN="$REPO/build/binbuild"
EMU2="$XDEV/bin/emu2"
LINK86="$XDEV/share/pcdev/linkcmd.exe"
OWC="$HERE/owc-drc"
RUNS=200
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
[ -f "$OWC/dhry21/dhry_1.c" ] || { echo "error: owc-drc/dhry21 missing; run ./build-owc-drc.sh dhry once to fetch it" >&2; exit 1; }

# build_variant <label> <cflags...>  -> writes owc-drc/DHRY-<label>.CMD
build_variant() {
    local label="$1"; shift
    local cflags="$*"
    local W; W="$(mktemp -d /tmp/bench.XXXXXX)"
    # Deterministic, drcified Dhrystone (watcom dialect: no NOENUM/NOSTRUCTASSIGN).
    python3 "$HERE/pure-drc/drcify.py" "$OWC/dhry21" "$W" "$RUNS" watcom >/dev/null
    cp "$OWC"/compat.h "$OWC"/compat-mixed.h "$OWC"/owcrt.asm "$OWC"/drc/clears.l86 "$W/"
    cp "$OWC"/drc/*.h "$W/" 2>/dev/null || true
    cp "$LINK86" "$W/LINKCMD.EXE"
    (
        cd "$W"
        "$BIN/bwasm" -0 -ms owcrt.asm -fo=OWCRT.OBJ >/dev/null
        for u in DHRY_1 DHRY_2; do
            "$BIN/bwcc" $cflags -Dmain=cmain -i. "$u.C" -fo="$u.OBJ" >/dev/null 2>&1 \
                || { echo "error: compile $u failed for '$label'" >&2; exit 1; }
        done
        EMU2_DRIVE_D="$W" EMU2_PROGNAME='d:\LINKCMD.EXE' \
            "$EMU2" "$W/LINKCMD.EXE" "DHRY=OWCRT,DHRY_1,DHRY_2,CLEARS.L86[S]" >link.log 2>&1 || true
        [ -f DHRY.CMD ] || { echo "error: link produced no DHRY.CMD for '$label'" >&2; cat link.log >&2; exit 1; }
        cp DHRY.CMD "$OWC/DHRY-$label.CMD"
    )
    rm -rf "$W"
}

echo "Building Watcom variants from identical drcified Dhrystone ($RUNS runs)..."
build_variant O0    -0 -ms -s -zl -ecc -fpi87 -nt=CODE -fi=compat.h       -od
build_variant O3    -0 -ms -s -zl -ecc -fpi87 -nt=CODE -fi=compat.h       -ox
build_variant mixed -0 -ms -s -zl      -fpi87 -nt=CODE -fi=compat-mixed.h -ox
echo

ORACLE="$HERE/pure-drc/dhry.cmd"
if [ -f "$ORACLE" ]; then
    for v in O0 O3 mixed; do
        echo "### DR C (oracle) vs Watcom $v ###"
        python3 "$HERE/bench.py" compare "$ORACLE" "$OWC/DHRY-$v.CMD" \
            --mhz "$MHZ" --label-candidate "Watcom $v"
        echo
    done
else
    echo "(DR C oracle pure-drc/dhry.cmd not present -- checking against baseline.json)"
    echo
    for v in O0 O3 mixed; do
        echo "### baseline dhry (DR C) vs Watcom $v ###"
        python3 "$HERE/bench.py" baseline check dhry "$OWC/DHRY-$v.CMD" --mhz "$MHZ" \
            || true
        echo
    done
fi
