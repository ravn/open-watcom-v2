/*
 * glue.c -- minimal platform glue for benchmarks built against DR C on
 * CP/M-86 under the cpm86run_unicorn emulator.
 *
 * Dhrystone's timing loop needs a clock.  Plain CP/M-86 has none, but the
 * emulator models the RC759 Piccoline's Intel 80186 timer as a monotonic
 * 50 Hz system tick, readable through I/O ports (see cpm86run_unicorn.py).
 * clock() below reports that tick, so Dhrystone measures genuine, monotonic,
 * reproducible elapsed (emulated) time at ~20 ms resolution -- far finer than
 * the 1-second T_GET clock.  Built with dhry.h's MSC_CLOCK "hi-res clock"
 * path and CLK_TCK == 50 (from the local time.h shim); the absolute
 * Dhrystones/sec depends on the emulator's clock rate (CPM86_CLOCK_HZ), so it
 * is a consistent synthetic figure that scales correctly with code efficiency.
 *
 * time() is also provided (via Concurrent CP/M-86 T_GET, BDOS 105) for any DR
 * C code that wants wall-clock seconds; Dhrystone itself uses clock().
 *
 * Declared with no leading underscore (compat.h) so DR C code that calls
 * these links against the definitions here.
 */

/* RC759 50 Hz system tick: a monotonic 32-bit counter read a word at a time
 * from the emulated 80186 timer's I/O ports.  Reading the low word latches the
 * high word, so the pair forms a consistent 32-bit value.  IN AX,DX reads a
 * word from the port in DX. */
extern unsigned tick_inpw( unsigned port );
#pragma aux tick_inpw =         \
    "in ax,dx"                  \
    parm [dx]                   \
    value [ax]                  \
    modify [ax];

#define TICK_PORT_LO 0xFE00u
#define TICK_PORT_HI 0xFE02u

long clock( void )
{
    unsigned lo = tick_inpw( TICK_PORT_LO );   /* latches the high word */
    unsigned hi = tick_inpw( TICK_PORT_HI );

    return (long)( ( (unsigned long)hi << 16 ) | lo );
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
