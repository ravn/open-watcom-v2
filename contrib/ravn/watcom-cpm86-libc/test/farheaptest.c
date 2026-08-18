/* farheaptest.c -- overlap-detecting stress test for the Stage A far heap
   (Phase A4, tasks/plan-cpm86-big-model-2026-08-18.md).

   Allocates NALLOC blocks of pseudo-random size (a fixed LCG, so the run is
   reproducible) via _fmalloc -- the explicit far-heap API, not plain
   malloc(), so this exercises port/farheap.c's __AllocSeg regardless of
   compile model. Each block gets a distinct fill pattern:

       byte j of block i  ==  (unsigned char)( (i*97 + 1) + j )

   The starting values i*97+1 (mod 256) are all DISTINCT for every i in
   0..255 -- 97 is odd (coprime with 256), so i -> i*97 mod 256 is a
   bijection over one byte -- and every block's pattern climbs at the SAME
   +1-per-byte slope. So if two blocks' memory ever overlapped, every
   overlapping byte would show a constant, nonzero discrepancy (the two
   blocks' start values differ), never an accidental match. All blocks are
   filled FIRST, then ALL are verified
   in a second pass -- so a later allocation's fill corrupting an earlier
   block (the actual bug class this is designed to catch: overlapping
   segments/pointer arithmetic mistakes in __AllocSeg) is only checked for
   after every allocation has had a chance to stomp on it.

   Chosen sizes/count push total usage past one 64 KB heap-list slab (see
   farheap.c's block comment on why 64 KB is Watcom's universal per-slab
   cap), so a correct run is also empirical proof the multi-slab carving in
   __AllocSeg (reading the true Extra-group size from the base page, not a
   single fixed segment) works, not just that "one _fmalloc call succeeds". */

#include <malloc.h>
#include <stdlib.h>

extern int cprintf( const char *, ... );

#define NALLOC  130

static unsigned lcg_seed = 12345u;

static unsigned lcg_next( void )
{
    lcg_seed = lcg_seed * 25173u + 13849u;
    return( lcg_seed );
}

int main( void )
{
    static void  __far   *blk[NALLOC];
    static unsigned       sz[NALLOC];
    int                    i;
    unsigned               j;
    unsigned char          start;
    unsigned char __far   *p;
    int                    fails;
    unsigned long          total;

    total = 0;
    for( i = 0; i < NALLOC; i++ ) {
        sz[i] = 512u + ( lcg_next() % 3584u );      /* 512..4095 bytes */
        blk[i] = _fmalloc( sz[i] );
        if( blk[i] == 0 ) {
            cprintf( "alloc %d FAIL (size %u, %lu so far)\n", i, sz[i], total );
            return( 1 );
        }
        total += sz[i];
        start = (unsigned char)( i * 97 + 1 );
        p = (unsigned char __far *)blk[i];
        for( j = 0; j < sz[i]; j++ )
            p[j] = (unsigned char)( start + j );
    }
    cprintf( "allocated %lu bytes in %d blocks\n", total, NALLOC );

    fails = 0;
    for( i = 0; i < NALLOC; i++ ) {
        start = (unsigned char)( i * 97 + 1 );
        p = (unsigned char __far *)blk[i];
        for( j = 0; j < sz[i]; j++ ) {
            unsigned char want = (unsigned char)( start + j );
            if( p[j] != want ) {
                cprintf( "MISMATCH block %d offset %u: want %02x got %02x\n",
                          i, j, (unsigned)want, (unsigned)p[j] );
                fails++;
                break;      /* one report per corrupted block is enough */
            }
        }
    }
    cprintf( "%s (%d block%s corrupted)\n",
              ( fails == 0 ) ? "PASS" : "FAIL",
              fails, ( fails == 1 ) ? "" : "s" );
    return( fails != 0 );
}
