/* portme.c -- stdcbench platform glue for Open Watcom C -> DR C on CP/M-86.

   Entry point is cmain (owcrt.asm bridges DR C's "main" to it, because Open
   Watcom special-cases the name "main").  See ../README.md.

   stdcbench_clock() returns a deterministic virtual clock: each call advances
   the counter by a fixed step, so the benchmark loops a fixed number of times
   and the score is reproducible.  It does NOT reflect real elapsed time (an
   instruction-level emulator has no wall clock). */
#include <stdio.h>
#include "stdcbench.h"

/* One virtual "tick" per stdcbench_clock() call.  The benchmark loops
   do{ work } while(clock()-start < SECONDS), calling clock() once per
   iteration; SECONDS is CLOCKS_PER_SEC*8 (c90base) and *40 (c90lib).  A
   step >= the largest SECONDS makes every module run exactly one iteration,
   which keeps the emulated run short while still producing the fixed,
   reproducible scores (c90base = 2, c90lib = 10). */
#define STDCBENCH_TICK_STEP 40000ul

unsigned long stdcbench_virtual_clock;

/* --- Heap base fix for DR C on this hybrid Open-Watcom/DR-C link ---------
   DR C's heap pointer HP. is initialised (in m.init.heap) from the BSS word
   ?MEMRY, which nothing in the run-time ever sets, so it starts at 0.  That
   makes malloc() hand out DGROUP offset ~0, on top of the program's static
   data: small allocations happen to survive (Dhrystone's two records), but
   any larger buffer corrupts static data.  We repair this before the first
   allocation by pointing the heap at a private static arena via DR C's
   brk(): malloc() then grows upward inside the arena instead of over our
   data.  The arena is far larger than the measured peak use (stdcbench's
   high-water mark is ~1536 bytes, verified via sbrk(0)), so every
   allocation stays strictly inside the array and can touch nothing else. */
extern int brk(void *addr);           /* DR C run-time (clears.l86) */
static char stdcbench_heap[20480];

static void stdcbench_init_heap(void)
{
    brk(stdcbench_heap);
}

stdcbench_clock_t stdcbench_clock(void)
{
    stdcbench_virtual_clock += STDCBENCH_TICK_STEP;
    return (stdcbench_clock_t)stdcbench_virtual_clock;
}

void stdcbench_error(const char *message)
{
    printf("ERROR: %s\n", message);
}

int cmain(void)
{
    unsigned long score;

    stdcbench_init_heap();

    printf("\n%s\n", stdcbench_name_version_string);
    score = stdcbench();
#ifdef C90BASE
    printf("stdcbench c90base score: %lu\n", c90base_score);
#endif
#ifdef C90LIB
    printf("stdcbench c90lib score: %lu\n", c90lib_score);
#endif
    printf("stdcbench final score: %lu\n", score);
    return 0;
}
