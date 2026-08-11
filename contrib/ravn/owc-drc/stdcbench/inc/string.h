/* Minimal neutral <string.h> matching the Digital Research C run-time ABI.
   Only the declarations stdcbench needs.  The mem* family and strstr are
   NOT in DR C (pre-ANSI); they are supplied by cpmlibc.c. */
#ifndef _CPM_STRING_H
#define _CPM_STRING_H
#include <stddef.h>

/* Provided by DR C (clears.l86) */
char  *strcpy(char *, const char *);
char  *strncpy(char *, const char *, size_t);
char  *strcat(char *, const char *);
int    strcmp(const char *, const char *);
int    strncmp(const char *, const char *, size_t);
size_t strlen(const char *);
char  *strchr(const char *, int);
char  *strrchr(const char *, int);

/* Supplied by cpmlibc.c (missing from DR C) */
void  *memcpy(void *, const void *, size_t);
void  *memmove(void *, const void *, size_t);
void  *memset(void *, int, size_t);
int    memcmp(const void *, const void *, size_t);
char  *strstr(const char *, const char *);

#endif
