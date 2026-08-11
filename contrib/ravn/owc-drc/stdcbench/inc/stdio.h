/* Minimal neutral <stdio.h> for stdcbench on the DR C run-time.
   Only the formatted-output functions stdcbench uses are declared; DR C's
   printf/sprintf are self-contained in clears.l86 (they manage their own
   FILE/stdout), so no FILE object is exposed here. */
#ifndef _CPM_STDIO_H
#define _CPM_STDIO_H

int printf(const char *, ...);
int sprintf(char *, const char *, ...);

#endif
