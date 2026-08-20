# Real `%e` / `%f` / `%g` printf on CP/M-86 (opt-in)

By default the CP/M-86 clib links the **`noefgfmt` stub**: `printf("%f", ...)`
compiles and links, but the float conversion prints nothing — `__EFG_printf`
points at `_no_support_loaded`. This keeps integer-only programs small (the
double→decimal `dtoa`/`cvt` subsystem is ~4 KB and pulls 64-bit helpers).

## Enabling it

Two requirements — a **reference** so the linker pulls the formatter, and a
**runtime install** because our minimal crt0 does not walk Watcom's auto-init
table:

1. Compile with **`-fpc`** (soft-float, no 8087 — same as every float program here).
2. Call **`__setEFGfmt()` once** before your first `%f`/`%e`/`%g`:

```c
#include <stdio.h>
extern void __setEFGfmt( void );   /* install real _EFG_Format */

int main( void )
{
    __setEFGfmt();                 /* one call, before any %f */
    printf( "%.4f\n", 3.14159265 );  /* -> 3.1416 */
    return 0;
}
```

3. Link the model's **libm** as well as clib — the formatter core `_EFG_Format`
   and `__cnvs2d` (scanf side) live in `libm{s,m,c}.lib`:

```
wlink format cpm86 ... library clib$MODEL.lib library libm$MODEL.lib
```

That is all: `__setEFGfmt()`'s reference pulls `setefg` → `cvt`/`ldcvt`/`efcvt`/
`gcvt` → `cvtbuf` → `__U8LS` (64-bit shift) from the clib archive, and
`_EFG_Format`/`__cnvs2d` from libm. A program that never calls `__setEFGfmt()`
pulls none of it.

## What is archived where

- **clib** (`clib{s,m,c}.lib`, built by `build-lib.sh`): `setefg`, `cvt`,
  `ldcvt`, `efcvt`, `gcvt`, `cvtbuf`, `i8ls086` — pulled only via `__setEFGfmt`.
- **libm** (`libm{s,m,c}.lib`): `efgfmt` (`_EFG_Format`), `cnvs2d` (`__cnvs2d`),
  and all the transcendentals — Watcom's stock 80186-safe soft-float mathlib.

## Verification

`test/floatfmt_test.c` is the regression: it calls `__setEFGfmt()` then prints
`%.4f`, `%.3e`, `%g` with the oracle **`f=3.1416 e=2.500e+00 g=0.001`**. It is the
`fltfmt` row of `run-all-models.sh` and PASSES in all three memory models
(small/medium/compact) under the Unicorn runner. No 8087 opcode is emitted or
executed (the `-fpc` `__FDxemu` path; the Unicorn harness has no FPU and would
trap on one).

## Not done

`scanf("%f")` (the `__cnvs2d` read side) is archived but untested here. `%a`
(hex-float) is not wired.
