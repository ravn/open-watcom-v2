#!/bin/bash
# run-all-models.sh -- build the CP/M-86 C library for EVERY memory model
# (small/medium/compact) and run the runtime-library functional tests against
# each, from the ONE installed model library (lib286/cpm86/clib{s,m,c}.lib).
#
# This is the all-models regression gate: it proves the SAME clib source, only
# recompiled with -m{s,m,c}, links + runs the heap / stdio / soft-float suite in
# each model. Tests link against the shipped model lib (no bespoke object list),
# so a link failure here is a genuine "routine missing from the archive" gap --
# exactly what this gate exists to catch.
#
# Runner: cpm86run_unicorn.py (a faithful CCP/M-86 load.sup port) applies the
# P_LOAD relocation records, so it runs small, medium AND compact .CMDs. Disk
# tests need the file BDOS the Unicorn harness does not emulate -> those run
# under emu2, which now ALSO applies P_LOAD relocation (ravn/emu2-cpm86#1), so
# disk is covered in all three models too.
#
# Usage:   bash run-all-models.sh              # all models, all applicable tests
#          MODELS="s c" bash run-all-models.sh # subset of models
#          KEEP=1 bash run-all-models.sh        # keep build dirs for inspection
set -u
cd "$(dirname "$0")"
OW="${OW:-$(cd ../../.. && pwd)}"; B="$OW/bld"
WCC="$B/cc/i86/osxa64/binbuild/wcc.exe"
WLINK="$B/wl/osxa64/wlink.exe"
LIBDIR="$OW/lib286/cpm86"
RUNNER="$OW/contrib/ravn/cpm86run_unicorn.py"
EMU2="${EMU2:-/Users/ravn/z80/emu2-cpm86/emu2}"
PY="${PYTHON:-python3}"
INC="-i=$B/lib_misc/h -i=$B/clib/streamio/h -i=$B/clib/string/h -i=$B/clib/h -i=$B/clib/heap/h -i=$B/clib/intel/h -i=$B/watcom/h -i=$B/hdr/dos/h"
MODELS="${MODELS:-s m c}"
WORK="$(mktemp -d)"; [ "${KEEP:-0}" = 1 ] || trap 'rm -rf "$WORK"' EXIT

# model -> (zm-flag, lib, crt0, extra-link-options)
model_zm()   { case $1 in m) echo "-zm";; *) echo "";; esac; }
model_lib()  { case $1 in s) echo clibs.lib;; m) echo clibm.lib;; c) echo clibc.lib;; esac; }
model_crt()  { case $1 in s) echo cstartcpm.obj;; m) echo cstartmm.obj;; c) echo cstartcm.obj;; esac; }
model_link() { case $1 in c) echo "option farheap=0x30000";; *) echo "";; esac; }
model_libm() { case $1 in s) echo libms.lib;; m) echo libmm.lib;; c) echo libmc.lib;; esac; }

pass=0; fail=0; skip=0
declare -a RESULTS

# run_test <model> <name> <src> <runner:uni|emu2> <oracle-mode:exact|substr> <oracle> [cflags] [+libm]
# 7th arg adds compile flags (e.g. -fpc: soft-float, no 8087); pass "libm" as the
# 8th arg to also link the model's math library (transcendentals).
run_test() {
    local model="$1" name="$2" src="$3" runner="$4" omode="$5" oracle="$6" xcflags="${7:-}" wantm="${8:-}"
    local zm lib crt lopt libmlib d cmd out
    zm="$(model_zm "$model")"; lib="$(model_lib "$model")"; crt="$(model_crt "$model")"; lopt="$(model_link "$model")"
    libmlib=""; [ "$wantm" = libm ] && libmlib="library $LIBDIR/$(model_libm "$model")"
    d="$WORK/$model-$name"; mkdir -p "$d"
    if ! "$WCC" -bt=dos -0 -m"$model" $zm $xcflags -zastd=c99 $INC -i="$B/mathlib/h" "test/$src" -fo="$d/t.obj" >"$d/cc.log" 2>&1; then
        RESULTS+=("$model  $name  COMPILE-FAIL"); fail=$((fail+1)); return
    fi
    cmd="$d/${name}.cmd"
    # shellcheck disable=SC2086
    "$WLINK" format cpm86 op dosseg op quiet op start=_cstart_ $lopt \
        name "$cmd" file "$LIBDIR/$crt" file "$d/t.obj" library "$LIBDIR/$lib" $libmlib >"$d/link.log" 2>&1
    if [ ! -f "$cmd" ]; then
        local undef; undef="$(grep -oE "undefined (reference|symbol) [A-Za-z0-9_]+" "$d/link.log" | awk '{print $NF}' | sort -u | tr '\n' ' ')"
        RESULTS+=("$model  $name  LINK-FAIL  undef: ${undef:-?}"); fail=$((fail+1)); return
    fi
    if [ "$runner" = emu2 ]; then
        out="$("$EMU2" "$cmd" 2>/dev/null | tr -d '\r\000')"
    else
        out="$("$PY" "$RUNNER" "$cmd" 2>"$d/run.log" | tr -d '\r\000')"
    fi
    local ok=0
    if [ "$omode" = exact ]; then [ "$out" = "$oracle" ] && ok=1; else echo "$out" | grep -q "$oracle" && ok=1; fi
    if [ "$ok" = 1 ]; then
        RESULTS+=("$model  $name  PASS"); pass=$((pass+1))
    else
        RESULTS+=("$model  $name  RUN-FAIL  got: $(echo "$out" | head -1)"); fail=$((fail+1))
        [ "${KEEP:-0}" = 1 ] && cp "$cmd" "./FAIL-$model-$name.cmd" 2>/dev/null
    fi
}

HEAP_ORACLE=$'sorted : 0 1 2 3 4 5 6 7 8 9\ncalloc : 0\nrealloc: 0 40\nreuse  : ok'
STDIO_ORACLE=$'printf 42 ok\nputs line\nfputs line\nfprintf 97406784'
FLOAT_ORACLE="pi6=3141592 mul=40115 add=468 sub=242"
MATH_ORACLE="sin=841470 cos=540302 atan=785398 exp=2718281 log=2302585 sqrt=1414213"

for m in $MODELS; do
    [ -f "$LIBDIR/$(model_lib "$m")" ] || { echo "!! missing $(model_lib "$m") -- run 'MODEL=$m bash build-lib.sh' first"; exit 1; }
    run_test "$m" heap   heaptest.c  uni  exact  "$HEAP_ORACLE"
    run_test "$m" stdio  stdiotest.c uni  exact  "$STDIO_ORACLE"
    run_test "$m" float  floattest.c uni  exact  "$FLOAT_ORACLE" "-fpc"
    run_test "$m" math   mathtest.c  uni  exact  "$MATH_ORACLE"  "-fpc" libm
    # disk needs the file BDOS only emu2 emulates; emu2 now also applies P_LOAD
    # relocation (ravn/emu2-cpm86#1), so it runs medium/compact .CMDs too -- disk
    # is verified in ALL models under emu2. (Requires the reloc-capable emu2; if
    # an older emu2 is on PATH, medium/compact disk will mis-load.)
    run_test "$m" disk disktest.c emu2 substr "DISKIO: PASS"
done

echo
echo "================ ALL-MODELS RUNTIME LIBRARY MATRIX ================"
printf '%s\n' "${RESULTS[@]}" | sort | awk '{printf "  %-3s %-7s %s\n", $1, $2, substr($0, index($0,$3))}'
echo "------------------------------------------------------------------"
echo "  PASS=$pass  FAIL=$fail  SKIP=$skip"
[ "$fail" = 0 ] && echo "  RESULT: all models GREEN" || echo "  RESULT: failures present"
exit $([ "$fail" = 0 ] && echo 0 || echo 1)
