/*
 * mandelf.c -- 80x25 ASCII Mandelbrot set, floating-point arithmetic.
 *
 * Float twin of mandel.c (fixed-point 8.8): the SAME picture, computed with
 * `double` instead of 8.8 fixed-point, so we can compare the *cost* of real
 * float arithmetic (8087 hardware vs software emulation) against the integer
 * version on the RC759 (8086, no 8087).
 *
 * K&R/C89-clean (all locals at top of block, K&R putchar decl, no mid-block
 * declarations) so the genuine Digital Research C v1.11 compiler and Open
 * Watcom accept the SAME source.  Output is deterministic ASCII art -- the
 * escape-count glyph per cell -- and must match mandel.c cell-for-cell within
 * the two-mapping caveat below, so it doubles as a correctness oracle.
 *
 * Mapping matches mandel.c exactly (cr = -2.0 + px*(2.5/80), stepped as
 * px*8/256; ci = -1.25 + py*(2.5/25)) so the two pictures are the same set
 * sampled at the same points -- the only differences come from fixed-point
 * rounding in mandel.c, which the float version does not have.
 */
int putchar();          /* K&R decl: DR C v1.11 predates ANSI prototypes */

int main()
{
    int py, px;
    for (py = 0; py < 25; py++) {
        for (px = 0; px < 80; px++) {
            double cr, ci, zr, zi, zr2, zi2, tmp;
            int iter;
            /* Same sample points as the 8.8 fixed-point version:
               cr = (-512 + px*8)/256, ci = (-320 + py*640/25)/256. */
            cr = (-512.0 + px * 8.0) / 256.0;
            ci = (-320.0 + (py * 640 / 25)) / 256.0;
            zr = 0.0;
            zi = 0.0;
            for (iter = 0; iter < 30; iter++) {
                zr2 = zr * zr;
                zi2 = zi * zi;
                if (zr2 + zi2 > 4.0)
                    break;
                tmp = zr2 - zi2 + cr;
                zi = 2.0 * zr * zi + ci;
                zr = tmp;
            }
            putchar(iter >= 30 ? '#' : " .:-=+*%@#"[iter % 10]);
        }
        putchar('\n');
    }
    return 0;
}
