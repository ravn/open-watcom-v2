/*
 * glue.c -- minimal platform glue for benchmarks built against DR C on
 * CP/M-86 under an instruction-level emulator.
 *
 * Dhrystone (and similar) need a time() for their timing loop.  Plain
 * CP/M-86 has no standard time-of-day/clock call and an instruction-level
 * emulator has no wall clock, so we provide a deterministic DUMMY timer.
 * It returns a monotonically increasing value; the reported Dhrystones/sec
 * is therefore meaningless, but the benchmark runs to completion and its
 * self-check output is valid.  Replace with a real BDOS/CCP/M clock read
 * when running on hardware or a full machine emulator.
 *
 * Declared with no leading underscore (compat.h) so DR C code that calls
 * time() links against this definition.  Note: a non-static global is used
 * on purpose -- Open Watcom emits a "static extdef" OMF record (type 0xB4)
 * for file-scope statics that DR LINK-86 rejects with OBJECT FILE ERROR 5.
 */
long owc_drc_ticks;

long time(long *p)
{
    (void)p;
    owc_drc_ticks += 100L;
    return owc_drc_ticks;
}
