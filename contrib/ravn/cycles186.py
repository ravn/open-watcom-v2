#!/usr/bin/env python3
"""Estimate 80186 execution time (clock cycles, "ticks") for a stream of
executed 8086/80186 instructions.

Unicorn (QEMU/TCG) is a *functional* emulator: it reproduces instruction
semantics exactly but models no timing at all -- no clock, no prefetch queue,
no bus wait states.  What it *does* give us is an exact, deterministic dynamic
instruction trace plus operand detail (via capstone).  This module layers an
Intel iAPX 186 clock-cycle table on top of that trace so we can attribute an
estimated cycle cost to each executed instruction and sum a program's total.

Accuracy / caveats (read before trusting a number):
  * These are the published iAPX 186 *execution* clock counts.  On the 80186
    effective-address computation is done by dedicated hardware, so (unlike the
    8086) memory operands carry no separate EA penalty -- the memory-form counts
    below already include it.
  * NOT modelled: the prefetch (BIU) queue, instruction-fetch bus cycles, and
    memory/IO wait states.  On real hardware these add cycles that depend on the
    RAM speed and bus width of the specific machine (e.g. the RC759).  So a
    total from this module is a solid, reproducible *lower-bound-ish estimate*
    of pure execution cycles, typically within a few percent for register-heavy
    code and more optimistic for memory/IO-bound code.
  * For true machine timing use a micro-architectural emulator (MAME's i80186
    core, or PCE) that models the bus and wait states.

Public API:
  model = Cycle186()
  clocks = model.clocks(cs_insn, taken=None)   # taken: bool for cond. branches
  model.is_conditional_branch(cs_insn) -> bool
"""
from capstone import Cs, CS_ARCH_X86, CS_MODE_16
from capstone.x86 import X86_OP_REG, X86_OP_IMM, X86_OP_MEM

# --- iAPX 186 execution clock counts -------------------------------------
# For two-operand data ops the tuple is (reg_dest, reg_from_mem, mem_dest),
# i.e. (no memory operand, memory as source, memory as destination).
_ALU = (3, 10, 16)          # add sub adc sbb and or xor
_CMP = (3, 10, 10)          # cmp/test never write back -> mem form is cheaper
_MOV = (2, 9, 9)            # mov (incl. imm); mem form 9

# single-operand / special: keyed name -> (reg_form, mem_form)
_UNARY = {
    "inc": (3, 15), "dec": (3, 15), "neg": (3, 12), "not": (3, 12),
    "push": (10, 16), "pop": (10, 20),
    "mul": (35, 41), "imul": (35, 41),        # 16-bit; byte forms ~26/32
    "div": (38, 44), "idiv": (44, 50),
}

# shifts/rotates: by 1 -> (2 reg, 15 mem); by CL/imm -> 5+n (reg) / 17+n (mem)
_SHIFT = {"shl", "shr", "sal", "sar", "rol", "ror", "rcl", "rcr"}

# fixed-cost, operand-independent instructions
_FIXED = {
    "nop": 3, "clc": 2, "stc": 2, "cmc": 2, "cld": 2, "std": 2, "cli": 2,
    "sti": 2, "cbw": 2, "cwd": 4, "lahf": 2, "sahf": 3, "xlat": 11, "xlatb": 11,
    "lea": 6, "pusha": 36, "popa": 51, "pushf": 9, "popf": 8, "int3": 45,
    "into": 48, "iret": 28, "hlt": 2, "wait": 6, "lock": 2, "aaa": 8, "aas": 7,
    "aam": 19, "aad": 15, "daa": 4, "das": 4,
}

# call/ret/jmp (non-conditional) by operand kind
_CALL = {"near_rel": 15, "reg": 13, "mem": 19, "far": 23}
_RET = {"ret": 16, "reti": 18, "retf": 22, "retfi": 25}
_JMP = {"near_rel": 13, "reg": 11, "mem": 17, "far": 13}

# conditional branch / loop: (taken, not_taken)
_COND = 13, 4
_LOOP = {"loop": (15, 6), "loope": (16, 6), "loopne": (16, 6),
         "loopz": (16, 6), "loopnz": (16, 6), "jcxz": (16, 6)}

# string primitives (no REP): name -> clocks
_STRING = {"movsb": 14, "movsw": 14, "stosb": 10, "stosw": 10,
           "lodsb": 10, "lodsw": 10, "cmpsb": 22, "cmpsw": 22,
           "scasb": 15, "scasw": 15}

_COND_MNEMONICS = {
    "ja", "jae", "jb", "jbe", "jc", "je", "jg", "jge", "jl", "jle", "jna",
    "jnae", "jnb", "jnbe", "jnc", "jne", "jng", "jnge", "jnl", "jnle", "jno",
    "jnp", "jns", "jnz", "jo", "jp", "jpe", "jpo", "js", "jz",
}


class Cycle186:
    def __init__(self):
        self.md = Cs(CS_ARCH_X86, CS_MODE_16)
        self.md.detail = True

    # -- helpers ----------------------------------------------------------
    @staticmethod
    def _opkinds(insn):
        mem = imm = False
        for o in insn.operands:
            if o.type == X86_OP_MEM:
                mem = True
            elif o.type == X86_OP_IMM:
                imm = True
        return mem, imm

    @staticmethod
    def _dest_is_mem(insn):
        ops = insn.operands
        return bool(ops) and ops[0].type == X86_OP_MEM

    def is_conditional_branch(self, insn):
        m = insn.mnemonic
        return m in _COND_MNEMONICS or m in _LOOP

    # -- main -------------------------------------------------------------
    def clocks(self, insn, taken=None):
        m = insn.mnemonic
        mem, imm = self._opkinds(insn)

        if m in _FIXED:
            return _FIXED[m]
        if m in _STRING:
            return _STRING[m]

        # conditional branches / loops (need taken/not-taken)
        if m in _LOOP:
            t, nt = _LOOP[m]
            return t if taken else nt
        if m in _COND_MNEMONICS:
            t, nt = _COND
            return t if taken else nt

        if m in ("add", "sub", "adc", "sbb", "and", "or", "xor"):
            return self._twoop(insn, _ALU, mem)
        if m in ("cmp", "test"):
            return self._twoop(insn, _CMP, mem)
        if m == "mov":
            return self._twoop(insn, _MOV, mem)
        if m == "xchg":
            return 17 if mem else 4

        if m in _UNARY:
            reg_form, mem_form = _UNARY[m]
            return mem_form if mem else reg_form

        if m in _SHIFT:
            # by 1:  reg 2 / mem 15
            # by CL or imm8 (186): 5+n reg / 17+n mem   (n = shift count)
            ops = insn.operands
            by_one = (len(ops) == 1) or (
                len(ops) == 2 and ops[1].type == X86_OP_IMM and ops[1].imm == 1)
            if by_one:
                return 15 if mem else 2
            # count in CL is unknown at decode time; assume a representative 4
            n = 4
            if len(ops) == 2 and ops[1].type == X86_OP_IMM:
                n = max(1, ops[1].imm & 0x1f)
            return (17 + n) if mem else (5 + n)

        if m == "lea":
            return 6
        if m in ("les", "lds"):
            return 18

        if m == "call":
            return self._calljmp(insn, _CALL)
        if m == "jmp":
            return self._calljmp(insn, _JMP)
        if m in ("ret", "retn"):
            return _RET["reti"] if imm else _RET["ret"]
        if m == "retf":
            return _RET["retfi"] if imm else _RET["retf"]
        if m == "int":
            return 47
        if m in ("in", "out"):
            return 10
        if m == "iret":
            return 28

        # unknown / uncounted opcode: charge a neutral default
        return 4

    def _twoop(self, insn, table, mem):
        reg_form, rm_form, mr_form = table
        if not mem:
            return reg_form
        return mr_form if self._dest_is_mem(insn) else rm_form

    def _calljmp(self, insn, table):
        ops = insn.operands
        if ops and ops[0].type == X86_OP_MEM:
            return table["mem"]
        if ops and ops[0].type == X86_OP_REG:
            return table["reg"]
        return table["near_rel"]


if __name__ == "__main__":  # tiny self-test / demo
    import sys
    model = Cycle186()
    # mov ax,bx / add [bx+si+8],cx / mul cx / shl ax,cl / push [bx] / jne / loop
    code = bytes.fromhex("89d8" "014808" "f7e1" "d3e0" "ff37" "75fe" "e2fe")
    for ins in model.md.disasm(code, 0x100):
        taken = True if model.is_conditional_branch(ins) else None
        c = model.clocks(ins, taken=taken)
        print("%-24s %2d clocks%s" % (
            ins.mnemonic + " " + ins.op_str, c,
            " (taken)" if taken else ""), file=sys.stderr)
