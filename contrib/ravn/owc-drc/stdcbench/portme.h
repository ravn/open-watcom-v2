/* portme.h -- stdcbench port for Open Watcom C -> Digital Research C
   run-time on CP/M-86, run under an instruction-level emulator.

   stdcbench_clock() (in portme.c) reads the emulator's RC759 50 Hz system
   tick (the emulated 80186 timer), so the benchmark measures genuine elapsed
   (emulated) time at ~20 ms resolution.  The tick is deterministic, so scores
   are reproducible; STDCBENCH_CLOCKS_PER_SEC is 50 to match the tick rate.
   Tune the emulated CPU speed via CPM86_CLOCK_HZ -- see ../README.md and the
   build script. */
typedef unsigned long stdcbench_clock_t;
#define STDCBENCH_CLOCKS_PER_SEC 50ul

#define C90BASE
#undef  C90FLOAT
#undef  C90DOUBLE
#define C90LIB
