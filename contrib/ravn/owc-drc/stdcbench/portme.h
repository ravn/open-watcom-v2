/* portme.h -- stdcbench port for Open Watcom C -> Digital Research C
   run-time on CP/M-86, run under an instruction-level emulator.

   stdcbench_clock() (in portme.c) reads the emulator's Concurrent CP/M-86
   date/time clock (T_GET, BDOS 105), so the benchmark measures genuine
   elapsed (emulated) time.  The clock is deterministic, so scores are
   reproducible; STDCBENCH_CLOCKS_PER_SEC is 1 because T_GET resolves to one
   second.  The run needs a high enough CPM86_CLOCK_HZ that an iteration fits
   its timing window -- see ../README.md and the build script. */
typedef unsigned long stdcbench_clock_t;
#define STDCBENCH_CLOCKS_PER_SEC 1ul

#define C90BASE
#undef  C90FLOAT
#undef  C90DOUBLE
#define C90LIB
