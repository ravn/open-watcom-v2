/* portme.c -- stdcbench platform glue for Open Watcom C -> DR C on CP/M-86.

   Entry point is cmain (owcrt.asm bridges DR C's "main" to it, because Open
   Watcom special-cases the name "main").  See ../README.md.

   stdcbench_clock() reads the elapsed time via the standard Concurrent CP/M-86
   BDOS call T_SECONDS (function 155 / 0x9B), NOT the PICCOLINE-specific XIOS
   "16 ms counter" (Int 28h fn 19).  Rationale (verified 2026-08-14): on the
   real RC759 turnkey disk under Concurrent CP/M-86 3.1, the XIOS does NOT
   maintain the Int 28h fn 19 counter -- clktest read it four ways (busy loop,
   20000 syscalls, busy again) and every field stayed 0, so the timed loop
   spun forever and stdcbench hung after its banner.  The ordinary BDOS
   time-of-day DOES advance (the CCP/M status-line clock ticks), so we read
   that instead.  Policy: use only BDOS (INT 0E0h) calls here, no XIOS calls.

   T_SECONDS returns a TOD structure {day: word since 1-Jan-1978; hour, min,
   sec: 2 BCD digits each}.  Resolution is 1 second -- coarser than the old
   16 ms, but the c90base/c90lib score formula divides by the *actual* measured
   elapsed (SECONDS / (end - start)), so a whole-second granularity over the 8 s
   window only quantises the result, it does not bias it.  We report the time in
   milliseconds (total_seconds * 1000), hence STDCBENCH_CLOCKS_PER_SEC = 1000.
   The absolute value is large (it includes the day count) but we only ever use
   differences, which are correct under unsigned-long modular arithmetic. */
#include <stdio.h>
#include "stdcbench.h"

/* Concurrent CP/M-86 T_SECONDS (BDOS fn 155 / 0x9B): entry CL = 155, DX = TOD
   offset, DS = TOD segment; fills the 5-byte TOD structure below.  We pass the
   struct address in BX and move it to DX; DS already addresses DGROUP (the
   struct is static), which is the required segment in both memory models. */
struct tod { unsigned day; unsigned char hour, min, sec; };
extern void t_seconds(struct tod *t);
#pragma aux t_seconds =         \
    "mov cl,155"                \
    "mov dx,bx"                 \
    "int 0E0h"                  \
    parm [bx]                   \
    modify [ax bx cx dx];

/* 2 BCD digits packed in one byte -> binary (e.g. 0x59 -> 59). */
#define BCD2BIN(b) ((unsigned)(((b) >> 4) * 10u + ((b) & 0x0Fu)))

#ifdef MAME_DONE
/* When built with -DMAME_DONE, signal the MAME rc759 host that the run has
   finished by writing the score to undecoded I/O port 0x2FE (see
   scratch/rc759-cmd-toolchain/mame-tests/mamedone.h + done_signal.lua). The
   port is not decoded by the rc759 driver, so the OUT is side-effect-free on
   hardware; a MAME io-space write-tap catches it and stops the emulator exactly
   when the benchmark ends, so we need not eyeball a fixed timer. Omitted from
   the Unicorn/emu2 build (no -DMAME_DONE) since those runners need no signal. */
extern void mame_done(unsigned status);
#pragma aux mame_done =         \
    "mov dx,02FEh"              \
    "out dx,ax"                 \
    parm [ax]                   \
    modify [dx];
#endif

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
    /* MUST be static (i.e. in DGROUP/DS), not a stack local.  t_seconds passes
       DS as the TOD segment and the BDOS writes the structure there; a static
       struct lives in DGROUP, which DS addresses in BOTH memory models, so the
       fill lands on it.  (A stack local would be in the SS segment, which in
       the LARGE model differs from DS, so the BDOS would write it elsewhere and
       we would read back stale garbage -- the timed loop would then never see
       time advance and spin forever.) */
    static struct tod t;
    unsigned long     secs;

    t_seconds(&t);
    /* Fold day:hour:min:sec into a single monotonically increasing second
       count.  Only differences are ever used, so the large magnitude (the day
       term dominates) is harmless under unsigned-long modular subtraction. */
    secs = ((((unsigned long)t.day * 24ul + BCD2BIN(t.hour)) * 60ul)
            + BCD2BIN(t.min)) * 60ul + BCD2BIN(t.sec);

    return secs * 1000ul;
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
#ifdef MAME_DONE
    /* Encode the final score in the signal word so the host reports it without
       OCR (e.g. score 12 -> word 0x000C). Must be after the last printf. */
    mame_done((unsigned)score);
#endif
    return 0;
}
