#!/usr/bin/env python3
"""Independent CP/M-86 .CMD runner using Unicorn Engine (QEMU's CPU core).

Unlike cpm86run.py (my own hand-written 8086 decoder), here the actual 8086
instruction execution is done by Unicorn/QEMU -- code I did not write -- so a
correct result is independent confirmation that the .CMD's machine code and
entry point are right. Only the CP/M-86 BDOS layer (INT 0E0h) is emulated by
hooking the interrupt.

Load model: CP/M-86 8080 -> single Code group at offset 0 of a segment, with
CS=DS=ES=SS=LOAD_SEG, SP at top, execution beginning at CS:0000.
"""

import sys
from unicorn import (Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR,
                     UcError)
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


def run(path):
    data = open(path, "rb").read()
    if len(data) < 128 or not (1 <= data[0] <= 9):
        raise ValueError("not a CP/M-86 .CMD file")
    body = data[128:]

    uc = Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(MEM_BASE, MEM_SIZE)

    base = (LOAD_SEG << 4)
    uc.mem_write(base, body)

    uc.reg_write(UC_X86_REG_CS, LOAD_SEG)
    uc.reg_write(UC_X86_REG_DS, LOAD_SEG)
    uc.reg_write(UC_X86_REG_ES, LOAD_SEG)
    uc.reg_write(UC_X86_REG_SS, LOAD_SEG)
    uc.reg_write(UC_X86_REG_SP, 0xFFFE)
    uc.reg_write(UC_X86_REG_IP, 0x0000)

    out = bytearray()

    def hook_intr(uc, intno, user_data):
        # Real-mode INT: Unicorn reports the vector number. CP/M-86 BDOS = 0E0h.
        if intno != 0xE0:
            uc.emu_stop()
            return
        cl = uc.reg_read(UC_X86_REG_CX) & 0xFF
        dx = uc.reg_read(UC_X86_REG_DX) & 0xFFFF
        ds = uc.reg_read(UC_X86_REG_DS) & 0xFFFF
        if cl == 0:                                  # P_TERMCPM
            uc.emu_stop()
            raise Done()
        elif cl == 2:                                # C_WRITE (DL)
            out.append(dx & 0xFF)
        elif cl in (6, 9):                           # C_WRITESTR ($-terminated)
            off = dx
            while True:
                ch = uc.mem_read((ds << 4) + (off & 0xFFFF), 1)[0]
                if ch == ord("$"):
                    break
                out.append(ch)
                off = (off + 1) & 0xFFFF
            ax = uc.reg_read(UC_X86_REG_AX) & 0xFF00
            uc.reg_write(UC_X86_REG_AX, ax | 0x24)

    uc.hook_add(UC_HOOK_INTR, hook_intr)

    try:
        uc.emu_start(base + 0x0000, base + len(body))
    except Done:
        pass
    except UcError as e:
        # emu_stop() from the terminate hook can surface as a benign stop.
        if "Done" not in repr(e):
            pass
    return out.decode("cp437", errors="replace")


def main(argv=None):
    argv = argv or sys.argv[1:]
    if not argv:
        print("usage: cpm86run_unicorn.py FILE.CMD", file=sys.stderr)
        return 2
    sys.stdout.write(run(argv[0]))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
