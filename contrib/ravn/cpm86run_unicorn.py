#!/usr/bin/env python3
"""Independent CP/M-86 .CMD runner using Unicorn Engine (QEMU's CPU core).

Unlike cpm86run.py (my own hand-written 8086 decoder), here the actual 8086
instruction execution is done by Unicorn/QEMU -- code I did not write -- so a
correct result is independent confirmation that the .CMD's machine code and
entry point are right. Only the CP/M-86 BDOS layer (INT 0E0h) is emulated by
hooking the interrupt.

This is a CPU + BDOS harness, not a full CP/M-86 machine: Unicorn provides the
instruction set (incl. 80186+), and this file emulates the BDOS system calls a
program makes. The console/string group is implemented; disk/file functions are
not yet (they raise a clear "unimplemented BDOS function" error so unsupported
programs fail loudly instead of silently).

Program load emulates the CCP: the memory model (8080 / small) is read from the
.CMD group descriptors, groups are placed in memory, segment registers and the
entry IP are set per the System Guide (8080 -> CS:0100H, small -> CS:0000H),
and the base page (group descriptors, default FCBs at 005CH/006CH, command tail
at 0080H) is populated from the command line via the ccp module.
"""

import os
import sys
from unicorn import (Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_CODE)
from unicorn.x86_const import (
    UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS,
    UC_X86_REG_SP, UC_X86_REG_IP, UC_X86_REG_CX, UC_X86_REG_DX,
    UC_X86_REG_AX,
)

import bin2cmd
import ccp

LOAD_SEG = 0x1000      # paragraph where the first (code) group is placed
CCP_SEG = 0x0800       # emulated CCP area: stack + a return stub below the program
MEM_BASE = 0x0000
MEM_SIZE = 0x100000    # 1 MB, must be page aligned for Unicorn
MAX_INSNS = 200_000_000  # runaway guard (large enough for real benchmarks)


class Done(Exception):
    pass


class BdosUnimplemented(Exception):
    def __init__(self, func):
        super().__init__(f"unimplemented CP/M-86 BDOS function {func} "
                         f"(0x{func:02X})")
        self.func = func


def _detect_model(groups):
    types = [g[0] for g in groups]
    if types == [bin2cmd.G_CODE]:
        return "8080"
    if sorted(types) == [bin2cmd.G_CODE, bin2cmd.G_DATA]:
        return "small"
    return "compact"


def _load(uc, data, cmdline):
    """Load a .CMD image into `uc` and set up registers + base page like the
    CCP. Returns (cs, ip). Raises ValueError on a malformed file."""
    if len(data) < 128 or not (1 <= data[0] <= 9):
        raise ValueError("not a CP/M-86 .CMD file")
    groups = bin2cmd.parse_header(data)
    if not groups:
        raise ValueError(".CMD header has no group descriptors")
    model = _detect_model(groups)
    body = data[128:]

    # Slice the body into per-group images, in header order.
    images, off = {}, 0
    order = []
    for (gtype, length, base, minp, maxp) in groups:
        nbytes = length * 16
        images[gtype] = body[off:off + nbytes]
        order.append(gtype)
        off += nbytes

    code_img = images.get(bin2cmd.G_CODE, b"")
    data_img = images.get(bin2cmd.G_DATA, b"")
    code_len = len(code_img)

    code_seg = LOAD_SEG
    uc.mem_write(code_seg << 4, code_img)

    if model == "8080":
        data_seg = code_seg
        data_len = code_len
        entry_ip = ccp.BASE_PAGE_SIZE            # 0x100: skip the base page
    else:
        code_paras = (code_len + 15) // 16
        data_seg = code_seg + max(code_paras, 1)
        uc.mem_write(data_seg << 4, data_img)
        data_len = len(data_img)
        entry_ip = 0x0000                        # small/compact enter at CS:0000

    # Build the base page from the command line and write it into the data
    # segment (which equals the code segment in the 8080 model).
    fcb1, fcb2, tail = ccp.fcbs_and_tail_from_cmdline(cmdline)
    bp = ccp.build_base_page(model=model, code_seg=code_seg, code_len=code_len,
                             data_seg=data_seg, data_len=data_len,
                             fcb1=fcb1, fcb2=fcb2, tail=tail)
    uc.mem_write(data_seg << 4, bytes(bp))

    # Segment registers per memory model (System Guide Section 2.3-2.5).
    uc.reg_write(UC_X86_REG_CS, code_seg)
    uc.reg_write(UC_X86_REG_DS, data_seg)
    uc.reg_write(UC_X86_REG_ES, data_seg)

    # SS:SP live in the CCP, not the program. The stack is placed in the
    # program's *data* group so that SS == DS: a real C program (e.g. the
    # Dhrystone benchmark) constantly takes the address of a stack local and
    # passes it as a small-model *near* pointer, which the callee dereferences
    # through DS -- so those pointers only resolve correctly when SS == DS.
    # Give (almost) a full 64K segment of stack and a far-return stub in the
    # CCP area so a program that RETFs also terminates cleanly via BDOS 0.
    uc.mem_write(CCP_SEG << 4, bytes([0xB1, 0x00, 0xCD, 0xE0]))  # mov cl,0; int E0h
    uc.reg_write(UC_X86_REG_SS, data_seg)
    sp = 0xFFFE
    ret_frame = bytes([0x00, 0x00, CCP_SEG & 0xFF, (CCP_SEG >> 8) & 0xFF])
    uc.mem_write((data_seg << 4) + sp - 4, ret_frame)          # [IP=0][CS=CCP]
    uc.reg_write(UC_X86_REG_SP, sp - 4)

    uc.reg_write(UC_X86_REG_IP, entry_ip)
    return code_seg, entry_ip


def run(path, cmdline=None, stdin_bytes=b"", count_insns=False):
    """Load and run a .CMD file. Returns the captured console output (str).

    cmdline is the command line as an operator would type it, e.g.
    "ECHOARG A.TXT B.DAT"; its two filename arguments populate the default FCBs
    at DS:005CH / DS:006CH and its tail is placed at DS:0080H, exactly as the
    CCP does. If omitted, the program's own file name is used as the command
    with no arguments.

    stdin_bytes feeds console-input BDOS calls (functions 1/6/10); when it runs
    out, input calls return 0 / empty.

    When count_insns is true, every executed instruction is counted and the
    total is returned as a second element (out, n_instructions); the tally is
    deterministic (host-independent) and is useful as a size/work metric since
    the emulator models no real cycle timing.
    """
    data = open(path, "rb").read()
    if cmdline is None:
        cmdline = os.path.splitext(os.path.basename(path))[0].upper()

    uc = Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(MEM_BASE, MEM_SIZE)
    cs, ip = _load(uc, data, cmdline)

    out = bytearray()
    inp = bytearray(stdin_bytes)
    state = {"error": None}

    def set_al(val):
        ax = uc.reg_read(UC_X86_REG_AX) & 0xFF00
        uc.reg_write(UC_X86_REG_AX, ax | (val & 0xFF))

    def next_in():
        return inp.pop(0) if inp else 0

    def hook_intr(uc, intno, user_data):
        if intno != 0xE0:                            # only CP/M-86 BDOS
            uc.emu_stop()
            state["error"] = RuntimeError(f"unexpected INT 0x{intno:02X}")
            return
        func = uc.reg_read(UC_X86_REG_CX) & 0xFF     # CL
        dx = uc.reg_read(UC_X86_REG_DX) & 0xFFFF
        ds = uc.reg_read(UC_X86_REG_DS) & 0xFFFF

        if func == 0:                                # P_TERMCPM
            uc.emu_stop()
            state["done"] = True
        elif func == 1:                              # C_READ (echoed)
            ch = next_in()
            out.append(ch)
            set_al(ch)
        elif func == 2:                              # C_WRITE (DL)
            out.append(dx & 0xFF)
        elif func == 5:                              # L_WRITE (list device)
            out.append(dx & 0xFF)
        elif func == 6:                              # C_RAWIO
            if (dx & 0xFF) == 0xFF:                  # input request
                set_al(next_in())
            else:                                    # output
                out.append(dx & 0xFF)
        elif func == 9:                              # C_WRITESTR ($-terminated)
            off = dx
            while True:
                ch = uc.mem_read((ds << 4) + (off & 0xFFFF), 1)[0]
                if ch == ord("$"):
                    break
                out.append(ch)
                off = (off + 1) & 0xFFFF
            set_al(0x24)
        elif func == 10:                             # C_READSTR (buffered line)
            mx = uc.mem_read((ds << 4) + dx, 1)[0]   # buffer[0] = max length
            line = bytearray()
            while len(line) < mx:
                ch = next_in()
                if ch in (0, 0x0D, 0x0A):
                    break
                line.append(ch)
                out.append(ch)
            uc.mem_write((ds << 4) + dx + 1, bytes([len(line)]))
            uc.mem_write((ds << 4) + dx + 2, bytes(line))
        elif func == 11:                             # C_STAT (console status)
            set_al(1 if inp else 0)
        else:
            uc.emu_stop()
            state["error"] = BdosUnimplemented(func)

    uc.hook_add(UC_HOOK_INTR, hook_intr)

    insns = {"n": 0}
    if count_insns:
        def hook_code(uc, address, size, user_data):
            insns["n"] += 1
        uc.hook_add(UC_HOOK_CODE, hook_code)

    try:
        uc.emu_start((cs << 4) + ip, 0, count=MAX_INSNS)
    except Exception:
        pass
    if state.get("error"):
        raise state["error"]
    text = out.decode("cp437", errors="replace")
    if count_insns:
        return text, insns["n"]
    return text


def main(argv=None):
    argv = argv or sys.argv[1:]
    count_insns = False
    if argv and argv[0] in ("--count", "-c"):
        count_insns = True
        argv = argv[1:]
    if not argv:
        print("usage: cpm86run_unicorn.py [--count] FILE.CMD [ARG ...]",
              file=sys.stderr)
        return 2
    path = argv[0]
    prog = os.path.splitext(os.path.basename(path))[0].upper()
    cmdline = " ".join([prog] + list(argv[1:]))
    try:
        stdin_bytes = b""
        try:
            if not sys.stdin.isatty():
                stdin_bytes = sys.stdin.buffer.read()
        except Exception:
            stdin_bytes = b""
        result = run(path, cmdline=cmdline, stdin_bytes=stdin_bytes,
                     count_insns=count_insns)
        if count_insns:
            text, n = result
            sys.stdout.write(text)
            sys.stdout.flush()
            print(f"\n[{n} instructions executed]", file=sys.stderr)
        else:
            sys.stdout.write(result)
            sys.stdout.flush()
    except BdosUnimplemented as e:
        print(f"\ncpm86run_unicorn: {e}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
