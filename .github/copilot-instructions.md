# Open Watcom v2 — Copilot Instructions

Open Watcom v2 is a large (2M+ LOC), self-hosting C/C++/Fortran compiler and
tools suite spanning DOS, Windows (16/32/64-bit), OS/2, and *nix hosts. The
codebase is old, portable, and highly convention-driven. Read this before
making changes.

## Environment setup (required before any build)

Everything is driven by environment variables loaded from `setvars` +
`cmnvars`. Never build without sourcing them first.

- Copy `setvars.sh` (or `setvars.bat`/`.cmd` on Windows/OS2) and edit it, or
  just source it — it defaults `OWROOT` to the current directory.
- Key variables: `OWROOT` (source tree root — **no `=` or spaces in the
  path**), `OWTOOLS` (`GCC` | `CLANG` | `WATCOM` | `VISUALC`), `OWOBJDIR`
  (build-tools output dir, default `binbuild`), `OWRELROOT` (ship/`rel` dir).
- `setvars.sh` sources `cmnvars.sh` at the end; `cmnvars` sets `PATH`,
  version vars (`OWBLDVER`), and detects the toolchain version.

## Build

Two-phase, bootstrapping build:

1. **Phase 1 (bootstrap):** the host's native compiler (gcc/clang/etc.)
   builds `wmake` and the `builder` tool into `build/$OWOBJDIR/`.
2. **Phase 2:** `builder` reads `*.ctl` scripts and builds the OW tools with
   the just-built (or existing) OW tools.

Commands (from `OWROOT`, after sourcing setvars):

- Full build: `./build.sh` (Unix) / `build.bat` (Windows) / `build.cmd` (OS2).
- Bootstrap only: `./build.sh boot`  (or `preboot` for just wmake+builder).
- Clean: `./clean.sh` / `clean.bat` / `clean.cmd`.
- The top-level `builder` rule is defined in `bld/builder.ctl`, which
  `INCLUDE`s each project's `builder.ctl` in a **dependency-significant
  order** — do not reorder those includes casually.

Per-project builds: `cd bld/<project>` then invoke `builder <rule>` (e.g.
`builder build`, `builder clean`, `builder rel`, `builder boot`). Rules are
defined in `build/master.ctl` and the project's `builder.ctl`.

## Test

Tests are OW projects too, listed in `.github/workflows/tests.yml`. Each is a
`bld/*test` directory with its own `builder.ctl` exposing a `test` rule
(typically wrapping `wmake -h`).

Test suites (project dir → what it tests):
`ctest` (C), `plustest` (C++), `f77test` (Fortran), `clibtest` (C runtime),
`mathtest` (math lib), `wmaktest` (wmake), `wasmtest` (assembler).

Run one suite: `cd bld/ctest && builder test` (and `builder testclean` /
`builder cleanlog` to reset). Inside a suite, sub-areas (e.g.
`ctest/positive`, `ctest/codegen`) each have their own `builder.ctl` and can
be run from that subdirectory.

## Architecture / big picture

- `bld/` — one subdirectory per project (compiler, linker, libraries, tools).
  See `projects.txt` for the annotated map (e.g. `cc`=C compiler,
  `plusplus`=C++ compiler, `cg`=code generator, `wl`=linker, `wmake`=make,
  `clib`/`mathlib`=runtime libs, `wv`=debugger, `vi`=editor).
- `build/` — the build system: `master.ctl` (shared builder rules),
  `*.ctl` fragments (`deflib.ctl`, `deftool.ctl`, `deftest.ctl`, …),
  `makeinit`, and awk helpers. `build/$OWOBJDIR/` holds phase-1 tools.
- `docs/` — documentation sources (GML) and doc-build tooling; building docs
  is optional and gated by `OWDOCBUILD`/`OWNOWGML` (needs WGML via DOSBOX and
  platform-specific help compilers — see `docs/howto.txt`).
- `contrib/` — third-party code (DOS extenders, zlib, libzip), not core OW.
  - `contrib/ravn/` — this fork's CP/M-86 experiments: building and running
    CP/M-86 programs with Open Watcom and the genuine Digital Research C
    run-time. Self-contained (own `README-cpm86.md`); does **not** touch the
    core OW build. Key pieces: `bin2cmd.py`/`ccp.py` (raw image → `.CMD` +
    base-page/CCP emulation), `cpm86run_unicorn.py` (Unicorn-based CP/M-86 +
    BDOS runner), `owc-drc/` (Watcom C linked against the DR C libc), and
    `pure-drc/` (the genuine DR C v1.11 compiler). DRI/toolchain binaries and
    disk images are copyright and gitignored.
- `distrib/` — installer/packaging manifests and scripts.
- `ci/` + `.github/workflows/` — CI drives the same `build.sh`/`buildx.sh`
  flow across host matrices; `cibuild.yml` bootstraps from prior OW releases.
- `rel/` — created on the fly; where built, shippable output lands
  (`OWRELROOT`).

## Key conventions

- **`.ctl` files are the build DSL.** `builder` interprets them:
  `[ INCLUDE ... ]`, `[ BLOCK <cond> <rule> ]`, `set VAR=...`, `<OWROOT>` /
  `<OWOBJDIR>` / `<BLD_HOST>` substitutions. New buildable code needs a
  `builder.ctl` wired into the parent `builder.ctl`, usually via the shared
  `deflib`/`deftool`/`deftest` templates in `build/`.
- **`.mif` files** are wmake include fragments (object lists, rules) pulled
  into makefiles; object lists use the `&` line-continuation and `.obj` names.
- **C/C++ style (`docs/doc/cstyle/cstyle.txt`, enforced on contributions):**
  4-space indentation, spaces only — **never hard tabs**; target ~80 col
  lines; lowercase 8.3 file names; every module starts with the standard
  Open Watcom / Sybase license header block with a `Description:` line.
- **Portability first.** Code targets many hosts/targets guarded by macros
  (`__LINUX__`, `__OSX__`, `__NT__`, `__OS2__`, `__DOS__`, etc.). Keep host
  conditionals in `.ctl`/`.mif`/source consistent with existing patterns.
- **Line endings** are governed by `.gitattributes`: most sources are
  normalized text; `*.bat` is forced CRLF; a handful of encoding-sensitive
  files are marked binary. Don't fight these.
- Separate formatting-only changes from functional changes; prefer
  reformatting a whole (sub)project over a single file.
