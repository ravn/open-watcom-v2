/* Minimal neutral <stdlib.h> matching the Digital Research C run-time ABI.
   strtol is NOT in DR C (pre-ANSI) and is supplied by cpmlibc.c. */
#ifndef _CPM_STDLIB_H
#define _CPM_STDLIB_H
#include <stddef.h>

/* Provided by DR C (clears.l86) */
void  *malloc(size_t);
void  *calloc(size_t, size_t);
void  *realloc(void *, size_t);
void   free(void *);
int    atoi(const char *);
int    abs(int);
void   qsort(void *, size_t, size_t, int (*)(const void *, const void *));
void   exit(int);

/* Supplied by cpmlibc.c (missing from DR C) */
long   strtol(const char *, char **, int);

#endif
