#!/bin/bash
# ===========================================================================
# build-lib.sh -- assemble a REAL CP/M-86 C-library archive, clibcpm.lib.
#
# Rationale (rc7xx-work#6): the per-milestone scripts (build-diskio.sh, ...)
# compile only the exact object subset ONE demo/test happens to reference and
# link them loose.  That does not scale: every new program (e.g. Info-ZIP
# UnZip) then triggers a manual undefined-symbol hunt.  The proper solution --
# what Open Watcom itself ships for DOS as clibs.lib -- is a single ARCHIVE of
# the whole OS-agnostic clib layer plus our thin CP/M-86 (BDOS) seam.  wlib
# builds it once; wlink then pulls ONLY the modules a given program needs.
#
# Layers (see README):
#   Layer 1  Watcom clib source, REUSED UNCHANGED: string, ctype table, the
#            __prtf formatter + full stdio FILE* read/write path, near-heap,
#            mem*, convert (itoa/ltoa), gmtime.
#   Layer 2  our CP/M-86 seam WE own: diskio.c (FCB BDOS file I/O + console),
#            lowlevel.c (arena heap __brk/sbrk), cominit.c, errnoptr.c,
#            abortcpm.c (BDOS warm-boot abort), stubs.c (closure symbols),
#            portmisc.c (getenv/setmode/signal/localtime/tzset seams).
#   Layer 3  BDOS (INT E0h) -- reached only through Layer 2.
#
# The startup object crt0sm.asm (public _cstart_) is emitted SEPARATELY (a
# start module must be an explicit linker `file`, not pulled from a library),
# alongside the archive, so a program links:
#     wlink format cpm86 op dosseg file crt0.obj file <prog>.obj \
#           library clibcpm.lib name PROG.CMD
#
# NOTE: deliberately EXCLUDES the scanf family (scnf/fscanf) and the 8087
# float emulator (FIDRQQ/FIERQQ/FIWRQQ, __U8M).  Nothing in the string/FILE*
# core needs them; they are added only by programs that actually call *scanf
# or printf %e/%f/%g.  Keeping them out halves the code footprint -- important
# under the 64 KB single-code-segment small-model ceiling.
# ===========================================================================
set -e
cd "$(dirname "$0")"
# NOTE: do NOT name the override vars WCC/WASM/WLIB/WLINK -- Open Watcom's
# own tools read an env var NAMED AFTER THEMSELVES for implicit default
# switches (confirmed 2026-08-18: an exported WCC=<path to wcc.exe> makes
# wcc.exe itself parse that path string as bogus extra command-line
# content -> "E1139: Command line contains more than one file to compile").
# unset here defensively in case the CALLER's shell exported one of these.
unset WCC WASM WLIB WLINK
OW="${OW:-$(cd "$(dirname "$0")/../../.." && pwd)}"; B="$OW/bld"
WCC="${OWCC_BIN:-$B/cc/i86/osxa64/binbuild/wcc.exe}"
WASM="${OWASM_BIN:-$B/wasm/osxa64/wasm.exe}"
WLIB="${OWLIB_BIN:-$B/nwlib/osxa64/wlib.exe}"

OUTDIR="${OUTDIR:-build-lib}"; mkdir -p "$OUTDIR"
SRC="$(pwd)"
cd "$OUTDIR"

INC="-i=$B/lib_misc/h -i=$B/clib/streamio/h -i=$B/clib/string/h -i=$B/clib/time/h -i=$B/clib/h -i=$B/clib/heap/h -i=$B/clib/intel/h -i=$B/comp_cfg/h -i=$B/watcom/h -i=$B/hdr/dos/h"
CLIB="-bt=dos -0 -ms -zastd=c99 -zl -x"        # compile stock Watcom clib source
USER="-bt=dos -0 -ms -zl -zastd=c99"           # compile our port seam

cw() { "$WCC" $CLIB $INC "$B/clib/$1" -fo="$2"; }   # compile a Watcom clib source

echo "==> Layer 1: string"
cw string/c/strlen.c   strlen.obj
cw string/c/strcmp.c   strcmp.obj
cw string/c/strcpy.c   strcpy.obj
cw string/c/strncpy.c  strncpy.obj
cw string/c/strcat.c   strcat.obj
cw string/c/strncmp.c  strncmp.obj
cw string/c/strnicmp.c strnicmp.obj
cw string/c/strchr.c   strchr.obj
cw string/c/strrchr.c  strrchr.obj
cw string/c/strupr.c   strupr.obj
cw string/c/strerror.c strerror.obj
cw string/c/sprintf.c  sprintf.obj
cw string/c/vsprintf.c vsprintf.obj

echo "==> Layer 1: ctype table"
cw char/c/istable.c    istable.obj      # __IsTable / __Bits classification table

echo "==> Layer 1: convert + mbyte helpers used by __prtf"
cw convert/c/itoa.c      itoa.obj
cw convert/c/ltoa.c      ltoa.obj
cw convert/c/lltoa.c     lltoa.obj
cw convert/c/alphabet.c  alphabet.obj
cw mbyte/c/wctomb.c      wctomb.obj

echo "==> Layer 1: string-to-number + strtok + toupper + setvbuf (editor deps)"
cw convert/c/atoi.c      atoi.obj
cw convert/c/strtol.c    strtol.obj
cw string/c/strtok.c     strtok.obj
cw string/c/setbits.c    setbits.obj
cw string/c/bits.c       bits.obj
cw char/c/toupper.c      toupper.obj
cw streamio/c/setvbuf.c  setvbuf.obj

echo "==> Layer 1: __prtf formatter core"
cw streamio/c/prtf.c     prtf.obj
cw streamio/c/noefgfmt.c noefgfmt.obj

echo "==> Layer 1: stdio FILE* write path"
cw streamio/c/printf.c   printf.obj
cw streamio/c/fprintf.c  fprintf.obj
cw streamio/c/fprtf.c    fprtf.obj
cw streamio/c/fputc.c    fputc.obj
cw streamio/c/putchar.c  putchar.obj    # putchar -> fputc(c,stdout); fputc already in archive
cw streamio/c/fputs.c    fputs.obj
cw streamio/c/puts.c     puts.obj
cw streamio/c/fwrite.c   fwrite.obj
cw streamio/c/flush.c    flush.obj
cw streamio/c/fflush.c   fflush.obj
cw streamio/c/perror.c   perror.obj

echo "==> Layer 1: stdio FILE* read/open path"
cw streamio/c/fopen.c    fopen.obj
cw streamio/c/fclose.c   fclose.obj
cw streamio/c/allocfp.c  allocfp.obj
cw streamio/c/fgetc.c    fgetc.obj
cw streamio/c/getchar.c  getchar.obj    # getchar -> fgetc(stdin); fgetc already in archive
cw streamio/c/fgets.c    fgets.obj
cw streamio/c/gets.c     gets.obj       # gets -> fgets over stdin; read path already present
cw streamio/c/fread.c    fread.obj
cw streamio/c/fseek.c    fseek.obj
cw streamio/c/ftell.c    ftell.obj
cw streamio/c/rewind.c   rewind.obj
cw streamio/c/feof.c     feof.obj
cw streamio/c/ferror.c   ferror.obj
cw streamio/c/ungetc.c   ungetc.obj
cw streamio/c/ioalloc.c  ioalloc.obj
cw streamio/c/chktty.c   chktty.obj
cw streamio/c/iob.c      iob.obj
cw streamio/c/initfile.c initfile.obj
cw streamio/c/comtflag.c comtflag.obj
cw streamio/c/freefp.c   freefp.obj
cw handleio/c/textmode.c textmode.obj

echo "==> Layer 1: near-heap manager"
cw heap/c/nmalloc.c   nmalloc.obj
cw heap/c/nfree.c     nfree.obj
cw heap/c/calloc.c    calloc.obj
cw heap/c/nrealloc.c  nrealloc.obj
cw heap/c/grownear.c  grownear.obj
cw heap/c/amblksiz.c  amblksiz.obj
cw heap/c/heapen.c    heapen.obj
cw heap/c/nheapmin.c  nheapmin.obj
cw heap/c/mem.c       mem.obj
cw heap/c/bfree.c     bfree.obj
cw heap/c/_expand.c   _expand.obj
cw heap/c/nmemneed.c  nmemneed.obj
cw heap/c/nmsize.c    nmsize.obj
cw heap/c/nexpand.c   nexpand.obj
cw heap/c/nheapunl.c  nheapunl.obj

echo "==> Layer 1: far heap manager (Stage A compact model)"
cw heap/c/fmalloc.c   fmalloc.obj
cw heap/c/ffree.c     ffree.obj
cw heap/c/fcalloc.c   fcalloc.obj
cw heap/c/frealloc.c  frealloc.obj
cw heap/c/fmsize.c    fmsize.obj
cw heap/c/fheapset.c  fheapset.obj
cw heap/c/fheapchk.c  fheapchk.obj
cw heap/c/fheapmin.c  fheapmin.obj
cw heap/c/fheapwal.c  fheapwal.obj

echo "==> Layer 1: mem helpers"
cw memory/c/memcpy.c  memcpy.obj
cw memory/c/memset.c  memset.obj
cw memory/c/memmove.c memmove.obj
cw memory/c/memcmp.c  memcmp.obj

echo "==> Layer 1: time-conversion subsystem (pure computation, no OS trap)"
cw time/c/gmtime.c    gmtime.obj      # UTC broken-down time
cw time/c/localtim.c  localtim.obj    # local time (== UTC here; _timezone=0)
cw time/c/mktime.c    mktime.obj      # inverse (struct tm -> time_t)
cw time/c/locmktim.c  locmktim.obj    # __localtime/__mktime core
cw time/c/timeutil.c  timeutil.obj    # __diyr/__dilyr day tables + helpers
cw time/c/leapyear.c  leapyear.obj    # __isleap
cw time/c/tzset.c     tzset.obj       # tzset/_timezone (reads TZ via getenv->NULL)
cw time/c/time.c      time.obj        # time() -> __getctime()+mktime() (unchanged)

echo "==> Layer 1: environment (real getenv over our empty environ)"

echo "==> Layer 1: long mul/div helpers (%ld, lseek arithmetic)"
"$WASM" -ms -0 -i="$B/watcom/h" "$B/clib/cgsupp/a/i4m.asm" -fo=i4m.obj
"$WASM" -ms -0 -i="$B/watcom/h" "$B/clib/cgsupp/a/i4d.asm" -fo=i4d.obj

echo "==> Layer 2: CP/M-86 seam (BDOS) + closure stubs + port seams"
"$WCC" $USER $INC "$SRC/port/cominit.c"  -fo=cominit.obj
"$WCC" $USER $INC "$SRC/port/diskio.c"   -fo=diskio.obj      # FCB BDOS file I/O
"$WCC" $USER $INC "$SRC/port/lowlevel.c" -fo=lowlevel.obj
"$WCC" $USER $INC "$SRC/port/farheap.c"  -fo=farheap.obj     # Stage A far heap __AllocSeg/__GrowSeg
"$WCC" $USER $INC "$SRC/port/errnoptr.c" -fo=errnoptr.obj
"$WCC" $USER $INC "$SRC/port/abortcpm.c" -fo=abortcpm.obj
"$WCC" $USER $INC "$SRC/port/portmisc.c" -fo=portmisc.obj    # setmode/signal/environ
"$WCC" $USER $INC "$SRC/port/gtctmcpm.c" -fo=gtctmcpm.obj    # __getctime() BDOS T_GET seam
"$WCC" $USER $INC "$SRC/port/dirent.c"   -fo=dirent.obj      # opendir/readdir BDOS F_SFIRST/F_SNEXT
# diskio.c owns the real __lseek/tolower/etc.; drop those overlapping stubs.
"$WCC" $USER $INC -DDISKIO_LSEEK "$SRC/port/stubs.c" -fo=stubs.obj

echo "==> startup (emitted separately, linked as an explicit file)"
"$WASM" -ms -0 "$SRC/port/crt0sm.asm" -fo=crt0.obj

echo "==> archive clibcpm.lib"
rm -f clibcpm.lib
# every object EXCEPT crt0.obj (a start module must be an explicit linker file)
"$WLIB" -q -b clibcpm.lib \
    +strlen.obj +strcmp.obj +strcpy.obj +strncpy.obj +strcat.obj +strncmp.obj \
    +strnicmp.obj +strchr.obj +strrchr.obj +strupr.obj +strerror.obj \
    +sprintf.obj +vsprintf.obj +istable.obj \
    +itoa.obj +ltoa.obj +lltoa.obj +alphabet.obj +wctomb.obj \
    +atoi.obj +strtol.obj +strtok.obj +setbits.obj +bits.obj +toupper.obj +setvbuf.obj \
    +prtf.obj +noefgfmt.obj \
    +printf.obj +fprintf.obj +fprtf.obj +fputc.obj +fputs.obj +puts.obj \
    +putchar.obj +getchar.obj +gets.obj \
    +fwrite.obj +flush.obj +fflush.obj +perror.obj \
    +fopen.obj +fclose.obj +allocfp.obj +fgetc.obj +fgets.obj +fread.obj \
    +fseek.obj +ftell.obj +rewind.obj +feof.obj +ferror.obj +ungetc.obj \
    +ioalloc.obj +chktty.obj +iob.obj +initfile.obj +comtflag.obj +freefp.obj \
    +textmode.obj \
    +nmalloc.obj +nfree.obj +calloc.obj +nrealloc.obj +grownear.obj \
    +amblksiz.obj +heapen.obj +nheapmin.obj +mem.obj +bfree.obj +_expand.obj \
    +nmemneed.obj +nmsize.obj +nexpand.obj +nheapunl.obj \
    +memcpy.obj +memset.obj +memmove.obj +memcmp.obj +gmtime.obj \
    +i4m.obj +i4d.obj \
    +cominit.obj +diskio.obj +lowlevel.obj +errnoptr.obj +abortcpm.obj \
    +portmisc.obj +gtctmcpm.obj +dirent.obj +stubs.obj \
    +localtim.obj +mktime.obj +locmktim.obj +timeutil.obj +leapyear.obj \
    +tzset.obj +time.obj

echo
echo "==> built $OUTDIR/clibcpm.lib + $OUTDIR/crt0.obj"
ls -l clibcpm.lib crt0.obj
echo "modules in archive:"
"$WLIB" clibcpm.lib 2>/dev/null | grep -c '\.obj' || true

# Install as the CANONICAL cpm86 standard library.
#
# owcc -bcpm86 links via `system cpm86` (bld/wl/lnk/osxa64/wlink.lnk): it does
#   libfile cstartcpm.obj          <- the C startup, auto-linked
#   libpath '%WATCOM%/lib286/cpm86' <- where the auto-fetched clib is searched
# and the compiled objects carry a default-library record naming `clibs`, so
# wlink auto-fetches clibs.lib from that dir. Dropping the FULL clib in as
# clibs.lib (and crt0.obj as cstartcpm.obj) makes a bare
#   owcc -bcpm86 prog.c -o PROG.CMD
# link the whole library + real startup with NO explicit `library`/`file` on
# the link line — superseding the old 4-module proof-of-concept stub
# (contrib/ravn/cpm86-clib/build.sh). lib286/cpm86 is a .gitignored install dir.
DEST="$OW/lib286/cpm86"
mkdir -p "$DEST"
cp clibcpm.lib "$DEST/clibs.lib"
cp crt0.obj    "$DEST/cstartcpm.obj"
echo "==> installed canonical: $DEST/{clibs.lib,cstartcpm.obj}"
echo "DONE."
