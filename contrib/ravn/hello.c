/****************************************************************************
*
*   Freestanding CP/M-86 "hello world" for Open Watcom (wcc, tiny model).
*
*   CP/M-86 has no C runtime under Open Watcom, so this program does NOT use
*   the standard library. It talks to the operating system directly through
*   BDOS, which on CP/M-86 is reached via software interrupt 224 (0E0h):
*
*       CL = function number, DX = parameter, result in AL/AX.
*
*   Functions used here (Digital Research CP/M-86 System Guide, BDOS calls):
*       9  C_WRITESTR   print '$'-terminated string at DS:DX
*       0  P_TERMCPM    terminate program, return to CCP
*
*   Build with small model (-ms) so code+data share one segment, matching the
*   CP/M-86 "8080 model" produced by bin2cmd.py (single relocatable group).
*
****************************************************************************/

/*
 * BDOS entry via INT 0E0h. wcc auxiliary pragma: pass function in CL and the
 * DX parameter, clobber the usual scratch registers. Value returned in AX.
 */
extern unsigned bdos( unsigned char func, unsigned dx );
#pragma aux bdos =              \
    "int 0E0h"                  \
    parm [cl] [dx]              \
    value [ax]                  \
    modify [ax bx cx dx es];

#define BDOS_WRITESTR   9
#define BDOS_TERMCPM    0

static char message[] = "Hello, CP/M-86 from Open Watcom!\r\n$";

/*
 * Entry symbol. build-cpm86.sh links this at load offset 0100H (wl 'option
 * offset=0x100') and bin2cmd.py reserves the 100H base page, so CP/M-86's
 * 8080 model enters here at CS:0100H. __watcall appends '_' to the symbol,
 * so the linker sees this as 'start__'. In the small/8080 model CS=DS already
 * holds for wcc-generated code, so 'message' is reachable via DS:DX.
 */
void start_( void )
{
    bdos( BDOS_WRITESTR, (unsigned)message );
    bdos( BDOS_TERMCPM, 0 );
}
