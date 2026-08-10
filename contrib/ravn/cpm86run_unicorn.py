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

Load model: CP/M-86 8080 -> single Code group at offset 0 of a segment, with
CS=DS=ES=SS=LOAD_SEG, SP at top, execution beginning at CS:0000.
"""

import sys
from unicorn import (Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR)
from unicorn.x86_const import (
    UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS,
    UC_X86_REG_SP, UC_X86_REG_IP, UC_X86_REG_CX, UC_X86_REG_DX,
    UC_X86_REG_AX,
)

LOAD_SEG = 0x1000
MEM_BASE = 0x0000
MEM_SIZE = 0x100000  # 1 MB, must be page aligned for Unicorn


class Done(Exception):
    pass


class BdosUnimplemented(Exception):
    def __init__(self, func):
        super().__init__(f"unimplemented CP/M-86 BDOS function {func} "
                         f"(0x{func:02X})")
        self.func = func


def run(path, stdin_bytes=b""):
    """Load and run a .CMD file. Returns the captured console output (str).

    stdin_bytes feeds console-input BDOS calls (functions 1/6/10); when it runs
    out, input calls return 0 / empty.
    """
    data = open(path, "rb").read()
    if len(data) < 128 or not (1 <= data[0] <= 9):
        raise ValueError("not a CP/M-86 .CMD file")
    body = data[128:]

    uc = Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(MEM_BASE, MEM_SIZE)

    base = LOAD_SEG << 4
    uc.mem_write(base, body)

    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        uc.reg_write(reg, LOAD_SEG)
    uc.reg_write(UC_X86_REG_SP, 0xFFFE)
    uc.reg_write(UC_X86_REG_IP, 0x0000)

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

    try:
        uc.emu_start(base + 0x0000, base + len(body))
    except Exception:
        pass
    if state.get("error"):
        raise state["error"]
    return out.decode("cp437", errors="replace")


def main(argv=None):
    argv = argv or sys.argv[1:]
    if not argv:
        print("usage: cpm86run_unicorn.py FILE.CMD", file=sys.stderr)
        return 2
    try:
        sys.stdout.write(run(argv[0]))
        sys.stdout.flush()
    except BdosUnimplemented as e:
        print(f"\ncpm86run_unicorn: {e}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
