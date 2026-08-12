/*
 * mandel-ow.c -- Open-Watcom-SPECIFIC variant of mandel.c.
 *
 * Identical computation to owc-drc/mandel.c, but FP_MUL is lowered through a
 * `#pragma aux` routine to a single 16x16->32 IMUL plus a byte-extract, instead
 * of the portable `(long)a * b >> 8` idiom which Open Watcom compiles to a
 * 32x32 __I4M library call followed by an 8-step carry-chained shift loop.
 *
 * This deliberately BREAKS the "one source, both compilers" oracle design:
 * genuine Digital Research C v1.11 cannot express inline IMUL, so this file is
 * NOT built by the pure-drc pipeline.  Its correctness is still checked the same
 * way -- its output must remain byte-identical to the DR C oracle -- because the
 * transform is exact:
 *
 *   FP_MUL takes only (int)(product >> 8) = the low 16 bits of the result =
 *   original product bits [8..23].  Those bits are unaffected by whether the
 *   shift is arithmetic or logical (sign only fills bits [24..31]), so the
 *   IMUL result reassembled as (AH, DL) equals (long)a*b>>8 cast to int for
 *   every sign of a and b.
 */
int putchar();          /* K&R decl (kept identical to mandel.c) */

/* fpmul(a,b) == (int)((long)a * b >> 8), via one 16x16 IMUL + byte extract.
 *   imul cx    -> DX:AX = a*b (signed 32-bit product); AX=parm a, CX=parm b
 *   mov al,ah  -> result low  byte = product bits [8..15]
 *   mov ah,dl  -> result high byte = product bits [16..23]
 * AX now holds bits [8..23] = the 8.8 fixed-point product, as an int. */
extern int fpmul(int a, int b);
#pragma aux fpmul =     \
    "imul cx"           \
    "mov al,ah"         \
    "mov ah,dl"         \
    parm [ax] [cx]      \
    value [ax]          \
    modify [dx];

#define FP_SHIFT 8
#define FP_ONE   (1 << FP_SHIFT)              /* 256 */
#define FP_MUL(a, b) fpmul((a), (b))          /* was (int)((long)(a)*(b)>>8) */

int main()
{
    int py, px;
    for (py = 0; py < 25; py++) {
        for (px = 0; px < 80; px++) {
            int cr = -512 + px * 8;              /* px*8 == px*640/80, overflow-free (px*640 wraps int16 at px>=52) */
            int ci = -320 + (py * 640 / 25);     /* py*640 (<=15360) doesn't overflow; 640/25 not integral */
            int zr = 0, zi = 0;
            int iter;
            int zr2, zi2, tmp;
            for (iter = 0; iter < 30; iter++) {
                zr2 = FP_MUL(zr, zr);
                zi2 = FP_MUL(zi, zi);
                if (zr2 + zi2 > 4 * FP_ONE)
                    break;
                tmp = zr2 - zi2 + cr;
                zi = 2 * FP_MUL(zr, zi) + ci;
                zr = tmp;
            }
            putchar(iter >= 30 ? '#' : " .:-=+*%@#"[iter % 10]);
        }
        putchar('\n');
    }
    return 0;
}
