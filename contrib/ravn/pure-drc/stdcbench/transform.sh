#!/bin/sh
# transform.sh -- down-convert one ANSI/C90 stdcbench translation unit into
# C that the genuine Digital Research C v1.11 compiler (CP/M-86, 1984) accepts.
#
# Usage:  ./transform.sh SRC.c  >  OUT.C
#   env:  STDCBENCH_SRC  dir with the upstream stdcbench-0.8 *.c/*.h
#                        (defaults to ../../owc-drc/stdcbench/src/stdcbench-0.8)
#         GLUE_INC       dir with the neutral ANSI libc headers + glue headers
#                        (defaults to ../../owc-drc/stdcbench and its inc/)
#
# Pipeline (each stage verified on real DR C 1.11 + the cpm86/emu2 emulator --
# see FINDINGS.md for the evidence behind every rule):
#
#   1. clang -E   preprocess.  We inject our own <stdint.h>/<stdbool.h>
#                 (inc/) because DR C predates them, and -D away the type
#                 qualifiers DR C rejects (const/volatile/restrict/inline) and
#                 the C99 bool keyword (bool/_Bool -> char; true/false -> 1/0).
#   2. perl       normalize `ident(*f)` -> `ident (*f)` and `(*f)(void)` ->
#                 `(*f)()` so unproto's function-pointer-parameter handling
#                 does not drop the parameter name (verified unproto weakness).
#   3. drc_enum   convert `enum {..}` -> `int` + inlined integer constants
#                 (DR C 1.11 has no enum keyword -- verified Error 89).
#   4. unproto    ANSI prototypes / `(void)` / new-style definitions -> K&R.
#   5. perl       type substitutions DR C needs:
#                   unsigned long  -> long   (DR C has no unsigned long;
#                                             DRI's own portab.h maps ULONG=long)
#                   unsigned char  -> char   (DR C char is UNSIGNED 0..255 --
#                                             verified -- so this is lossless)
#                   signed int/char/long -> int/char/long ; bare signed -> int
#                   1000ul / 1000LU -> 1000L ; 42u -> 42   (no unsigned suffix)
#                 plus strip trailing commas before `}` (no trailing-comma
#                 initializers in DR C) and rewrite sizeof("lit") -> length.
#   6. perl       drop the `#line` directives unproto emits (input is already
#                 fully preprocessed, so they are noise to DR C's own cpp).
#   7. drc_reflow reflow long `{…}` initializer lines onto <=16 elements/line.
#                 DR C 1.11 silently truncates a source line past an internal
#                 parse-buffer capacity; when the lost tail holds the closing
#                 `}` it emits a SPURIOUS "Error 61 too many initializers".
#                 Verified: c90base-data's 417-value table on one ~1900-char
#                 line fails, but reflowed it compiles + links.  Formatting
#                 only -- values/element count unchanged.
#   8. perl       slurp-mode trailing-comma strip `s/,(\s*)}/$1}/g` -- removes a
#                 comma before `}` even when they are on separate lines (the
#                 line-mode strip in stage 5 misses peep's multiline `ftab[]`).
#
# NOTE: this pipeline compiles 11 of the 14 stdcbench modules cleanly.  Three
# modules still fail (see FINDINGS.md for the exact DR C errors): compression
# (unproto drops a no-space func-ptr param name) and isort + lnlc (DR C has no
# pointer-to-array `(*p)[N]`).  Those need per-file source patches no textual
# transform can cover; they are NOT yet written.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
IN=${1:?usage: transform.sh SRC.c}
SRC=${STDCBENCH_SRC:-"$HERE/../../owc-drc/stdcbench/src/stdcbench-0.8"}
GLUE=${GLUE_INC:-"$HERE/../../owc-drc/stdcbench"}
UP=${UNPROTO:-"$HERE/unproto"}

[ -x "$UP" ] || { echo "ERROR: unproto missing; run ./fetch-unproto.sh" >&2; exit 1; }

clang -E -P -nostdinc \
      -I"$HERE/inc" -I"$GLUE/inc" -I"$SRC" -I"$GLUE" \
      -Dconst= -Dvolatile= -Drestrict= -Dinline= \
      -Dbool=char -D_Bool=char -Dtrue=1 -Dfalse=0 \
      -DC90BASE -DC90LIB "$IN" 2>/dev/null \
| perl -pe 's/([A-Za-z_0-9\])])\(\s*\*/$1 (*/g;
            s/(\(\s*\*\s*\w+\s*\))\s*\(\s*void\s*\)/$1()/g;' \
| python3 "$HERE/drc_enum.py" \
| "$UP" 2>/dev/null \
| perl -pe 's/\bunsigned\s+long\b/long/g;
            s/\bunsigned\s+char\b/char/g;
            s/\bsigned\s+int\b/int/g;
            s/\bsigned\s+char\b/char/g;
            s/\bsigned\s+long\b/long/g;
            s/\bsigned\b/int/g;
            s/([0-9a-fA-F])[uU][lL]\b/${1}L/g;
            s/([0-9a-fA-F])[lL][uU]\b/${1}L/g;
            s/([0-9])[uU]\b/$1/g;
            s/,(\s*\})/$1/g;' \
| perl -pe 's/sizeof\s*\(\s*"((?:[^"\\]|\\.)*)"\s*\)/my $s=$1; $s=~s{\\.}{.}g; length($s)+1/ge;' \
| perl -ne 'print unless /^\s*#/' \
| python3 "$HERE/drc_reflow.py" \
| perl -0pe 's/,(\s*)\}/$1}/g'
