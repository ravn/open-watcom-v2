/* portme.c -- stdcbench platform glue for Open Watcom C -> DR C on CP/M-86.

   Entry point is cmain (owcrt.asm bridges DR C's "main" to it, because Open
   Watcom special-cases the name "main").  See ../README.md.

   stdcbench_clock() reads the emulator's Concurrent CP/M-86 date/time clock
   (T_GET, BDOS 105), so the benchmark measures genuine elapsed (emulated)
   time.  The clock has 1-second resolution and is deterministic (host
   independent), so scores are reproducible and reflect how much work the
   emulated 8086 completes per second -- see STDCBENCH_CLOCKS_PER_SEC = 1. */
#include <stdio.h>
#include "stdcbench.h"

/* CP/M-86 BDOS entry: CL = function, DX = parameter, result in AX.  T_GET
   (function 105) fills a time-of-day structure at DS:DX and returns the
   seconds field (BCD) in AL. */
extern unsigned bdos(unsigned char func, unsigned dx);
#pragma aux bdos =              \
    "int 0E0h"                  \
    parm [cl] [dx]              \
    value [ax]                  \
    modify [ax bx cx dx es];

/* T_GET's structure: word date (day 1 == 1978-01-01), then hour and minute
   as packed BCD; seconds (BCD) come back in AL. */
struct stdcbench_tod {
    unsigned      date;
    unsigned char hour;
    unsigned char minute;
};

static unsigned long stdcbench_bcd2bin(unsigned char b)
{
    return (unsigned long)((b >> 4) * 10 + (b & 0x0F));
}

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
    struct stdcbench_tod tod;
    unsigned char        seconds;

    seconds = (unsigned char)(bdos(105, (unsigned)&tod) & 0xFF);

    return (stdcbench_clock_t)tod.date * 86400ul
         + stdcbench_bcd2bin(tod.hour) * 3600ul
         + stdcbench_bcd2bin(tod.minute) * 60ul
         + stdcbench_bcd2bin(seconds);
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
