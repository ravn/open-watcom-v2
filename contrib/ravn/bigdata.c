/* ---------------------------------------------------------------------------
 * bigdata.c - a large CP/M-86 program (lots of code) that builds a data
 * structure spanning MORE THAN 64 KB and computes several checksums over it.
 *
 * The CP/M-86 8080/small program itself is <64 KB (code + near data + stack in
 * one group), but the *data structure* lives in separate 64 KB segments placed
 * above the program in the 1 MB real-mode address space and is reached through
 * explicit __far pointers.  This is exactly how CP/M-86 lets a program use far
 * more than 64 KB of data: the program manages its own segment registers (here
 * via far pointers) to address the whole memory space (System Guide 2.5).
 *
 * Layout of the data structure (deterministically generated, so every checksum
 * is reproducible and independently verifiable):
 *
 *   N_SEG (3) segments of 64 KB each, starting at paragraph DATA_BASE (0x3000)
 *   => 3 * 65536 = 196608 bytes = 192 KB > 64 KB.
 *
 *   Viewed as an array of REC records (64 bytes each, 1024 per 64 KB segment,
 *   N = 3072 records total).  Each record:
 *       u16 id;            record index (0..N-1)
 *       u16 next;          (id + STEP) mod N  -- forms a single ring because
 *                          gcd(STEP, N) == 1, so following `next` N times
 *                          visits every record exactly once, jumping across
 *                          segments each step.
 *       u8  payload[60];   pseudo-random bytes (16-bit xorshift PRNG)
 *
 * All arithmetic avoids 32-bit multiply/divide so no C runtime helper library
 * is needed (this is a freestanding image linked with -zl).
 * ------------------------------------------------------------------------- */

typedef unsigned char  u8;
typedef unsigned int   u16;
typedef unsigned long  u32;

#define DATA_BASE  0x3000u        /* first data segment (paragraph)          */
#define SEG_STEP   0x1000u        /* +64 KB in paragraphs                    */
#define N_SEG      3u             /* number of 64 KB data segments           */
#define REC_SIZE   64u            /* bytes per record                        */
#define RECS_SEG   1024u          /* records per 64 KB segment (65536/64)    */
#define N_REC      (N_SEG * RECS_SEG)   /* 3072 records                      */
#define STEP       1025u          /* coprime with 3072 -> single ring        */

#define MK_FP(seg, off) ((u8 __far *)(((u32)(seg) << 16) | (u16)(off)))

/* ---- record view over a far byte pointer ------------------------------- */
typedef struct {
    u16 id;
    u16 next;
    u8  payload[REC_SIZE - 4];
} REC;

#define REC_FP(seg, off) ((REC __far *)(((u32)(seg) << 16) | (u16)(off)))

/* ---- BDOS console I/O -------------------------------------------------- */
static void bdos_conout(u8 c)
{
    u16 val = c;
    __asm {
        mov cl, 2
        mov dx, val
        int 0E0h
    }
}

static void puts_(const char *s)
{
    while (*s) {
        if (*s == '\n') bdos_conout('\r');
        bdos_conout((u8)*s++);
    }
}

static void put_hex32(u32 v)
{
    static const char hx[] = "0123456789ABCDEF";
    int i;
    for (i = 28; i >= 0; i -= 4)
        bdos_conout((u8)hx[(v >> i) & 0xF]);
}

/* Decimal printer for values that fit in 16 bits: uses only 16-bit div/mod,
 * which the compiler emits inline (DIV), so no 32-bit runtime helper (__U4D)
 * is pulled in -- important for this freestanding, -zl linked image. */
static void put_u16dec(u16 v)
{
    char buf[6];
    int n = 0;
    if (v == 0) { bdos_conout('0'); return; }
    while (v) { buf[n++] = (char)('0' + (u8)(v % 10)); v /= 10; }
    while (n) bdos_conout((u8)buf[--n]);
}

/* ---- helpers to locate a record by global index (no 32-bit mul/div) ---- */
static u16 rec_seg(u16 g)      { return (u16)(DATA_BASE + (u16)((g >> 10) * SEG_STEP)); }
static u16 rec_off(u16 g)      { return (u16)((g & (RECS_SEG - 1)) << 6); }   /* *64 */

/* ---- 16-bit xorshift PRNG (shifts + xor only) -------------------------- */
static u16 prng_state;
static u8 prng_byte(void)
{
    u16 x = prng_state;
    x ^= (u16)(x << 7);
    x ^= (u16)(x >> 9);
    x ^= (u16)(x << 8);
    prng_state = x;
    return (u8)(x >> 8);
}

/* ---- CRC-32 (table driven; only shifts and xor, no multiply) ----------- */
static u32 crc_table[256];
static void crc_init(void)
{
    u16 n, k;
    for (n = 0; n < 256; n++) {
        u32 c = n;
        for (k = 0; k < 8; k++)
            c = (c & 1) ? (0xEDB88320UL ^ (c >> 1)) : (c >> 1);
        crc_table[n] = c;
    }
}

/* ---- build the >64 KB data structure ----------------------------------- */
static void build_structure(void)
{
    u16 g;
    prng_state = 0xACE1u;
    for (g = 0; g < N_REC; g++) {
        REC __far *r = REC_FP(rec_seg(g), rec_off(g));
        u16 j;
        u16 nx = (u16)(g + STEP);
        if (nx >= N_REC) nx = (u16)(nx - N_REC);
        r->id = g;
        r->next = nx;
        for (j = 0; j < REC_SIZE - 4; j++)
            r->payload[j] = prng_byte();
    }
}

/* ---- flat byte checksums over the whole >64 KB region ------------------ */
static u32 sum32;      /* additive sum of every byte                        */
static u32 crc32;      /* CRC-32 of every byte                              */
static u16 fl_a, fl_b; /* Fletcher-16 style rolling pair (mod 2^16)         */

static void checksum_bytes(void)
{
    u16 s;
    sum32 = 0;
    crc32 = 0xFFFFFFFFUL;
    fl_a = 0; fl_b = 0;
    for (s = 0; s < N_SEG; s++) {
        u8 __far *p = MK_FP(DATA_BASE + s * SEG_STEP, 0);
        u32 off;
        for (off = 0; off < 0x10000UL; off++) {
            u8 b = p[(u16)off];
            sum32 += b;
            crc32 = crc_table[(u8)(crc32 ^ b)] ^ (crc32 >> 8);
            fl_a = (u16)(fl_a + b);
            fl_b = (u16)(fl_b + fl_a);
        }
    }
    crc32 ^= 0xFFFFFFFFUL;
}

/* ---- structural traversal: follow the `next` ring across segments ------ */
static u32 walk_ids(void)
{
    u32 acc = 0;
    u16 cur = 0;
    u16 steps;
    for (steps = 0; steps < N_REC; steps++) {
        REC __far *r = REC_FP(rec_seg(cur), rec_off(cur));
        acc += r->id;
        cur = r->next;
    }
    return acc;   /* every id visited once => 0+1+...+(N-1) */
}

void cpmmain(void)
{
    u32 walk, expect;

    puts_("CP/M-86 >64 KB data structure checksum\n");
    puts_("--------------------------------------\n");
    put_u16dec(N_REC); puts_(" records x ");
    put_u16dec(REC_SIZE); puts_(" bytes = ");
    put_u16dec(N_SEG * 64); puts_(" KB (");
    put_u16dec(N_SEG); puts_(" segments of 64 KB)\n\n");

    crc_init();
    build_structure();
    checksum_bytes();
    walk = walk_ids();

    puts_("sum32      = "); put_hex32(sum32);  puts_("\n");
    puts_("crc32      = "); put_hex32(crc32);  puts_("\n");
    puts_("fletcher   = "); put_hex32(((u32)fl_b << 16) | fl_a); puts_("\n");
    puts_("ring-walk  = "); put_hex32(walk);   puts_("\n");

    /* the ring visits every id exactly once, so the sum must be N*(N-1)/2 */
    expect = ((u32)N_REC * (N_REC - 1)) / 2;
    puts_("expected   = "); put_hex32(expect);
    puts_(walk == expect ? "  [MATCH]\n" : "  [FAIL]\n");
}
