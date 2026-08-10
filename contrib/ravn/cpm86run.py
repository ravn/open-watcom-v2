#!/usr/bin/env python3
"""cpm86run - a minimal but real 8086 interpreter that runs CP/M-86 .CMD files.

This is NOT a full PC emulator. It decodes and executes actual 8086 real-mode
machine code from the .CMD image and services CP/M-86 BDOS calls (INT 0E0h),
which is enough to run small freestanding programs such as HELLO.CMD.

Loading follows the CP/M-86 8080 memory model: the single Code group is placed
at offset 0 of a segment, CS=DS=ES=SS point at that segment, SP starts at the
top, and execution begins at CS:0000 (per the DR CP/M-86 System Guide).
"""

import sys

MEM_SIZE = 1 << 20  # 1 MB real-mode address space


class Halt(Exception):
    pass


class CPU:
    def __init__(self):
        self.mem = bytearray(MEM_SIZE)
        self.r = {k: 0 for k in ("ax", "bx", "cx", "dx", "sp", "bp", "si", "di")}
        self.s = {k: 0 for k in ("cs", "ds", "es", "ss")}
        self.ip = 0
        self.out = bytearray()

    # ---- byte/word register access ------------------------------------
    _R8 = ["al", "cl", "dl", "bl", "ah", "ch", "dh", "bh"]
    _R16 = ["ax", "cx", "dx", "bx", "sp", "bp", "si", "di"]
    _SREG = ["es", "cs", "ss", "ds"]

    def get8(self, i):
        name = self._R8[i]
        base = name[0] + "x"
        v = self.r[base]
        return v & 0xFF if name[1] == "l" else (v >> 8) & 0xFF

    def set8(self, i, val):
        name = self._R8[i]
        base = name[0] + "x"
        v = self.r[base]
        val &= 0xFF
        if name[1] == "l":
            self.r[base] = (v & 0xFF00) | val
        else:
            self.r[base] = (v & 0x00FF) | (val << 8)

    def get16(self, i):
        return self.r[self._R16[i]] & 0xFFFF

    def set16(self, i, val):
        self.r[self._R16[i]] = val & 0xFFFF

    # ---- memory -------------------------------------------------------
    @staticmethod
    def lin(seg, off):
        return ((seg << 4) + (off & 0xFFFF)) & 0xFFFFF

    def r8(self, seg, off):
        return self.mem[self.lin(seg, off)]

    def r16(self, seg, off):
        a = self.lin(seg, off)
        return self.mem[a] | (self.mem[(a + 1) & 0xFFFFF] << 8)

    def w16(self, seg, off, val):
        a = self.lin(seg, off)
        self.mem[a] = val & 0xFF
        self.mem[(a + 1) & 0xFFFFF] = (val >> 8) & 0xFF

    def push(self, val):
        self.r["sp"] = (self.r["sp"] - 2) & 0xFFFF
        self.w16(self.s["ss"], self.r["sp"], val)

    def pop(self):
        val = self.r16(self.s["ss"], self.r["sp"])
        self.r["sp"] = (self.r["sp"] + 2) & 0xFFFF
        return val

    # ---- instruction fetch -------------------------------------------
    def fetch8(self):
        b = self.r8(self.s["cs"], self.ip)
        self.ip = (self.ip + 1) & 0xFFFF
        return b

    def fetch16(self):
        lo = self.fetch8()
        hi = self.fetch8()
        return lo | (hi << 8)

    # ---- 16-bit ModR/M ------------------------------------------------
    def modrm(self):
        m = self.fetch8()
        mod = (m >> 6) & 3
        reg = (m >> 3) & 7
        rm = m & 7
        if mod == 3:
            return mod, reg, rm, None  # register direct
        # memory operand: compute effective address (offset)
        if rm == 0:
            off = self.get16(3) + self.get16(6)          # bx+si
        elif rm == 1:
            off = self.get16(3) + self.get16(7)          # bx+di
        elif rm == 2:
            off = self.get16(5) + self.get16(6)          # bp+si
        elif rm == 3:
            off = self.get16(5) + self.get16(7)          # bp+di
        elif rm == 4:
            off = self.get16(6)                          # si
        elif rm == 5:
            off = self.get16(7)                          # di
        elif rm == 6:
            off = 0 if mod == 0 else self.get16(5)       # disp16 / bp
            if mod == 0:
                off = self.fetch16()
                return mod, reg, rm, off & 0xFFFF
        else:
            off = self.get16(3)                          # bx
        if mod == 1:
            disp = self.fetch8()
            if disp & 0x80:
                disp -= 0x100
            off += disp
        elif mod == 2:
            off += self.fetch16()
        return mod, reg, rm, off & 0xFFFF

    # ---- BDOS (INT 0E0h) ---------------------------------------------
    def bdos(self):
        func = self.r["cx"] & 0xFF          # CL
        dx = self.r["dx"] & 0xFFFF
        if func == 0:                        # P_TERMCPM
            raise Halt()
        elif func == 2:                      # C_WRITE (char in DL)
            self.out.append(dx & 0xFF)
        elif func in (9, 6):                 # C_WRITESTR ($-terminated at DS:DX)
            off = dx
            while True:
                ch = self.r8(self.s["ds"], off)
                if ch == ord("$"):
                    break
                self.out.append(ch)
                off = (off + 1) & 0xFFFF
            self.r["ax"] = (self.r["ax"] & 0xFF00) | 0x24
        else:
            # Unimplemented call: ignore, return 0 in AL.
            self.r["ax"] &= 0xFF00

    # ---- main loop ----------------------------------------------------
    def step(self):
        op = self.fetch8()
        if op == 0x90:                                   # nop
            return
        if op == 0xF4:                                   # hlt
            raise Halt()
        if op in (0x06, 0x0E, 0x16, 0x1E):               # push sreg
            self.push(self.s[["es", "cs", "ss", "ds"][op >> 3]])
            return
        if op in (0x07, 0x17, 0x1F):                     # pop es/ss/ds
            self.s[{0x07: "es", 0x17: "ss", 0x1F: "ds"}[op]] = self.pop()
            return
        if 0x50 <= op <= 0x57:                           # push r16
            self.push(self.get16(op - 0x50))
            return
        if 0x58 <= op <= 0x5F:                           # pop r16
            self.set16(op - 0x58, self.pop())
            return
        if 0xB0 <= op <= 0xB7:                           # mov r8, ib
            self.set8(op - 0xB0, self.fetch8())
            return
        if 0xB8 <= op <= 0xBF:                           # mov r16, iw
            self.set16(op - 0xB8, self.fetch16())
            return
        if op in (0x88, 0x89, 0x8A, 0x8B):               # mov (modrm)
            w = op & 1
            d = (op >> 1) & 1
            mod, reg, rm, off = self.modrm()
            if mod == 3:
                if w:
                    src, dst = (reg, rm) if d else (rm, reg)
                    self.set16(dst, self.get16(src))
                else:
                    src, dst = (reg, rm) if d else (rm, reg)
                    self.set8(dst, self.get8(src))
            else:
                seg = self.s["ds"]
                if w:
                    if d:
                        self.set16(reg, self.r16(seg, off))
                    else:
                        self.w16(seg, off, self.get16(reg))
                else:
                    if d:
                        self.set8(reg, self.r8(seg, off))
                    else:
                        a = self.lin(seg, off)
                        self.mem[a] = self.get8(reg)
            return
        if op == 0x8E:                                   # mov sreg, r/m16
            mod, reg, rm, off = self.modrm()
            val = self.get16(rm) if mod == 3 else self.r16(self.s["ds"], off)
            self.s[self._SREG[reg & 3]] = val
            return
        if op == 0x8C:                                   # mov r/m16, sreg
            mod, reg, rm, off = self.modrm()
            val = self.s[self._SREG[reg & 3]]
            if mod == 3:
                self.set16(rm, val)
            else:
                self.w16(self.s["ds"], off, val)
            return
        if op == 0x8D:                                   # lea r16, m
            mod, reg, rm, off = self.modrm()
            self.set16(reg, off or 0)
            return
        if op in (0x30, 0x31, 0x32, 0x33):               # xor
            w = op & 1
            d = (op >> 1) & 1
            mod, reg, rm, off = self.modrm()
            if mod == 3:
                if w:
                    res = self.get16(rm) ^ self.get16(reg)
                    self.set16(rm if not d else reg, res)
                else:
                    res = self.get8(rm) ^ self.get8(reg)
                    self.set8(rm if not d else reg, res)
            return
        if op == 0xEB:                                   # jmp short
            rel = self.fetch8()
            if rel & 0x80:
                rel -= 0x100
            self.ip = (self.ip + rel) & 0xFFFF
            return
        if op == 0xE9:                                   # jmp near
            rel = self.fetch16()
            if rel & 0x8000:
                rel -= 0x10000
            self.ip = (self.ip + rel) & 0xFFFF
            return
        if op == 0xC3:                                   # ret (near)
            self.ip = self.pop()
            return
        if op == 0xCB:                                   # retf
            self.ip = self.pop()
            self.s["cs"] = self.pop()
            return
        if op == 0xCD:                                   # int ib
            n = self.fetch8()
            if n == 0xE0:
                self.bdos()
                return
            if n == 0x21:                                # tolerate DOS-style too
                self.bdos()
                return
            raise Halt()
        raise NotImplementedError(f"unimplemented opcode 0x{op:02X} at "
                                  f"{self.s['cs']:04X}:{(self.ip-1)&0xFFFF:04X}")

    def run(self, max_steps=100000):
        try:
            for _ in range(max_steps):
                self.step()
        except Halt:
            pass


def load_cmd(path, cpu, load_seg=0x1000, cmdline=None):
    import os as _os
    import ccp
    import bin2cmd
    data = open(path, "rb").read()
    if len(data) < 128 or not (1 <= data[0] <= 9):
        raise ValueError("not a CP/M-86 .CMD file")
    if cmdline is None:
        cmdline = _os.path.splitext(_os.path.basename(path))[0].upper()
    groups = bin2cmd.parse_header(data)
    body = data[128:]
    # This interpreter supports the 8080 model (single code group): the loader
    # reserves the base page (0..0FFH) and enters at CS:0100H.
    code_len = groups[0][1] * 16 if groups else len(body)
    base = cpu.lin(load_seg, 0)
    cpu.mem[base:base + len(body)] = body
    fcb1, fcb2, tail = ccp.fcbs_and_tail_from_cmdline(cmdline)
    bp = ccp.build_base_page(model="8080", code_seg=load_seg, code_len=code_len,
                             fcb1=fcb1, fcb2=fcb2, tail=tail)
    cpu.mem[base:base + len(bp)] = bp
    for sreg in ("cs", "ds", "es", "ss"):
        cpu.s[sreg] = load_seg
    cpu.ip = ccp.BASE_PAGE_SIZE  # 0x100
    cpu.r["sp"] = 0xFFFE


def main(argv=None):
    import os as _os
    argv = argv or sys.argv[1:]
    if not argv:
        print("usage: cpm86run.py FILE.CMD [ARG ...]", file=sys.stderr)
        return 2
    cpu = CPU()
    prog = _os.path.splitext(_os.path.basename(argv[0]))[0].upper()
    cmdline = " ".join([prog] + list(argv[1:]))
    load_cmd(argv[0], cpu, cmdline=cmdline)
    cpu.run()
    sys.stdout.write(cpu.out.decode("cp437", errors="replace"))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
