/* Minimal neutral <stddef.h> for Open Watcom C -> DR C runtime on CP/M-86.
   Small memory model: size_t is a 16-bit unsigned int, pointers are near. */
#ifndef _CPM_STDDEF_H
#define _CPM_STDDEF_H
typedef unsigned int   size_t;
typedef int            ptrdiff_t;
#ifndef NULL
#define NULL ((void *)0)
#endif
#endif
