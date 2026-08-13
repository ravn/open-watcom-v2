/* portme.c -- stdcbench platform glue for Open Watcom C -> DR C on CP/M-86.

   Entry point is cmain (owcrt.asm bridges DR C's "main" to it, because Open
   Watcom special-cases the name "main").  See ../README.md.

   stdcbench_clock() reads the RC759 XIOS "16 ms counter" (Int 28h function 19,
   per the PICCOLINE Programmer's Guide), the machine's documented fine
   relative-time source, so the benchmark measures genuine elapsed (emulated)
   time at 16 ms resolution.  The counter is deterministic (host independent),
   so scores are reproducible.  We express it in milliseconds, hence
   STDCBENCH_CLOCKS_PER_SEC = 1000 (values step by 16). */
#include <stdio.h>
#include "stdcbench.h"

/* RC759 XIOS Int 28h function 19 ("Returns 16 ms counter"): on entry AL = 19;
   on return DX:AX = seconds since boot and CX = elapsed 16 ms periods of the
   current second.  We copy the three words into a struct via BX (small model:
   DS-relative). */
struct xios_tick { unsigned lo, hi, per; };
extern void xios_tick16(struct xios_tick *t);
#pragma aux xios_tick16 =       \
    "mov al,19"                 \
    "int 28h"                   \
    "mov [bx],ax"               \
    "mov [bx+2],dx"             \
    "mov [bx+4],cx"             \
    parm [bx]                   \
    modify [ax cx dx];

#define XIOS_TICK_MS 16u

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
    /* MUST be static (i.e. in DGROUP/DS), not a stack local.  The xios_tick16
       pragma stores its result with `mov [bx],ax`, which is DS-relative.  In
       the LARGE model DS != SS (verified: DS=1EA9 vs SS=36A9), so a stack-local
       struct would be written through DS at the wrong linear address and read
       back as stack garbage -- c90base()'s timed do-while (run until elapsed >=
       8 s) would then never see time advance and spin forever (the XIOS INT 28h
       still fires, but t.lo/hi/per are stale).  A static struct lives in DS, so
       the DS-relative store lands on it in BOTH models.  Small model was fine
       either way because there SS == DS == DGROUP. */
    static struct xios_tick t;
    unsigned long    secs;

    xios_tick16(&t);
    secs = ((unsigned long)t.hi << 16) | t.lo;

    return secs * 1000ul + (unsigned long)t.per * XIOS_TICK_MS;
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
