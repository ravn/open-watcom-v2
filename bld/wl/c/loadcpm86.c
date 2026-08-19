/****************************************************************************
*
*                            Open Watcom Project
*
* Copyright (c) 2026 The Open Watcom Contributors. All Rights Reserved.
*
*  ========================================================================
*
*    This file contains Original Code and/or Modifications of Original
*    Code as defined in and that are subject to the Sybase Open Watcom
*    Public License version 1.0 (the 'License'). You may not use this file
*    except in compliance with the License. BY USING THIS FILE YOU AGREE TO
*    ALL TERMS AND CONDITIONS OF THE LICENSE. A copy of the License is
*    provided with the Original Code and Modifications, and is also
*    available at www.sybase.com/developer/opensource.
*
*    The Original Code and all software distributed under the License are
*    distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
*    EXPRESS OR IMPLIED, AND SYBASE AND ALL CONTRIBUTORS HEREBY DISCLAIM
*    ALL SUCH WARRANTIES, INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF
*    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR
*    NON-INFRINGEMENT. Please see the License for the specific language
*    governing rights and limitations under the License.
*
*  ========================================================================
*
* Description:  Routines for creation of CP/M-86 .CMD command files.
*
*   A .CMD file is a 128-byte header followed by group images.  The header is
*   up to eight 9-byte group descriptors:
*       db type   (1=CODE, 2=DATA, 3=EXTRA, 4=STACK, 9=pure code)
*       dw length (paragraphs of stored image)
*       dw base   (load paragraph; 0 => relocated by the loader)
*       dw min    (paragraphs to allocate, incl. BSS)
*       dw max    (maximum paragraphs to allocate)
*   Group images are packed at PARAGRAPH (16-byte) granularity: each group's
*   stored image is padded to a paragraph so its byte length matches the
*   paragraph "length" field in its descriptor, and the loader finds the next
*   group at base + length*16.  (Genuine DRI .CMD files pack this way; padding
*   an image to a 128-byte record while declaring only its paragraph length
*   left every following group's data at an offset the loader never read.)
*   Phase 1 emits
*   base=0 relocatable images with no fixup table (header 0x7F bit 7 clear),
*   which covers the small (CODE+DATA) and 8080 (single group) models.
*
****************************************************************************/


#include <string.h>
#include "linkstd.h"
#include "loadfile.h"
#include "dbgall.h"
#include "loadcpm86.h"
#include "cmdcpm86.h"


#ifdef _CPM86

#define CMD_HDR_SIZE    128
#define CMD_REC_SIZE    128
#define CMD_PARA_SIZE   16
#define CMD_MAX_GROUPS  8

#define CMD_TYPE_CODE   1
#define CMD_TYPE_DATA   2
#define CMD_TYPE_EXTRA  3

/* number of 16-byte paragraphs needed to hold size bytes */
#define CMD_PARAS(size) ((unsigned_16)( __ROUND_UP_SIZE_PARA( size ) >> 4 ))

static unsigned_8 *putU16( unsigned_8 *p, unsigned_16 val )
/*********************************************************/
{
    *p++ = (unsigned_8)val;
    *p++ = (unsigned_8)( val >> 8 );
    return( p );
}

void FiniCPM86LoadFile( void )
/*****************************
 * write the group images and the 128-byte descriptor header
 */
{
    group_entry     *group;
    unsigned_8      header[CMD_HDR_SIZE];
    unsigned_8      *desc;
    int             ndesc;
    offset          img_len;
    size_t          pad;

    memset( header, 0, sizeof( header ) );
    OrderGroups( CompareDosSegments );
    CurrSect = Root;
    Root->outfile->file_loc = 0;
    SeekLoad( CMD_HDR_SIZE );           /* reserve the header record */

    desc = header;
    ndesc = 0;

    /* Coalesce ALL CLASS_CODE groups into ONE type-1 CODE group descriptor
     * (Stage B step 1).  The medium model (`-mm -zm`) emits one `<func>_TEXT`
     * CODE group per function; a genuine CP/M-86 .CMD may hold at most eight
     * groups and expects a SINGLE type-1 CODE group whose far references are
     * resolved by loader fixups, not one type-1 descriptor per source segment
     * (which is what the old per-group loop wrote, overflowing CMD_MAX_GROUPS
     * and giving each func its own load base).  We write every code group's
     * image contiguously, paragraph-packed, and sum their paragraph lengths
     * into one descriptor.  In the small/8080 models there is exactly one
     * CLASS_CODE group, so this is byte-identical to the old output.
     *
     * OrderGroups(CompareDosSegments) has already placed all CODE-class groups
     * ahead of DATA, so writing code in this first pass and data in the second
     * keeps the file image code-first / data-second regardless. */
    {
        offset          code_img_paras = 0;     /* stored image, paragraphs */
        offset          code_alloc_paras = 0;   /* min==max alloc, paras    */
        bool            have_code = false;

        for( group = Groups; group != NULL; group = group->next ) {
            if( CalcGroupSize( group ) == 0 )
                continue;
            if( ( group->leaders->class->flags & CLASS_CODE ) == 0 )
                continue;
            CurrSect = group->section;
            img_len = WriteGroupLoad( group, false );   /* stored image bytes */
            /* Pad each code group's stored image to a PARAGRAPH (16-byte)
             * boundary so the concatenated code image stays paragraph-aligned
             * and the summed paragraph length matches the bytes on disk. */
            pad = (size_t)( -(long)img_len & ( CMD_PARA_SIZE - 1 ) );
            if( pad != 0 )
                PadLoad( pad );
            code_img_paras += CMD_PARAS( img_len );
            code_alloc_paras += CMD_PARAS( CalcGroupSize( group ) );
            have_code = true;
        }
        if( have_code ) {
            *desc++ = CMD_TYPE_CODE;
            desc = putU16( desc, (unsigned_16)code_img_paras );    /* length */
            desc = putU16( desc, 0 );                              /* base   */
            desc = putU16( desc, (unsigned_16)code_alloc_paras );  /* min    */
            desc = putU16( desc, (unsigned_16)code_alloc_paras );  /* max    */
            ndesc++;
        }
    }

    /* Now the non-CODE groups (DATA, and any others): one descriptor each,
     * written after the coalesced code image so the loader reads code then
     * data contiguously. */
    for( group = Groups; group != NULL; group = group->next ) {
        if( ndesc >= CMD_MAX_GROUPS )
            break;
        if( CalcGroupSize( group ) == 0 )
            continue;
        if( group->leaders->class->flags & CLASS_CODE )
            continue;
        CurrSect = group->section;
        img_len = WriteGroupLoad( group, false );   /* stored image bytes */
        /* Pad the stored image to a PARAGRAPH (16-byte) boundary so its byte
         * length equals the paragraph "length" written into the descriptor
         * below.  The loader locates each following group at base + length*16,
         * so padding to a 128-byte record here while declaring only the
         * paragraph length would leave the next group's image 0..112 bytes
         * past where the loader reads it -- making all of its data come back
         * zero.  Genuine DRI .CMD files pack groups at paragraph granularity. */
        pad = (size_t)( -(long)img_len & ( CMD_PARA_SIZE - 1 ) );
        if( pad != 0 )
            PadLoad( pad );
        *desc++ = CMD_TYPE_DATA;
        desc = putU16( desc, CMD_PARAS( img_len ) );            /* length */
        desc = putU16( desc, 0 );                               /* base   */
        desc = putU16( desc, CMD_PARAS( CalcGroupSize( group ) ) ); /* min */
        desc = putU16( desc, CMD_PARAS( CalcGroupSize( group ) ) ); /* max */
        ndesc++;
    }

    /* Stage A compact model (`OPTION FARHEAP=<size>`): append a type-3
     * Extra group descriptor with NO stored image -- its memory is never
     * written by the linker, only reserved by the loader at load time
     * (G_Length==0).  Per the CP/M-86 System Guide Sec.2.5, the loader sets
     * ES to this group's base automatically at program entry -- crt0 needs
     * no code for this at all (see reference_cpm86_cmd_header.md's Sec.2.5
     * note).  This descriptor, being present at all, is what makes the
     * loader treat the whole file as "Compact Model" instead of "Small
     * Model" -- the model is implicit in which group types exist, not a
     * separate header flag.
     *
     * G_Min is deliberately just ONE paragraph, not the same value as
     * G_Max: G_Min is what the loader must satisfy to run the program at
     * all (a large G_Min made an early 300K test outright REFUSE to load
     * under real Concurrent CP/M-86, "For lidt lager", even though less
     * memory would have been fine) while G_Max=FARHEAP size is only a
     * ceiling -- CP/M-86's loader grants whatever is actually free between
     * G_Min and G_Max, and reports the ACTUAL grant back via the base
     * page's Extra-group length field. port/farheap.c's __AllocSeg already
     * reads that actual (not requested) size, so this makes `OPTION
     * FARHEAP=<size>` mean "use up to this much of whatever RAM is really
     * available", not "fail unless exactly this much is free". */
    if( CPM86FarHeapSize != 0 && ndesc < CMD_MAX_GROUPS ) {
        unsigned_16     paras;

        paras = CMD_PARAS( CPM86FarHeapSize );
        *desc++ = CMD_TYPE_EXTRA;
        desc = putU16( desc, 0 );          /* length: no stored image   */
        desc = putU16( desc, 0 );          /* base: relocatable         */
        desc = putU16( desc, 1 );          /* min: just enough to load  */
        desc = putU16( desc, paras );      /* max: ceiling              */
        ndesc++;
    }

    /* Append any debug info AFTER the group images.  This is safe ONLY while
     * header byte 127 (ch_lbyte) bit 7 is clear, i.e. Phase 1 (no fixups):
     * with bit 7 clear the genuine CP/M-86 loader never reads past the images.
     * But byte 127 bit 7 = "fixup records present" and header word 0x7D
     * (ch_fixrec) names a trailing file RECORD the loader DOES read and apply
     * (verified in Concurrent CP/M-86 2.0 source kern/cmdh.def + kern/load.sup;
     * see reference_cpm86_cmd_header_ccpm_source.md).  So once Stage B sets
     * bit 7, the fixup table must sit at exactly the ch_fixrec record and debug
     * info must go AFTER it without shifting that record number.
     * Stage B model (LOCKED 2026-08-19): PURE loader-relocation -- emit the
     * fixup table + bit 7 + ch_fixrec, NO crt0 self-reloc, and NO type-8 AUX4
     * copy of the reloc table.  (DR C ships a guard-coordinated dual path AND
     * an AUX4 duplicate so it also runs on emu2; we take ONLY the loader half.
     * @ravn 2026-08-19: emu2 not applying P_LOAD fixups is an emu2 BUG to fix
     * later, tracked ravn/emu2-cpm86#1 -- not worked around with AUX4 here;
     * medium-model .CMDs verify on real CP/M-86 (MAME) per ravn/rc7xx-work#15.
     * See reference_drc_cpm86_reloc_mechanism_VERIFIED.md.)
     * Must happen before we seek back to write the header, else it would
     * overwrite the images at offset 128. */
    DBIWrite();

    CurrSect = Root;
    SeekLoad( 0 );                      /* rewrite the reserved 128-byte header last */
    WriteLoad( header, sizeof( header ) );
}

#endif
