/* time.h -- minimal <time.h> shim for building unmodified Dhrystone 2.1
   against the Digital Research C run-time on CP/M-86.

   dhry.h's MSC_CLOCK ("hi-res clock") timing path pulls in <time.h> for the
   CLK_TCK macro and the clock_t type; DR C ships neither.  We supply just
   those two, matching the emulated RC759 50 Hz system tick that glue.c's
   clock() reads through the 80186 timer's I/O ports.  The build copies this
   file into the work directory as time.h for the Dhrystone compile only. */
#ifndef _CPM86_TIME_H_SHIM
#define _CPM86_TIME_H_SHIM

typedef long clock_t;

/* Emulated RC759 system tick rate (see cpm86run_unicorn.py CPM86_TICK_HZ). */
#define CLK_TCK 50

extern clock_t clock(void);

#endif
