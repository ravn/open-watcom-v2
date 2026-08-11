/* portme.h -- stdcbench port for Open Watcom C -> Digital Research C
   run-time on CP/M-86, run under an instruction-level emulator.

   stdcbench_clock() (in portme.c) reads the RC759 XIOS "16 ms counter"
   (Int 28h function 19), the machine's documented fine relative-time source,
   and returns milliseconds, so the benchmark measures genuine elapsed
   (emulated) time at 16 ms resolution.  The counter is deterministic, so
   scores are reproducible; STDCBENCH_CLOCKS_PER_SEC is 1000 (ms).  Tune the
   emulated CPU speed via CPM86_CLOCK_HZ -- see ../README.md and the build
   script. */
typedef unsigned long stdcbench_clock_t;
#define STDCBENCH_CLOCKS_PER_SEC 1000ul

#define C90BASE
#undef  C90FLOAT
#undef  C90DOUBLE
#define C90LIB
