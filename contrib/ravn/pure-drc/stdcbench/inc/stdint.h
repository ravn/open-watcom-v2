#ifndef _DRC_STDINT_H
#define _DRC_STDINT_H
/* DR C 1.11 type map: char is unsigned 0..255; no unsigned long; no signed
   8-bit type (widen to int).  32-bit uses DR C signed long (portab ULONG). */
typedef char           uint8_t;
typedef int            int8_t;
typedef unsigned int   uint16_t;
typedef int            int16_t;
typedef long           uint32_t;
typedef long           int32_t;
typedef char           uint_least8_t;
typedef int            int_least8_t;
typedef unsigned int   uint_least16_t;
typedef int            int_least16_t;
typedef long           uint_least32_t;
typedef long           int_least32_t;
typedef int            uint_fast8_t;
typedef int            int_fast8_t;
typedef unsigned int   uint_fast16_t;
typedef int            int_fast16_t;
typedef long           uint_fast32_t;
typedef long           int_fast32_t;
typedef int            intptr_t;
typedef unsigned int   uintptr_t;
typedef long           intmax_t;
typedef long           uintmax_t;
#endif
