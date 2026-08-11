; crt.asm - minimal CP/M-86 C runtime for Open Watcom objects, in OMF.
;
; This is a *deliberately tiny* runtime that demonstrates the linkage path
; "Open Watcom C (OMF) + runtime (OMF) -> DR LINK86 -> CP/M-86 .CMD". It is NOT
; a full C library; it provides only:
;
;   start_    program entry: call the C entry point, then terminate via BDOS.
;   _putstr   the single libc-style helper referenced by hello.c.
;
; Conventions (must match Open Watcom compiled with -ecc, i.e. cdecl):
;   * leading-underscore symbol names (_cmain, _putstr)
;   * arguments pushed right-to-left on the stack, caller cleans up
;   * near pointers (small memory model, -ms)
;
; CP/M-86 BDOS is invoked via INT 0E0h: function number in CL, console-output
; char in DL (function 2), P_TERMCPM is function 0. This is the SAME BDOS
; convention used by contrib/ravn/cpmstart.asm and by Aztec's c86.lib.
;
; Assemble with the Open Watcom assembler (wasm/bwasm):
;   bwasm -0 crt.asm -fo=crt.obj

name crt
DGROUP group _DATA

_TEXT segment byte public 'CODE'
      assume cs:_TEXT, ds:DGROUP

      public start_
      extrn  _cmain:near
start_:
      call   _cmain           ; run the C entry point
      mov    cl,0             ; BDOS 0 = P_TERMCPM
      int    0E0h

; void putstr(char *s) -- cdecl; near pointer arg at [bp+4]
      public _putstr
_putstr:
      push   bp
      mov    bp,sp
      mov    si,[bp+4]
ps_l: mov    dl,[si]
      or     dl,dl
      jz     ps_d
      push   si
      mov    cl,2             ; BDOS 2 = console output, char in DL
      int    0E0h
      pop    si
      inc    si
      jmp    ps_l
ps_d: pop    bp
      ret

_TEXT ends

_DATA segment word public 'DATA'
_DATA ends

      end start_
