/*
 * glue.c -- minimal platform glue for benchmarks built against DR C on
 * CP/M-86 under the cpm86run_unicorn emulator.
 *
 * Dhrystone (and similar) need a time() for their timing loop.  Plain
 * CP/M-86 has no time-of-day call, but Concurrent CP/M-86 adds T_GET
 * (BDOS function 105), which our emulator implements: it returns the real
 * base date/time plus a deterministic virtual clock (proportional to the
 * code the emulated 8086 executes).  So time() below reports genuine,
 * monotonic, reproducible elapsed seconds -- the benchmark now measures
 * (emulated) time instead of a dummy counter.  The absolute Dhrystones/sec
 * depends on the emulator's clock rate (CPM86_CLOCK_HZ), so it is a
 * consistent synthetic figure rather than a hardware measurement, but it
 * scales correctly with code efficiency and the number of runs.
 *
 * Declared with no leading underscore (compat.h) so DR C code that calls
 * time() links against this definition.
 */

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
