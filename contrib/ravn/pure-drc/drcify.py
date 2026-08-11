#!/usr/bin/env python3
"""Transform stock Dhrystone 2.1 sources into a form the genuine Digital
Research C v1.11 compiler (CP/M-86, April 1984) accepts.

This is *pure* DR C: the real DRI compiler (drc.cmd) and DR LINK-86 building
against the real DR C run-time (clears.l86) -- no Open Watcom involved. The
benchmark computation is left completely untouched; only the host/OS glue that
DR C 1.11 cannot handle is adjusted:

  * <sys/times.h> / times() -- DR C for CP/M-86 has no UNIX process timer.
    We disable the TIMES/TIME/MSC_CLOCK paths so Begin_Time/End_Time stay 0 and
    the benchmark takes its own "Measured time too small" branch (no clock, no
    float division, no divide-by-zero).  Correctness is proven by the final
    variable values, which are clock-independent.

  * HZ -- referenced by the (now dead) timing-math else branch; define it so
    that branch still compiles.

  * NOSTRUCTASSIGN -- DR C 1.11 raises "Error 66: Internal compiler error.
    Unknown pointer size" on a plain C struct assignment (`*a = *b`).  The
    benchmark already ships a memcpy-based structassign() under this macro, so
    enabling it sidesteps the compiler bug.  (clears.l86 has no memcpy(), but
    dhry_1.c defines its own under NOSTRUCTASSIGN.)

  * NOENUM -- use `typedef int Enumeration` instead of a real enum, which the
    1984 compiler handles more reliably.  Output is identical.

  * scanf() for the run count -- replaced by a fixed count so the run is
    deterministic and needs no console input in either emulator.

Usage: drcify.py SRC_DIR OUT_DIR [RUNS]
  SRC_DIR must contain stock dhry.h, dhry_1.c, dhry_2.c (Dhrystone 2.1).
  OUT_DIR receives DR C-buildable dhry.h, dhry_1.c, dhry_2.c.
"""
import os
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: drcify.py SRC_DIR OUT_DIR [RUNS]")
    src, out = sys.argv[1], sys.argv[2]
    runs = int(sys.argv[3]) if len(sys.argv) > 3 else 200
    os.makedirs(out, exist_ok=True)

    # --- dhry.h -----------------------------------------------------------
    h = open(os.path.join(src, "dhry.h")).read()
    # Do not let dhry.h force the UNIX "times" path on.
    h = h.replace("#ifndef TIME\n#undef TIMES\n#define TIMES\n#endif",
                  "/* timing macros disabled for CP/M-86 DR C */")
    # Compile-time knobs DR C 1.11 needs (see module docstring).
    h = ("#define NOENUM 1\n"
         "#define Too_Small_Time 2\n"
         "#define HZ 60\n"
         "#define NOSTRUCTASSIGN 1\n") + h
    open(os.path.join(out, "dhry.h"), "w").write(h)

    # --- dhry_1.c ---------------------------------------------------------
    c1 = open(os.path.join(src, "dhry_1.c")).read()
    c1 = c1.replace(
        '''  printf ("Please give the number of runs through the benchmark: ");
  {
    int n;
    scanf ("%d", &n);
    Number_Of_Runs = n;
  }''',
        '''  printf ("Please give the number of runs through the benchmark: ");
  Number_Of_Runs = %d;   /* fixed for a deterministic CP/M-86 run */
  printf ("%%d\\n", Number_Of_Runs);''' % runs)
    open(os.path.join(out, "dhry_1.c"), "w").write(c1)

    # --- dhry_2.c (verbatim) ---------------------------------------------
    open(os.path.join(out, "dhry_2.c"), "w").write(
        open(os.path.join(src, "dhry_2.c")).read())

    print("drcify: wrote DR C-buildable dhry.[h|_1.c|_2.c] to", out,
          "(RUNS=%d)" % runs)


if __name__ == "__main__":
    main()
