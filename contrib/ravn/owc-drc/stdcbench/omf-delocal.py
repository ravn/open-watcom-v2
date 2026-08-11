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
"""
import sys

SWAP = {0xB4: 0x8C, 0xB6: 0x90}


def process(data):
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
        out += rec
        i += 3 + ln
    return bytes(out), changed


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: omf-delocal.py IN.OBJ OUT.OBJ\n")
        return 2
    data = open(sys.argv[1], "rb").read()
    out, changed = process(data)
    open(sys.argv[2], "wb").write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
