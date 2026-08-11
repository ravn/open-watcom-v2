/* portme.h -- stdcbench port for Open Watcom C -> Digital Research C
   run-time on CP/M-86, run under an instruction-level emulator.

   There is no wall clock, so stdcbench_clock() (in portme.c) returns a
   deterministic virtual counter.  The reported score is therefore a fixed,
   reproducible figure that reflects a constant iteration count rather than
   real time -- like the dummy timer used for Dhrystone in this deliverable. */
typedef unsigned long stdcbench_clock_t;
#define STDCBENCH_CLOCKS_PER_SEC 1000ul

#define C90BASE
#undef  C90FLOAT
#undef  C90DOUBLE
#define C90LIB
