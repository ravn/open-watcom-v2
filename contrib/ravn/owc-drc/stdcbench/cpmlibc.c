/* cpmlibc.c -- the ANSI C90 library routines that the pre-ANSI Digital
   Research C run-time (clears.l86, ~1984) does not provide, implemented in
   portable C90 on top of what DR C does offer.
 *
 * DR C predates the ANSI C standard, so it lacks the mem* family, strstr,
 * strtol and linkable ctype functions (it still ships the old BSD names
 * index/rindex instead of relying solely on strchr/strrchr).  These small
 * implementations fill exactly the gap stdcbench needs.
 *
 * Symbols are emitted with no leading underscore (compat.h) so references
 * from the benchmark objects resolve against these definitions.  Only
 * non-static globals/functions are used (DR LINK-86 rejects Open Watcom's
 * 0xB4 "static extdef" records).
 */
#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) *d++ = *s++;
    return dest;
}

void *memmove(void *dest, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else if (d > s) {
        d += n; s += n;
        while (n--) *--d = *--s;
    }
    return dest;
}

void *memset(void *dest, int c, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    while (n--) *d++ = (unsigned char)c;
    return dest;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    while (n--) {
        if (*pa != *pb) return (int)*pa - (int)*pb;
        pa++; pb++;
    }
    return 0;
}

char *strstr(const char *hay, const char *needle)
{
    if (!*needle) return (char *)hay;
    for (; *hay; hay++) {
        const char *h = hay, *n = needle;
        while (*h && *n && *h == *n) { h++; n++; }
        if (!*n) return (char *)hay;
    }
    return NULL;
}

/* Enough of strtol for stdcbench (base 10 / 16 / 0-auto, optional sign). */
long strtol(const char *s, char **end, int base)
{
    const char *p = s;
    long val = 0;
    int neg = 0, any = 0, digit;

    while (*p == ' ' || (*p >= 9 && *p <= 13)) p++;
    if (*p == '+' || *p == '-') { neg = (*p == '-'); p++; }
    if ((base == 0 || base == 16) && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
        p += 2; base = 16;
    } else if (base == 0) {
        base = (p[0] == '0') ? 8 : 10;
    }
    for (;; p++) {
        int c = (unsigned char)*p;
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'z') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z') digit = c - 'A' + 10;
        else break;
        if (digit >= base) break;
        val = val * base + digit;
        any = 1;
    }
    if (end) *end = (char *)(any ? p : s);
    return neg ? -val : val;
}

/* ctype: ASCII, locale-independent. */
int isdigit(int c) { return c >= '0' && c <= '9'; }
int isupper(int c) { return c >= 'A' && c <= 'Z'; }
int islower(int c) { return c >= 'a' && c <= 'z'; }
int isalpha(int c) { return isupper(c) || islower(c); }
int isalnum(int c) { return isalpha(c) || isdigit(c); }
int isspace(int c) { return c == ' ' || (c >= 9 && c <= 13); }
int tolower(int c) { return isupper(c) ? c + ('a' - 'A') : c; }
int toupper(int c) { return islower(c) ? c - ('a' - 'A') : c; }
