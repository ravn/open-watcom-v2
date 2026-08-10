;****************************************************************************
;
;   Minimal CP/M-86 C startup stub for Open Watcom (wasm), 8080/small model.
;
;   `wl format raw` concatenates the _TEXT segments of the linked objects in
;   link order and does NOT reorder them to put the entry symbol first -- the
;   CP/M-86 loader simply jumps to the first byte of the code group. For a C
;   program with several functions the entry function is therefore usually NOT
;   first, so we must supply a startup object linked *first* whose first byte
;   is the real entry point. It calls the C entry `cpmmain()` (wcc __watcall
;   name: cpmmain_) and, when that returns, terminates via BDOS P_TERMCPM.
;
;   The emulator/CCP sets CS = DS = ES = SS to the single program group and
;   gives a full-segment stack (see cpm86run_unicorn.py), matching the CP/M-86
;   8080 model, so no segment/stack setup is needed here.
;
;   Link (see build-cpm86.sh, C path):
;       wasm cpmstart.asm ; wcc ... prog.c
;       wl format raw bin option quiet, offset=0x100 &
;          name prog.bin file cpmstart.obj file prog.obj
;       python3 bin2cmd.py prog.bin PROG.CMD      (reserves the 100H base page)
;
;****************************************************************************
        .8086

_TEXT   segment byte public 'CODE'
        assume  cs:_TEXT

        extrn   cpmmain_ : near
        public  cpmstart_

cpmstart_:
        call    cpmmain_                ; run the C program
        mov     cl, 0                   ; BDOS P_TERMCPM
        int     0E0h

_TEXT   ends
        end     cpmstart_
