/*
 * compat-mixed.h -- forced-include shim for a MIXED calling-convention build
 * of Open Watcom C against the Digital Research C (CP/M-86) run-time.
 *
 * Goal (the "llvm-z80 trick"): let calls BETWEEN the program's own functions
 * use Open Watcom's fast register convention (__watcall: arguments in
 * AX/DX/BX/CX), while calls INTO the DR C standard library (clears.l86) still
 * use the stack, because that library was compiled by DR C and expects the
 * classic 8086 C convention (arguments pushed right-to-left on the stack,
 * caller cleans up, result in AX / DX:AX) with NO leading underscore.
 *
 * Build WITHOUT -ecc so the compile-time default stays __watcall, and force
 * every symbol's name verbatim (no decoration) so both user symbols and the
 * DR C imports match clears.l86:
 *
 *     #pragma aux default "*";
 *
 * Then override just the DR C library entry points to the stack convention.
 * Each is aliased to Open Watcom's built-in __cdecl (arguments pushed
 * right-to-left on the stack, caller cleans up, result in AX / DX:AX -- the
 * classic 8086 C convention DR C uses) with the name forced verbatim ("*") so
 * it resolves to clears.l86's undecorated symbol (printf, not _printf):
 *
 *     #pragma aux (__cdecl) printf "*";
 *
 * Use:  bwcc ... -fi=compat-mixed.h ...   (and NOT -ecc)
 */
#pragma aux default "*";

/* Every DR C libc function the program calls must be aliased to __cdecl so it
 * is invoked on the stack.  (printf is variadic, which on its own already
 * forces stack passing; the others would otherwise be register-called.) */
#pragma aux (__cdecl) printf  "*";
#pragma aux (__cdecl) scanf   "*";
#pragma aux (__cdecl) malloc  "*";
#pragma aux (__cdecl) strcpy  "*";
#pragma aux (__cdecl) strcmp  "*";
#pragma aux (__cdecl) strlen  "*";
#pragma aux (__cdecl) memcpy  "*";
#pragma aux (__cdecl) puts    "*";
#pragma aux (__cdecl) putchar "*";
#pragma aux (__cdecl) exit    "*";
