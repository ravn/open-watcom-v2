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
stdcbench c90base score: 7
stdcbench c90lib score: 5
stdcbench final score: 12
```

The scores are **reproducible, real (emulated) timings** -- see the clock
note below.

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

2. **Watcom 32-bit long helpers (cgsupp `i4m`/`i4d`).** The score arithmetic
   uses `unsigned long` multiply/divide, so the code generator references
   `__U4M`/`__I4M` (32-bit multiply) and `__U4D`/`__I4D` (32-bit divide),
   which live in Watcom's own library. Rather than hand-write them, the build
   assembles Open Watcom's OWN cgsupp sources
   (`bld/clib/cgsupp/a/i4m.asm`, `i4d.asm`) with `bwasm -0 -ms`, then folds the
   helper's `_TEXT` into `CODE` (`omf-delocal.py --merge-text-into-code`) so the
   small-model near CALL stays in-segment. All runtime helpers come from the
   compiler, never from us.

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

### Heap verification

The repaired heap was stress-tested under the emulator to confirm the DR C
allocator behaves correctly once its base is fixed:

* **Allocator behaviour (all pass):** distinct, non-overlapping allocations;
  no cross-corruption when every block is written and read back; `calloc`
  zeroes; `realloc` grows while preserving contents; `free` returns blocks
  to a free list that later `malloc`/`realloc` calls reuse (both interior
  holes and the whole freed span).
* **Monotonic break:** `free` does *not* lower the break pointer (it only
  adds to the free list), so `sbrk(0)` is monotonic and its value at the end
  of a run equals the true high-water mark.
* **stdcbench peak = 1536 bytes**, measured via `sbrk(0)` -- comfortably
  inside the 20 KiB (`20480`-byte) arena, a ~13x margin. Because every
  allocation therefore stays strictly within the arena array, it cannot
  touch any other static or the stack, so the run is provably safe.

One characteristic worth noting: the arena size is *not* a hard cap. Like
any `sbrk`-style heap, DR C's `malloc` keeps extending toward the stack and
only returns `NULL` when the break nears `SP`, so a program that allocated
more than the arena would grow past it. stdcbench never approaches this
(1536 << 20480); a workload with a larger footprint should raise
`stdcbench_heap`'s size accordingly.

## The clock

`portme.c`'s `stdcbench_clock()` reads the RC759 XIOS **"16 ms counter"**
(**Int 28h function 19**, per the PICCOLINE Programmer's Guide App. A) -- the
machine's documented fine relative-time source -- so the benchmark measures
genuine elapsed (emulated) time at **16 ms resolution**. The call returns a
32-bit second count plus the elapsed 16 ms periods of the current second; we
express it in milliseconds, so `STDCBENCH_CLOCKS_PER_SEC` is `1000`. The
counter is deterministic (a virtual clock proportional to the code the emulated
8086 executes), so scores are **reproducible**.

The 16 ms tick replaces the earlier 1-second T_GET clock, whose coarse
resolution made the score-normalisation fragile (a single overshooting
iteration could underflow it to `0`). The emulated CPU rate must still be high
enough that a heavy iteration fits its module's timing window (`SECONDS` = 8 for
c90base, 40 for c90lib), so the build script runs `SCB.CMD` with
`CPM86_CLOCK_HZ=700000`; the 16 ms tick then resolves the `end-start` interval
finely. The score scales with code efficiency.

## Files

| File | Purpose |
| --- | --- |
| `portme.c` / `portme.h` | entry point (`cmain`), RC759 XIOS 16 ms clock (Int 28h fn 19), heap-base fix, module selection |
| `cpmlibc.c` | the ANSI routines DR C lacks (`mem*`, `strstr`, `strtol`, `ctype`) |
| `inc/*.h` | neutral C90 headers matching DR C's small-model ABI |
| `omf-delocal.py` | rewrites Watcom `LEXTDEF`/`LPUBDEF` so DR LINK-86 accepts the objects; `--merge-text-into-code` folds the cgsupp helper `_TEXT` into `CODE` |
| _(long helpers)_ | Open Watcom's OWN `bld/clib/cgsupp/a/i4m.asm` + `i4d.asm` (`__U4M`/`__I4M`/`__U4D`/`__I4D`), assembled at build time — no hand-written helper |
| `src/` | the downloaded upstream tarball (git-ignored) |

## Provenance

stdcbench 0.8 is fetched from SourceForge
(`https://downloads.sourceforge.net/project/stdcbench/stdcbench-0.8.tar.gz`)
and is unmodified; all adaptation lives in the glue files above. stdcbench
is distributed under the GNU General Public License v2 or later.
