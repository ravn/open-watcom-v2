; putchar-far.asm -- LARGE/COMPACT-model (FAR) putchar for DR C large-model
; builds. DR C defaults to the large model and calls external functions with a
; FAR call (pushes CS:IP = 4 bytes). The small-model putchar.asm (near ret)
; corrupts the stack when called far -> "Stack Overflow". Here the proc is FAR
; (retf) and the int arg sits at [bp+6]:  [bp]=old bp, [bp+2]=IP, [bp+4]=CS,
; [bp+6]=arg.  BDOS function 2 (C_WRITE: CL=2, DL=char, INT 0E0h).
	.8086
CGROUP	group	CODE
CODE	segment	byte public 'CODE'
	assume	cs:CODE
	public	putchar
putchar	proc	far
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	es
	push	bx
	mov	dl,[bp+6]		; low byte of the int arg (far frame)
	mov	cl,2			; BDOS C_WRITE
	int	0E0h
	pop	bx
	pop	es
	pop	di
	pop	si
	mov	al,[bp+6]		; return the character (as int)
	xor	ah,ah
	pop	bp
	retf
putchar	endp
CODE	ends
	end
