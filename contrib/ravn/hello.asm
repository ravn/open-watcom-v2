;****************************************************************************
;
;   Basic CP/M-86 "hello world" for Open Watcom (wasm).
;
;   Prints a '$'-terminated string via BDOS and terminates. No C runtime is
;   used -- BDOS is reached directly through software interrupt 224 (0E0h):
;
;       CL = function number, DX = parameter (DS:DX for strings).
;
;   Functions (Digital Research CP/M-86 System Guide):
;       9  C_WRITESTR  print '$'-terminated string at DS:DX
;       0  P_TERMCPM   terminate, return to CCP
;
;   CP/M-86 8080 model: the loader jumps to CS:0000 with the code group as the
;   single segment. We force DS = CS at entry so 'msg' (which lives in the same
;   group) is addressable regardless of how the loader set DS / the base page.
;
;   Build:  wasm hello.asm
;           wl format raw bin option start=start_ name hello.bin file hello.obj
;           python3 bin2cmd.py hello.bin HELLO.CMD
;
;****************************************************************************
        .8086

_TEXT   segment byte public 'CODE'
        assume  cs:_TEXT, ds:_TEXT, ss:_TEXT

        org     0                       ; entry must be at offset 0 (CS:0000)
start_:
        push    cs
        pop     ds                      ; DS = CS -> 'msg' addressable
        mov     dx, offset msg
        mov     cl, 9                   ; BDOS C_WRITESTR
        int     0E0h
        mov     cl, 0                   ; BDOS P_TERMCPM
        int     0E0h

msg     db      'Hello, CP/M-86 from Open Watcom!', 0Dh, 0Ah, '$'

_TEXT   ends
        end     start_
