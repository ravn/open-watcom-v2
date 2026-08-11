/*
 * hello.c -- smoke test: Open Watcom C calling the Digital Research C
 * run-time library's printf on CP/M-86.
 *
 * The entry function is named cmain (not main) because Open Watcom
 * special-cases "main"; owcrt.asm bridges DR C's "main" call to cmain.
 * compat.h (forced-included at compile time) strips the leading underscore
 * so this object's "printf" reference resolves against clears.l86.
 */
extern int printf(const char *, ...);

int cmain(void)
{
    printf("Hello from Open Watcom C + DR C run-time on CP/M-86: %d %x %s\n",
           42, 255, "ok");
    return 0;
}
