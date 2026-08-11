;
; putchar.asm -- a freestanding putchar() for the CP/M-86 Mandelbrot benchmark,
; shared byte-for-byte by BOTH the genuine Digital Research C oracle build and
; every Open Watcom variant.  Assembled with Open Watcom's wasm (bwasm); the
; OMF is accepted by DR LINK-86 (same as owcrt.asm).
;
; Why not the DR C library putchar?  DR C's <stdio.h> defines
;   #define putchar(c) putc((c),stdout)     -> fputc -> buffered FILE I/O
; which pulls in the full stdio buffer machinery (and BDOS calls the bare
; cpm86run_unicorn harness does not model).  The benchmark only needs to emit
; bytes, so this putchar writes each character straight to the console with
; BDOS function 2 (C_WRITE: CL=2, DL=char, INT 0E0h).  Using the SAME tiny
; primitive for both compilers keeps the program output byte-identical (the
; correctness oracle) and keeps the measured work the fixed-point compute loop,
; not two different libc stdout paths.
;
; Calling convention: classic 8086 cdecl (DR C's, and Open Watcom's under
; -ecc / the compat-mixed.h alias): the int argument is pushed by the caller;
; on a NEAR call the stack on entry is [SP]=return, [SP+2]=arg.  Result in AX.
;
; CP/M-86 BDOS may alter AX, BX, CX, DX, SI, DI, ES and flags (System Guide),
; but cdecl requires the callee preserve SI, DI and BP -- so we save SI, DI,
; ES (and BX) around the call, or the Mandelbrot loop's register variables
; would be corrupted by the very act of printing a character.
;
; The segment is CODE / class 'CODE' / group CGROUP so it merges with DR C's
; and Open Watcom's (-nt=CODE) CODE segment; otherwise the near call from the
; C code to putchar is "TARGET OUT OF RANGE" at link time.
;
	.8086
CGROUP	group	CODE
CODE	segment	byte public 'CODE'
	assume	cs:CODE
	public	putchar
putchar:
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	es
	push	bx
	mov	dl,[bp+4]		; low byte of the int arg = char to write
	mov	cl,2			; BDOS C_WRITE
	int	0E0h
	pop	bx
	pop	es
	pop	di
	pop	si
	mov	al,[bp+4]		; return the character (as int)
	xor	ah,ah
	pop	bp
	ret
CODE	ends
	end
