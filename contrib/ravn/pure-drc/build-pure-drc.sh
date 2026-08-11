#!/bin/sh
# build-pure-drc.sh -- build a program with the *genuine* Digital Research C
# v1.11 compiler and DR LINK-86, then run it in BOTH CP/M-86 emulators
# (the cpm86/emu2 host emulator and ../cpm86run_unicorn.py).
#
# This is pure DR C: the real DRI toolchain building against the real DR C
# run-time (clears.l86).  No Open Watcom is involved (that is ../owc-drc).
#
# Targets:
#   ./build-pure-drc.sh sample     tiny printf smoke test (sample.c)
#   ./build-pure-drc.sh dhry       unmodified* Dhrystone 2.1  (*see drcify.py)
#
# Requirements (the DRI tool binaries are copyright and NOT in this repo):
#   DRC_HOME  dir with drc.cmd, drc860.cmd, drc861.cmd, drc862.cmd,
#             drcrpp.cmd, r.cmd, link86.cmd, clears.l86 and the DR C *.h
#             headers.  Extract them from the DDHF "Digital Research C" floppy
#             (see ../owc-drc/fetch-drc.sh, which already fetches clears.l86 and
#             the headers; the *.cmd tools come from the same image).
#   XDEV      ../cpm86-crossdev checkout providing bin/cpm86 + bin/emu2.
#   DHRY_SRC  (dhry target) dir with stock dhry.h, dhry_1.c, dhry_2.c
#             (defaults to ../owc-drc/dhry21, populated by fetch-drc/build-owc-drc).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
TARGET=${1:-sample}
DRC_HOME=${DRC_HOME:-/tmp/puredrc}
DRC_INC=${DRC_INC:-"$HERE/../owc-drc/drc"}
XDEV=${XDEV:-"$HERE/../cpm86-crossdev"}
DHRY_SRC=${DHRY_SRC:-"$HERE/../owc-drc/dhry21"}
RUNNER="$HERE/../cpm86run_unicorn.py"
WORK=$(mktemp -d /tmp/puredrc-build.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

need() { [ -e "$1" ] || { echo "ERROR: missing $2: $1" >&2; exit 1; }; }
need "$XDEV/bin/cpm86" "cpm86 wrapper (set XDEV)"
for f in drc.cmd drc860.cmd drc861.cmd drc862.cmd drcrpp.cmd r.cmd \
         link86.cmd clears.l86; do
    need "$DRC_HOME/$f" "DR C tool (set DRC_HOME)"
done

# Copy the toolchain, headers and sources into a short work dir (DR tools want
# 8.3 names and DR LINK-86 dislikes long THEADR paths -- same reason as owc-drc).
cp "$DRC_HOME"/drc.cmd "$DRC_HOME"/drc86?.cmd "$DRC_HOME"/drcrpp.cmd \
   "$DRC_HOME"/r.cmd "$DRC_HOME"/link86.cmd "$DRC_HOME"/clears.l86 "$WORK"/
# DR C headers (stdio.h etc.); DRC_HOME may lack them, so also try DRC_INC.
cp "$DRC_HOME"/*.h "$WORK"/ 2>/dev/null || true
[ -f "$WORK/stdio.h" ] || cp "$DRC_INC"/*.h "$WORK"/ 2>/dev/null || true
need "$WORK/stdio.h" "DR C headers (set DRC_INC to a dir with stdio.h)"

case "$TARGET" in
  sample)
    cp "$HERE/sample.c" "$WORK/sample.c"
    UNITS="SAMPLE"
    OUT=sample.cmd ;;
  dhry)
    need "$DHRY_SRC/dhry_1.c" "stock Dhrystone (set DHRY_SRC)"
    python3 "$HERE/drcify.py" "$DHRY_SRC" "$WORK" "${RUNS:-200}"
    UNITS="DHRY_1 DHRY_2"
    OUT=dhry.cmd ;;
  *)
    echo "usage: $0 {sample|dhry}" >&2; exit 2 ;;
esac

# emu2 needs a controlling TTY, so drive the DR tools through a pty.  (macOS has
# no coreutils `timeout`; the pty helper enforces its own wall-clock budget.)
ptyrun() {
    PATH="$XDEV/bin:$PATH" python3 - "$WORK" "$@" <<'PY'
import os, sys, pty, select, time
work = sys.argv[1]; args = sys.argv[2:]
os.chdir(work)
out = bytearray(); pid, fd = pty.fork()
if pid == 0:
    os.execvp(args[0], args)
end = time.time() + 180
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d
    try:
        wpid, _ = os.waitpid(pid, os.WNOHANG)
        if wpid:
            time.sleep(0.2)
            while True:
                r, _, _ = select.select([fd], [], [], 0.2)
                if not r: break
                try: d = os.read(fd, 4096)
                except OSError: break
                if not d: break
                out += d
            break
    except ChildProcessError: break
sys.stdout.write(out.decode('latin1'))
PY
}

CPM86="$XDEV/bin/cpm86"

echo "==> compiling with genuine DR C v1.11 ($TARGET)"
for u in $UNITS; do
    echo "--- drc $u"
    ptyrun "$CPM86" drc.cmd "$u" | grep -iE 'error|version 1.11' || true
    [ -f "$WORK/$(echo "$u" | tr 'A-Z' 'a-z').obj" ] || \
        { echo "ERROR: $u.obj not produced"; exit 1; }
done

echo "==> linking with DR LINK-86"
LINKUNITS=$(echo "$UNITS" | tr ' ' ',')
NAME=$(echo "$OUT" | sed 's/\.cmd$//' | tr 'a-z' 'A-Z')
ptyrun "$CPM86" link86.cmd "$NAME=$LINKUNITS,CLEARS.L86[S]" | grep -iE 'error|CODE|DATA' || true
need "$WORK/$OUT" "linked .CMD"
cp "$WORK/$OUT" "$HERE/$OUT"
echo "==> built $HERE/$OUT ($(wc -c < "$HERE/$OUT") bytes)"

echo
echo "==================== run in cpm86 / emu2 emulator ===================="
ptyrun "$CPM86" "$OUT" | sed 's/\r$//'

echo
echo "==================== run in cpm86run_unicorn.py ======================"
( cd "$HERE" && python3 "$RUNNER" "$OUT" )
