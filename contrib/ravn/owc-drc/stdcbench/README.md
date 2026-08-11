# stdcbench 0.8 on Open Watcom C + Digital Research C

This directory ports **stdcbench 0.8** (Philipp Klaus Krause's portable C
benchmark) to the toolchain in `../` -- modern Open Watcom C generating code
that links against the genuine, pre-ANSI Digital Research C run-time library
(`clears.l86`) and runs on the Unicorn CP/M-86 harness.

Build and run it with:

```sh
../build-owc-drc.sh stdcbench
```

which fetches the upstream tarball, compiles the `c90base` and `c90lib`
integer modules (the float/double modules are excluded), links, and runs:

```
stdcbench 0.8
stdcbench c90base score: 2
stdcbench c90lib score: 10
stdcbench final score: 12
```

The scores are **fixed, reproducible figures**, not timings -- see the
virtual clock note below.

## Why glue is needed

DR C dates from ~1984 and predates ANSI C (C89/C90). It ships `printf`,
`sprintf`, `malloc`/`free`/`calloc`/`realloc`, `qsort`, `atoi`, `abs`, the
`str*` family, and the old BSD `index`/`rindex`, but it lacks several
routines that stdcbench (portable C90) expects:

* `memcpy`, `memmove`, `memset`, `memcmp`
* `strstr`, `strtol`
* linkable `ctype` functions (`isdigit`, `isspace`, `tolower`, ...)

`cpmlibc.c` implements exactly these missing routines in portable C90.
`inc/` holds neutral C90 headers (`stddef.h`, `string.h`, `stdlib.h`,
`stdio.h`, `ctype.h`) whose prototypes match DR C's small-model ABI
(`size_t` = `unsigned int`); they note which symbols come from DR C and
which from `cpmlibc.c`.

## The three toolchain hurdles

1. **OMF static symbols (`omf-delocal.py`).** Open Watcom emits `LEXTDEF`
   (`0xB4`) / `LPUBDEF` (`0xB6`) records for file-scope `static` symbols.
   1987 DR LINK-86 rejects them with `OBJECT FILE ERROR 5`. Those records
   are byte-for-byte identical to plain `EXTDEF` (`0x8C`) / `PUBDEF`
   (`0x90`) and share the external-index space, so `omf-delocal.py` simply
   rewrites the record-type byte (promoting the statics to globals) and
   fixes the record checksum. There are no cross-module static-name
   collisions in stdcbench, so this is safe. Every `.OBJ` is filtered before
   linking.

2. **Watcom 32-bit long helpers (`owmath.asm`).** The score arithmetic uses
   `unsigned long` multiply/divide, so the code generator references
   `__U4M`/`__I4M` (32-bit multiply) and `__U4D` (unsigned 32-bit divide),
   which live in Watcom's own library. `owmath.asm` re-implements just those
   three, standalone, in segment `CODE`/`CGROUP`.

3. **THEADR length.** DR LINK-86 rejects long module names
   (`OBJECT FILE ERROR 10`); Open Watcom stamps the source path into the OMF
   `THEADR`. The build sidesteps this by compiling from a short work
   directory with short `8.3` names (`N00.C` .. `N15.C`).

## The DR C heap-base bug (the tricky one)

`c90base` validated immediately, but `c90lib` failed
(`c90lib_lnlc(): Result validation failed`). The cause was **not** in the
benchmark or in `sprintf`: DR C's `malloc` was handing out memory **on top
of the program's static data**.

DR C computes its heap pointer `HP.` (in the run-time's `m.init.heap`) as
`align16(?MEMRY)`, where `?MEMRY` is a run-time BSS word. In this hybrid
Open-Watcom / DR-C link nothing ever initialises `?MEMRY`, so it stays `0`
and the heap starts at DGROUP offset ~0 -- overlapping every static and
global. Small allocations happen to land in unused low bytes (which is why
Dhrystone's two ~48-byte records worked), but `c90lib_lnlc`'s 772-byte
buffer overlapped the benchmark's own static arrays, whose updates then
corrupted the buffer mid-string.

`portme.c` repairs this before the first allocation by pointing the heap at
a private static arena with DR C's `brk()`. `malloc` then grows upward
inside that arena instead of over the program's data. See the comment in
`portme.c`.

## The virtual clock

An instruction-level emulator has no wall clock, so `portme.c`'s
`stdcbench_clock()` returns a deterministic virtual counter that advances a
fixed step per call. `STDCBENCH_TICK_STEP` is set so each module runs
exactly one iteration of its `do { work } while(clock()-start < SECONDS)`
loop, which keeps the emulated run short. The reported scores are therefore
constant, reproducible figures reflecting a fixed iteration count rather
than real time -- the same trade-off as the dummy timer used for Dhrystone
in `../`.

## Files

| File | Purpose |
| --- | --- |
| `portme.c` / `portme.h` | entry point (`cmain`), virtual clock, heap-base fix, module selection |
| `cpmlibc.c` | the ANSI routines DR C lacks (`mem*`, `strstr`, `strtol`, `ctype`) |
| `inc/*.h` | neutral C90 headers matching DR C's small-model ABI |
| `omf-delocal.py` | rewrites Watcom `LEXTDEF`/`LPUBDEF` so DR LINK-86 accepts the objects |
| `owmath.asm` | standalone `__U4M` / `__I4M` / `__U4D` long helpers |
| `src/` | the downloaded upstream tarball (git-ignored) |

## Provenance

stdcbench 0.8 is fetched from SourceForge
(`https://downloads.sourceforge.net/project/stdcbench/stdcbench-0.8.tar.gz`)
and is unmodified; all adaptation lives in the glue files above. stdcbench
is distributed under the GNU General Public License v2 or later.
