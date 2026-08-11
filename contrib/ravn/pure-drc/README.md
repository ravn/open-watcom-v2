# Pure Digital Research C on CP/M-86 (and in the Unicorn runner)

This directory builds programs with the **genuine, unmodified Digital Research
C (DR C) v1.11 compiler** (CP/M-86, April 1984) and **DR LINK-86**, linked
against the real DR C run-time `clears.l86`, then runs the result in **both**
CP/M-86 emulators used in this project:

* the host **cpm86 / emu2** emulator (`../cpm86-crossdev/bin/cpm86`), and
* the from-scratch **Unicorn** runner (`../cpm86run_unicorn.py`).

It is the *pure DR C* counterpart to `../owc-drc`, which instead makes the
**modern Open Watcom** compiler link against the same DR C run-time. Here no
Watcom is involved at all — it is DRI's own compiler, linker and libc, exactly
as shipped in 1984.

## Why this exists

While bringing Open Watcom C up on the DR C run-time (`../owc-drc`) we hit a
`printf` that produced garbage on real RC759 hardware. To isolate whether the
fault was ours or DR C's, we built the **same program with pure DR C** and it
worked perfectly — proving DR C ↔ (Concurrent) CP/M-86 are fully compatible and
that the bug was in our Watcom startup glue (which jumps straight to `_main`
and skips DR C's real entry chain `m.init`). These pure-DR-C builds are that
reference, and they now also run in the Unicorn emulator (see the fix below).

## Results (verified)

```
./build-pure-drc.sh sample   # tiny printf smoke test  -> sample.cmd (20096 B)
./build-pure-drc.sh dhry     # Dhrystone 2.1           -> dhry.cmd   (30464 B)
```

Both print **byte-identical** output in the emu2 emulator and in the Unicorn
runner (only emu2's own startup banner differs). Dhrystone's every self-check
variable matches its expected value (`Int_Glob=5`, `Arr_2_Glob[8][7]=210`,
`Str_Comp=DHRYSTONE PROGRAM, SOME STRING`, …).

## Quick start

```sh
# DRC_HOME must hold the DRI tool binaries + clears.l86 (see "Toolchain" below);
# DR C headers are taken from ../owc-drc/drc by default (run ../owc-drc/fetch-drc.sh).
DRC_HOME=/path/to/drc ./build-pure-drc.sh sample
DRC_HOME=/path/to/drc ./build-pure-drc.sh dhry
```

The build pipeline (all under emu2, driven through a pty because emu2 needs a
controlling TTY, and with an internal wall-clock budget because macOS has no
`timeout`):

```
drc.cmd   UNIT               -> UNIT.obj      (DR C v1.11: preprocessor + code gen)
link86.cmd NAME=UNIT,CLEARS.L86[S] -> NAME.cmd (DR LINK-86, DR C libc as .L86 lib)
```

## Two things pure DR C needs that we had to get right

### 1. The Unicorn runner must set up the base page like the real CCP

DR C programs enter through DR C's own startup **`m.init`** (in `clears.l86`),
which — for the small memory model — initialises the stack pointer from the
**base-page data-length field LD** (offset `06H`):

```
m.init.stack:  ...  pop ss  ;  mov sp,6[bx]   ; SP = word at base page 06H (=LD)
               inc sp  ;  and sp,0FFFEh       ; use the whole segment, align
```

So `LD` must describe the **whole segment the program was granted**, not just
its initialised data image. The real CCP allocates the data group up to its
maximum (`G_MAX` paragraphs — `0x1000` = a full 64 KB for these programs) and
records *that* in `LD`. Our runner originally wrote only the data-image size,
so `SP` landed on top of the data/heap and the program crashed within a handful
of BDOS calls. `cpm86run_unicorn.py` now sizes `LD` from the data group's
`G_MAX` (clamped to 64 KB); see the `_load()` comment and commit
`cpm86run_unicorn: run pure DR C programs under Unicorn`.

`m.init` also issues the disk-system BDOS calls `DRV_ALLRESET` (13),
`DRV_SET` (14) and `DRV_GET` (25) while locating the `.CMD` drive; the runner
answers them as drive-A: no-ops.

### 2. DR C v1.11 compiler quirks (handled by `drcify.py`)

The 1984 compiler is pre-ANSI and has real limitations. `drcify.py` adapts
stock Dhrystone 2.1 for it **without touching the benchmark computation**:

| Quirk in DR C v1.11 | Symptom | Fix in `drcify.py` |
|---------------------|---------|--------------------|
| Struct assignment `*a = *b` | `Error 66: Internal compiler error. Unknown pointer size.` | `#define NOSTRUCTASSIGN` — use the benchmark's own `memcpy`-based `structassign()` |
| No `memcpy` in `clears.l86` | link would be unresolved | Dhrystone itself defines `memcpy` under `NOSTRUCTASSIGN` |
| No UNIX `<sys/times.h>` / `times()` | missing header / symbol | disable the `TIMES`/`TIME` timing paths; the run takes the benchmark's own "Measured time too small" branch (correctness is clock-independent) |
| `HZ` only defined by a timing path | `Error 47: HZ undefined` in the (now dead) timing math | `#define HZ 60` |
| Interactive `scanf` for the run count | needs console input | fixed run count for a deterministic run in both emulators |

`NOENUM` (use `typedef int Enumeration`) is also set for robustness; output is
identical. Everything else — structs, unions, pointer chasing, string handling,
`Proc_1..8`/`Func_1..3`, and the full correctness printout — is the real,
unmodified Dhrystone 2.1.

Note DR C's own libc **does** provide `printf`, `scanf`, `malloc`, `strcpy`,
`strcmp`, etc.; only the UNIX process-timer and struct-assignment gaps needed
work.

## The DR runtime symbol convention (`.` in names)

DR's run-time symbols contain periods — `m.init`, `m.init.heap`, `cinit.` — so
they can never collide with user identifiers. DRI assembled them with an
**in-house patched RASM86** that allows `.` in identifiers (stock RASM86 and
Open Watcom's `wasm` both reject it). LINK-86 special-cases the `cinit.` code
segment and places it **first**, so `m.init` ends up at offset 0 and becomes the
`.CMD` entry point. This is why the pure-DR-C `.CMD` "just works" while the
Watcom hybrid in `../owc-drc` has to bridge into `_main` manually.

## Toolchain (not committed — DRI copyright)

The DR C tool binaries are copyright Digital Research and are **not** in this
repo. Obtain them from the DDHF "Digital Research C" floppy image
(<https://ddhf.dk/wiki/Bits:30002664>, `Digital-Research-C-May84.bin`; a v1.11
IMD is at <https://ddhf.dk/wiki/Bits:30005869>). `../owc-drc/fetch-drc.sh`
already extracts `clears.l86` and the headers; the `*.cmd` tools
(`drc.cmd`, `drc860/861/862.cmd`, `drcrpp.cmd`, `r.cmd`, `link86.cmd`) come from
the same image via `cpmtools`. Point `DRC_HOME` at a directory holding them.

## Files

| File | Purpose |
|------|---------|
| `build-pure-drc.sh` | Build with DR C + DR LINK-86 under emu2, then run in **both** emulators. Targets `sample`, `dhry`. |
| `drcify.py` | Transform stock Dhrystone 2.1 into DR C v1.11-buildable form (see table above); benchmark logic untouched. |
| `sample.c` | Minimal pure-DR-C `printf` smoke test (uses DR C libc + `m.init` startup). |

Toolchain binaries, headers and generated `*.cmd`/`*.obj`/`*.sym` are
gitignored.
