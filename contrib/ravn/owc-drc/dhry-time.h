/* time.h -- minimal <time.h> shim for building unmodified Dhrystone 2.1
   against the Digital Research C run-time on CP/M-86.

   dhry.h's MSC_CLOCK ("hi-res clock") timing path pulls in <time.h> for the
   CLK_TCK macro and the clock_t type; DR C ships neither.  We supply just
   those two.  glue.c's clock() reports the RC759 XIOS "16 ms counter"
   (Int 28h function 19) in milliseconds, so CLK_TCK is 1000.  The build copies
   this file into the work directory as time.h for the Dhrystone compile
   only. */
#ifndef _CPM86_TIME_H_SHIM
#define _CPM86_TIME_H_SHIM

typedef long clock_t;

/* glue.c's clock() returns milliseconds (16 ms resolution). */
#define CLK_TCK 1000

extern clock_t clock(void);

#endif
