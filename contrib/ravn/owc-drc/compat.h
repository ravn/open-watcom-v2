/*
 * compat.h -- forced-include shim so Open Watcom emits object symbols that
 * match the Digital Research C (CP/M-86) run-time library naming.
 *
 * DR C exposes libc functions with NO leading underscore (printf, main,
 * malloc, strcpy, ...).  Open Watcom's -ecc (cdecl) normally adds a leading
 * underscore.  The line below redefines the default auxiliary pragma so that
 * every symbol -- both definitions and references -- is emitted verbatim,
 * i.e. with no underscore decoration, matching DR C's clears.l86.
 *
 * Include it on every translation unit with:  bwcc ... -fi=compat.h ...
 */
#pragma aux default "*";
