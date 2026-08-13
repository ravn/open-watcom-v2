#!/bin/sh
# fetch-unproto.sh -- obtain and build the genuine `unproto` ANSI->K&R filter.
#
# unproto (Wietse Venema, 1993) rewrites ANSI C -- function prototypes,
# `(void)` parameter lists, and new-style function definitions -- back into
# K&R C that a pre-ANSI compiler like DR C 1.11 accepts.  It is the first stage
# of the stdcbench transform pipeline (see transform.sh / FINDINGS.md).
#
# The historic FTP mirrors (ftp.porcupine.org, coast.cs.purdue.edu) are dead.
# The live, buildable copy is Udo Munk's fork (same author as z80pack, which is
# already in this workspace):
#
#     https://github.com/udo-munk/unproto   (unproto 1.6)
#
# We build it as a *pure stdin->stdout filter* with `PIPE=` (the default build
# hardcodes an absent `/lib/cpp`).  Output binary: ./unproto  (gitignored).
#
# License: free to use, must credit Wietse Venema.  We do not vendor the source
# tree -- this script fetches it on demand, like ../fetch-drc.sh does for DR C.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/unproto-src"
OUT="$HERE/unproto"

if [ -x "$OUT" ]; then
    echo "unproto already built: $OUT"
    exit 0
fi

if [ ! -d "$SRC" ]; then
    git clone --depth 1 https://github.com/udo-munk/unproto "$SRC"
fi

# Build the filter.  PIPE= disables the embedded /lib/cpp path (we feed it
# already-preprocessed C on stdin).  The -w / -Wno-* silence the warnings the
# 1993 K&R sources raise under a modern clang; unproto itself is C89.
make -C "$SRC" PIPE= CC="clang -std=gnu89 -w \
  -Wno-implicit-int -Wno-implicit-function-declaration -Wno-int-conversion \
  -Wno-return-mismatch -Wno-deprecated-non-prototype"

cp "$SRC/unproto" "$OUT"
echo "built: $OUT"
