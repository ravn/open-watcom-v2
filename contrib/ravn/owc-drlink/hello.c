/* Demo: Open Watcom C compiled to OMF, linked by DR LINK86 into a CP/M-86 .CMD.
 *
 * The entry point is deliberately NOT called `main`: naming it `main` makes the
 * Watcom compiler emit a reference to its own C startup (`_cstart_`) and export
 * the symbol as `main_` (register/__watcall decoration). Using a plain name and
 * compiling with -ecc (force cdecl) makes the compiler emit ordinary
 * stack-based, leading-underscore calls (`_cmain`, `_putstr`) that match a
 * classic C runtime ABI and link cleanly against the tiny OMF runtime in
 * crt.asm. See README.md for the full rationale and evidence.
 */
extern void putstr(char *s);

int cmain(void)
{
    putstr("Hello from Open Watcom C via DR LINK86 on CP/M-86\r\n");
    return 0;
}
