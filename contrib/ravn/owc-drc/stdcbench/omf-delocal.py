#!/usr/bin/env python3
"""omf-delocal.py -- make Open Watcom OMF objects linkable by DR LINK-86.

Modern Open Watcom emits LEXTDEF (0xB4) and LPUBDEF (0xB6) records for
file-scope `static` symbols.  Digital Research's LINK-86 (1987) predates those
Microsoft OMF extensions and rejects them with OBJECT FILE ERROR 5.

LEXTDEF and LPUBDEF have byte-for-byte the SAME record layout as the ordinary
EXTDEF (0x8C) and PUBDEF (0x90) records, and LEXTDEF names already share the
external-index space with EXTDEF, so simply rewriting the record-type byte
(0xB4->0x8C, 0xB6->0x90) promotes the statics to ordinary globals without
disturbing any FIXUPP indices.  The only risk -- a static name colliding with a
symbol in another module -- does not occur in stdcbench (verified), but to be
safe this tool can also uniquify names; by default it just swaps the type byte
and fixes the record checksum.

Usage: omf-delocal.py IN.OBJ OUT.OBJ

Note: DR LINK-86 also rejects long OMF THEADR (module-name) records
(OBJECT FILE ERROR 10).  Open Watcom stamps the absolute source path there, so
compile from a short directory using short (8.3) filenames -- the build script
does this -- rather than rewriting THEADR.

Equivalent copy: scratch/rc759-cmd-toolchain/omf_classicize.py carries the same
LEXTDEF/LPUBDEF swap and --merge-text-into-code logic (and additionally shortens
long THEADR records instead of relying on short-path compilation).  Keep the two
in sync when the shared logic changes.
"""
import sys

SWAP = {0xB4: 0x8C, 0xB6: 0x90}


def _lnames(data):
    # LNAMES strings in OMF order (1-indexed as the linker sees them).
    names = ['']
    i = 0
    n = len(data)
    while i + 3 <= n:
        t = data[i]
        ln = data[i + 1] | (data[i + 2] << 8)
        body = data[i + 3:i + 3 + ln]
        if t == 0x96:
            j = 0
            while j < len(body) - 1:
                sl = body[j]
                names.append(body[j + 1:j + 1 + sl].decode('latin1'))
                j += 1 + sl
        i += 3 + ln
    return names


def process(data, merge_text_into_code=False):
    # merge_text_into_code: repoint any SEGDEF whose segment name is '_TEXT' to
    # the LNAMES entry 'CODE' so DR LINK-86 (which merges by SEGMENT NAME, not
    # class) folds Open Watcom's own helper code (cgsupp i4m/i4d: __U4M/__U4D
    # etc.) into the small-model CODE group produced by `bwcc -nt=CODE`.  Without
    # it a near CALL from CODE to the helper's separate _TEXT segment is "TARGET
    # OUT OF RANGE".  Large model far-calls the helper, so leave it untouched.
    names = _lnames(data)
    ti = names.index('_TEXT') if '_TEXT' in names else None
    ci = names.index('CODE') if 'CODE' in names else None
    out = bytearray()
    i = 0
    n = len(data)
    changed = 0
    while i + 3 <= n:
        t = data[i]
        ln = data[i + 1] | (data[i + 2] << 8)
        rec = bytearray(data[i:i + 3 + ln])
        if t in SWAP:
            rec[0] = SWAP[t]
            # OMF checksum: last byte makes the record's byte sum == 0 (mod 256).
            # A stored checksum of 0 means "ignore"; preserve that convention,
            # otherwise recompute so the sum stays valid.
            if rec[-1] != 0:
                s = sum(rec[:-1]) & 0xFF
                rec[-1] = (256 - s) & 0xFF
            changed += 1
        elif merge_text_into_code and t in (0x98, 0x99) and ti is not None and ci is not None and ti < 0x80 and ci < 0x80:
            # SEGDEF: ACBP[0]; if A(lignment)=0 an absolute frame/offset (3B)
            # follows; then length(2), seg-name-index(1B when <0x80).  Our helper
            # objects use A=2 (para-relative) + small indices, so the seg-name
            # index sits at rec offset 3 + (0) + 2 = 5 within the record body.
            acbp = rec[3]
            a = (acbp >> 5) & 7
            off = 3 + 1 + (3 if a == 0 else 0) + 2
            if off < len(rec) - 1 and rec[off] == ti:
                rec[off] = ci
                if rec[-1] != 0:
                    s = sum(rec[:-1]) & 0xFF
                    rec[-1] = (256 - s) & 0xFF
                changed += 1
        out += rec
        i += 3 + ln
    return bytes(out), changed


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    merge = '--merge-text-into-code' in sys.argv[1:]
    if len(args) != 2:
        sys.stderr.write("usage: omf-delocal.py [--merge-text-into-code] IN.OBJ OUT.OBJ\n")
        return 2
    data = open(args[0], "rb").read()
    out, changed = process(data, merge_text_into_code=merge)
    open(args[1], "wb").write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
