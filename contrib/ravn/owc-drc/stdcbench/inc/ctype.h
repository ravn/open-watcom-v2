/* Minimal neutral <ctype.h> for stdcbench on the DR C run-time.
   DR C does not export these as linkable symbols, so they are supplied as
   real functions by cpmlibc.c (declared here, not as macros). */
#ifndef _CPM_CTYPE_H
#define _CPM_CTYPE_H

int isspace(int);
int isalnum(int);
int isalpha(int);
int isdigit(int);
int isupper(int);
int islower(int);
int tolower(int);
int toupper(int);

#endif
