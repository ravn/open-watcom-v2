/*
 * farheap_smalltest.c  --  VERIFIED small-model explicit far-heap proof.
 *
 * WHAT this proves (and WHY it matters for the UnZip DEFLATE port):
 *   In SMALL model the clib's own globals + string literals stay NEAR, in the
 *   single 64 KB DGROUP, so wlink emits exactly ONE type=2 group (no far-data
 *   collision).  A program can STILL move its big buffers off DGROUP by calling
 *   _fmalloc() explicitly: the far heap is a separate paragraph arena (the .CMD
 *   "Extra" group, type=3) handed out by port/farheap.c::__AllocSeg.
 *
 * This test allocates 8 * 12 KB = 96 KB of FAR blocks, fills each with a
 * position-dependent pattern, reads it back, and checks two invariants:
 *   (a) every block's segment != DS  -> it really lives OUTSIDE DGROUP;
 *   (b) every byte survives the round-trip -> the far arena is real RAM.
 * 96 KB > 64 KB, so this could not possibly fit in DGROUP -- the pass is only
 * explicable by a working far heap.  Verified PASS under cpm86run_unicorn.py.
 *
 * WHY explicit _fmalloc and NOT transparent -mc (compact) malloc:
 *   Compact model makes clib globals (e.g. int __heap_enabled=1) FAR; wlink's
 *   `format cpm86` emits those as a SECOND type=2 group, which the CP/M-86 .CMD
 *   header (groups keyed by TYPE 1-8) cannot place -> the globals read 0 ->
 *   __heap_enabled==0 -> __AllocSeg refuses -> malloc()==NULL.  Root cause is a
 *   wlink/loader limitation, not this clib.  Until that is fixed, SMALL model +
 *   explicit _fmalloc is the path that works today.  See build-lib.sh MODEL=c.
 *
 * Uses inline-asm BDOS conout + a near string so the pass/fail signal itself
 * pulls no stdio far data -- the test isolates the far HEAP, nothing else.
 */
#include <malloc.h>
#include <i86.h>

extern void bdos_conout( char c );
#pragma aux bdos_conout = "mov cl,2" "int 0E0h" parm [dl] modify [cl];
extern unsigned _getds( void );
#pragma aux _getds = "mov ax,ds" value [ax] modify [ax];

static void puts_n( const char *s ) { while( *s ) bdos_conout( *s++ ); }

#define NBLK 8
#define BSZ  12288u                     /* 8 * 12 KB = 96 KB, > 64 KB DGROUP */

static char __far *blk[NBLK];

int main( void )
{
    unsigned ds = _getds(), i, j, nf = 0;
    int bad = 0;

    for( i = 0; i < NBLK; i++ ) {
        char __far *p = _fmalloc( BSZ );
        blk[i] = p;
        if( !p ) { puts_n( "FAIL: _fmalloc returned NULL\r\n" ); return 1; }
        if( FP_SEG( p ) != ds ) nf++;   /* seg != DS  ->  outside DGROUP     */
        for( j = 0; j < BSZ; j++ ) p[j] = (char)( i * 97u + 1u + j );
    }
    for( i = 0; i < NBLK; i++ ) {
        char __far *p = blk[i];
        for( j = 0; j < BSZ; j++ )
            if( (unsigned char)p[j] != (unsigned char)( i * 97u + 1u + j ) ) {
                bad++; break;
            }
    }
    puts_n( ( nf == NBLK && !bad )
            ? "PASS small+explicit far-heap (96KB off DGROUP)\r\n"
            : "FAIL far-heap round-trip\r\n" );
    return ( nf == NBLK && !bad ) ? 0 : 1;
}
