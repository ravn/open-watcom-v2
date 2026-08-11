/* portme.h -- stdcbench port for Open Watcom C -> Digital Research C
   run-time on CP/M-86, run under an instruction-level emulator.

   stdcbench_clock() (in portme.c) currently returns a deterministic virtual
   counter, so the reported score is a fixed, reproducible figure reflecting a
   constant iteration count rather than elapsed time.  (Dhrystone's glue.c has
   since been switched to the emulator's real Concurrent CP/M-86 T_GET clock;
   stdcbench could be rewired the same way -- see issue #3.) */
typedef unsigned long stdcbench_clock_t;
#define STDCBENCH_CLOCKS_PER_SEC 1000ul

#define C90BASE
#undef  C90FLOAT
#undef  C90DOUBLE
#define C90LIB
