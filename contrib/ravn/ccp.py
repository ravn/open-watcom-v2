#!/usr/bin/env python3
"""ccp - emulate what the CP/M-86 CCP sets up before a transient program runs.

When the CP/M-86 Console Command Processor (CCP) loads a .CMD file and transfers
control to it, it first populates the program's **base page** (the first 100H
bytes of the data segment) from the command line the operator typed:

  * up to two filename arguments are parsed into default FCBs at DS:005CH and
    DS:006CH,
  * the rest of the command line (the "command tail") is placed at DS:0080H as
    a length byte followed by the characters (this doubles as the default DMA
    buffer),
  * group length/base descriptors and the 8080-model flag (M80) are filled in
    from the .CMD header.

This module builds exactly that memory image so an emulator can hand a program
the same environment a real CCP would. References are to the *CP/M-86 System
Guide* (Jun 1983), Sections 2.6/2.7 and 4.3, in this folder.

Base page layout (relative to DS), from Figure 2-4. Each group descriptor is
6 bytes: a 3-byte length/last-location (L) + a 2-byte paragraph base (B) + a
trailing byte (M80 for the code group, unused otherwise):

  00-02 LC  last code location (len-1)      03-04 BC code base para   05 M80
  06-08 LD  last data location              09-0A BD data base para   0B  -
  0C-0E LE  last extra location             0F-10 BE extra base       11  -
  12-14 LS  last stack location             15-16 BS stack base       17  -
  18-2F LX/BX  four optional auxiliary group descriptors (6 bytes each)
  5C    default FCB #1 (parsed first filename)
  6C    default FCB #2 (parsed second filename)
  80    command tail / default 128-byte DMA buffer
  100   begin user data
"""

# Base-page field offsets (relative to DS).
BP_LC = 0x00
BP_BC = 0x03
BP_M80 = 0x05
BP_LD = 0x06
BP_BD = 0x09
BP_LE = 0x0C
BP_BE = 0x0F
BP_LS = 0x12
BP_BS = 0x15
BP_FCB1 = 0x5C
BP_FCB2 = 0x6C
BP_DMA = 0x80
BASE_PAGE_SIZE = 0x100
DMA_BUF_SIZE = 0x80

FCB_SIZE = 16  # the name/extent portion the CCP fills in (bytes 0..15)


def _put16(buf, off, val):
    buf[off] = val & 0xFF
    buf[off + 1] = (val >> 8) & 0xFF


def _put24(buf, off, val):
    buf[off] = val & 0xFF
    buf[off + 1] = (val >> 8) & 0xFF
    buf[off + 2] = (val >> 16) & 0xFF


def parse_fcb(token):
    """Parse one command-line filename into a 16-byte FCB name/extent image.

    Layout (System Guide 4.3): byte 0 = drive code (0 = default, 1 = A .. 16 =
    P); bytes 1..8 = filename; bytes 9..11 = type; both space-padded, ASCII
    upper case, high bit clear. Bytes 12..15 (ex, s1, s2, rc) are zeroed, as
    the CCP leaves them for OPEN. A '*' fills the remainder of its field with
    '?' wildcards; a literal '?' is kept.
    """
    fcb = bytearray(FCB_SIZE)
    for i in range(1, 12):               # name+type default to spaces
        fcb[i] = ord(" ")

    t = token or ""
    # Optional drive prefix "X:".
    if len(t) >= 2 and t[1] == ":":
        c = t[0].upper()
        if "A" <= c <= "P":
            fcb[0] = ord(c) - ord("A") + 1
        t = t[2:]

    if "." in t:
        name, _, ext = t.partition(".")
    else:
        name, ext = t, ""

    def fill(field, start, width):
        i = 0
        while i < width and i < len(field):
            ch = field[i]
            if ch == "*":                # star fills rest of field with '?'
                while i < width:
                    fcb[start + i] = ord("?")
                    i += 1
                return
            fcb[start + i] = ord(ch.upper()) & 0x7F
            i += 1

    fill(name, 1, 8)
    fill(ext, 9, 3)
    return bytes(fcb)


def split_command_line(cmdline):
    """Split a typed command line into (program, tail, arg_tokens).

    `program` is the first whitespace-delimited token; `tail` is the remainder
    of the line verbatim (including the separating whitespace), which is what
    the CCP stores at 0080H; `arg_tokens` are the whitespace-delimited
    arguments used to build the two default FCBs.
    """
    cmdline = cmdline or ""
    stripped = cmdline.lstrip()
    lead = len(cmdline) - len(stripped)
    if not stripped:
        return "", "", []
    # program name = first token
    j = 0
    while j < len(stripped) and not stripped[j].isspace():
        j += 1
    program = stripped[:j]
    tail = cmdline[lead + j:]
    arg_tokens = stripped[j:].split()
    return program, tail, arg_tokens


def build_command_tail(tail):
    """Build the 128-byte default buffer at 0080H holding the command tail.

    Byte 0 is the character count; bytes 1.. are the tail, upper-cased as the
    CCP does, followed by a terminating 0. The buffer is exactly 128 bytes so
    it fills 0080H..00FFH.
    """
    text = (tail or "").upper().encode("ascii", errors="replace")
    text = text[:DMA_BUF_SIZE - 2]       # leave room for count + terminator
    buf = bytearray(DMA_BUF_SIZE)
    buf[0] = len(text)
    buf[1:1 + len(text)] = text
    # remaining bytes (incl. terminator right after the text) stay zero
    return bytes(buf)


def build_base_page(*, model, code_seg, code_len,
                    data_seg=None, data_len=None,
                    fcb1=None, fcb2=None, tail=""):
    """Build the 256-byte base page the CCP hands to a transient program.

    model:    "8080", "small" or "compact".
    code_seg: paragraph base of the code group (BC).
    code_len: byte length of the code group (LC = code_len - 1).
    data_seg/data_len: data group base/length (small/compact); default to the
              code group for the 8080 model where code and data overlap.
    fcb1/fcb2: 16-byte FCB images (see parse_fcb); default to empty FCBs.
    tail:     the command tail string placed at 0080H.
    """
    if data_seg is None:
        data_seg = code_seg
    if data_len is None:
        data_len = code_len

    bp = bytearray(BASE_PAGE_SIZE)

    _put24(bp, BP_LC, max(code_len - 1, 0))
    _put16(bp, BP_BC, code_seg)
    bp[BP_M80] = 1 if model == "8080" else 0
    _put24(bp, BP_LD, max(data_len - 1, 0))
    _put16(bp, BP_BD, data_seg)

    if fcb1 is None:
        fcb1 = parse_fcb("")
    if fcb2 is None:
        fcb2 = parse_fcb("")
    bp[BP_FCB1:BP_FCB1 + FCB_SIZE] = fcb1[:FCB_SIZE]
    bp[BP_FCB2:BP_FCB2 + FCB_SIZE] = fcb2[:FCB_SIZE]

    tailbuf = build_command_tail(tail)
    bp[BP_DMA:BP_DMA + len(tailbuf)] = tailbuf
    return bp


def fcbs_and_tail_from_cmdline(cmdline):
    """Convenience: from a typed command line return (fcb1, fcb2, tail)."""
    _prog, tail, args = split_command_line(cmdline)
    a0 = args[0] if len(args) >= 1 else ""
    a1 = args[1] if len(args) >= 2 else ""
    return parse_fcb(a0), parse_fcb(a1), tail


def _selftest():
    # FCB parsing
    f = parse_fcb("b:file.txt")
    assert f[0] == 2, f[0]
    assert f[1:9] == b"FILE    ", f[1:9]
    assert f[9:12] == b"TXT", f[9:12]
    assert f[12:16] == b"\x00\x00\x00\x00"
    # default drive + wildcard
    f = parse_fcb("a*.c")
    assert f[0] == 0
    assert f[1:9] == b"A???????", f[1:9]
    assert f[9:12] == b"C  ", f[9:12]
    # no name
    assert parse_fcb("")[1:12] == b" " * 11

    # command-line split
    prog, tail, args = split_command_line("ECHOARG one two.dat")
    assert prog == "ECHOARG", prog
    assert tail == " one two.dat", repr(tail)
    assert args == ["one", "two.dat"], args

    # command tail buffer
    buf = build_command_tail(" one two.dat")
    assert buf[0] == len(" ONE TWO.DAT"), buf[0]
    assert buf[1:1 + buf[0]] == b" ONE TWO.DAT"
    assert len(buf) == 0x80

    # base page
    fcb1, fcb2, tail = fcbs_and_tail_from_cmdline("PROG A.TXT B.DAT")
    bp = build_base_page(model="8080", code_seg=0x1000, code_len=0x130,
                         fcb1=fcb1, fcb2=fcb2, tail=tail)
    assert len(bp) == 0x100
    assert bp[BP_M80] == 1
    assert bp[BP_BC] | (bp[BP_BC + 1] << 8) == 0x1000
    assert bp[BP_LC] | (bp[BP_LC + 1] << 8) == 0x12F
    assert bp[BP_FCB1] == 0
    assert bp[BP_FCB1 + 1:BP_FCB1 + 9] == b"A       "
    assert bp[BP_FCB1 + 9:BP_FCB1 + 12] == b"TXT"
    assert bp[BP_FCB2 + 1:BP_FCB2 + 9] == b"B       "
    assert bp[BP_FCB2 + 9:BP_FCB2 + 12] == b"DAT"
    assert bp[BP_DMA] == len(" A.TXT B.DAT")
    # small model clears M80 and uses the data group
    bp2 = build_base_page(model="small", code_seg=0x1000, code_len=0x40,
                          data_seg=0x1040, data_len=0x200)
    assert bp2[BP_M80] == 0
    assert bp2[BP_BD] | (bp2[BP_BD + 1] << 8) == 0x1040
    print("ccp selftest OK")


if __name__ == "__main__":
    _selftest()
