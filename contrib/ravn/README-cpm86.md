# Building CP/M-86 programs with Open Watcom

## Short answer

Open Watcom **cannot** build CP/M-86 executables out of the box. It has:

- no `.CMD` output format in the linker (`wl` supports DOS `.EXE`/`.COM`,
  OS/2, Windows, ELF, Phar Lap, QNX, RDOS, Novell and raw binary only — see
  `bld/wl/h/_formats.h`), and
- no CP/M-86 C runtime (`clib` targets DOS/OS2/Windows/etc. via INT 21h).

There is **no** `__CPM__` target macro or CP/M header/library anywhere in the
tree. The only `CPM`/`CP/M` strings in the source are unrelated (DOS PSP
compatibility fields, an SCSI bitflag, a comment about the CP/M-era EOF byte).

## But it is achievable via a workaround

CP/M-86 and DOS both run 8086 code, so you can compile with Open Watcom and
retarget the *output packaging* and *system-call layer*:

```
wcc  -0 -mt -s -oi hello.c            # 16-bit x86, tiny model, no runtime
wl   format raw bin option start=_start_ name hello.bin file hello.obj
python3 bin2cmd.py hello.bin HELLO.CMD
```

`build-cpm86.sh` accepts a `CPU` variable to select the instruction level
(`-<n>`): `CPU=0` = 8086 (default), `CPU=1` = 80186, `CPU=2` = 80286, etc.
Only the instruction set matters here -- CP/M-86 is real-mode and the result is
run at instruction level (Unicorn/QEMU executes 80186+ opcodes fine); the
80186's on-chip peripherals are out of scope.

### The `.CMD` header (`bin2cmd.py`)

CP/M-86 executables start with a 128-byte **Command File Header**: eight 9-byte
group descriptors (`type, length, base, min, max`, little-endian, in 16-byte
paragraphs), followed by RSX/fixup/flags fields. Verified against Digital
Research's *CP/M-86 System Guide* (Command File Format appendix) and the
seasip.info archive.

`bin2cmd.py` supports two models:

- `--model 8080` (default): one Code group holding code+data — mirrors a
  CP/M-80 `.COM` layout; pair with `wcc -mt` (tiny).
- `--model small`: separate Code (type 1) and Data (type 2) groups — pair with
  `wcc -ms` and supply the data image via `--data`.

The header layout and both models are covered by the self-tests (run
`python3 bin2cmd.py --help`; the test block is in the session notes).

### The system-call layer (`hello.asm` / `hello.c`)

With no C runtime, the program calls **BDOS directly via `INT 0E0h`**
(`CL`=function, `DX`=parameter). Functions used: 9 (print `$`-terminated
string at `DS:DX`) and 0 (terminate).

**Entry & segment convention (per the DR System Guide, Section 2.3–2.5).** The
loader picks the memory model from the `.CMD` group descriptors and initialises
the segment registers and entry `IP` accordingly:

| Model | Groups | CS/DS/ES | Entry IP |
|-------|--------|----------|----------|
| 8080  | code only | CS=DS=ES=code base | **`0100H`** |
| Small | code + data | CS=code, DS=ES=data | `0000H` |

In the **8080 model** the first `100H` bytes of the (shared) code group are the
**base page**, and execution begins at **`CS:0100H`** — exactly like CP/M-80's
`.COM`. (An earlier version of this note incorrectly said `CS:0000`; only the
Small/Compact models enter at offset 0.) The base page lives at `DS:0000`. The
entry code **forces `DS = CS`** (`push cs` / `pop ds`) so the `$`-string, which
lives in the same group, is addressable regardless of how the loader set `DS`.

- `hello.asm` (wasm) is the recommended starting point: code is assembled at
  `org 100h` (after the base page) and the loader enters there.
- `hello.c` shows the same thing in C via a `#pragma aux` BDOS call, for once a
  C runtime is added later.

### Command line, FCB and base page setup

Before entering a program the emulated CCP (`ccp.py`) populates the base page
from the typed command line, just like real CP/M-86 (System Guide 2.6/2.7):

- the two filename arguments are parsed into the **default FCBs** at `DS:005CH`
  and `DS:006CH` (drive code, 8.3 name, wildcards);
- the **command tail** is stored at `DS:0080H` (length byte + upper-cased
  characters), which is also the default DMA buffer;
- the group length/base descriptors and the `M80` flag (offset `05H`) are
  filled in from the header.

`ECHOARG.CMD` demonstrates this — it prints the command tail the CCP left at
`0080H`:

```
python3 cpm86run_unicorn.py ECHOARG.CMD one two.dat   ->   " ONE TWO.DAT"
```

### Ready-to-run artifact: `HELLO.CMD`

`HELLO.CMD` in this folder is a **complete, runnable** CP/M-86 executable. It is
now produced by the real Open Watcom toolchain (`build-cpm86.sh hello.asm`:
`wasm` → `wl format raw` → `bin2cmd.py`); the resulting file is byte-identical
to the earlier hand-assembled reference, which validates both the pipeline and
the hand analysis. Code layout (after the base page):

```
0100: 0e 1f ba 0d 01 b1 09 cd e0       ; push cs; pop ds; mov dx,msg; mov cl,9; int E0h
      b1 00 cd e0                       ; mov cl,0; int E0h
010d: "Hello, CP/M-86 from Open Watcom!\r\n$"
```

## Building the toolchain

Open Watcom does not need a full release build to compile CP/M-86 programs: the
**bootstrap** cross-tools are enough. On this arm64 macOS host the toolchain was
built with the CI bootstrap path (native `clang`):

```
export OWROOT=$(pwd) OWTOOLS=CLANG OWOBJDIR=binbuild OWBUILD_STAGE=boot
. ./cmnvars.sh
cd bld && sh $OWROOT/ci/buildx.sh          # builds wmake, builder, then `builder boot`
```

This populates `build/binbuild/` with the bootstrap cross-compilers/-assembler/
-linker: `bwcc` (16-bit C), `bwasm` (assembler) and `bwlink` (linker). Put that
directory on `PATH` and `build-cpm86.sh` uses those automatically (it prefers a
released `wasm`/`wcc`/`wl` if present, else falls back to `bwasm`/`bwcc`/
`bwlink`).

## What is still required

1. **A CP/M-86 runtime** if you want the standard C library (stdio, malloc,
   `printf`). That means a CP/M-86 startup stub (`_cstart_`) plus a BDOS-based
   shim replacing clib's INT 21h calls. Freestanding code (own BDOS calls, as
   in `hello.c`) needs none of this and is the right first milestone.
2. **Validation on real CP/M-86.** The `.CMD` runs under the included
   instruction-level emulators (see below); a full-machine emulator (86Box,
   PCem, or a CP/M-86 VM) is still the way to validate OS-loader specifics.

## Emulation / testing

Two included runners execute the actual machine code at instruction level:

- `cpm86run.py` — a small hand-written 8086 interpreter with a BDOS hook.
- `cpm86run_unicorn.py` — uses **Unicorn Engine** (QEMU's CPU core), so the
  8086/80186+ instructions are decoded by independent, well-tested code; only
  the CP/M-86 BDOS layer is emulated here.

Both print `Hello, CP/M-86 from Open Watcom!` for `HELLO.CMD`.

### Non-trivial program: Dhrystone 2.1

`dhry.c` is a faithful port of Reinhold Weicker's **Dhrystone 2.1** benchmark
(structs, unions, enums, pointer chasing, record assignment, string handling
and many cross-function calls) made freestanding for CP/M-86: `printf`/`scanf`
are replaced by BDOS console output and a fixed run count, `malloc` by a static
pool, and `strcpy`/`strcmp` are provided locally. Build and run it with the
same pipeline:

```
export PATH=$OWROOT/build/binbuild:$PATH
./build-cpm86.sh dhry.c
python3 cpm86run_unicorn.py DHRY.CMD
```

It prints the benchmark's documented final values and every one matches its
`should be:` line (`Int_Glob 5`, `Bool_Glob 1`, `Arr_2_Glob[8][7] == runs+10`,
the record fields, the strings, …) — i.e. the 16-bit code the bootstrapped
`wcc` generated executes **correctly**. Timing is intentionally omitted: an
instruction-level emulator has no meaningful wall clock, so the benchmark is
used here as a correctness stress test, not a MIPS figure.

If you do want a *host-independent* work metric, pass `--count` to the runner
and it reports the exact number of instructions executed:

```
python3 cpm86run_unicorn.py --count DHRY.CMD
    ...
    [14946252 instructions executed]     # ~747 instructions per Dhrystone run
```

That tally is deterministic (it depends only on the generated code and the
emulator, not on the host). It is *not* a Dhrystones/second score — deriving
one would require multiplying by 8086 cycle counts (≈15–30 cyc/insn), which for
14.9M instructions over 20000 runs works out to roughly 300–500 Dhrystones/sec
on a 5–8 MHz 8086, in line with period measurements. Those are estimates; only
the instruction count is actually measured.

Because a C program has many functions and `wl format raw` does not reorder
`_TEXT` to put the entry symbol first, the C path links a tiny startup stub
(`cpmstart.asm`) **first**; its first byte is the entry point and it calls the
C entry `cpmmain()`.

### Large program with more than 64 KB of data: `bigdata.c`

`bigdata.c` is a bigger program (a PRNG, a table-driven CRC-32, three more
checksum routines, record generation, a cross-segment ring traversal and
hex/decimal printers) that builds and checksums a **data structure larger than
64 KB**. The program image itself stays inside one ≤64 KB CP/M-86 group, but
the data structure — 3072 records × 64 bytes = **192 KB**, three 64 KB
segments — lives *above* the program in the 1 MB real-mode address space and is
reached through explicit `__far` pointers. This is exactly how CP/M-86 lets a
program use far more than 64 KB of data: the program manages its own segment
registers (here via far pointers) to address the whole memory space (System
Guide §2.5). No linker/model change is needed — small model plus `__far` is
enough, and the emulator already maps the full 1 MB and does real segment
arithmetic.

```
./build-cpm86.sh bigdata.c
python3 cpm86run_unicorn.py BIGDATA.CMD
    ...
    sum32      = 01730B21
    crc32      = 2CA68199
    fletcher   = C3BF0B21
    ring-walk  = 0047FA00
    expected   = 0047FA00  [MATCH]
```

Everything is deterministic (fixed PRNG seed) and independently verified: the
`crc32` value matches Python's `binascii.crc32` over the same 192 KB, and the
`ring-walk` — which follows a `next` index that jumps across all three segments
in a single Hamiltonian ring — equals `N*(N-1)/2`, proving non-sequential far
pointer chasing across segment boundaries works. To avoid pulling in C runtime
helpers (this is a `-zl` freestanding image) the code uses only 16-bit
multiply/divide and 32-bit add/shift/xor — no 32-bit `mul`/`div`.

**Scope — what "run a full program" needs:** Unicorn supplies the CPU; *we*
supply the OS. `cpm86run_unicorn.py` implements the BDOS console/string group
(functions 0, 1, 2, 5, 6, 9, 10, 11) and feeds console input via
`run(path, stdin_bytes=...)`. It loads the program into a single group with
`CS = DS = ES = SS` and a full-segment stack (the CP/M-86 8080 model), which is
required for real C code that passes the address of a stack local as a
small-model *near* pointer. Disk/file functions (open/close/read/write,
15/16/20/21/…) are **not** implemented yet and raise `BdosUnimplemented` so an
unsupported program fails loudly. Note the instruction set (incl. 80186 via
`CPU=1`) is fully covered by Unicorn/QEMU; the remaining work to test "full"
programs is BDOS coverage, not CPU emulation.

## Running under a real CP/M-86 (full-machine emulators)

The bundled `cpm86run_unicorn.py` is an *instruction-level* harness: great for
fast, deterministic tests, but it has no real OS, no disk and no clock. To run
the programs under a **genuine Digital Research CP/M-86**, use a full-machine
emulator and boot a real CP/M-86 disk. This works because our programs use the
real CP/M-86 ABI — they call the BDOS through `INT 0E0h` (software interrupt
224) with the standard function numbers — so the console demos run unmodified.

Recommended emulators (in order):

1. **86Box** — the most hardware-accurate, actively maintained PC emulator
   (8086/8088/80186/80286…), with native macOS/arm64 builds. Emulates a real
   IBM PC/XT/AT; boot DR CP/M-86 and mount an image built below.
2. **QEMU** (`qemu-system-i386`) — lighter and scriptable, good for CI/
   automation; boots a CP/M-86-for-the-IBM-PC image on emulated PC hardware.
3. **MAME** — cycle-accurate IBM PC 5150 (real 8088 timing). Heavier, but the
   only option that yields a *real* Dhrystones/sec figure (see the timing note
   above) since it models true 8086 cycle timing.

Getting the OS: Digital Research CP/M-86 is now freely redistributable and its
IBM-PC disk images are available from the CP/M preservation sites
(e.g. `www.cpm.z80.de`).

Transferring the `.CMD` files onto a CP/M-86 disk image is automated with
`mkdisk-cpm86.sh` (needs [cpmtools](http://www.moria.de/~michael/cpmtools/):
`brew install cpmtools` / `apt-get install cpmtools`):

```
./mkdisk-cpm86.sh cpm86.img          # packs every *.CMD into an IBM CP/M-86 image
    Wrote cpm86.img (ibmpc-514ds):
    0:
    bigdata.cmd  dhry.cmd  echoarg.cmd  hello.cmd
```

Then mount `cpm86.img` as a drive in the emulator and run e.g. `HELLO` or
`DHRY`. The `.CMD` files round-trip through the image byte-identically, and the
image is padded to the drive's full geometry so a full-machine emulator accepts
it.

### RC759 "Piccoline" / Concurrent CP/M-86

The Regnecentralen **RC759 Piccoline** is an **80186** machine running
**Concurrent CP/M-86** — an ideal real target, and its dedicated emulator is
**PCE** by Hampa Hug (see `https://rc700.dk/emulator.php`, which also links a
browser-based build); MAME has an `rc759` driver too, though it is still marked
non-working as of 2026. Concurrent CP/M-86 is a BDOS-compatible superset, so our
`INT 0E0h` console programs run unmodified — and, unlike plain CP/M-86 1.x, it
*does* provide date/time (BDOS 104/105).

Build for the 80186 (`CPU=1`) and pack an RC759-format image:

```
CPU=1 ./build-cpm86.sh dhry.c
FORMAT=rc75x ./mkdisk-cpm86.sh rc759.img HELLO.CMD DHRY.CMD
```

`rc75x` is the RC759 geometry (77 cyl × 2 heads × 8 × 1024-byte sectors); the
script pads the image to the full 1,261,568 bytes. PCE's floppy format is
`.pbit`, so convert the raw image with the `pfdc`/`pbit` tools bundled with PCE
(the script prints the exact commands):

```
pfdc -r 0-76 0-1 1-8 -p new -e size 1024 -e mfm-hd 1 -p load rc759.img -o rc759.pfdc
pbit -p encode mfm-hd-360 rc759.pfdc -o rc759.pbit
```

then, in the emulator monitor, `-m fdc.insert 0:rc759.pbit`.

**Portability caveat:** `HELLO`, `ECHOARG` and `DHRY` use only standard BDOS
console calls and run unmodified on real CP/M-86. `BIGDATA` addresses a
*hard-coded* far segment (`0x3000`) that it does not own — fine under the bare
bundled emulator, but on a real CP/M-86 a program must obtain memory legally
(Concurrent CP/M-86 memory calls 55–58, or the free-memory info in the base
page) before using segments outside its load image. So treat `BIGDATA` as an
emulator demo, not a portable CP/M-86 program.

## Files in this proof-of-concept

| File | Purpose |
|------|---------|
| `bin2cmd.py` | raw 8086 image → CP/M-86 `.CMD` (8080 + small models, base page reserved), with tests |
| `ccp.py` | emulate the CCP: parse the command line into FCBs + command tail and build the base page |
| `hello.asm` | basic freestanding CP/M-86 hello-world (wasm, org 100h), raw BDOS (`INT 0E0h`) |
| `hello.c` | same program in C via `#pragma aux`; entry `cpmmain()` |
| `echoarg.asm` | prints the command tail — demonstrates CCP base-page setup |
| `dhry.c` | freestanding CP/M-86 port of the Dhrystone 2.1 benchmark (non-trivial C demo) |
| `bigdata.c` | large program using `__far` pointers to build and checksum a >64 KB (192 KB) data structure |
| `cpmstart.asm` | minimal C startup stub (linked first) — calls `cpmmain()`, then BDOS terminate |
| `HELLO.CMD` | ready-to-run executable (built by `build-cpm86.sh hello.asm`; byte-identical to the earlier hand-assembled reference) |
| `ECHOARG.CMD` | ready-to-run command-tail demo |
| `DHRY.CMD` | ready-to-run Dhrystone 2.1 benchmark (built by `build-cpm86.sh dhry.c`) |
| `BIGDATA.CMD` | ready-to-run >64 KB data-structure checksum demo (built by `build-cpm86.sh bigdata.c`) |
| `build-cpm86.sh` | the wasm/wcc → wl → bin2cmd pipeline (`CPU=` selects 8086/80186/…) |
| `mkdisk-cpm86.sh` | pack the `.CMD` files into a CP/M-86 disk image (cpmtools) for full-machine emulators |
| `cpm86run.py` | minimal hand-written 8086 interpreter + BDOS |
| `cpm86run_unicorn.py` | independent Unicorn/QEMU runner + BDOS console group |
| `CPM-86_Programmers_Guide_Jan83.pdf` | Digital Research reference manual (BDOS calls, `.CMD` format, base page) |
| `CPM-86_Programmers_Guide_Jan83.txt` | plain-text extraction of the manual (grep-able) |
| `CPM-86_System_Guide_Jun83.pdf` | DR System Guide — BDOS & BIOS call reference, `.CMD` format |
| `CPM-86_System_Guide_Jun83.txt` | plain-text extraction of the System Guide (grep-able) |
| `README-cpm86.md` | this document |

## Reference

`CPM-86_Programmers_Guide_Jan83.pdf` is the authoritative Digital Research
*CP/M-86 Operating System Programmer's Guide* (Jan 1983). It documents the BDOS
function numbers, the `.CMD` command-file / group-descriptor format, the base
page, and the segment/entry conventions this PoC implements. The companion
*CP/M-86 System Guide* (`CPM-86_System_Guide_Jun83.pdf`) is the reference for
the **BDOS and BIOS call interface** (function numbers, register conventions,
FCB layout). Both are mirrored from
[bitsavers](http://www.bitsavers.org/pdf/digitalResearch/cpm-86/); the CP/M
documentation was released for free non-commercial use by the copyright holder.
