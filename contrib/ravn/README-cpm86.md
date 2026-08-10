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

**Entry & segment convention (verified against the DR System Guide):** in the
8080 model the loader jumps to **`CS:0000`** (unlike CP/M-80's `.COM`, which
starts at `0100h`), with the code group as the single segment. The base page
lives at `DS:0000`. The entry code therefore **forces `DS = CS`**
(`push cs` / `pop ds`) so the `$`-string — which lives in the same group — is
addressable no matter how the loader set `DS`.

- `hello.asm` (wasm) is the recommended starting point: entry is guaranteed at
  offset 0 (`org 0`), no toolchain layout assumptions.
- `hello.c` shows the same thing in C via a `#pragma aux` BDOS call, for once a
  C runtime is added later.

### Ready-to-run artifact: `HELLO.CMD`

`HELLO.CMD` in this folder is a **complete, runnable** CP/M-86 executable built
by hand-assembling `hello.asm` and wrapping it with `bin2cmd.py` — so you can
test the pipeline in an emulator before building the OW toolchain. Layout:

```
0000: 01 03 00 00 00 03 00 ff 0f ...   ; Code group, 3 paragraphs, relocatable
0080: 0e 1f ba 0d 00 b1 09 cd e0       ; push cs; pop ds; mov dx,msg; mov cl,9; int E0h
      b1 00 cd e0                       ; mov cl,0; int E0h
      "Hello, CP/M-86 from Open Watcom!\r\n$"
```

## What is still required

1. **A built OW toolchain** — run the repo's `./build.sh` (after sourcing
   `setvars.sh`) so `wcc`/`wl` are on `PATH`. Not attempted here (heavy build;
   this host is arm64 macOS).
2. **A CP/M-86 runtime** if you want the standard C library (stdio, malloc,
   `printf`). That means a CP/M-86 startup stub (`_cstart_`) plus a BDOS-based
   shim replacing clib's INT 21h calls. Freestanding code (own BDOS calls, as
   in `hello.c`) needs none of this and is the right first milestone.
3. **Validation** in a CP/M-86 emulator (86Box, PCem, or a CP/M-86 VM). The
   `.CMD` structure is unit-tested, but real-hardware/emulator execution has
   not been performed.

## Files in this proof-of-concept

| File | Purpose |
|------|---------|
| `bin2cmd.py` | raw 8086 image → CP/M-86 `.CMD` (8080 + small models), with tests |
| `hello.asm` | basic freestanding CP/M-86 hello-world (wasm), raw BDOS (`INT 0E0h`) |
| `hello.c` | same program in C via `#pragma aux`, for when a C runtime is added |
| `HELLO.CMD` | ready-to-run executable (hand-assembled `hello.asm` + `bin2cmd`) |
| `build-cpm86.sh` | the wasm/wcc → wl → bin2cmd pipeline |
| `README-cpm86.md` | this document |
