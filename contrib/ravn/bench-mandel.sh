#!/usr/bin/env bash
#
# bench-mandel.sh -- build the fixed-point Mandelbrot kernel with the native
# one-step Open Watcom CP/M-86 driver (owcc -bcpm86) and compare each variant
# against the genuine DR C build, which stays the correctness ORACLE and the
# size/speed BASELINE.
#
# REWRITTEN 2026-08-19 to the pure owcc path: the old build linked Open Watcom
# objects against DR C's CLEARS.L86 through DR LINK-86 (run under emu2). The
# user does not want DR C's LINK-86 linker used with Watcom, so every variant
# is now built by `owcc -bcpm86` alone (wcc + wlink `format cpm86`, the fork's
# own crt0 + clib). No owcrt.asm/putchar.asm/I4M/I4D/omf-delocal/LINK86/clears.
# The SAME source (owc-drc/mandel.c: 80x25 ASCII Mandelbrot, fixed-point 8.8)
# is built at two optimisation levels, plus the OW-specific IMUL variant
# (owc-drc/mandel-ow.c, FP_MUL via a #pragma aux 16x16->32 IMUL):
#
#   O0       -O0      optimiser disabled
#   O2       -O2      full optimisation
#   OWIMUL   -O2      mandel-ow.c: FP_MUL lowered to one IMUL + byte-extract
#
# The kernel is fixed-point (NO float), so no soft-float flag is needed here
# (float builds must use owcc -msoft-float == wcc -fpc; see
# tasks/memory/reference_watcom_cpm86_softfloat_fpc.md). Output is deterministic
# (25 lines x 80 columns, no timing, no input) so every build reproduces the
# DR C oracle byte-for-byte; the only I/O is clib putchar() (BDOS C_WRITE).
#
# Speed is reported as INSTRUCTIONS and estimated iAPX 186 CLOCK CYCLES
# (contrib/ravn/cycles186.py) and, at --mhz (default 6, the RC759 Piccoline),
# as an estimated wall-clock time. The clock figure is an estimate: Unicorn is
# a functional emulator with no timing; cycles186.py layers an 80186 clock
# table on a capstone decode and does NOT model the prefetch queue or memory
# wait-states. Treat it as "cirka-ish"; use MAME/PCE for cycle-exact timing.
# NOTE: the Unicorn measurer hooks every instruction in Python (~0.4M insns/s),
# so a full run of all variants takes ~half a minute.
#
# The DR C oracle (owc-drc/MANDEL-DRC.CMD) needs the DRI copyright toolchain,
# so it is not committed. If present this script compares against it directly;
# otherwise it falls back to the persisted numbers in baseline.json ("mandel").
#
# Usage:  ./bench-mandel.sh [--mhz N]
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/owc-drc"                    # benchmark sources (mandel.c, mandel-ow.c)
MHZ=6

while [ $# -gt 0 ]; do
    case "$1" in
        --mhz) MHZ="$2"; shift 2;;
        --mhz=*) MHZ="${1#*=}"; shift;;
        *) echo "usage: $0 [--mhz N]" >&2; exit 2;;
    esac
done

# owcc -bcpm86 environment (host-agnostic; builds the drivers from the fork tree).
. "$HERE/cpm86-clib/env.sh"

for f in mandel.c mandel-ow.c; do
    [ -f "$SRC/$f" ] || { echo "error: missing benchmark source $SRC/$f" >&2; exit 1; }
done

# build_variant <label> <src> <optflags...>  -> writes owc-drc/MANDEL-<label>.CMD
build_variant() {
    local label="$1" src="$2"; shift 2
    owcc -bcpm86 -march=i186 -mcmodel=s "$@" -o "$SRC/MANDEL-$label.CMD" "$src" \
        || { echo "error: owcc build failed for '$label'" >&2; exit 1; }
}

echo "Building owcc -bcpm86 variants of the Mandelbrot kernel from owc-drc/mandel.c..."
build_variant O0     "$SRC/mandel.c"    -O0
build_variant O2     "$SRC/mandel.c"    -O2
build_variant OWIMUL "$SRC/mandel-ow.c" -O2
echo

ORACLE="$SRC/MANDEL-DRC.CMD"
if [ -f "$ORACLE" ]; then
    # NOTE: bench.py's byte-for-byte "behaviour" check will report a MISMATCH
    # that is purely line-endings -- owcc's clib putchar translates '\n' -> CR/LF
    # (correct CP/M console behaviour), while the DR C oracle's raw putchar.asm
    # (BDOS C_WRITE) emitted bare '\n'. The fractal itself is byte-identical
    # line-for-line, so the compute measurement is apples-to-apples. Non-fatal
    # so all variants report.
    for v in O0 O2 OWIMUL; do
        echo "### DR C (oracle) vs owcc $v ###"
        python3 "$HERE/bench.py" compare "$ORACLE" "$SRC/MANDEL-$v.CMD" \
            --mhz "$MHZ" --label-candidate "owcc $v" || true
        echo
    done
else
    echo "(DR C oracle owc-drc/MANDEL-DRC.CMD not present -- checking against baseline.json)"
    echo
    for v in O0 O2 OWIMUL; do
        echo "### baseline mandel (DR C) vs owcc $v ###"
        python3 "$HERE/bench.py" baseline check mandel "$SRC/MANDEL-$v.CMD" --mhz "$MHZ" \
            || true
        echo
    done
fi
