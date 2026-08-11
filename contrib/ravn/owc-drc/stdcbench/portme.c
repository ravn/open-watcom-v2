/* portme.c -- stdcbench platform glue for Open Watcom C -> DR C on CP/M-86.

   Entry point is cmain (owcrt.asm bridges DR C's "main" to it, because Open
   Watcom special-cases the name "main").  See ../README.md.

   stdcbench_clock() reads the emulator's RC759 50 Hz system tick through the
   80186 timer's I/O ports, so the benchmark measures genuine elapsed
   (emulated) time at ~20 ms resolution.  The tick is deterministic (host
   independent), so scores are reproducible and reflect how much work the
   emulated 8086 completes per tick -- see STDCBENCH_CLOCKS_PER_SEC = 50. */
#include <stdio.h>
#include "stdcbench.h"

/* RC759 50 Hz system tick: a monotonic 32-bit counter read a word at a time
   from the emulated 80186 timer's I/O ports.  Reading the low word latches the
   high word, so the pair forms a consistent 32-bit value.  IN AX,DX reads a
   word from the port in DX. */
extern unsigned tick_inpw(unsigned port);
#pragma aux tick_inpw =         \
    "in ax,dx"                  \
    parm [dx]                   \
    value [ax]                  \
    modify [ax];

#define TICK_PORT_LO 0xFE00u
#define TICK_PORT_HI 0xFE02u

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
    unsigned lo = tick_inpw(TICK_PORT_LO);   /* latches the high word */
    unsigned hi = tick_inpw(TICK_PORT_HI);

    return ((stdcbench_clock_t)hi << 16) | lo;
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
