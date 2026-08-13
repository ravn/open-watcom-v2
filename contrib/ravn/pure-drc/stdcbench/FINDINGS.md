# Pure DR C + unproto → stdcbench 0.8: feasibility findings

**Goal:** compile the [stdcbench 0.8](https://sourceforge.net/projects/stdcbench/)
integer benchmark with the **genuine Digital Research C v1.11** compiler
(CP/M-86, April 1984) — not the Open Watcom→DR-C-runtime hybrid in `../owc-drc`.

stdcbench is written in ANSI/C90. DR C 1.11 is a **pre-ANSI K&R** compiler with
a limited type system. The bridge is [unproto](https://github.com/udo-munk/unproto)
(Wietse Venema's ANSI→K&R filter) plus a set of textual transforms that map the
C90 type system onto what DR C accepts. See `transform.sh` for the pipeline and
`fetch-unproto.sh` for the tool.

## Status: pipeline proven, 9 of 14 modules compile; 5 need per-file patches

Every claim below was verified empirically on the real `drc.cmd` running under
the `../cpm86-crossdev/bin/cpm86` (emu2) emulator, cross-checked against the DR C
1.11 manual where noted. Nothing here is inferred.

### DR C 1.11 type system (verified: manual §6 + probes + emulator)

| Feature | DR C 1.11 | Transform |
| --- | --- | --- |
| `char` | **unsigned** 0..255 (manual §6.1; emulator-confirmed) | — |
| `int` / `short` | 16-bit signed | — |
| `unsigned` / `unsigned int` / `unsigned short` | 16-bit unsigned ✓ | — |
| `long` | 32-bit **signed only** — "C does not implement unsigned long integers" (manual) | — |
| `unsigned long` | ✗ Error 14 | `→ long` (DRI's own `portab.h` maps `ULONG≡long`) |
| `unsigned char` | ✗ Error 13 | `→ char` (lossless — char is already unsigned) |
| `signed` keyword | ✗ Error 19/89 | `signed int/char/long → int/char/long`; bare `signed → int` |
| `const` / `volatile` / `restrict` / `inline` | ✗ | `-D…=` stripped at preprocess |
| `(void)` params, prototypes, new-style defs | ✗ Error 55 | **unproto** → K&R |
| `1000ul` / `42u` literal suffix | ✗ Error 60 | `→ 1000L` / `42` |
| `bool` / `_Bool` / `true` / `false` (C99) | ✗ | `-Dbool=char -D_Bool=char -Dtrue=1 -Dfalse=0` |
| `<stdint.h>` fast/least/exact types | ✗ (no header) | `inc/stdint.h` typedefs (see note) |
| `enum` | ✗ Error 89 | `drc_enum.py` → `#define`s + `typedef int` |
| trailing comma in `{…,}` initializer | ✗ Error 89 | stripped |
| `sizeof("literal")` | ✗ Error 115 (`sizeof` wants a *type*) | computed → integer length |
| `void` return type | ✓ | — |
| `L` suffix | ✓ | — |
| 2-D array subscript `a[i][j]` | ✓ | — |

**stdint.h note:** `uint8_t→char` (unsigned, faithful). No signed 8-bit type
exists, so `int8_t→int` (widened). 32-bit maps to DR C signed `long`. `fast`
counters map to native 16-bit `int`. See `inc/stdint.h`.

### Per-module result (14 upstream TUs, transformed then compiled on real DR C)

Clean through the general pipeline (`transform.sh`) — **11/14**: c90base,
c90base-immul, c90base-huffman-recursive, huffman-iterative, huffman_tree,
c90lib, c90lib-peep-stm8, c90lib-htab, stdcbench, **c90base-data** (large
initializer, fixed by `drc_reflow.py`), **c90lib-peep** (multiline trailing
comma, fixed by the slurp-mode comma strip).

The 3 that still fail, with the exact DR C error and verified root cause:

| Module | DR C error (transformed line) | Root cause (verified) | Kind |
| --- | --- | --- | --- |
| `c90base-compression.c` | `41: Error 26 abstract declarator` (+ cascade) | **unproto bug**: for a function-pointer parameter `unsigned char (*input)(void)` it emits the K&R decl `unsigned char ()(void);` — dropping BOTH the parameter name AND the `(*…)` pointer syntax (the name survives only in the id-list). DR C then rejects the nameless/abstract declarator. Spacing is irrelevant (see below). | unproto bug — no textual transform fixes it |
| `c90base-isort.c` | `112,125: Error 92 lvalue required before [` | `int (*p)[20]` **pointer-to-array** unsupported; the `y_startpos`/`y_endpos`/`y_endl` aliases use it | DR C limit → `#define` aliases to the underlying 2-D arrays |
| `c90lib-lnlc.c` | `269: Error 55` / `271-272: Error 27` / `280-281: Error 47/93` | unproto drops the name from **pointer-to-array parameter** `char (*adjacency_matrix)[8]`, emitting the type keyword in the K&R id-list (`(…,char ,…)`) | unproto weakness + DR C limit → flatten param to `char *` + manual stride (**changes benchmark source**, validate carefully) |

**FIXED in the pipeline (2026-08-12):**

- `c90base-data.c` "Error 61 Too many initializers" was NOT an element-count
  limit and NOT unproto corruption — it is a DR C 1.11 **single-line
  parse/token-buffer** limit: a long source line is silently truncated
  mid-initializer, dropping the closing `}`, so the compiler reports a
  *spurious* "missing brace / too many initializers". Verified on the emulator:
  the identical 417-value table on one ~1900-char line FAILS, but reflowed to
  ≤16 values/line it compiles and links (`N01.OBJ` produced). The exact byte
  threshold depends on token width (3-digit numeric tokens trip it at ~1030+
  char lines; narrower tokens tolerate longer lines) — consistent with a fixed
  internal buffer whose overflow depends on layout; not fully isolated. Fix:
  `drc_reflow.py` wraps long `{…}` initializer lines onto short lines
  (formatting only, zero value/element change). This is a genuine DR C defect
  held as fork knowledge (the "maintainer" is a 1984 compiler — unfixable
  upstream), worked around in our transform.
- `c90lib-peep.c` "Error 89" (trailing comma in `ftab[]` split across newlines)
  is fixed by a final slurp-mode `s/,(\s*)}/$1}/g` that strips a comma before a
  `}` even when they are on separate lines.

### Transforms that are only *partially* covered (do not over-trust)

- **func-ptr `(*f)(void)` params — this is an unproto BUG, not a spacing issue.**
  Verified on the vendored unproto binary (2026-08-12), both forms produce the
  same broken output:

  ```
  in:  int f(unsigned char (*input)(void), int n) {...}   // spaced
  in:  int f(unsigned char(*input)(void),  int n) {...}   // no-space
  out: int f(input,n)
       unsigned char ()(void);      <-- name AND (*..) both dropped
       int n;
       {...}
  ```

  unproto keeps `input` in the identifier list `f(input,n)` but emits a
  nameless, non-pointer declarator `unsigned char ()(void);` for it. Control:
  a plain `unsigned char *input` param round-trips correctly
  (`unsigned char *input;`), so the defect is specific to the
  function-pointer-parameter case. My earlier claim that only the *no-space*
  form failed was WRONG — spacing makes no difference. Affects both
  `cvu_init_huffman` and `cvu_init_rle` in c90base-compression.c → N10.
  No textual transform in this pipeline can reconstruct the parameter unproto
  discarded; a per-file source rewrite (or a typedef'd param) is required.
- **pointer-to-array** (`(*p)[N]`) as a type, variable, or parameter — no
  textual transform can bridge this DR C limit; needs a per-file rewrite
  (N11 isort, N12 lnlc).

## Remaining work (deferred — tracked as ravn/rc7xx-work#5)

1. Write the four per-file patches; confirm all 14 TUs → `.obj` on real DR C.
2. Port the glue through the same pipeline: `cpmlibc.c` (mem*/strstr/strtol/ctype
   DR C lacks) and a pure-DR-C `portme.c` — entry is `main()` (DR C's `_main`
   inits then calls `main`, so **no** owcrt/cmain bridge), keep the `brk()` heap
   fix (owc-drc issue #1), clock `printf` uses `%ld`.
3. Replace Watcom's `#pragma aux xios_tick16` (Int 28h fn 19 timer) with a
   `bwasm` cdecl clock stub — the clock is load-bearing (c90base loops
   `do{…}while((end=clock())-start < SECONDS)`; a stuck clock infinite-loops).
4. Link with `clears.l86` via DR LINK-86; run in `cpm86`/emu2 **and**
   `cpm86run_unicorn.py`; validate non-zero scores (`CPM86_CLOCK_HZ≈700000`, as
   owc-drc uses).

The Watcom cgsupp long helpers (`i4m`/`i4d`) and `omf-delocal.py` from owc-drc
are **not** needed here: DR C's `clears.l86` provides signed-long mul/div (proven
by the pure-DR-C mandel build) and DR C emits clean OMF (the delocalizer only
fixed Watcom's `LEXTDEF`).
