;
; owmath.asm -- the handful of Open Watcom 32-bit integer helper routines that
;               the Digital Research C run-time does not provide.
;
; The Open Watcom code generator emits calls to internal helpers for 32-bit
; (long) multiply and divide.  DR C's library has no such routines, so we
; supply the three that stdcbench references, using Watcom's own register
; calling convention:
;
;   __U4M / __I4M : DX:AX * CX:BX -> DX:AX          (low 32 bits of product)
;                   (signed and unsigned low products are identical)
;   __U4D         : DX:AX / CX:BX -> DX:AX quotient, CX:BX remainder (unsigned)
;
; Placed in segment CODE / group CGROUP so they merge with DR C and the rest of
; the Open Watcom code (see owcrt.asm).
;
; RETURN DISTANCE MUST FOLLOW THE CODE MODEL.  In the small model the Watcom
; code generator reaches these helpers with a NEAR call, so a near `ret` (pop
; IP only) is correct.  In the LARGE model every inter-module call is FAR, so
; the compiler far-calls these helpers too (it pushes CS:IP, 4 bytes); the
; helper must then `retf` to pop all 4.  A near `ret` in the large model pops
; only 2 bytes, leaking the pushed CS every call -> the stack slowly unwinds
; into garbage and the program eventually far-jumps to an unmapped segment and
; faults.  That was the stdcbench-large early-exit (banner only): portme far-
; called __U4M at CS 0039, which near-returned, and a few hundred K insns later
; CS was a wild ACB8 running through unmapped memory.  Small model was fine
; (near call + near ret matched), so the bug was large-only.
;
; @CodeSize is 1 under -ml (large code) and 0 under -ms (small code), so the
; same source assembles correctly for both models -- see the RET_ macro below.
;
        .8086
CGROUP  group   CODE
CODE    segment byte public 'CODE'
        assume  cs:CODE

if @CodeSize
RET_    macro
        retf
        endm
else
RET_    macro
        ret
        endm
endif

        public  __U4M
        public  __I4M
        public  __U4D

; --- 32x32 -> low 32 multiply (Watcom algorithm, from bld/clib i4m.asm) ---
__I4M:
__U4M:
        xchg    ax,bx           ; ax=low(M2), bx=low(M1)
        push    ax              ; save low(M2)
        xchg    ax,dx           ; ax=high(M1), dx=low(M2)
        or      ax,ax
        jz      u4m_1
        mul     dx              ; high(M1)*low(M2) -> dx:ax (dx clobbered)
u4m_1:
        xchg    ax,cx           ; cx=partial, ax=high(M2)
        or      ax,ax
        jz      u4m_2
        mul     bx              ; high(M2)*low(M1)
        add     cx,ax
u4m_2:
        pop     ax              ; low(M2)
        mul     bx              ; low(M2)*low(M1) -> dx:ax
        add     dx,cx
        RET_

; --- unsigned 32/32 divide by binary long division ---
; in : DX:AX dividend, CX:BX divisor
; out: DX:AX quotient, CX:BX remainder ; preserves SI,DI,BP
__U4D:
        push    si
        push    di
        push    bp
        xor     si,si           ; remainder high
        xor     di,di           ; remainder low
        mov     bp,32           ; bit count
u4d_loop:
        shl     ax,1            ; dividend <<= 1, CF = top bit
        rcl     dx,1
        rcl     di,1            ; remainder = (remainder<<1)|CF
        rcl     si,1
        cmp     si,cx           ; remainder >= divisor ?
        ja      u4d_sub
        jb      u4d_next
        cmp     di,bx
        jb      u4d_next
u4d_sub:
        sub     di,bx           ; remainder -= divisor
        sbb     si,cx
        or      ax,1            ; set quotient bit (low bit is 0 after shl)
u4d_next:
        dec     bp
        jnz     u4d_loop
        mov     cx,si           ; remainder -> CX:BX
        mov     bx,di
        pop     bp
        pop     di
        pop     si
        RET_

CODE    ends
        end
