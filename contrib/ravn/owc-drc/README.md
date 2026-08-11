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
| `hello.c` | printf smoke test (entry `cmain`). |
| `glue.c` | RC759 XIOS 16 ms `clock()` (Int 28h fn 19) + T_GET `time()`, non-static globals. |
| `dhry-time.h` | Tiny `<time.h>` shim (`CLK_TCK`=1000, `clock_t`) so unmodified Dhrystone builds with its `MSC_CLOCK` path. |
| `diskdefs` | `cpmtools` format `drc-rc759` for the DDHF DR C floppy. |

Downloaded and generated artifacts (`Digital-Research-C-May84.bin`, `drc/`,
`dhry21/`, `*.CMD`, `*.OBJ`) are gitignored.
