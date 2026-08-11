;
; owcrt.asm -- tiny CP/M-86 entry/bridge object for linking Open Watcom C
;              against the Digital Research C run-time library (clears.l86).
;
; Assembled with Open Watcom's wasm (bwasm); the resulting OMF is consumed
; directly by DR LINK-86.  It provides two things the DR C run-time expects
; but that a Watcom object does not supply on its own:
;
;   1. The program entry point.  A CP/M-86 CMD begins executing at CS:0000,
;      so the FIRST object on the LINK-86 command line owns offset 0.  Label
;      "owcrt" jumps to the DR C internal start routine "_main", which sets
;      up the OS/stack/heap and then calls "main".
;
;   2. The C entry bridge.  The DR C start code calls a function named "main"
;      (no underscore).  Open Watcom special-cases the name "main" (it emits
;      "main_" plus a reference to Watcom's own _cstart_), so the C entry is
;      compiled under a different name -- "cmain" -- and this stub forwards
;      the DR C "main" call to it.  Build the C file with -Dmain=cmain, or
;      simply name the entry function cmain().
;
; The segment is named CODE / class 'CODE' (group CGROUP) so it merges with
; DR C's own CODE segment; otherwise LINK-86 reports "TARGET OUT OF RANGE"
; for near calls that cross the Watcom (_TEXT) / DR C (CODE) boundary.  For
; the same reason compile the C with -nt=CODE.
;
	.8086
CGROUP	group	CODE
CODE	segment	byte public 'CODE'
	assume	cs:CODE
	extrn	_main:near		; DR C start (inits, then calls 'main')
	extrn	cmain:near		; Watcom-compiled user entry
	public	main			; symbol the DR C run-time calls
owcrt:
	jmp	_main
main:
	jmp	cmain
CODE	ends
	end	owcrt
