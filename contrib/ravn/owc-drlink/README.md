# Open Watcom C → CP/M-86 via DR LINK86

This directory demonstrates — with reproducible, verified test cases — that
**Open Watcom can generate object code that links against an existing CP/M-86
runtime, using that runtime's own (OMF) linker**, with *no* object-format
conversion and *no* `bin2cmd.py` post-processing.

It is the "linkable against an existing runtime" counterpart to the freestanding
pipeline in `../build-cpm86.sh` (which links to a flat raw binary with `wl` and
wraps it in a hand-built `.CMD` header).

## The key result

```
Open Watcom C   (bwcc -ms -s -zl -ecc)  → HELLO.OBJ  ┐
                                                      ├→ DR LINK86 → HELLO.CMD → CP/M-86
tiny OMF runtime (bwasm crt.asm)        → CRT.OBJ   ┘
```

`HELLO.CMD` runs on CP/M-86 and prints:

```
Hello from Open Watcom C via DR LINK86 on CP/M-86
```

Build + run it (after prerequisites below):

```sh
./build-owc-drlink.sh
```

## Why this works — the facts (all verified)

The question was whether Watcom output is compatible with an existing runtime.
Two independent axes matter: the **object/container format** and the **ABI**.

### 1. Object format: Watcom OMF is consumed by DR LINK86 as-is

Open Watcom emits Intel/Microsoft **OMF**. Digital Research's `LINK86` (the
native CP/M-86 cross linker, v2.02, part of the `cpm86-crossdev` submodule's DR
tools) reads Watcom `.obj` files directly and emits a proper `.CMD` with correct
group descriptors. Verified by assembling a trivial object with `bwasm` and
linking it with `linkcmd.exe` → a runnable `.CMD`.

By contrast, the **Aztec** C runtime (`c86.lib`, `begin86.o`) is *not* OMF — its
objects begin with the magic bytes `66 54` (`"fT…"`, e.g. `fTbegin`) and Watcom's
OMF tools reject them. So Aztec's libraries can only be used via Aztec's own
`ln`, not mixed with Watcom objects.

### 2. ABI: `-ecc` makes Watcom emit classic cdecl

Watcom's default `__watcall` passes arguments in registers and decorates symbols
with a *trailing* underscore (`foo_`). Compiling with **`-ecc`** switches to
**cdecl**: arguments pushed right-to-left on the stack, caller cleans up,
*leading*-underscore names (`_foo`) — exactly the classic K&R/C runtime ABI.
Verified by disassembly:

```
__watcall  bar_:  push dx; mov dx,4; mov ax,3; call foo_        ; args in regs
cdecl (-ecc) _bar: mov ax,4; push ax; mov ax,3; push ax;
                   call _foo; add sp,4                          ; args on stack
```

### 3. Two Watcom gotchas the demo works around

* **Do not name the entry `main`.** With `main`, Watcom exports `main_` (register
  decoration, ignoring `-ecc`) *and* emits a reference to its own C startup
  `_cstart_`, which drags in the DOS-hosted Watcom runtime. Using a plain name
  (here `cmain`) keeps it cdecl and self-contained. (`../build-cpm86.sh` sidesteps
  the same issue by calling its entry `cpmmain`.)
* **DR LINK86 has a short OMF THEADR (module-name) limit.** The Watcom compiler
  fills THEADR with the *absolute* source path; a long path (e.g. a macOS
  `/var/folders/…` temp dir, ~80 chars) makes LINK86 fail with
  `OBJECT FILE ERROR 10` at the THEADR record. The build script therefore compiles
  from a short `/tmp/owcdr.XXXX` work dir with bare filenames.

### BDOS convention

`crt.asm` invokes CP/M-86 BDOS via `INT 0E0h` (function in `CL`): function 2 =
console output (`DL`), function 0 = `P_TERMCPM`. This is the **same** BDOS
convention as `../cpmstart.asm` and as Aztec's `c86.lib`.

## What this means for "compatible with an existing runtime"

* The **container barrier is gone** for any runtime that is in OMF form: Watcom
  `-ecc` objects link with DR `LINK86` straight into a `.CMD`.
* `crt.asm` here is a *minimal* runtime (entry + one `putstr`), not a full libc.
  To use a *complete* existing C runtime you need one **in OMF** (e.g. a DR C /
  C86-class library). The Aztec runtimes are close references but are in Aztec's
  own object format, so they would first require an Aztec-object → OMF translator.
* Caveat: Watcom's compiler may emit calls to its own helper routines (long
  arithmetic, structure copy, stack-overflow `__STK` — the latter disabled by
  `-s`). Programs that use such features need those helpers provided; a
  console-only `printf`-style program like this one does not.

## Prerequisites

1. Built Open Watcom cross-tools (`bwcc`/`bwasm`, or `wcc`/`wasm` on `PATH`) —
   run the repo's top-level `./build.sh`.
2. The `contrib/ravn/cpm86-crossdev` submodule populated with the DR tools and
   `emu2` (and `cpm86` for running):

   ```sh
   cd ../cpm86-crossdev
   ./src/fetch/buildemu2      # builds bin/emu2
   ./src/fetch/drtools        # fetches share/pcdev/linkcmd.exe, lib86.exe
   # (for running: ./src/fetch/aztec34 + ./src/fetch/buildcpm86 → share/emu/cpm86.exe)
   ```

   The fetched binaries live under the submodule's gitignored `share/`, `bin/`
   and `archive/` — they are **not** committed.

## Files

| File | Purpose |
|------|---------|
| `hello.c` | Demo C program; entry `cmain()` calls `putstr()`. |
| `crt.asm` | Minimal OMF CP/M-86 runtime (entry + BDOS `putstr`). |
| `build-owc-drlink.sh` | Compile (Watcom) → link (DR LINK86) → run (cpm86). |
