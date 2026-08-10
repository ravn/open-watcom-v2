#!/usr/bin/env python3
"""bin2cmd - wrap a raw 8086 binary image in a CP/M-86 .CMD header.

Open Watcom's linker (wl) cannot emit CP/M-86 .CMD executables directly.
Its closest outputs are `format dos com` and `format raw` (see
bld/wl/h/_formats.h). This tool takes a raw 8086 code image -- for example
produced by:

    wcc     -ms -0 -oi hello.c            # 16-bit, small/8080-ish memory model
    wl      format raw bin  file hello.obj name hello.bin

and prepends the 128-byte CP/M-86 Command File Header so the result can be
loaded by CP/M-86.

Only the "8080 model" (single code group that also contains data, mirroring a
CP/M-80 .COM layout) is emitted here; it is the simplest model to target from a
freestanding raw image and matches wcc's tiny/small model output the closest.

Reference: Digital Research "CP/M-86 Operating System System Guide",
Appendix on Command (.CMD) File Format; cross-checked with seasip.info/Cpm/
cmdfile.html. Header = 128 bytes = 8 x 9-byte group descriptors (72 bytes) +
reserved/RSX/fixup/flags fields; each descriptor is
type(1) + length(2) + base(2) + min(2) + max(2), little-endian, in 16-byte
paragraphs. Type 1=Code, 2=Data, 4=Stack, 9=pure/shareable code. base=0 means
the group is relocatable (loader assigns the segment).
"""

import argparse
import sys

HEADER_SIZE = 128
PARA = 16  # bytes per paragraph (16-byte segment granularity)
BASE_PAGE_SIZE = 0x100  # CP/M-86 reserves 100H bytes for the base page

# Group descriptor types
G_CODE = 0x01
G_DATA = 0x02


def paragraphs(nbytes: int) -> int:
    """Round a byte count up to whole 16-byte paragraphs."""
    return (nbytes + PARA - 1) // PARA


def _put_desc(hdr, off, gtype, length, base, minp, maxp):
    """Write one 9-byte group descriptor (little-endian) into hdr at off."""
    hdr[off + 0] = gtype
    hdr[off + 1] = length & 0xFF
    hdr[off + 2] = (length >> 8) & 0xFF
    hdr[off + 3] = base & 0xFF
    hdr[off + 4] = (base >> 8) & 0xFF
    hdr[off + 5] = minp & 0xFF
    hdr[off + 6] = (minp >> 8) & 0xFF
    hdr[off + 7] = maxp & 0xFF
    hdr[off + 8] = (maxp >> 8) & 0xFF


def build_header_8080(code_len: int, max_paras: int = 0x0FFF) -> bytes:
    """Build a 128-byte CP/M-86 .CMD header for the 8080 memory model.

    A single Code group (type 1) describes the whole image. Base is 0
    (relocatable / loader-assigned). Min alloc equals the image size; max
    alloc requests extra paragraphs for stack/heap.
    """
    if code_len <= 0:
        raise ValueError("code image must be non-empty")

    g_len = paragraphs(code_len)
    if g_len > 0xFFFF:
        raise ValueError("code group exceeds 1 MB (0xFFFF paragraphs)")
    if max_paras < g_len:
        max_paras = g_len

    hdr = bytearray(HEADER_SIZE)
    _put_desc(hdr, 0, G_CODE, g_len, 0x0000, g_len, max_paras)
    # Group 1: code (holds code+data in 8080 model). Remaining 7 descriptors
    # stay zero (type 0 = unused terminator).
    return bytes(hdr)


def build_header_small(code_len: int, data_len: int,
                       data_max_paras: int = 0x0FFF) -> bytes:
    """Build a 128-byte CP/M-86 .CMD header for the small memory model.

    Two relocatable groups: Code (type 1) and Data (type 2). Matches wcc's
    small model (`-ms`), where code and data live in separate 64 KB segments.
    The Data group's max allocation is inflated to reserve stack/heap space.
    """
    if code_len <= 0:
        raise ValueError("code image must be non-empty")
    if data_len < 0:
        raise ValueError("data length must be non-negative")

    c_len = paragraphs(code_len)
    d_len = paragraphs(data_len)
    if c_len > 0xFFFF or d_len > 0xFFFF:
        raise ValueError("a group exceeds 1 MB (0xFFFF paragraphs)")
    d_max = data_max_paras if data_max_paras >= d_len else d_len

    hdr = bytearray(HEADER_SIZE)
    _put_desc(hdr, 0, G_CODE, c_len, 0x0000, c_len, c_len)
    _put_desc(hdr, 9, G_DATA, d_len, 0x0000, d_len, d_max)
    return bytes(hdr)


def parse_header(data: bytes):
    """Parse the group descriptors of a .CMD header (for tests/inspection)."""
    groups = []
    for i in range(8):
        off = i * 9
        gtype = data[off]
        if gtype == 0:
            break
        length = data[off + 1] | (data[off + 2] << 8)
        base = data[off + 3] | (data[off + 4] << 8)
        minp = data[off + 5] | (data[off + 6] << 8)
        maxp = data[off + 7] | (data[off + 8] << 8)
        groups.append((gtype, length, base, minp, maxp))
    return groups


def convert(in_path: str, out_path: str, max_paras: int,
            model: str = "8080", data_path: str = None,
            reserve_basepage: bool = True) -> None:
    """Wrap a raw image in a .CMD header.

    When reserve_basepage is true (the CP/M-86 default), a 100H-byte base page
    region is placed at offset 0 of the group the program runs from -- the code
    group in the 8080 model, the data group in the small model -- so the loader
    can fill in FCBs, the command tail, and group descriptors there. The raw
    code image is therefore assumed to be assembled at org 100H for the 8080
    model (execution begins at CS:0100H), matching the System Guide's 8080
    memory-model transient-program layout (Section 2.3).
    """
    with open(in_path, "rb") as f:
        image = f.read()
    pad = b"\x00" * BASE_PAGE_SIZE if reserve_basepage else b""
    if model == "small":
        data = b""
        if data_path:
            with open(data_path, "rb") as f:
                data = f.read()
        data_image = pad + data          # base page lives at DS:0000
        header = build_header_small(len(image), len(data_image), max_paras)
        payload = image + data_image
    else:
        code_image = pad + image         # base page at CS:0000, code at CS:0100
        header = build_header_8080(len(code_image), max_paras)
        payload = code_image
    with open(out_path, "wb") as f:
        f.write(header)
        f.write(payload)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Wrap a raw 8086 image in a CP/M-86 .CMD header")
    ap.add_argument("input", help="raw 8086 code image (e.g. from wl format raw)")
    ap.add_argument("output", help="output .CMD file")
    ap.add_argument("--model", choices=("8080", "small"), default="8080",
                    help="memory model: 8080 (single group, tiny) or small (code+data groups)")
    ap.add_argument("--data", dest="data_path", default=None,
                    help="raw data image for the small model's Data group (optional)")
    ap.add_argument("--max-paras", type=lambda x: int(x, 0), default=0x0FFF,
                    help="max allocation in 16-byte paragraphs (default 0x0FFF)")
    ap.add_argument("--no-basepage", dest="basepage", action="store_false",
                    help="do not reserve the 100H-byte base page (raw org-0 image)")
    ap.set_defaults(basepage=True)
    args = ap.parse_args(argv)
    try:
        convert(args.input, args.output, args.max_paras, args.model,
                args.data_path, args.basepage)
    except (OSError, ValueError) as e:
        print(f"bin2cmd: error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
