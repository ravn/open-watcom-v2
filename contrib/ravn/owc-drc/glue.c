/*
 * glue.c -- minimal platform glue for benchmarks built against DR C on
 * CP/M-86 under the cpm86run_unicorn emulator.
 *
 * Dhrystone's timing loop needs a clock.  Plain CP/M-86 has none; the RC759
 * Piccoline offers a one-second real-time clock (read via Concurrent CP/M-86
 * T_GET) and, for finer relative timing, the XIOS "16 ms counter" reached
 * through Int 28h function 19 (PICCOLINE Programmer's Guide, App. A).  The
 * emulator models that call, so clock() below reports genuine, monotonic,
 * reproducible elapsed (emulated) time in milliseconds at 16 ms resolution --
 * the finest a real RC759 program can obtain.  Built with dhry.h's MSC_CLOCK
 * "hi-res clock" path and CLK_TCK == 1000 (from the local time.h shim); the
 * absolute Dhrystones/sec depends on the emulator's clock rate
 * (CPM86_CLOCK_HZ), so it is a consistent synthetic figure that scales
 * correctly with code efficiency.
 *
 * time() is also provided (via Concurrent CP/M-86 T_GET, BDOS 105) for any DR
 * C code that wants wall-clock seconds; Dhrystone itself uses clock().
 *
 * Declared with no leading underscore (compat.h) so DR C code that calls
 * these links against the definitions here.
 */

/* RC759 XIOS Int 28h function 19 ("Returns 16 ms counter"): on entry AL = 19;
 * on return DX:AX = seconds since boot and CX = elapsed 16 ms periods of the
 * current second.  We copy the three words into a struct via BX (small model:
 * DS-relative). */
struct xios_tick { unsigned lo, hi, per; };
extern void xios_tick16( struct xios_tick *t );
#pragma aux xios_tick16 =       \
    "mov al,19"                 \
    "int 28h"                   \
    "mov [bx],ax"               \
    "mov [bx+2],dx"             \
    "mov [bx+4],cx"             \
    parm [bx]                   \
    modify [ax cx dx];

#define XIOS_TICK_MS 16u

long clock( void )
{
    struct xios_tick t;
    unsigned long    secs;

    xios_tick16( &t );
    secs = ( (unsigned long)t.hi << 16 ) | t.lo;

    return (long)( secs * 1000ul + (unsigned long)t.per * XIOS_TICK_MS );
}

/* CP/M-86 BDOS entry: CL = function, DX = parameter, result in AX.  T_GET
 * (function 105) fills a time-of-day structure at DS:DX and returns the
 * seconds field (BCD) in AL. */
extern unsigned bdos( unsigned char func, unsigned dx );
#pragma aux bdos =              \
    "int 0E0h"                  \
    parm [cl] [dx]              \
    value [ax]                  \
    modify [ax bx cx dx es];

#define BDOS_T_GET 105

/* T_GET's structure: word date (day 1 == 1978-01-01), then hour and minute
 * as packed BCD; seconds (BCD) come back in AL. */
struct cpm_tod {
    unsigned      date;
    unsigned char hour;
    unsigned char minute;
};

/* Non-static on purpose: Open Watcom emits a "static extdef" OMF record
 * (type 0xB4) for file-scope statics that DR LINK-86 rejects with OBJECT
 * FILE ERROR 5 (the dhry link does not post-process objects). */
long owc_bcd2bin( unsigned char b )
{
    return (long)((b >> 4) * 10 + (b & 0x0F));
}

long time( long *p )
{
    struct cpm_tod tod;
    unsigned char  seconds;

    seconds = (unsigned char)( bdos( BDOS_T_GET, (unsigned)&tod ) & 0xFF );

    if( p != 0 )
        *p = 0L;

    return (long)tod.date * 86400L
         + owc_bcd2bin( tod.hour ) * 3600L
         + owc_bcd2bin( tod.minute ) * 60L
         + owc_bcd2bin( seconds );
}
