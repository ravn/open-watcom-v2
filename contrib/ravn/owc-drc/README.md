# Open Watcom C on the Digital Research C run-time (CP/M-86)

This directory demonstrates — with reproducible, verified test cases — that the
**modern Open Watcom C compiler can produce CP/M-86 programs that link against
the genuine, unmodified Digital Research C (DR C) run-time library**
(`clears.l86`) using DR's own `LINK-86`, with no object-format conversion.

It builds on the `../owc-drlink/` demo (which linked Watcom C against a *minimal*
hand-written OMF runtime). Here the runtime is a **complete, real libc** — the
DR C library — so ordinary C programs that call `printf`, `malloc`, `strcpy`,
`scanf`, floating point, etc. link and run. The headline result: **unmodified
Dhrystone 2.1 compiles, links and runs.**

## Results

```
Open Watcom C   (bwcc -ecc -fpi87 -nt=CODE -fi=compat.h)  → *.OBJ  ┐
owcrt.asm entry (bwasm)                                   → OWCRT.OBJ ├→ DR LINK-86 → *.CMD → CP/M-86
DR C library                                              → CLEARS.L86 ┘
```

* `./build-owc-drc.sh` (or `hello`) →
  `Hello from Open Watcom C + DR C run-time on CP/M-86: 42 FF ok`
* `./build-owc-drc.sh dhry` → fetches **unmodified** Dhrystone 2.1 and runs it to
  completion; every self-check variable matches its expected value, and it now
  reports a real (emulated) timing via the Concurrent CP/M-86 clock — see the
  timer section below.

## Quick start

```sh
./fetch-drc.sh          # download + extract the DR C run-time and headers
./build-owc-drc.sh      # hello smoke test
./build-owc-drc.sh dhry # unmodified Dhrystone 2.1
```

## DR C as the oracle and the size/speed baseline

Genuine Digital Research C (DR C 1.11) is treated as the **correctness oracle**
and the **size/speed baseline**: whatever DR C does is *defined* to be correct,
and every Open Watcom build is scored relative to it. The harness lives one
level up in [`../`](..):

* `../cycles186.py` — an iAPX 186 (80186) **clock-cycle estimator** ("ticks").
  Unicorn is a *functional* emulator with no notion of time, so it can only
  count instructions. `cycles186.py` layers a capstone decode + an 80186 clock
  table on top to estimate cycles. It does **not** model the prefetch queue or
  memory wait-states, so the figure is deliberately "cirka-ish"; for true
  cycle-accurate timing use MAME or PCE against the real RC759 XIOS. The 186 has
  hardware effective-address calculation (no separate EA penalty) and much
  faster `MUL`/`DIV` than the 8086, and memory/stack operands cost roughly 3×
  a register operand — which is why raw instruction counts *understate* how much
  Open Watcom's register allocation beats DR C's memory-heavy code.
* `../bench.py` — `measure` / `compare` / `baseline`. `compare ORACLE CANDIDATE`
  runs both `.CMD`s on the Unicorn harness and reports size, instructions,
  estimated 80186 clocks and (at `--mhz`, default **6**, the RC759 Piccoline)
  an estimated wall-clock time, plus a **behaviour verdict** — MATCH only if the
  candidate reproduces the DR C oracle output byte-for-byte (Dhrystone's one
  documented implementation-dependent value, `Ptr_Comp`, is masked).
* `../baseline.json` — the persisted DR C oracle numbers, so `bench.py baseline
  check` works **without** the (copyright) DRI toolchain present.
* `./bench.sh` — one reproducible driver: it builds Dhrystone several ways from
  the **same** drcified, deterministic source (fixed run count, timing disabled
  → identical output) in the **same** small/8080 memory model DR C uses, then
  prints the matrix. The only thing that varies is the Open Watcom code
  generator settings.

The comparison is apples-to-apples because the memory model is identical (both
are small/8080: one `CODE` group + one 64 KB `DATA` group, near pointers,
`SS == DS`, verified from the `.CMD` group descriptors), the source is identical,
and the run is deterministic.

### Optimisation level and calling convention

Three Open Watcom variants are compared against the DR C oracle:

| variant | flags | calls |
|---------|-------|-------|
| **O0**  | `-ecc -od` | cdecl (stack), optimiser disabled (≈ `-O0`) |
| **O3**  | `-ecc -ox` | cdecl (stack), full optimisation (≈ `-O2`/`-O3`) |
| **mixed** | `-ox` (no `-ecc`) | **register** calls user↔user, cdecl to the DR C library |

The *mixed* variant is the same trick used for LLVM-Z80: user-space functions
call each other in registers (Open Watcom's default `__watcall`), while only the
DR C library entry points are forced back onto the stack via
`-fi=compat-mixed.h`, which aliases each libc function to the built-in `__cdecl`
convention with its name forced verbatim (`#pragma aux (__cdecl) printf "*";`).

Dhrystone 2.1, 200 runs, estimated 80186 clocks @ 6 MHz (all **MATCH** the DR C
oracle output):

| build | size (B) | instructions | ~80186 clocks | ~ms @6 MHz | vs DR C |
|-------|---------:|-------------:|--------------:|-----------:|--------:|
| **DR C** (oracle/baseline) | 30,464 | 397,284 | 2,950,838 | 491.8 | 1.00× |
| Open Watcom **O0** (`-ecc -od`) | 29,056 | 293,194 | 2,376,097 | 396.0 | 0.81× |
| Open Watcom **O3** (`-ecc -ox`) | 28,544 | 259,984 | 1,969,511 | 328.3 | 0.67× |
| Open Watcom **mixed** (`-ox`, register) | 28,544 | 249,390 | 1,864,971 | 310.8 | **0.63×** |

So on this benchmark full optimisation buys ~33 % fewer clocks than DR C, and
switching user-space calls from the stack to registers saves a further ~5 %.
Reproduce with `./bench.sh` (or `./bench.sh --mhz 8` for a different clock).

## How Watcom is made compatible with DR C — the facts (all verified)

### 1. Object format: Watcom OMF links with DR LINK-86 as-is

Open Watcom emits Intel/Microsoft **OMF**, which DR `LINK-86` consumes directly —
including the DR C library `clears.l86` (an OMF `.L86` library searched with the
`[S]` attribute). No format conversion, no `bin2cmd.py` post-processing.

### 2. Symbol naming: DR C has NO leading underscore

DR C's libc publics are undecorated (`printf`, `main`, `malloc`, `strcpy`).
Leading-underscore names in the library (`_main`, `__main`, `_exit`) are internal
run-time helpers. Open Watcom's `-ecc` (cdecl) would normally add a leading
underscore. `compat.h` — force-included with `-fi=compat.h` — contains a single
line, `#pragma aux default "*";`, which makes Watcom emit **every** symbol
verbatim (no decoration), matching DR C. This is what lets **unmodified** source
resolve against `clears.l86`.

### 3. The `main` special-case

Open Watcom special-cases the name `main`: even under `-ecc` and the global
pragma it emits `main_` plus a reference to Watcom's own `_cstart_`. So the C
entry is compiled under the name `cmain` (via `-Dmain=cmain`, or by naming the
function `cmain()` directly) and `owcrt.asm` bridges DR C's `main` call to it.

### 4. Segment merge: compile with `-nt=CODE`

Watcom code defaults to segment `_TEXT`; DR C uses `CODE` (class `'CODE'`, group
`CGROUP`). If they don't merge, LINK-86 reports `TARGET OUT OF RANGE` on near
calls crossing the boundary. Compiling with `-nt=CODE` and putting `owcrt.asm`
in segment `CODE`/`CGROUP` merges everything. (Data already matches — both use
group `DGROUP`.)

### 5. Floating point: `-fpi87`

Watcom float code normally calls its own helpers (`FIDRQQ`, `FIWRQQ`, …) that DR
C's library does not provide. `-fpi87` emits **inline 8087** opcodes instead, so
no Watcom float helpers are referenced. The Unicorn/QEMU CP/M-86 harness emulates
the x87; on real hardware this requires an actual 8087.

### 6. The startup object `owcrt.asm`

A CP/M-86 `.CMD` starts executing at `CS:0000`, so the **first** object on the
LINK-86 line owns offset 0. `owcrt.asm` provides that entry (`jmp _main` into DR
C's start chain, which inits the OS/stack/heap and then calls `main`) plus the
`main → cmain` bridge. Assembled with `bwasm`, consumed by LINK-86.

### 7. Avoid file-scope `static` in code linked by LINK-86

Open Watcom emits OMF record type `0xB4` (“static extdef”) for file-scope
`static` variables; DR LINK-86 rejects it with `OBJECT FILE ERROR 5`. Use
non-static globals instead (see `glue.c`).

### 8. Short module paths (THEADR)

Watcom stamps the *absolute* source path into the OMF THEADR; a long path makes
LINK-86 fail with `OBJECT FILE ERROR 10`. `build-owc-drc.sh` therefore compiles
and links inside a short `/tmp/owcdrc.XXXXXX` work dir using bare filenames.

### 9. Headers

The DR C headers extracted from the floppy image contain CP/M text padding
(`^Z`/`CR`) that the Watcom parser chokes on. `fetch-drc.sh` strips it. Programs
may also use minimal neutral prototypes (as `hello.c` does for `printf`) instead
of the DR C headers.

### The timer (`glue.c`)

Dhrystone needs a clock for its timing loop. Plain CP/M-86 has none, and the
Concurrent CP/M-86 **T_GET** call (BDOS 105) only resolves whole seconds. The
RC759's own on-chip 80186 timers are wired to sound/cassette, not timekeeping
(PICCOLINE Programmer's Guide §2.3); for fine relative timing the machine
provides an XIOS **"16 ms counter"** via **Int 28h function 19** (Programmer's
Guide App. A): it returns a 32-bit second count plus the elapsed 16 ms periods
of the current second, i.e. **16 ms resolution**. The `cpm86run_unicorn`
emulator models that call, and `glue.c`'s `clock()` reads it (built via
Dhrystone's `MSC_CLOCK` "hi-res clock" path with `CLK_TCK == 1000`, returning
milliseconds). The counter is a deterministic virtual clock (proportional to
the code the emulated 8086 executes), so the reported Dhrystones/sec is
**reproducible** and scales with code efficiency and the emulated CPU rate
(`CPM86_CLOCK_HZ`). `glue.c` also still provides a whole-second `time()` via
T_GET for any code that wants wall-clock seconds. The link includes
`owmath.asm` because the millisecond arithmetic needs Watcom's 32-bit long
helpers, which DR C lacks.

## Why not use Watcom's own run-time?

Watcom has no CP/M-86 target, so its run-time cannot be used here. Mixing
Watcom's headers with DR C's run-time is also a bad idea — the `FILE` layout,
`__iob`, decorated symbols and intrinsic helpers differ. Use DR C's headers
(cleaned) or minimal neutral prototypes, as done here.

## Provenance of the DR C run-time

`fetch-drc.sh` downloads the CP/M-86-native **Digital Research C (May 1984)**
floppy image from the Danish Data History Society (DDHF),
<https://ddhf.dk/wiki/Bits:30002664> (`Digital-Research-C-May84.bin`,
sha256-verified), and extracts `clears.l86` plus the headers via `cpmtools`
using the bundled `diskdefs` format `drc-rc759`. A newer v1.11 image exists at
<https://ddhf.dk/wiki/Bits:30005869> (IMD format; not used here).

## Prerequisites

1. Open Watcom native tools built in `../../../build/binbuild` (`bwcc`, `bwasm`) —
   run the repo's top-level `./build.sh`.
2. The `../cpm86-crossdev` submodule populated with `emu2` and the DR tools
   (`bin/emu2`, `share/pcdev/linkcmd.exe`) — see that submodule's fetch scripts.
3. `cpmtools`, `curl`, `shasum` on `PATH` (for `fetch-drc.sh`).
4. `python3` with the `unicorn` package (for `../cpm86run_unicorn.py`).

## Files

| File | Purpose |
|------|---------|
| `fetch-drc.sh` | Download + extract the DR C run-time and headers into `drc/`. |
| `build-owc-drc.sh` | Compile (Watcom) → link (DR LINK-86) → run (Unicorn); targets `hello`, `dhry`. |
| `owcrt.asm` | CP/M-86 entry object: `jmp _main` + `main → cmain` bridge, segment `CODE`/`CGROUP`. |
| `compat.h` | Forced-include naming shim (`#pragma aux default "*";`). |
| `compat-mixed.h` | Mixed-convention shim: register calls user↔user, cdecl to libc (`#pragma aux (__cdecl) printf "*";`). |
| `hello.c` | printf smoke test (entry `cmain`). |
| `glue.c` | RC759 XIOS 16 ms `clock()` (Int 28h fn 19) + T_GET `time()`, non-static globals. |
| `dhry-time.h` | Tiny `<time.h>` shim (`CLK_TCK`=1000, `clock_t`) so unmodified Dhrystone builds with its `MSC_CLOCK` path. |
| `diskdefs` | `cpmtools` format `drc-rc759` for the DDHF DR C floppy. |

Downloaded and generated artifacts (`Digital-Research-C-May84.bin`, `drc/`,
`dhry21/`, `*.CMD`, `*.OBJ`) are gitignored.
