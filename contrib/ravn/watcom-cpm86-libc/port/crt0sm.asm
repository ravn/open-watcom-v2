        name    crt0sm
        extrn   main_ : near
        extrn   wc_heap_init_ : near
        extrn   __CommonInit_ : near
        public  _cstart_
        public  _small_code_
_small_code_    equ     0
        public  __STK

DGROUP  group   BEGDATA, _DATA, STACK

_TEXT   segment word public 'CODE'
        assume  cs:_TEXT, ds:DGROUP, ss:DGROUP
; Entry CS:0000. Loader already set DS=ES=data group + a 96-byte scratch stack.
; Do NOT touch DS/ES; just move SS to DS and set SP to the top of our DGROUP stack.
_cstart_:
        mov     ax, ds
        mov     ss, ax
        mov     sp, offset DGROUP:stktop
        call    wc_heap_init_
; ow#16: this minimal crt0 does not walk Watcom's XI init table, so run the C
; runtime initializers here (must be AFTER wc_heap_init -- __InitFiles allocates
; the stdout FILE buffer from the near heap). __CommonInit is macro-gated per
; build (see port/cominit.c): empty for the cprintf-only demos, __InitFiles for
; stdio builds, +__setEFGfmt for float-printing builds.
        call    __CommonInit_
; ow#3 streamio: Watcom's main(argc,argv) is __watcall -- argc in AX, argv in DX.
; Parse the CP/M-86 command tail (base page DS:0080h = length byte, DS:0081h.. =
; characters, space-separated) into a real argv vector so hosted programs like
; UnZip see their operands.  argv[0] is a fixed program name; tokens are
; NUL-terminated in place (we own the base-page scratch) and their offsets stored
; in _argvtab.  Example: tail " -l TEST.ZIP" -> argc=3,
; argv={"UNZIP","-l","TEST.ZIP",NULL}.
        mov     di, offset DGROUP:_argvtab
        mov     ax, offset DGROUP:_prog0
        mov     [di], ax                ; argv[0] = program name
        add     di, 2
        mov     bx, 1                   ; argc = 1
        mov     si, 81h                 ; first command-tail character
        mov     cl, byte ptr ds:[80h]   ; tail length
        xor     ch, ch
        mov     bp, si
        add     bp, cx                  ; bp = one past last tail char
ct_skip:
        cmp     si, bp
        jae     ct_done                 ; end of tail -> stop
        cmp     byte ptr [si], ' '
        jne     ct_tok                  ; non-space starts a token
        inc     si
        jmp     ct_skip
ct_tok:
        cmp     bx, 32                  ; argv table guard (32 slots)
        jae     ct_done
        mov     [di], si                ; argv[argc] = token start
        add     di, 2
        inc     bx
ct_scan:
        cmp     si, bp
        jae     ct_end                  ; token runs to end of tail
        cmp     byte ptr [si], ' '
        je      ct_cut                  ; space ends the token
        inc     si
        jmp     ct_scan
ct_cut:
        mov     byte ptr [si], 0        ; terminate token in place
        inc     si
        jmp     ct_skip
ct_end:
        mov     byte ptr [si], 0        ; terminate final token (within base page)
ct_done:
        mov     word ptr [di], 0        ; argv[argc] = NULL
        mov     word ptr ds:__argc, bx  ; publish argc to the marker
        mov     ax, bx                  ; argc -> AX (__watcall)
        mov     dx, offset DGROUP:_argvtab   ; argv -> DX
        call    main_
        xor     dx, dx
        mov     cl, 0
        int     0E0h
; Watcom stack-overflow check helper — no-op stub (no clib on CP/M-86 yet)
__STK:
        ret
_TEXT   ends

BEGDATA segment word public 'BEGDATA'
        db      100h dup(0)             ; base page area DS:0000-00FF
BEGDATA ends

_DATA   segment word public 'DATA'
        public  __argc
__argc  dw      1                       ; argc marker EXTRN'd by main's object
_prog0  db      'UNZIP', 0              ; argv[0]
        public  __argv
__argv  label   word                    ; keep the public symbol some objs EXTRN
_argvtab dw     33 dup(0)               ; argv[]: 32 slots + NULL terminator
_DATA   ends

STACK   segment word public 'STACK'
        db      512 dup(0)
stktop  label   word
STACK   ends
        end     _cstart_
