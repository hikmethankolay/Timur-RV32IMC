#!/usr/bin/env python3
"""Timur SoC system tests: assembler, RV32IM reference model and test writer.

Writes, relative to the project root (run it from there):
  vectors/timur_soc_<name>.hex   ROM images loaded by tb/timur_soc_tb.v
  vectors/timur_soc_vectors.txt  programs and expected results for that testbench
  rom.hex, rom.mif               default ROM image: the final cross-phase program
  sw/bringup/*.hex, *.mif        hardware bring-up programs (Phase 9)

The reference model executes the programs on the Timur memory map as it stands
at the end of Phase 9: no CSR file (CSR instructions write 0 to rd), ECALL,
EBREAK, MRET, WFI, FENCE and illegal encodings retire as NOPs. Programs whose
results depend on timing (UART busy flags, DMAC polling) carry hand-written
expectations instead of model results.

The Phase 7 random program is generated from --seed; the seed is recorded in
the vector file so a failing run can be reproduced.

Usage:  python3 sw/gen_soc_tests.py [--seed N] [--length N]
"""

import argparse
import os
import random
import sys

MASK = 0xFFFFFFFF
DEFAULT_SEED = 20260926
DEFAULT_LENGTH = 600
GPIO_IN = 0x15A            # switch value driven by tb/timur_soc_tb.v
UART_BIT = 434             # cycles per bit at 50 MHz, 115200 baud

# ---------------------------------------------------------------------------
# Assembler
# ---------------------------------------------------------------------------
CSRS = {"mstatus": 0x300, "misa": 0x301, "mie": 0x304, "mtvec": 0x305,
        "mscratch": 0x340, "mepc": 0x341, "mcause": 0x342, "mtval": 0x343,
        "mip": 0x344, "cycle": 0xC00, "time": 0xC01, "instret": 0xC02}
R_OPS = {"add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
         "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
         "or": (0x00, 6), "and": (0x00, 7), "mul": (0x01, 0), "mulh": (0x01, 1),
         "mulhsu": (0x01, 2), "mulhu": (0x01, 3), "div": (0x01, 4), "divu": (0x01, 5),
         "rem": (0x01, 6), "remu": (0x01, 7)}
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_I = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}
CSR_OPS = {"csrrw": 1, "csrrs": 2, "csrrc": 3, "csrrwi": 5, "csrrsi": 6, "csrrci": 7}
FIXED = {"nop": 0x00000013, "ecall": 0x00000073, "ebreak": 0x00100073,
         "mret": 0x30200073, "wfi": 0x10500073, "fence": 0x0FF0000F}


class AsmError(Exception):
    pass


def _reg(tok):
    tok = tok.strip()
    if not (tok.startswith("x") and tok[1:].isdigit() and 0 <= int(tok[1:]) < 32):
        raise AsmError("bad register %r" % tok)
    return int(tok[1:])


def _value(tok, labels):
    """Integer literal, label, or label/literal +/- label/literal."""
    tok = tok.replace(" ", "")
    for i in range(len(tok) - 1, 0, -1):
        if tok[i] in "+-" and tok[i - 1] not in "+-":
            left, right = tok[:i], tok[i + 1:]
            if left and right:
                lv, rv = _value(left, labels), _value(right, labels)
                return lv + rv if tok[i] == "+" else lv - rv
    if tok in labels:
        return labels[tok]
    try:
        return int(tok, 0)
    except ValueError:
        raise AsmError("bad value %r" % tok)


def _mem(tok, labels):
    """'imm(xN)' -> (imm, N)."""
    tok = tok.strip()
    if not tok.endswith(")") or "(" not in tok:
        raise AsmError("bad memory operand %r" % tok)
    imm, reg = tok[:-1].split("(", 1)
    return (_value(imm, labels) if imm else 0), _reg(reg)


def _check(v, lo, hi, what):
    if not lo <= v <= hi:
        raise AsmError("%s %d out of range" % (what, v))
    return v


def enc_r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | 0x23


def enc_b(imm, rs2, rs1, f3):
    return ((((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15)
            | (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63)


def enc_j(imm, rd):
    return ((((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20)
            | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F)


def encode(text, pc, labels):
    mnem, _, rest = text.partition(" ")
    mnem = mnem.lower()
    ops = [o.strip() for o in rest.split(",")] if rest.strip() else []
    if mnem == ".word":
        return _value(ops[0], labels) & MASK
    if mnem in FIXED:
        return FIXED[mnem]
    if mnem in R_OPS:
        f7, f3 = R_OPS[mnem]
        return enc_r(f7, _reg(ops[2]), _reg(ops[1]), f3, _reg(ops[0]), 0x33)
    if mnem in I_OPS:
        imm = _check(_value(ops[2], labels), -2048, 2047, "immediate")
        return enc_i(imm, _reg(ops[1]), I_OPS[mnem], _reg(ops[0]), 0x13)
    if mnem in SHIFT_I:
        f7, f3 = SHIFT_I[mnem]
        sh = _check(_value(ops[2], labels), 0, 31, "shift amount")
        return enc_i((f7 << 5) | sh, _reg(ops[1]), f3, _reg(ops[0]), 0x13)
    if mnem in LOADS:
        imm, rs1 = _mem(ops[1], labels)
        return enc_i(_check(imm, -2048, 2047, "offset"), rs1, LOADS[mnem], _reg(ops[0]), 0x03)
    if mnem in STORES:
        imm, rs1 = _mem(ops[1], labels)
        return enc_s(_check(imm, -2048, 2047, "offset"), _reg(ops[0]), rs1, STORES[mnem])
    if mnem in BRANCHES:
        off = _check(_value(ops[2], labels) - pc, -4096, 4094, "branch offset")
        return enc_b(off, _reg(ops[1]), _reg(ops[0]), BRANCHES[mnem])
    if mnem == "jal":
        off = _check(_value(ops[1], labels) - pc, -(1 << 20), (1 << 20) - 2, "jump offset")
        return enc_j(off, _reg(ops[0]))
    if mnem == "jalr":
        imm, rs1 = _mem(ops[1], labels)
        return enc_i(_check(imm, -2048, 2047, "offset"), rs1, 0, _reg(ops[0]), 0x67)
    if mnem in ("lui", "auipc"):
        imm = _check(_value(ops[1], labels), 0, 0xFFFFF, "upper immediate")
        return (imm << 12) | (_reg(ops[0]) << 7) | (0x37 if mnem == "lui" else 0x17)
    if mnem in CSR_OPS:
        csr = CSRS[ops[1]] if ops[1] in CSRS else _value(ops[1], labels)
        f3 = CSR_OPS[mnem]
        src = _check(_value(ops[2], labels), 0, 31, "uimm") if f3 & 4 else _reg(ops[2])
        return enc_i(csr, src, f3, _reg(ops[0]), 0x73)
    raise AsmError("unknown mnemonic %r" % mnem)


def assemble(source):
    """Two-pass assembler: returns ({address: word}, [(address, word, text)], labels)."""
    items, labels, addr = [], {}, 0
    for raw in source.splitlines():
        text = raw.split("#", 1)[0].strip()
        while ":" in text:
            label, text = text.split(":", 1)
            labels[label.strip()] = addr
            text = text.strip()
        if not text:
            continue
        if text.startswith(".org"):
            addr = _value(text.split()[1], labels)
            continue
        items.append((addr, text))
        addr += 4
    image, listing = {}, []
    for addr, text in items:
        try:
            word = encode(text, addr, labels)
        except AsmError as err:
            raise AsmError("0x%04X %s: %s" % (addr, text, err))
        if addr in image:
            raise AsmError("0x%04X: overlapping code" % addr)
        image[addr] = word
        listing.append((addr, word, " ".join(text.split())))
    return image, listing, labels


# ---------------------------------------------------------------------------
# Reference model
# ---------------------------------------------------------------------------
def s32(v):
    v &= MASK
    return v - (1 << 32) if v & 0x80000000 else v


def legal(ins):
    """Mirror of main_control_unit's illegal-instruction rules."""
    op, f3, f7, rs2 = ins & 0x7F, (ins >> 12) & 7, ins >> 25, (ins >> 20) & 31
    if op == 0x33:
        return f7 in (0x00, 0x01) or (f7 == 0x20 and f3 in (0, 5))
    if op == 0x13:
        return not ((f3 == 1 and f7 != 0) or (f3 == 5 and f7 not in (0x00, 0x20)))
    if op == 0x03:
        return f3 not in (3, 6, 7)
    if op == 0x23:
        return f3 < 3
    if op == 0x63:
        return f3 not in (2, 3)
    if op == 0x67:
        return f3 == 0
    if op in (0x6F, 0x37, 0x17):
        return True
    if op == 0x0F:
        return f3 in (0, 1)
    if op == 0x73:
        if f3 == 0:
            return ((f7 << 5) | rs2) in (0x000, 0x001, 0x302, 0x105)
        return f3 != 4
    return False


def imm_i(ins):
    return s32(ins) >> 20


def imm_s(ins):
    return (s32(ins) >> 25 << 5) | ((ins >> 7) & 0x1F)


def imm_b(ins):
    return ((s32(ins) >> 31) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1)


def imm_j(ins):
    return ((s32(ins) >> 31) << 20) | (((ins >> 12) & 0xFF) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1)


def divide(a, b, op):
    signed = op in (4, 6)
    if b == 0:
        return MASK if op in (4, 5) else a
    if signed and a == 0x80000000 and b == MASK:
        return 0x80000000 if op == 4 else 0
    if signed:
        q = abs(s32(a)) // abs(s32(b))
        if (s32(a) < 0) != (s32(b) < 0):
            q = -q
        return (q if op == 4 else s32(a) - q * s32(b)) & MASK
    return a // b if op == 5 else a % b


class Timur:
    """Instruction-level model of the Timur SoC at the end of Phase 9."""

    def __init__(self, image):
        self.rom = dict(image)
        self.ram = bytearray(0x10000)
        self.ram_written = set()
        self.x = [0] * 32
        self.pc = 0
        self.gpio_out = self.gpio_dir = self.uart_ctrl = 0
        self.uart_tx = []
        self.dmac = {"src": 0, "dst": 0, "len": 0, "irq": 0, "done": 0}
        self.trace = []
        self.divs = 0

    def read_word(self, a):
        region = a >> 16
        if region == 0x0000:
            return self.rom.get(a & 0xFFFC, 0)
        if region == 0x2000:
            i = a & 0xFFFC
            return int.from_bytes(self.ram[i:i + 4], "little")
        if region == 0x4000:
            page, reg = (a >> 8) & 0xFF, (a >> 2) & 0x3F
            if page == 0:      # UART: nothing received; the model sends at once (never busy)
                return {2: self.uart_ctrl}.get(reg, 0)
            if page == 1:
                return {0: self.gpio_out, 1: GPIO_IN, 2: self.gpio_dir}.get(reg, 0)
            if page == 2:
                d = self.dmac
                return {0: d["src"], 1: d["dst"], 2: d["len"], 3: d["irq"] << 1, 4: d["done"] << 1}.get(reg, 0)
        return 0               # default slave

    def write_ram_word(self, a, data, be):
        i = a & 0xFFFC
        for k in range(4):
            if be >> k & 1:
                self.ram[i + k] = (data >> (8 * k)) & 0xFF
        self.ram_written.add(i)

    def store(self, a, f3, value):
        size = f3 & 3
        data = (value & 0xFF) * 0x01010101 if size == 0 else (value & 0xFFFF) * 0x00010001 if size == 1 else value
        region = a >> 16
        if region == 0x2000:
            be = (1 << (a & 3)) if size == 0 else ((0b1100 if a & 2 else 0b0011) if size == 1 else 0b1111)
            self.write_ram_word(a, data, be)
        elif region == 0x4000:  # APB: no byte strobes, whole-register writes decoded on PADDR[7:2]
            page, reg = (a >> 8) & 0xFF, (a >> 2) & 0x3F
            if page == 0:
                if reg == 0:
                    self.uart_tx.append(data & 0xFF)
                elif reg == 2:
                    self.uart_ctrl = data & 3
            elif page == 1:
                if reg == 0:
                    self.gpio_out = data & 0x3FF
                elif reg == 2:
                    self.gpio_dir = data & 0x3FF
            elif page == 2:
                d = self.dmac
                if reg in (0, 1, 2):
                    d[("src", "dst", "len")[reg]] = data
                elif reg == 3:
                    d["irq"], d["done"] = (data >> 1) & 1, 0
                    if data & 1:        # the model copies at once, the SoC over many cycles
                        for i in range(d["len"]):
                            dst = (d["dst"] + 4 * i) & MASK
                            if dst >> 16 == 0x2000:
                                self.write_ram_word(dst, self.read_word((d["src"] + 4 * i) & MASK), 0b1111)
                        d["done"] = 1
        # ROM and unmapped addresses: writes ignored

    def load(self, a, f3):
        w = self.read_word(a)
        byte = (w >> (8 * (a & 3))) & 0xFF
        half = (w >> (16 * ((a >> 1) & 1))) & 0xFFFF
        if f3 == 0:
            return byte | (0xFFFFFF00 if byte & 0x80 else 0)
        if f3 == 1:
            return half | (0xFFFF0000 if half & 0x8000 else 0)
        if f3 == 4:
            return byte
        if f3 == 5:
            return half
        return w

    def step(self):
        pc = self.pc
        ins = self.rom.get(pc & 0xFFFC, 0)
        self.trace.append(pc)
        op, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
        a, b = self.x[(ins >> 15) & 31], self.x[(ins >> 20) & 31]
        f7 = ins >> 25
        nxt, res = (pc + 4) & MASK, None
        if not legal(ins):
            pass
        elif op == 0x33:
            if f7 == 0x01:
                if f3 == 0:
                    res = (a * b) & MASK
                elif f3 == 1:
                    res = (s32(a) * s32(b)) >> 32
                elif f3 == 2:
                    res = (s32(a) * b) >> 32
                elif f3 == 3:
                    res = (a * b) >> 32
                else:
                    res = divide(a, b, f3)
                    self.divs += 1
            else:
                res = self.alu(f3, a, b, f7 == 0x20)
        elif op == 0x13:
            imm = imm_i(ins) & MASK
            if f3 in (1, 5):
                res = self.alu(f3, a, imm & 31, f7 == 0x20)
            else:
                res = self.alu(f3, a, imm, False)
        elif op == 0x03:
            res = self.load((a + imm_i(ins)) & MASK, f3)
        elif op == 0x23:
            self.store((a + imm_s(ins)) & MASK, f3, b)
        elif op == 0x63:
            take = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b), 6: a < b, 7: a >= b}[f3]
            if take:
                nxt = (pc + imm_b(ins)) & MASK
        elif op == 0x6F:
            res, nxt = (pc + 4) & MASK, (pc + imm_j(ins)) & MASK
        elif op == 0x67:
            res, nxt = (pc + 4) & MASK, (a + imm_i(ins)) & MASK & ~1
        elif op == 0x37:
            res = ins & 0xFFFFF000
        elif op == 0x17:
            res = (pc + (ins & 0xFFFFF000)) & MASK
        elif op == 0x73 and f3 != 0:
            res = 0                   # CSR read: no CSR file before Phase 10
        if res is not None and rd:
            self.x[rd] = res & MASK
        self.pc = nxt
        return ins == 0x0000006F      # JAL x0, 0: halt loop

    @staticmethod
    def alu(f3, a, b, alt):
        if f3 == 0:
            return (a - b if alt else a + b) & MASK
        if f3 == 1:
            return (a << (b & 31)) & MASK
        if f3 == 2:
            return int(s32(a) < s32(b))
        if f3 == 3:
            return int(a < b)
        if f3 == 4:
            return a ^ b
        if f3 == 5:
            return (s32(a) >> (b & 31)) & MASK if alt else a >> (b & 31)
        if f3 == 6:
            return a | b
        return a & b

    def run(self, limit=200000):
        for _ in range(limit):
            if self.step():
                return self
        raise RuntimeError("program did not reach its halt loop")


# ---------------------------------------------------------------------------
# Directed programs
# ---------------------------------------------------------------------------
PHASE5 = """
# Phase 5 test program (no loads)
        addi  x1, x0, 5
        addi  x2, x0, 3
        add   x3, x1, x2
        sub   x4, x1, x2
        and   x5, x1, x2
        or    x6, x1, x2
        lui   x10, 0x20000
        sw    x3, 0(x10)
        beq   x1, x1, t2c
        lui   x7, 0xDEADC          # skipped
        lui   x7, 0xDEADC          # skipped
t2c:    addi  x7, x0, 1
        lui   x8, 0x12345          # LUI fix
        auipc x9, 0x1
        addi  x11, x0, -5          # decoder fix: ADD, not SUB
        addi  x12, x0, 40          # decoder fix: ADD, not MUL
        jal   x13, t48
        addi  x14, x0, 1           # skipped
t48:    jal   x0, t48              # halt
"""
PHASE5_WORDS = [0x00500093, 0x00300113, 0x002081B3, 0x40208233, 0x0020F2B3, 0x0020E333,
                0x20000537, 0x00352023, 0x00108663, 0xDEADC3B7, 0xDEADC3B7, 0x00100393,
                0x12345437, 0x00001497, 0xFFB00593, 0x02800613, 0x008006EF, 0x00100713,
                0x0000006F]
PHASE5_EXPECTED = {1: 5, 2: 3, 3: 8, 4: 2, 5: 1, 6: 7, 7: 1, 8: 0x12345000, 9: 0x1034,
                   10: 0x20000000, 11: 0xFFFFFFFB, 12: 0x28, 13: 0x44, 14: 0}

PHASE6 = """
# Phase 6: loads of every size, stores of every size and offset, links, LUI/AUIPC,
# register-file bypass at distance three, loads from the ROM data port
        lui   x31, 0x20000         # RAM base
        lui   x1, 0x80FF8
        addi  x1, x1, 0x17F        # x1 = 80FF817F
        sw    x1, 0(x31)
        nop
        nop
        lb    x2, 0(x31)           # 0000007F
        lb    x3, 1(x31)           # FFFFFF81
        lbu   x4, 1(x31)           # 00000081
        lb    x5, 2(x31)           # FFFFFFFF
        lbu   x6, 3(x31)           # 00000080
        lb    x7, 3(x31)           # FFFFFF80: sign extension of 0x80
        lh    x8, 0(x31)           # FFFF817F
        lhu   x9, 0(x31)           # 0000817F
        lh    x10, 2(x31)          # FFFF80FF: sign extension of 0x80FF
        lhu   x11, 2(x31)          # 000080FF
        lw    x12, 0(x31)          # 80FF817F
        addi  x13, x0, -1
        sw    x13, 4(x31)          # FFFFFFFF
        sb    x0, 5(x31)           # FFFF00FF: other lanes untouched
        addi  x14, x0, 0x5A
        sb    x14, 7(x31)          # 5AFF00FF
        lui   x15, 0x12345
        addi  x15, x15, 0x678      # 12345678
        sh    x15, 10(x31)         # word 8 = 56780000
        sb    x15, 12(x31)         # word 12 = 00000078
        sb    x15, 14(x31)         # word 12 = 00780078
        sh    x13, 16(x31)         # word 16 = 0000FFFF
        sb    x14, 18(x31)         # word 16 = 005AFFFF
        lw    x16, 4(x31)
        lw    x17, 8(x31)
        lw    x18, 12(x31)
        lw    x19, 16(x31)
        jal   x20, link1           # x20 = PC + 4
        addi  x21, x0, 1           # skipped
link1:  auipc x21, 0               # x21 = PC
        jalr  x22, 12(x21)         # to link2, x22 = PC + 4
        addi  x23, x0, 1           # skipped
link2:  lui   x23, 0xFEDCB         # FEDCB000
        addi  x24, x0, 42
        nop
        nop
        add   x25, x24, x0         # distance 3: register-file write-through bypass
        addi  x26, x0, 7
        nop
        nop
        nop
        add   x27, x26, x0         # distance 4: register file
        lw    x28, 0(x0)           # ROM data port: first program word
        lhu   x29, 2(x0)
        lb    x30, 7(x0)
halt:   jal   x0, halt
"""

PHASE7 = """
# Phase 7: forwarding, load-use, divider, multiplier, redirects, bus waits
        lui   x31, 0x20000         # RAM base
        lui   x30, 0x40000         # APB base
# forwarding: EX/MEM (10), MEM/WB (01), EX/MEM priority, x0 never forwarded
        addi  x1, x0, 7
        addi  x2, x1, 3            # x1 from EX/MEM -> 10
        addi  x3, x1, 1            # x1 from MEM/WB -> 8
        add   x4, x2, x3           # x2 from MEM/WB, x3 from EX/MEM -> 18
        addi  x5, x0, 1
        addi  x5, x0, 2
        add   x6, x5, x5           # EX/MEM wins over MEM/WB -> 4
        addi  x0, x0, 5            # the write to x0 is dropped
        add   x7, x0, x0           # x0 reads 0 -> 0
        sw    x2, 0x40(x31)
        sw    x3, 0x44(x31)
        sw    x4, 0x48(x31)
        sw    x6, 0x4C(x31)
        sw    x7, 0x50(x31)
# store immediately followed by a load of the same address (RAM bypass)
        sw    x4, 0(x31)
        lw    x8, 0(x31)           # 18
# load-use: dependent ALU op, dependent store data, dependent store address
        addi  x9, x8, 1            # one bubble -> 19
        lw    x10, 0(x31)
        sw    x10, 4(x31)          # store data from the load
        lw    x11, 4(x31)          # 18
        addi  x12, x31, 8
        sw    x12, 12(x31)
        lw    x13, 12(x31)         # pointer 20000008
        sw    x9, 0(x13)           # store address from the load: word 8 = 19
        lw    x14, 8(x31)          # 19
# Phase 7 walkthrough: LW, dependent ADD, DIV, taken BEQ on the DIV result
        addi  x15, x0, 5
        sw    x15, 16(x31)
        addi  x16, x31, 16
        addi  x17, x0, 1
        addi  x18, x0, 100
        lw    x19, 0(x16)          # LW  x1, 0(x2)   -> 5
        add   x20, x19, x17        # ADD x3, x1, x4  -> 6 (load-use)
        div   x21, x20, x18        # DIV x5, x3, x6  -> 0 (EX stall)
        beq   x21, x0, walk        # BEQ x5, x0, +16: taken
        addi  x22, x0, 1           # wrong path, killed
        addi  x22, x0, 2           # wrong path, killed
        addi  x22, x0, 3           # never fetched
walk:
# MUL: one EX stall cycle (operand capture), result forwarded
        mul   x22, x20, x18        # 600
        add   x23, x22, x1         # 607
# DIV and REM results forwarded to the next instruction
        div   x24, x23, x1         # 86
        addi  x25, x24, 1          # 87
        rem   x26, x23, x1         # 5
        sw    x22, 0x54(x31)
        sw    x23, 0x58(x31)
        sw    x24, 0x5C(x31)
        sw    x25, 0x60(x31)
        sw    x26, 0x64(x31)
# DIV whose operand comes from an APB load: the start waits for the bus
        addi  x27, x0, 0x155
        sw    x27, 0x100(x30)      # GPIO_OUT
        lw    x28, 0x100(x30)      # 155
        div   x29, x28, x1         # 48
        sw    x29, 0x68(x31)
# DIV whose operand comes straight from a RAM load: with HREADY wait states
# the start must wait until the data phase completes
        lw    x5, 0x58(x31)        # 607
        div   x6, x5, x1           # 86
        sw    x6, 0x7C(x31)
# MUL whose operand comes straight from a RAM load: the operand capture must
# also wait for the data phase
        lw    x5, 0x58(x31)        # 607
        mul   x6, x5, x1           # 4249
        sw    x6, 0x80(x31)
# REM by zero right after an independent APB load: done is not lost
        addi  x5, x0, 123
        lw    x6, 0x108(x30)       # GPIO_DIR = 0
        rem   x7, x5, x0           # 123
        divu  x8, x5, x0           # FFFFFFFF
        sw    x7, 0x6C(x31)
        sw    x8, 0x70(x31)
# signed overflow: 80000000 / FFFFFFFF
        lui   x9, 0x80000
        addi  x10, x0, -1
        div   x11, x9, x10         # 80000000
        rem   x12, x9, x10         # 0
        sw    x11, 0x74(x31)
        sw    x12, 0x78(x31)
# taken branch, JAL and JALR each kill exactly two instructions
        addi  x13, x0, 0
        addi  x14, x0, 0
        addi  x15, x0, 0
        beq   x0, x0, b1
        addi  x13, x13, 1          # killed
        addi  x13, x13, 2          # killed
b1:     jal   x16, b2
        addi  x14, x14, 1          # killed
        addi  x14, x14, 2          # killed
b2:     auipc x17, 0
        jalr  x18, 12(x17)         # to b3
        addi  x15, x15, 1          # killed
        addi  x15, x15, 2          # killed
b3:     bne   x0, x0, bad          # not taken: nothing is killed
        addi  x19, x0, 77
# branch and JALR operands straight from a load
        lw    x20, 0(x31)          # 18
        bne   x20, x4, bad
        sw    x17, 20(x31)
        lw    x21, 20(x31)
        jalr  x22, b4-b2(x21)      # load-use into JALR
        jal   x0, bad
b4:     addi  x23, x0, 99
halt:   jal   x0, halt
bad:    lui   x24, 0xBAD00
        jal   x0, bad
"""

SYSTEM = """
# Phase 9 system test: GPIO, UART, DMA copy while the CPU uses the bus,
# DMAC STATUS busy/done, LEN = 0, default slave
        lui   x20, 0x20000         # RAM base
        lui   x21, 0x40000         # APB base
        addi  x1, x0, 0x2A5
        sw    x1, 0x100(x21)       # GPIO_OUT
        lw    x2, 0x100(x21)       # 2A5
        lw    x3, 0x104(x21)       # GPIO_IN = switches
        addi  x4, x0, 0x3FF
        sw    x4, 0x108(x21)       # GPIO_DIR
        lw    x5, 0x108(x21)       # 3FF
        addi  x6, x0, 0xC3
        sb    x6, 0x101(x21)       # SB to an APB register: whole-register write of C3C3C3C3
        lw    x7, 0x100(x21)       # 3C3
        lbu   x8, 0x101(x21)       # byte 1 of GPIO_OUT = 03
        addi  x9, x0, 0x55
        sw    x9, 0(x21)           # UART_DATA = 'U'
        lw    x10, 4(x21)          # STATUS: tx_busy -> 1
        addi  x11, x0, 0x56
        sw    x11, 0(x21)          # ignored while tx_busy
        lw    x12, 8(x21)          # CTRL resets to 0
        addi  x13, x0, 1
        sw    x13, 8(x21)          # rx_enable
        lw    x14, 8(x21)          # 1
        addi  x15, x21, 0x200      # DMAC registers
        lui   x16, 0x1             # SRC = 0x1000 (table in ROM)
        sw    x16, 0(x15)
        addi  x17, x20, 0x100      # DST = 0x2000_0100
        sw    x17, 4(x15)
        addi  x18, x0, 8
        sw    x18, 8(x15)          # LEN = 8 words
        addi  x19, x0, 1
        sw    x19, 12(x15)         # start
        sw    x1, 0(x20)           # CPU loads and stores while the DMA runs
        lw    x22, 0(x20)          # 2A5
        sw    x22, 4(x20)
        lw    x23, 4(x16)          # ROM data port: 22222222
        sw    x23, 8(x20)
        lw    x24, 8(x20)          # 22222222
dma:    lw    x25, 16(x15)         # poll STATUS until busy clears
        andi  x26, x25, 1
        bne   x26, x0, dma
        lw    x27, 12(x15)         # CTRL: start reads 0, irq_enable 0
        sw    x0, 12(x15)          # any CTRL write clears done
        lw    x28, 16(x15)         # 0
        sw    x0, 8(x15)           # LEN = 0: done at once, no transfer
        sw    x19, 12(x15)
        nop
        nop
        lw    x29, 16(x15)         # done -> 2
uart:   lw    x30, 4(x21)          # wait for the 'U' frame to finish
        andi  x30, x30, 1
        bne   x30, x0, uart
        addi  x9, x0, 0x4B
        sb    x9, 0(x21)           # SB to UART_DATA: 'K'
        lui   x31, 0x10000         # unmapped: default slave
        sw    x1, 0(x31)           # ignored
        lw    x31, 0(x31)          # 0
halt:   jal   x0, halt
        .org 0x1000
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444
        .word 0x55555555
        .word 0x66666666
        .word 0x77777777
        .word 0x88888888
"""
SYSTEM_EXPECTED = {1: 0x2A5, 2: 0x2A5, 3: GPIO_IN, 4: 0x3FF, 5: 0x3FF, 6: 0xC3, 7: 0x3C3, 8: 0x03,
                   9: 0x4B, 10: 1, 11: 0x56, 12: 0, 13: 1, 14: 1, 15: 0x40000200, 16: 0x1000,
                   17: 0x20000100, 18: 8, 19: 1, 20: 0x20000000, 21: 0x40000000, 22: 0x2A5,
                   23: 0x22222222, 24: 0x22222222, 25: 2, 26: 0, 27: 0, 28: 0, 29: 2, 30: 0, 31: 0}
SYSTEM_RAM = dict([(0x20000000, 0x2A5), (0x20000004, 0x2A5), (0x20000008, 0x22222222)] +
                  [(0x20000100 + 4 * i, 0x11111111 * (i + 1)) for i in range(8)])

FINAL = """
# Final cross-phase verification program
        lui   x20, 0x20000         # RAM base
        lui   x21, 0x40000         # APB base
        addi  x1, x0, 10
        addi  x2, x0, 1
        sw    x1, 0(x20)           # AHB write to RAM
        lw    x3, 0(x20)           # store -> load of the same word: RAM bypass
        add   x4, x3, x2           # load-use bubble + WB forwarding -> 11
        mul   x5, x1, x2           # multiply, one EX stall -> 10
        div   x6, x1, x2           # divider EX stall -> 10
        bne   x5, x6, skip         # not taken (forwarding from EX/MEM)
        addi  x7, x0, 42           # must execute
skip:   sw    x7, 0x100(x21)       # GPIO_OUT: LEDs show 42
        addi  x10, x0, 0x55
        sw    x10, 0(x21)          # UART: 'U'
        addi  x11, x21, 0x200      # DMAC register base
        lui   x12, 0x1             # 0x1000: data table in ROM
        sw    x12, 0(x11)          # DMAC_SRC
        addi  x13, x20, 0x100
        sw    x13, 4(x11)          # DMAC_DST = 0x2000_0100
        addi  x14, x0, 4
        sw    x14, 8(x11)          # DMAC_LEN = 4 words
        addi  x15, x0, 1
        sw    x15, 12(x11)         # DMAC_CTRL: start
poll:   lw    x16, 16(x11)         # DMAC_STATUS (APB wait states)
        andi  x16, x16, 1          # busy bit
        bne   x16, x0, poll
        csrrs x17, cycle, x0       # read-only CSR read, no trap
        addi  x18, x0, 0x100       # handler address
        csrrw x0, mtvec, x18       # mtvec = 0x100
        ecall                      # trap to 0x100 (Phase 10)
        addi  x19, x0, 99          # executed after MRET
halt:   jal   x0, halt
        .org 0x100
        csrrs x22, mcause, x0      # handler: x22 = 11
        csrrs x23, mepc, x0        # x23 = 0x74
        addi  x23, x23, 4
        csrrw x0, mepc, x23        # mepc = 0x78
        mret                       # return to 0x78
        .org 0x1000
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444
"""
# Expected state before Phase 10: there is no CSR file (x17 reads 0 instead of a cycle
# count) and ECALL does not trap, so the handler at 0x100 never runs (x22 = x23 = 0).
FINAL_EXPECTED = {1: 10, 2: 1, 3: 10, 4: 11, 5: 10, 6: 10, 7: 42, 10: 0x55, 11: 0x40000200,
                  12: 0x1000, 13: 0x20000100, 14: 4, 15: 1, 16: 0, 17: 0, 18: 0x100, 19: 99,
                  20: 0x20000000, 21: 0x40000000, 22: 0, 23: 0}
FINAL_RAM = dict([(0x20000000, 10)] + [(0x20000100 + 4 * i, 0x11111111 * (i + 1)) for i in range(4)])


# Hardware bring-up order (Phase 9). Each is written to sw/bringup/ as .hex and
# .mif; copy the .mif over rom.mif (and the .hex over rom.hex) and recompile.
BRINGUP_GPIO = """
# Bring-up 1, GPIO only: the LEDs mirror the switches; with every switch off
# they show the pattern 0x2A5
        lui   x21, 0x40000         # APB base
        addi  x2, x0, 0x2A5
loop:   lw    x1, 0x104(x21)       # GPIO_IN
        bne   x1, x0, show
        addi  x1, x2, 0
show:   sw    x1, 0x100(x21)       # GPIO_OUT
        jal   x0, loop
"""

BRINGUP_UART = """
# Bring-up 2, UART transmit: 'U' (0x55) in a loop, a square wave on a scope and
# UUUU in a terminal at 115200 8N1
        lui   x21, 0x40000         # APB base
        addi  x1, x0, 0x55
wait:   lw    x2, 4(x21)           # UART_STATUS
        andi  x2, x2, 1            # tx_busy
        bne   x2, x0, wait
        sw    x1, 0(x21)           # UART_DATA
        jal   x0, wait
"""

BRINGUP_DMA = """
# Bring-up 3, DMA: copy four ROM words into RAM, read them back and show the
# checksum AAAAAAAA on the LEDs (0x2AA)
        lui   x20, 0x20000         # RAM base
        lui   x21, 0x40000         # APB base
        addi  x11, x21, 0x200      # DMAC registers
        lui   x12, 0x1
        sw    x12, 0(x11)          # SRC = 0x1000
        addi  x13, x20, 0x100
        sw    x13, 4(x11)          # DST = 0x2000_0100
        addi  x14, x0, 4
        sw    x14, 8(x11)          # LEN = 4 words
        addi  x15, x0, 1
        sw    x15, 12(x11)         # start
poll:   lw    x16, 16(x11)         # STATUS
        andi  x16, x16, 1
        bne   x16, x0, poll
        lw    x1, 0(x13)
        lw    x2, 4(x13)
        lw    x3, 8(x13)
        lw    x4, 12(x13)
        add   x5, x1, x2
        add   x5, x5, x3
        add   x5, x5, x4           # checksum
        sw    x5, 0x100(x21)       # GPIO_OUT
halt:   jal   x0, halt
        .org 0x1000
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444
"""

# ---------------------------------------------------------------------------
# Random dependency-dense program (Phase 7 checklist)
# ---------------------------------------------------------------------------
def random_program(seed, length):
    """Forward-only control flow, so every program terminates.

    x31 = RAM base, x30 = APB base, x29 = JALR base, x28 = computed address base,
    x1..x20 carry the random data flow. Loads and stores mix RAM, APB registers
    (GPIO OUT/IN/DIR, UART CTRL, DMAC SRC/DST/LEN, unmapped APB offsets), the ROM
    data port and unmapped addresses; DIV/REM include divide-by-zero and
    signed-overflow operands.
    """
    rnd = random.Random(seed)
    out = ["# Phase 7 random program, seed %d" % seed,
           "        lui   x31, 0x20000", "        lui   x30, 0x40000", "        addi  x28, x31, 0"]
    pool = list(range(1, 21))
    for r in pool:
        v = rnd.getrandbits(32)
        hi, lo = ((v + 0x800) >> 12) & 0xFFFFF, v & 0xFFF
        lo = lo - 0x1000 if lo & 0x800 else lo
        out.append("        lui   x%d, 0x%05X" % (r, hi))
        out.append("        addi  x%d, x%d, %d" % (r, r, lo))
    recent = []
    labels = [0]

    def src():
        if recent and rnd.random() < 0.7:
            return rnd.choice(recent[-3:])
        return rnd.choice(pool + [0])

    def dst():
        return rnd.choice(pool)

    def wrote(r):
        recent.append(r)
        del recent[:-6]

    apb_load = [0x008, 0x100, 0x104, 0x108, 0x10C, 0x200, 0x204, 0x208, 0x300, 0x014]
    apb_store = [0x008, 0x100, 0x108, 0x10C, 0x200, 0x204, 0x208, 0x300]

    def simple():
        k = rnd.random()
        if k < 0.20:
            op = rnd.choice(["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"])
            rd = dst(); out.append("        %-5s x%d, x%d, x%d" % (op, rd, src(), src())); wrote(rd)
        elif k < 0.36:
            op = rnd.choice(["addi", "slti", "sltiu", "xori", "ori", "andi", "slli", "srli", "srai"])
            imm = rnd.randint(0, 31) if op in ("slli", "srli", "srai") else rnd.randint(-2048, 2047)
            rd = dst(); out.append("        %-5s x%d, x%d, %d" % (op, rd, src(), imm)); wrote(rd)
        elif k < 0.40:
            op = rnd.choice(["lui", "auipc"])
            rd = dst(); out.append("        %-5s x%d, 0x%05X" % (op, rd, rnd.getrandbits(20))); wrote(rd)
        elif k < 0.48:
            op = rnd.choice(["mul", "mulh", "mulhsu", "mulhu"])
            rd = dst(); out.append("        %-5s x%d, x%d, x%d" % (op, rd, src(), src())); wrote(rd)
        elif k < 0.56:
            op = rnd.choice(["div", "divu", "rem", "remu"])
            c = rnd.random()
            if c < 0.15:     # divide by zero
                rd = dst(); out.append("        %-5s x%d, x%d, x0" % (op, rd, src())); wrote(rd)
            elif c < 0.25:   # signed overflow operands
                ra, rb = rnd.sample(pool, 2)
                out.append("        lui   x%d, 0x80000" % ra)
                out.append("        addi  x%d, x0, -1" % rb)
                rd = dst(); out.append("        %-5s x%d, x%d, x%d" % (op, rd, ra, rb)); wrote(rd)
            else:
                rd = dst(); out.append("        %-5s x%d, x%d, x%d" % (op, rd, src(), src())); wrote(rd)
        elif k < 0.67:       # RAM load
            op = rnd.choice(["lw", "lh", "lhu", "lb", "lbu"])
            base = rnd.choice([31, 28])
            size = {"lw": 4, "lh": 2, "lhu": 2}.get(op, 1)
            rd = dst(); out.append("        %-5s x%d, %d(x%d)" % (op, rd, rnd.randrange(0, 256, size), base)); wrote(rd)
        elif k < 0.77:       # RAM store
            op = rnd.choice(["sw", "sh", "sb"])
            base = rnd.choice([31, 28])
            size = {"sw": 4, "sh": 2}.get(op, 1)
            out.append("        %-5s x%d, %d(x%d)" % (op, src(), rnd.randrange(0, 256, size), base))
        elif k < 0.83:       # APB load
            op = rnd.choice(["lw", "lw", "lh", "lbu", "lb"])
            off = rnd.choice(apb_load) + (rnd.choice([0, 1, 2, 3]) if op in ("lb", "lbu") else
                                          rnd.choice([0, 2]) if op == "lh" else 0)
            rd = dst(); out.append("        %-5s x%d, %d(x30)" % (op, rd, off)); wrote(rd)
        elif k < 0.87:       # APB store: whole-register writes
            op = rnd.choice(["sw", "sw", "sh", "sb"])
            off = rnd.choice(apb_store) + (rnd.choice([0, 1, 2, 3]) if op == "sb" else
                                           rnd.choice([0, 2]) if op == "sh" else 0)
            out.append("        %-5s x%d, %d(x30)" % (op, src(), off))
        elif k < 0.89:       # ROM data port: read back program words
            op = rnd.choice(["lw", "lhu", "lb"])
            size = {"lw": 4, "lhu": 2}.get(op, 1)
            rd = dst(); out.append("        %-5s x%d, %d(x0)" % (op, rd, rnd.randrange(0, 512, size))); wrote(rd)
        elif k < 0.90:       # default slave and ROM writes: ignored, loads read 0
            if rnd.random() < 0.5:
                out.append("        lui   x29, 0x%05X" % rnd.choice([0x10000, 0x30000, 0x60000]))
                out.append("        sw    x%d, 0(x29)" % src())
                rd = dst(); out.append("        lw    x%d, 0(x29)" % rd); wrote(rd)
            else:
                out.append("        sw    x%d, %d(x0)" % (src(), rnd.randrange(0, 256, 4)))
        else:                # new data base in RAM, used by later loads and stores
            out.append("        addi  x28, x31, %d" % rnd.randrange(0, 1024, 4))

    count = 0
    while count < length:
        k = rnd.random()
        if k < 0.10:
            labels[0] += 1
            target = "L%d" % labels[0]
            op = rnd.choice(["beq", "bne", "blt", "bge", "bltu", "bgeu"])
            out.append("        %-5s x%d, x%d, %s" % (op, src(), src(), target))
            for _ in range(rnd.randint(0, 3)):
                simple()
            out.append(target + ":")
        elif k < 0.13:
            labels[0] += 1
            target = "L%d" % labels[0]
            rd = rnd.choice(pool + [0])
            out.append("        jal   x%d, %s" % (rd, target))
            if rd:
                wrote(rd)
            for _ in range(rnd.randint(0, 3)):
                simple()
            out.append(target + ":")
        elif k < 0.16:
            skip = rnd.randint(0, 3)
            rd = rnd.choice(pool + [0])
            out.append("        auipc x29, 0")
            out.append("        jalr  x%d, %d(x29)" % (rd, 8 + 4 * skip))
            if rd:
                wrote(rd)
            for _ in range(skip):
                simple()
        else:
            simple()
        count += 1
    out.append("halt:   jal   x0, halt")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def image_words(image):
    last = max(image) // 4
    return [image.get(4 * i, 0) for i in range(last + 1)]


def write_hex(path, image, listing, comments=True):
    notes = {a: t for a, _, t in listing}
    with open(path, "w") as f:
        for i, w in enumerate(image_words(image)):
            if comments and 4 * i in notes:
                f.write("%08X  // %04X: %s\n" % (w, 4 * i, notes[4 * i]))
            else:
                f.write("%08X\n" % w)


def write_mif(path, image, title):
    words = image_words(image)
    if len(words) > 16384:
        raise RuntimeError("image exceeds 64 KB")
    with open(path, "w") as f:
        f.write("-- Timur RV32IMC instruction ROM: %s\n" % title)
        f.write("-- 16384 x 32-bit words; unused words are 00000000 (illegal instruction)\n\n")
        f.write("DEPTH = 16384;\nWIDTH = 32;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n\nCONTENT BEGIN\n")
        for i, w in enumerate(words):
            f.write("    %04X : %08X;\n" % (i, w))
        if len(words) < 16384:
            f.write("    [%04X..3FFF] : 00000000;\n" % len(words))
        f.write("END;\n")


class Vectors:
    def __init__(self):
        self.lines = []

    def comment(self, text=""):
        self.lines.append("//" + (" " + text if text else ""))

    def prog(self, image_file, max_cycles, halt, hready_waits):
        self.lines.append("PROG %s %d %08X %d" % (image_file, max_cycles, halt, hready_waits))

    def regs(self, values):
        for r in range(1, 32):
            if r in values:
                self.lines.append("REG %d %08X" % (r, values[r] & MASK))

    def ram(self, words):
        for a in sorted(words):
            self.lines.append("RAM %08X %08X" % (a, words[a]))

    def add(self, text):
        self.lines.append(text)


def model_checks(vec, model, halt, trace=True):
    vec.regs({r: model.x[r] for r in range(1, 32)})
    vec.ram({0x20000000 | a: int.from_bytes(model.ram[a:a + 4], "little") for a in model.ram_written})
    vec.add("RAMNZ %d" % sum(1 for a in range(0, 0x1000, 4) if any(model.ram[a:a + 4])))
    vec.add("LEDS %03X" % model.gpio_out)
    for byte in model.uart_tx:
        vec.add("UART %02X" % byte)
    vec.add("UARTN %d" % len(model.uart_tx))
    vec.add("DIVS %d" % model.divs)
    if trace:
        vec.add("RETIRED %d" % len(model.trace))
        for pc in model.trace:
            vec.add("TRACE %08X" % pc)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED)
    ap.add_argument("--length", type=int, default=DEFAULT_LENGTH)
    args = ap.parse_args()

    vec = Vectors()
    vec.comment("timur_soc test vectors, generated by sw/gen_soc_tests.py (random seed %d)" % args.seed)
    vec.comment("Directives, one per line:")
    vec.comment("  PROG <image> <max_cycles> <halt_pc> <hready_waits>  load the image into the ROM, clear the")
    vec.comment("      RAM, reset, run until the instruction at halt_pc leaves EX, drain the pipeline and")
    vec.comment("      wait for the UART. halt_pc FFFFFFFF: no halt expected, run max_cycles (endless loops).")
    vec.comment("      hready_waits = 1: HREADY is forced low for three cycles in the")
    vec.comment("      data phase of every RAM load, with garbage on HRDATA until the last cycle.")
    vec.comment("      After each PROG the testbench also checks: halt reached,")
    vec.comment("      fetch word = ROM[PC] and IF/ID word = ROM[IF/ID pc] every cycle, one multiplier")
    vec.comment("      start and one stall cycle per MUL, exactly one divider start per DIV, one bubble")
    vec.comment("      per load-use.")
    vec.comment("  REG <n> <value>      register x<n> at the end of the run")
    vec.comment("  RAM <addr> <value>   RAM word")
    vec.comment("  RAMNZ <count>        number of non-zero words in 0x2000_0000 - 0x2000_0FFF")
    vec.comment("  LEDS <value>         gpio_out")
    vec.comment("  UART <byte>          next byte decoded from uart_tx (8N1, 434 cycles per bit)")
    vec.comment("  UARTN <count>        number of bytes decoded from uart_tx")
    vec.comment("  DIVS <count>         divider start pulses")
    vec.comment("  RETIRED <count>      instructions that left EX, up to and including the first halt")
    vec.comment("  TRACE <pc>           next PC in the order instructions left EX")
    vec.comment("")

    # ---- Phase 5 -----------------------------------------------------------------------------
    image, listing, labels = assemble(PHASE5)
    if [image[4 * i] for i in range(len(PHASE5_WORDS))] != PHASE5_WORDS:
        sys.exit("Phase 5 program does not match its reference encoding")
    m = Timur(image).run()
    for r, v in PHASE5_EXPECTED.items():
        if m.x[r] != v:
            sys.exit("model: Phase 5 x%d = %08X, expected %08X" % (r, m.x[r], v))
    write_hex("vectors/timur_soc_phase5.hex", image, listing)
    vec.comment("==== Phase 5 test program (no loads)")
    vec.prog("vectors/timur_soc_phase5.hex", 2000, labels["t48"], 0)
    model_checks(vec, m, labels["t48"])

    # ---- Phase 6 -----------------------------------------------------------------------------
    image, listing, labels = assemble(PHASE6)
    m = Timur(image).run()
    write_hex("vectors/timur_soc_phase6.hex", image, listing)
    vec.comment("==== Phase 6: loads and stores of every size, links, LUI/AUIPC, register-file bypass")
    vec.prog("vectors/timur_soc_phase6.hex", 2000, labels["halt"], 0)
    model_checks(vec, m, labels["halt"])

    # ---- Phase 7 -----------------------------------------------------------------------------
    image, listing, labels = assemble(PHASE7)
    m = Timur(image).run()
    write_hex("vectors/timur_soc_phase7.hex", image, listing)
    for waits in (0, 1):
        vec.comment("==== Phase 7: hazards%s" % (", HREADY forced low for three cycles during every RAM load" if waits else ""))
        vec.prog("vectors/timur_soc_phase7.hex", 5000, labels["halt"], waits)
        model_checks(vec, m, labels["halt"])

    # ---- random ------------------------------------------------------------------------------
    source = random_program(args.seed, args.length)
    image, listing, labels = assemble(source)
    m = random_model = Timur(image).run()
    write_hex("vectors/timur_soc_random.hex", image, listing)
    for waits in (0, 1):
        vec.comment("==== Phase 7 random dependency-dense program, seed %d, %d instructions executed%s"
                    % (args.seed, len(m.trace), ", with HREADY waits" if waits else ""))
        vec.prog("vectors/timur_soc_random.hex", 40 * len(m.trace) + 2000, labels["halt"], waits)
        model_checks(vec, m, labels["halt"])

    # ---- Phase 9 system ----------------------------------------------------------------------
    image, listing, labels = assemble(SYSTEM)
    write_hex("vectors/timur_soc_system.hex", image, listing)
    vec.comment("==== Phase 9 system test: GPIO, UART, DMA while the CPU runs loads and stores, default slave")
    vec.prog("vectors/timur_soc_system.hex", 20000, labels["halt"], 0)
    vec.regs(SYSTEM_EXPECTED)
    vec.ram(SYSTEM_RAM)
    vec.add("RAMNZ %d" % len(SYSTEM_RAM))
    vec.add("LEDS %03X" % 0x3C3)
    vec.add("UART 55")
    vec.add("UART 4B")
    vec.add("UARTN 2")
    vec.add("DIVS 0")

    # ---- final cross-phase program (also the default rom.hex / rom.mif) ------------------------
    image, listing, labels = assemble(FINAL)
    m = Timur(image).run()
    for r, v in FINAL_EXPECTED.items():
        if m.x[r] != v:
            sys.exit("model: final program x%d = %08X, expected %08X" % (r, m.x[r], v))
    write_hex("rom.hex", image, listing, comments=False)
    write_mif("rom.mif", image, "final cross-phase verification program")
    vec.comment("==== Final cross-phase program from rom.hex, state before Phase 10:")
    vec.comment("     x17 = 0 (no CSR file yet), x22 = x23 = 0 (ECALL does not trap yet)")
    vec.prog("rom.hex", 3000, labels["halt"], 0)
    vec.regs(FINAL_EXPECTED)
    vec.ram(FINAL_RAM)
    vec.add("RAMNZ %d" % len(FINAL_RAM))
    vec.add("LEDS %03X" % 42)
    vec.add("UART 55")
    vec.add("UARTN 1")
    vec.add("DIVS 1")

    # ---- hardware bring-up programs (Phase 9) --------------------------------------------------
    os.makedirs("sw/bringup", exist_ok=True)
    bringup = [("bringup_1_gpio", BRINGUP_GPIO, "GPIO: LEDs mirror the switches"),
               ("bringup_2_uart", BRINGUP_UART, "UART: 'U' in a loop"),
               ("bringup_3_dma", BRINGUP_DMA, "DMA copy of four ROM words, checksum on the LEDs")]
    for name, src, title in bringup:
        image, listing, labels = assemble(src)
        write_hex("sw/bringup/%s.hex" % name, image, listing, comments=False)
        write_mif("sw/bringup/%s.mif" % name, image, "bring-up, " + title)
    vec.comment("==== Hardware bring-up 1: LEDs mirror the switches (endless loop)")
    vec.prog("sw/bringup/bringup_1_gpio.hex", 300, 0xFFFFFFFF, 0)
    vec.add("LEDS %03X" % GPIO_IN)
    vec.comment("==== Hardware bring-up 2: 'U' in a loop (endless loop)")
    vec.prog("sw/bringup/bringup_2_uart.hex", 3 * 10 * UART_BIT, 0xFFFFFFFF, 0)
    vec.add("UART 55")
    vec.add("UART 55")
    image, listing, labels = assemble(BRINGUP_DMA)
    m = Timur(image).run()
    vec.comment("==== Hardware bring-up 3: DMA copy, checksum AAAAAAAA on the LEDs")
    vec.prog("sw/bringup/bringup_3_dma.hex", 2000, labels["halt"], 0)
    vec.regs({5: 0xAAAAAAAA})
    vec.ram({0x20000100 + 4 * i: 0x11111111 * (i + 1) for i in range(4)})
    vec.add("LEDS %03X" % (0xAAAAAAAA & 0x3FF))
    if m.x[5] != 0xAAAAAAAA:
        sys.exit("model: bring-up checksum %08X" % m.x[5])

    with open("vectors/timur_soc_vectors.txt", "w") as f:
        f.write("\n".join(vec.lines) + "\n")
    print("random program: seed %d, %d instructions executed" % (args.seed, len(random_model.trace)))


if __name__ == "__main__":
    main()
