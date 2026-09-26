#!/usr/bin/env python3
"""Timur SoC system tests: assembler, RV32IMC reference model and test writer.

Writes, relative to the project root (run it from there):
  vectors/timur_soc_<name>.hex   ROM images (32-bit words) loaded by tb/timur_soc_tb.v
  vectors/timur_soc_vectors.txt  programs and expected results for that testbench
  rom.hex                        default ROM image, 32-bit words (testbenches)
  rom_lo.hex, rom_hi.hex,        the same image as the two 16-bit ROM banks: the
  rom_lo.mif, rom_hi.mif         simulation and synthesis initialisation of rom_ahb
  sw/bringup/*.hex, *_lo.mif, *_hi.mif   hardware bring-up programs (Phase 9)

Most programs are assembled by the small assembler below. The Phase 11
programs, which need real 16-bit encodings, are assembled with the GNU
toolchain (riscv-none-elf-as on PATH or in .tools/); without it the committed
images in vectors/ are used, so the expectations can still be regenerated.

The reference model executes the programs on the Timur memory map with the
machine-mode CSRs and precise traps of Phase 10 and the compressed
instructions of Phase 11: illegal encodings, ECALL, EBREAK and misaligned
loads and stores trap to mtvec; MRET returns; WFI and FENCE are NOPs. Values the model cannot know (the cycle and
instret counters, mip) taint the registers and RAM words derived from them;
those are left out of the automatic checks and given hand-written ones, as are
programs whose results depend on timing (UART busy flags, DMAC polling,
interrupts).

The Phase 7 random program is generated from --seed; the seed is recorded in
the vector file so a failing run can be reproduced.

Usage:  python3 sw/gen_soc_tests.py [--seed N] [--length N]
"""

import argparse
import glob
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

import bin2mem

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
        "mip": 0x344, "mcycle": 0xB00, "minstret": 0xB02, "mcycleh": 0xB80,
        "minstreth": 0xB82, "cycle": 0xC00, "time": 0xC01, "instret": 0xC02,
        "cycleh": 0xC80, "timeh": 0xC81, "instreth": 0xC82, "mvendorid": 0xF11,
        "marchid": 0xF12, "mimpid": 0xF13, "mhartid": 0xF14}
CSR_TIMING = {0x344, 0xB00, 0xB02, 0xB80, 0xB82, 0xC00, 0xC01, 0xC02, 0xC80, 0xC81, 0xC82}
MISA = 0x40001104                      # RV32IMC
CSR_IMPLEMENTED = set(CSRS.values())
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
# RV32C expansion for the model (checked against vectors/decompressor_vectors.txt,
# which comes from the GNU toolchain)
# ---------------------------------------------------------------------------
def decompress(h):
    """32-bit expansion of the 16-bit instruction h; 0 for illegal and reserved encodings."""
    q, f3 = h & 3, (h >> 13) & 7
    rd, rs2 = (h >> 7) & 31, (h >> 2) & 31
    rdp, rs1p = 8 + ((h >> 2) & 7), 8 + ((h >> 7) & 7)

    def bit(i):
        return (h >> i) & 1

    def bits(hi, lo):
        return (h >> lo) & ((1 << (hi - lo + 1)) - 1)

    def sx(v, n):
        return v - (1 << n) if (v >> (n - 1)) & 1 else v

    if q == 0:
        mem = bit(5) << 6 | bits(12, 10) << 3 | bit(6) << 2
        if f3 == 0:
            nz = bits(10, 7) << 6 | bits(12, 11) << 4 | bit(5) << 3 | bit(6) << 2
            return enc_i(nz, 2, 0, rdp, 0x13) if nz else 0
        if f3 == 2:
            return enc_i(mem, rs1p, 2, rdp, 0x03)
        if f3 == 6:
            return enc_s(mem, rdp, rs1p, 2)
        return 0
    if q == 1:
        imm6 = sx(bit(12) << 5 | bits(6, 2), 6)
        if f3 == 0:
            return enc_i(imm6, rd, 0, rd, 0x13)
        if f3 in (1, 5):
            off = sx(bit(12) << 11 | bit(8) << 10 | bits(10, 9) << 8 | bit(6) << 7 | bit(7) << 6
                     | bit(2) << 5 | bit(11) << 4 | bits(5, 3) << 1, 12)
            return enc_j(off, 1 if f3 == 1 else 0)
        if f3 == 2:
            return enc_i(imm6, 0, 0, rd, 0x13)
        if f3 == 3:
            if rd == 2:
                nz = sx(bit(12) << 9 | bits(4, 3) << 7 | bit(5) << 6 | bit(2) << 5 | bit(6) << 4, 10)
                return enc_i(nz, 2, 0, 2, 0x13) if nz else 0
            nz = bit(12) << 5 | bits(6, 2)
            return ((sx(nz, 6) << 12) & MASK) | (rd << 7) | 0x37 if nz else 0
        if f3 == 4:
            sub, sh = bits(11, 10), bits(6, 2)
            if sub in (0, 1):
                return 0 if bit(12) else enc_i((0x400 if sub else 0) | sh, rs1p, 5, rs1p, 0x13)
            if sub == 2:
                return enc_i(imm6, rs1p, 7, rs1p, 0x13)
            if bit(12):
                return 0
            f3r, f7 = [(0, 0x20), (4, 0), (6, 0), (7, 0)][bits(6, 5)]
            return enc_r(f7, rdp, rs1p, f3r, rs1p, 0x33)
        off = sx(bit(12) << 8 | bits(6, 5) << 6 | bit(2) << 5 | bits(11, 10) << 3 | bits(4, 3) << 1, 9)
        return enc_b(off, 0, rs1p, 0 if f3 == 6 else 1)
    if q == 2:
        if f3 == 0:
            return 0 if bit(12) else enc_i(bits(6, 2), rd, 1, rd, 0x13)
        if f3 == 2:
            off = bits(3, 2) << 6 | bit(12) << 5 | bits(6, 4) << 2
            return enc_i(off, 2, 2, rd, 0x03) if rd else 0
        if f3 == 4:
            if not bit(12):
                if rs2 == 0:
                    return enc_i(0, rd, 0, 0, 0x67) if rd else 0
                return enc_r(0, rs2, 0, 0, rd, 0x33)
            if rs2 == 0:
                return 0x00100073 if rd == 0 else enc_i(0, rd, 0, 1, 0x67)
            return enc_r(0, rs2, rd, 0, rd, 0x33)
        if f3 == 6:
            return enc_s(bits(8, 7) << 6 | bits(12, 9) << 2, rs2, 2, 2)
        return 0
    return 0


def check_decompress():
    """The model's expansion must match the toolchain for every encoding."""
    path = "vectors/decompressor_vectors.txt"
    if not os.path.exists(path):
        return
    for line in open(path):
        f = line.split()
        if len(f) == 3 and not line.startswith("//"):
            h, w = int(f[0], 16), int(f[1], 16)
            if decompress(h) != w:
                sys.exit("model decompressor: %04X -> %08X, toolchain %08X" % (h, decompress(h), w))


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


class ModelError(Exception):
    pass


def sources(ins):
    """Registers an instruction actually reads."""
    op, f3, r1, r2 = ins & 0x7F, (ins >> 12) & 7, (ins >> 15) & 31, (ins >> 20) & 31
    if op in (0x33, 0x23, 0x63):
        return {r1, r2} - {0}
    if op in (0x13, 0x03, 0x67) or (op == 0x73 and f3 in (1, 2, 3)):
        return {r1} - {0}
    return set()


class Timur:
    """Instruction-level model of the Timur SoC (machine mode, precise traps).

    Optional, for the C programs of Phase 12: uart_rx is the byte stream a
    terminal sends (each byte arrives once the receiver is enabled and the
    previous byte was read); interrupts=True takes the external interrupt
    (DMAC done with irq_enable, UART rx_valid with rx_irq_enable) before an
    instruction whenever mstatus.MIE and mie.MEIE are set; trace=False keeps
    only the instruction count."""

    def __init__(self, image, uart_rx=b"", interrupts=False, trace=True):
        self.rom = dict(image)
        self.ram = bytearray(0x10000)
        self.ram_written = set()
        self.ram_taint = set()
        self.x = [0] * 32
        self.taint = set()
        self.pc = 0
        self.gpio_out = self.gpio_dir = self.uart_ctrl = 0
        self.uart_tx = []
        self.uart_rx = list(uart_rx)
        self.rx_valid = self.rx_data = 0
        self.interrupts, self.keep_trace, self.retired = interrupts, trace, 0
        self.dmac = {"src": 0, "dst": 0, "len": 0, "irq": 0, "done": 0}
        self.trace = []
        self.traps = []
        self.divs = 0
        self.mie = self.mpie = self.meie = 0
        self.mtvec = self.mscratch = self.mepc = self.mcause = self.mtval = 0

    # ---- CSRs --------------------------------------------------------------
    def csr_read(self, a):
        if a == 0x344 and self.interrupts:   # mip.MEIP: the OR of the interrupt lines
            return int(bool(self.irq_line())) << 11
        return {0x300: (3 << 11) | (self.mpie << 7) | (self.mie << 3), 0x301: MISA,
                0x304: self.meie << 11, 0x305: self.mtvec, 0x340: self.mscratch,
                0x341: self.mepc, 0x342: self.mcause, 0x343: self.mtval}.get(a, 0)

    def csr_write(self, a, v):
        if a == 0x300:
            self.mie, self.mpie = (v >> 3) & 1, (v >> 7) & 1
        elif a == 0x304:
            self.meie = (v >> 11) & 1
        elif a == 0x305:
            self.mtvec = v & ~3 & MASK
        elif a == 0x340:
            self.mscratch = v
        elif a == 0x341:
            self.mepc = v & ~1 & MASK
        elif a == 0x342:
            self.mcause = v
        elif a == 0x343:
            self.mtval = v
        # misa, mip, the counters: writes change nothing the model tracks

    def trap(self, cause, tval):
        self.traps.append((cause, self.pc, tval))
        self.mepc, self.mcause, self.mtval = self.pc & ~1 & MASK, cause, tval & MASK
        self.mpie, self.mie = self.mie, 0
        self.pc = self.mtvec
        return False

    # ---- memory ------------------------------------------------------------
    def read_word(self, a):
        region = a >> 16
        if region == 0x0000:
            return self.rom.get(a & 0xFFFC, 0)
        if region == 0x2000:
            i = a & 0xFFFC
            return int.from_bytes(self.ram[i:i + 4], "little")
        if region == 0x4000:
            page, reg = (a >> 8) & 0xFF, (a >> 2) & 0x3F
            if page == 0:      # UART: the model sends at once (never busy)
                self.uart_deliver()
                if reg == 0:
                    self.rx_valid = 0
                    return self.rx_data
                return {1: self.rx_valid << 1, 2: self.uart_ctrl}.get(reg, 0)
            if page == 1:
                return {0: self.gpio_out, 1: GPIO_IN, 2: self.gpio_dir}.get(reg, 0)
            if page == 2:
                d = self.dmac
                return {0: d["src"], 1: d["dst"], 2: d["len"], 3: d["irq"] << 1, 4: d["done"] << 1}.get(reg, 0)
        return 0               # default slave

    def uart_deliver(self):
        if self.uart_ctrl & 1 and not self.rx_valid and self.uart_rx:
            self.rx_data, self.rx_valid = self.uart_rx.pop(0), 1

    def irq_line(self):
        self.uart_deliver()
        return (self.dmac["irq"] and self.dmac["done"]) or (self.rx_valid and self.uart_ctrl & 2)

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

    # ---- one instruction ---------------------------------------------------
    def half(self, a):
        return (self.rom.get(a & 0xFFFC, 0) >> (16 * ((a >> 1) & 1))) & 0xFFFF

    def step(self):
        pc = self.pc
        if self.interrupts and self.mie and self.meie and self.irq_line():
            return self.trap(0x8000000B, 0)
        low = self.half(pc)
        if low & 3 != 3:                  # 16-bit instruction: execute its expansion
            ins, length = decompress(low), 2
        else:
            ins, length = low | self.half(pc + 2) << 16, 4
        op, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
        r1 = (ins >> 15) & 31
        a, b = self.x[r1], self.x[(ins >> 20) & 31]
        f7 = ins >> 25
        nxt, res, res_taint = (pc + length) & MASK, None, False
        tainted = bool(sources(ins) & self.taint)
        if not legal(ins):
            return self.trap(2, 0)
        if op in (0x03, 0x23, 0x63, 0x67) and tainted and not (op == 0x23 and r1 not in self.taint):
            raise ModelError("0x%04X: a timing-dependent value controls an address or a branch" % pc)
        if op == 0x33:
            res_taint = tainted
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
            res_taint = tainted
            imm = imm_i(ins) & MASK
            if f3 in (1, 5):
                res = self.alu(f3, a, imm & 31, f7 == 0x20)
            else:
                res = self.alu(f3, a, imm, False)
        elif op == 0x03:
            addr = (a + imm_i(ins)) & MASK
            if (f3 & 3 == 2 and addr & 3) or (f3 & 3 == 1 and addr & 1):
                return self.trap(4, addr)
            res = self.load(addr, f3)
            res_taint = addr >> 16 == 0x2000 and (addr & 0xFFFC) in self.ram_taint
        elif op == 0x23:
            addr = (a + imm_s(ins)) & MASK
            if (f3 & 3 == 2 and addr & 3) or (f3 & 3 == 1 and addr & 1):
                return self.trap(6, addr)
            self.store(addr, f3, b)
            if addr >> 16 == 0x2000:
                if ((ins >> 20) & 31) in self.taint:
                    self.ram_taint.add(addr & 0xFFFC)
                elif f3 & 3 == 2:
                    self.ram_taint.discard(addr & 0xFFFC)
        elif op == 0x63:
            take = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b), 6: a < b, 7: a >= b}[f3]
            if take:
                nxt = (pc + imm_b(ins)) & MASK
        elif op == 0x6F:
            res, nxt = (pc + length) & MASK, (pc + imm_j(ins)) & MASK
        elif op == 0x67:
            res, nxt = (pc + length) & MASK, (a + imm_i(ins)) & MASK & ~1
        elif op == 0x37:
            res = ins & 0xFFFFF000
        elif op == 0x17:
            res = (pc + (ins & 0xFFFFF000)) & MASK
        elif op == 0x73 and f3 != 0:
            addr, kind, imm_form = ins >> 20, f3 & 3, f3 & 4
            write = not (kind in (2, 3) and r1 == 0)
            if addr not in CSR_IMPLEMENTED or (write and addr >> 10 == 3):
                return self.trap(2, 0)
            if write and not imm_form and r1 in self.taint:
                raise ModelError("0x%04X: a timing-dependent value is written to a CSR" % pc)
            src = r1 if imm_form else a
            old = self.csr_read(addr)
            if write:
                self.csr_write(addr, src if kind == 1 else (old | src) if kind == 2 else (old & ~src & MASK))
            res, res_taint = old, addr in CSR_TIMING and not (addr == 0x344 and self.interrupts)
        elif op == 0x73:
            f12 = ins >> 20
            if f12 == 0x000:
                return self.trap(11, 0)
            if f12 == 0x001:
                return self.trap(3, pc)
            if f12 == 0x302:                  # MRET
                nxt = self.mepc
                self.mie, self.mpie = self.mpie, 1
            # WFI: nothing to wait for
        if res is not None and rd:
            self.x[rd] = res & MASK
            if res_taint:
                self.taint.add(rd)
            else:
                self.taint.discard(rd)
        if self.keep_trace:
            self.trace.append(pc)
        self.retired += 1
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

PHASE10 = """
# Phase 10: CSR instructions, precise traps, MRET, counters
        lui   x31, 0x20000         # RAM base
        addi  x28, x31, 0x200      # trap log: mcause, mepc, mtval for each trap
        addi  x1, x0, handler
        csrrw x0, mtvec, x1        # mtvec = handler
        csrrs x2, mtvec, x0        # read back
# WRITE, SET, CLEAR and the immediate forms on mscratch
        addi  x3, x0, 0x5A
        csrrw x4, mscratch, x3     # old value 0, mscratch = 5A
        csrrs x5, mscratch, x0     # 5A, no write
        addi  x6, x0, 0x0F
        csrrs x7, mscratch, x6     # 5A, mscratch = 5F
        csrrc x8, mscratch, x6     # 5F, mscratch = 50
        csrrwi x9, mscratch, 7     # 50, mscratch = 7
        csrrsi x10, mscratch, 8    # 7, mscratch = F
        csrrci x11, mscratch, 3    # F, mscratch = C
        csrrs x12, mscratch, x0    # C
# the operand arrives by forwarding; the old value is forwarded onwards
        addi  x15, x0, 0x123
        csrrw x0, mscratch, x15
        csrrs x16, mscratch, x0    # 123
        add   x17, x16, x16        # 246
# back-to-back CSR instructions on the same CSR behave sequentially
        csrrwi x0, mscratch, 1
        csrrsi x13, mscratch, 2    # 1, mscratch = 3
        csrrs x14, mscratch, x0    # 3
# WARL fields and identification
        addi  x18, x0, 0x7FF
        csrrw x0, mepc, x18        # mepc[1:0] read 0
        csrrs x18, mepc, x0        # 7FC
        csrrs x19, misa, x0        # 40001104
        csrrs x20, mhartid, x0     # 0
        csrrsi x0, mstatus, 8      # MIE = 1
        csrrs x21, mstatus, x0     # 1808
        csrrci x0, mstatus, 8      # MIE = 0
# counters: csrr of a read-only CSR does not trap; cycle advances by one per
# cycle, instret by one per retired instruction
        csrrs x22, cycle, x0
        csrrs x23, cycle, x0
        sub   x24, x23, x22        # 1
        csrrs x25, instret, x0
        addi  x0, x0, 0
        addi  x0, x0, 0
        addi  x0, x0, 0
        csrrs x26, instret, x0
        sub   x26, x26, x25        # 4
# a CSR instruction held in EX by a bus freeze writes once: with HREADY waits
# the CSRRSI sits in EX while the load's data phase waits
        lw    x27, 0(x31)
        addi  x0, x0, 0
        csrrsi x13, mscratch, 4    # old value 3 (written twice it would read 7)
        csrrs x14, mscratch, x0    # 7
# traps: the handler logs mcause, mepc and mtval and returns behind the
# trapping instruction, which leaves no trace
        ecall                      # 11
        ebreak                     # 3, mtval = PC
        .word 0x00000000           # 2: illegal instruction
        csrrs x0, 0x7C0, x0        # 2: CSR not implemented
        csrrw x0, cycle, x1        # 2: write to the read-only space
        lw    x1, 1(x31)           # 4, mtval = address; x1 keeps its value
        lh    x1, 3(x31)           # 4
        lhu   x1, 1(x31)           # 4
        addi  x27, x31, 2
        lw    x1, 0(x27)           # 4: misaligned through the base register
        sw    x3, 0(x27)           # 6
        lw    x27, 2(x27)          # base + offset aligned: no trap
        lb    x27, 3(x31)          # bytes never trap
        sw    x3, 2(x31)           # 6: misaligned store, the RAM is not written
        sh    x3, 1(x31)           # 6
        sb    x3, 3(x31)           # RAM word 0 = 5A000000
        csrrs x29, mstatus, x0     # 1880: MPIE = 1 after MRET
        csrrs x30, mepc, x0        # behind the last trapping instruction
halt:   jal   x0, halt
        .org 0x300
handler:
        csrrs x29, mcause, x0
        sw    x29, 0(x28)
        csrrs x29, mepc, x0
        sw    x29, 4(x28)
        csrrs x30, mtval, x0
        sw    x30, 8(x28)
        addi  x28, x28, 12
        addi  x29, x29, 4          # return behind the trapping instruction
        csrrw x0, mepc, x29
        mret
"""

INTERRUPT = """
# Phase 10: the DMAC's done interrupt. The DMA finishes while a chain of DIVs
# occupies EX; the interrupt waits until no DIV is in EX, then enters the
# handler exactly once.
        lui   x31, 0x20000         # RAM base
        lui   x30, 0x40000         # APB base
        addi  x29, x30, 0x200      # DMAC registers
        addi  x1, x0, handler
        csrrw x0, mtvec, x1
        addi  x1, x0, 1
        slli  x1, x1, 11
        csrrs x0, mie, x1          # MEIE = 1
        csrrsi x0, mstatus, 8      # MIE = 1
        lui   x2, 0x1
        sw    x2, 0(x29)           # SRC = 0x1000 (ROM)
        addi  x3, x31, 0x100
        sw    x3, 4(x29)           # DST = 0x2000_0100
        addi  x4, x0, 4
        sw    x4, 8(x29)           # LEN = 4 words
        addi  x5, x0, 3
        sw    x5, 12(x29)          # CTRL: start, irq_enable
        lui   x6, 0x12345
        addi  x7, x0, 7
        div   x8, x6, x7           # the DMA finishes during this chain
        div   x9, x8, x7
        div   x10, x9, x7
        div   x11, x10, x7
wait:   beq   x20, x0, wait        # the handler sets x20
        addi  x21, x0, 1
halt:   jal   x0, halt
        .org 0x300
handler:
        csrrs x22, mcause, x0      # 8000000B
        csrrs x23, mip, x0         # 800: MEIP
        sw    x0, 12(x29)          # a CTRL write clears done: the interrupt line drops
        lw    x24, 16(x29)         # STATUS: 0
        add   x24, x24, x0
        csrrs x25, mip, x0         # 0
        addi  x20, x0, 1
        addi  x26, x26, 1          # interrupts taken: exactly one
        mret
        .org 0x1000
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444
"""

PHASE11 = """
# Phase 11: every kind of compressed instruction, 32-bit instructions at both
# alignments (at 2 mod 4 a 32-bit instruction straddles two ROM words),
# compressed control flow with PC + 2 links, traps from 16-bit instructions.
# Assembled by GNU as; the c.* mnemonics force the 16-bit forms.
        .option rvc
start:  lui    x31, 0x20000             # RAM base
        addi   x28, x31, 0x200          # trap log: mcause, mepc, mtval
        lui    x2, 0x20001              # sp = 2000_1000
        la     x1, handler
        csrw   mtvec, x1
# arithmetic on x8-x15, the registers the 3-bit fields reach
        c.li   x8, 5
        c.li   x9, -3
        c.addi x8, 7                    # 12
        c.lui  x10, 0x12                # 0001_2000
        c.lui  x11, 0xfffe0             # FFFE_0000
        c.andi x9, 15                   # 13
        c.srli x10, 4                   # 0000_1200
        c.srai x11, 8                   # FFFF_FE00
        c.slli x8, 3                    # 96
        c.mv   x12, x8                  # 96
        c.add  x12, x9                  # 109
        c.sub  x12, x10                 # 109 - 1200
        c.li   x13, 0x15
        c.xor  x13, x8                  # 75
        c.li   x14, 0x0A
        c.or   x14, x9                  # 0F
        c.li   x15, -1
        c.and  x15, x10                 # 1200
# stack- and register-relative loads and stores
        c.addi16sp sp, -64              # sp = 2000_0FC0
        c.addi4spn x14, sp, 16          # x14 = 2000_0FD0
        c.swsp x12, 0(sp)
        c.lwsp x15, 0(sp)
        c.addi x15, 1                   # load-use with a 16-bit consumer
        c.sw   x15, 4(x14)
        c.lw   x13, 4(x14)
        c.mv   x16, x13
# 32-bit instructions at 2 mod 4 straddle two ROM words
        .balign 4
        c.nop
        addi   x17, x0, 0x123           # at 2 mod 4
        lui    x18, 0x54321             # at 2 mod 4
        c.nop
        addi   x18, x18, 0x765          # at 0 mod 4
        lw     x19, 4(x14)
        addi   x19, x19, 1              # load-use between straddling instructions
# compressed branches, taken and not taken, at both alignments
        c.li   x8, 0
        c.beqz x8, 1f                   # taken
        c.li   x9, 1                    # skipped
1:      c.bnez x8, 2f                   # not taken
        c.li   x9, 2
2:      c.j    3f
        c.li   x9, 3                    # skipped
3:      c.li   x10, 1
        c.bnez x10, 4f                  # taken
        c.li   x9, 4                    # skipped
4:
# links: PC + 2 for C.JAL and C.JALR, PC + 4 for JAL and JALR
        c.jal  inc20
        c.mv   x21, x1
        jal    x1, inc20
        c.mv   x22, x1
        la     x5, inc20
        c.jalr x5
        c.mv   x23, x1
        jalr   x1, 0(x5)
        c.mv   x24, x1
# a JALR to a target with bit 1 set is legal with the C extension
        la     x5, odd_target
        jalr   x0, 0(x5)
        c.li   x9, 5                    # skipped
        .balign 4
        c.nop
odd_target:
        addi   x25, x0, 0x77            # at 2 mod 4
# traps from 16-bit instructions: the handler steps over 2 bytes
        c.ebreak                        # 3, mtval = PC
        .2byte 0x0000                   # 2: the defined illegal encoding
        .2byte 0x6101                   # 2: C.ADDI16SP with a zero immediate is reserved
        ecall                           # 11: 32-bit, the handler steps over 4 bytes
        csrr   x26, misa                # 40001104
halt:   c.j    halt
inc20:  c.addi x20, 1
        c.jr   x1
        .org   0x600
handler:
        csrr   x29, mcause
        sw     x29, 0(x28)
        csrr   x29, mepc
        sw     x29, 4(x28)
        csrr   x30, mtval
        sw     x30, 8(x28)
        addi   x28, x28, 12
        lhu    x30, 0(x29)              # first halfword of the trapping instruction
        andi   x30, x30, 3
        addi   x29, x29, 2
        addi   x27, x0, 3
        bne    x30, x27, 5f             # 16-bit: 2 bytes
        addi   x29, x29, 2              # 32-bit: 4 bytes
5:      csrw   mepc, x29
        mret
"""

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
        ecall                      # trap to 0x100
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
# Expected state: the ECALL traps to the handler at 0x100 (x22 = mcause = 11,
# x23 = mepc + 4 = 0x78); x17 holds a cycle count and is checked for non-zero.
FINAL_EXPECTED = {1: 10, 2: 1, 3: 10, 4: 11, 5: 10, 6: 10, 7: 42, 10: 0x55, 11: 0x40000200,
                  12: 0x1000, 13: 0x20000100, 14: 4, 15: 1, 16: 0, 18: 0x100, 19: 99,
                  20: 0x20000000, 21: 0x40000000, 22: 11, 23: 0x78}
FINAL_RAM = dict([(0x20000000, 10)] + [(0x20000100 + 4 * i, 0x11111111 * (i + 1)) for i in range(4)])


# Hardware bring-up order (Phase 9). Each is written to sw/bringup/ as a 32-bit
# .hex (testbench) and as the two ROM banks (_lo/_hi .hex and .mif); copy the
# bank files over rom_lo.* and rom_hi.* and recompile.
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
def random_program(seed, length, gnu=False):
    """Forward-only control flow, so every program terminates.

    x31 = RAM base, x30 = APB base, x29 = JALR base, x28 = computed address base,
    x1..x20 carry the random data flow. Loads and stores mix RAM, APB registers
    (GPIO OUT/IN/DIR, UART CTRL, DMAC SRC/DST/LEN, unmapped APB offsets), the ROM
    data port and unmapped addresses; DIV/REM include divide-by-zero and
    signed-overflow operands.
    """
    rnd = random.Random(seed)
    out = ["# %s random program, seed %d" % ("Phase 11 compressed" if gnu else "Phase 7", seed),
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
            if gnu:                  # instruction sizes vary: jump to a label
                labels[0] += 1
                target = "L%d" % labels[0]
                out.append("        lui   x29, %%hi(%s)" % target)
                out.append("        jalr  x%d, %%lo(%s)(x29)" % (rd, target))
            else:
                out.append("        auipc x29, 0")
                out.append("        jalr  x%d, %d(x29)" % (rd, 8 + 4 * skip))
            if rd:
                wrote(rd)
            for _ in range(skip):
                simple()
            if gnu:
                out.append(target + ":")
        else:
            simple()
        count += 1
    out.append("halt:   jal   x0, halt")
    return "\n".join(out) + "\n"


def random_c_program(seed, length):
    """Dependency-dense program of 16-bit instructions mixed with 32-bit ones, for GNU as.

    x9 = RAM base and x2 = sp (RAM + 0x800) stay fixed; x8 and x10-x15 carry the data
    flow of the 3-bit register fields, x1 and x16-x22 that of the full ones. Control
    flow is forward only (compressed branches and jumps, C.JAL, C.JR/C.JALR through
    x5), so every program terminates; 32-bit instructions land at both alignments.
    """
    rnd = random.Random(seed)
    D = [8, 10, 11, 12, 13, 14, 15]
    A = D + [1, 16, 17, 18, 19, 20, 21, 22]
    out = ["# Phase 11 random program of compressed and 32-bit instructions, seed %d" % seed,
           "        .option rvc",
           "        lui   x9, 0x20000",
           "        lui   x2, 0x20001",
           "        addi  x2, x2, -0x800",
           "        lui   x30, 0x40000"]
    for r in A:
        v = rnd.getrandbits(32)
        hi, lo = ((v + 0x800) >> 12) & 0xFFFFF, v & 0xFFF
        lo = lo - 0x1000 if lo & 0x800 else lo
        out.append("        lui   x%d, 0x%05X" % (r, hi))
        out.append("        addi  x%d, x%d, %d" % (r, r, lo))
    nlab = [0]

    def label():
        nlab[0] += 1
        return "C%d" % nlab[0]

    def nz6():
        return rnd.choice([v for v in range(-32, 32) if v])

    def one():
        k = rnd.random()
        d, d2, a, a2 = rnd.choice(D), rnd.choice(D), rnd.choice(A), rnd.choice(A)
        if k < 0.07:
            out.append("        c.addi  x%d, %d" % (a, nz6()))
        elif k < 0.12:
            out.append("        c.li    x%d, %d" % (a, rnd.randint(-32, 31)))
        elif k < 0.15:
            out.append("        c.lui   x%d, 0x%x" % (a, rnd.choice(list(range(1, 32)) + list(range(0xFFFE0, 0x100000)))))
        elif k < 0.19:
            out.append("        c.slli  x%d, %d" % (a, rnd.randint(1, 31)))
        elif k < 0.23:
            out.append("        c.%s  x%d, %d" % (rnd.choice(["srli", "srai"]), d, rnd.randint(1, 31)))
        elif k < 0.26:
            out.append("        c.andi  x%d, %d" % (d, rnd.randint(-32, 31)))
        elif k < 0.31:
            out.append("        c.mv    x%d, x%d" % (a, a2))
        elif k < 0.36:
            out.append("        c.add   x%d, x%d" % (a, a2))
        elif k < 0.44:
            out.append("        c.%s   x%d, x%d" % (rnd.choice(["sub", "xor", "or", "and"]), d, d2))
        elif k < 0.50:
            out.append("        c.lw    x%d, %d(x9)" % (d, rnd.randrange(0, 128, 4)))
        elif k < 0.55:
            out.append("        c.sw    x%d, %d(x9)" % (d, rnd.randrange(0, 128, 4)))
        elif k < 0.59:
            out.append("        c.lwsp  x%d, %d(x2)" % (a, rnd.randrange(0, 256, 4)))
        elif k < 0.63:
            out.append("        c.swsp  x%d, %d(x2)" % (a, rnd.randrange(0, 256, 4)))
        elif k < 0.67:
            op = rnd.choice(["lb", "lbu", "lh", "lhu"])
            off = rnd.randrange(0, 128, 2 if op in ("lh", "lhu") else 1)
            out.append("        %-6s x%d, %d(x9)" % (op, a, off))
        elif k < 0.70:
            op = rnd.choice(["sb", "sh"])
            out.append("        %-6s x%d, %d(x9)" % (op, a, rnd.randrange(0, 128, 2 if op == "sh" else 1)))
        elif k < 0.76:
            op = rnd.choice(["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"])
            out.append("        %-6s x%d, x%d, x%d" % (op, a, a2, rnd.choice(A)))
        elif k < 0.82:
            op = rnd.choice(["add", "sub", "xor", "or", "and", "sll", "srl", "sra", "slt", "sltu"])
            out.append("        %-6s x%d, x%d, x%d" % (op, a, a2, rnd.choice(A)))
        elif k < 0.86:
            op = rnd.choice(["addi", "xori", "ori", "andi", "slti", "sltiu"])
            out.append("        %-6s x%d, x%d, %d" % (op, a, a2, rnd.randint(-2048, 2047)))
        elif k < 0.88:
            out.append("        lw     x%d, %d(x30)" % (a, rnd.choice([0x100, 0x104, 0x108, 0x200, 0x204])))
        else:
            out.append("        sw     x%d, %d(x9)" % (a, rnd.randrange(128, 256, 4)))

    count = 0
    while count < length:
        k = rnd.random()
        if k < 0.08:
            t = label()
            out.append("        c.%s  x%d, %s" % (rnd.choice(["beqz", "bnez"]), rnd.choice(D), t))
            for _ in range(rnd.randint(0, 3)):
                one()
            out.append(t + ":")
        elif k < 0.11:
            t = label()
            out.append("        %-6s x%d, x%d, %s" % (rnd.choice(["beq", "bne", "blt", "bge", "bltu", "bgeu"]),
                                                     rnd.choice(A), rnd.choice(A), t))
            for _ in range(rnd.randint(0, 3)):
                one()
            out.append(t + ":")
        elif k < 0.13:
            t = label()
            out.append("        c.%s    %s" % (rnd.choice(["j", "jal"]), t))
            for _ in range(rnd.randint(0, 3)):
                one()
            out.append(t + ":")
        elif k < 0.15:
            t = label()
            out.append("        la     x5, %s" % t)
            out.append("        c.%s   x5" % rnd.choice(["jr", "jalr"]))
            for _ in range(rnd.randint(0, 3)):
                one()
            out.append(t + ":")
        else:
            one()
        count += 1
    out.append("halt:   c.j    halt")
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


def write_banks(prefix, image, title):
    """<prefix>_lo / _hi .hex and .mif: the two ROM banks (sw/bin2mem.py)."""
    bin2mem.write_banks(prefix, image_words(image), title)


def toolchain_prefix():
    if shutil.which("riscv-none-elf-as"):
        return "riscv-none-elf-"
    for d in sorted(glob.glob(".tools/xpack-riscv-none-elf-gcc-*/bin")):
        return os.path.join(d, "riscv-none-elf-")
    return None


def _run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("command failed: %s\n%s" % (" ".join(cmd), r.stderr[:3000]))
    return r.stdout


def gnu_program(name, source):
    """Assemble with GNU as for rv32imc_zicsr (16-bit forms wherever possible), link at
    address 0, write vectors/timur_soc_<name>.hex with the labels as comments, and return
    (image, labels). Without the toolchain the committed file is read back instead."""
    path = "vectors/timur_soc_%s.hex" % name
    pre = toolchain_prefix()
    if pre is None:
        words, labels = [], {}
        for line in open(path):
            m = re.match(r"// label (\S+) ([0-9A-F]{8})", line)
            if m:
                labels[m.group(1)] = int(m.group(2), 16)
            elif line.strip() and not line.startswith("//"):
                words.append(int(line.split()[0], 16))
        return {4 * i: w for i, w in enumerate(words)}, labels
    with tempfile.TemporaryDirectory() as tmp:
        src, obj = os.path.join(tmp, "p.s"), os.path.join(tmp, "p.o")
        elf, binary = os.path.join(tmp, "p.elf"), os.path.join(tmp, "p.bin")
        with open(src, "w") as f:
            f.write(source)
        _run([pre + "as", "-march=rv32imc_zicsr", "-mabi=ilp32", "-mno-relax", "-o", obj, src])
        _run([pre + "ld", "-m", "elf32lriscv", "-Ttext=0", "-e", "0", "-o", elf, obj])
        _run([pre + "objcopy", "-O", "binary", "-j", ".text", elf, binary])
        data = open(binary, "rb").read()
        data += b"\0" * (-len(data) % 4)
        labels = {}
        for line in _run([pre + "nm", elf]).splitlines():
            f = line.split()
            if len(f) == 3 and f[1] in "tT" and not f[2].startswith((".", "_")):
                labels[f[2]] = int(f[0], 16)
        listing = _run([pre + "objdump", "-d", "-M", "no-aliases", elf])
    image = {4 * i: int.from_bytes(data[4 * i:4 * i + 4], "little") for i in range(len(data) // 4)}
    halves = sum(1 for l in listing.splitlines() if re.match(r"\s+[0-9a-f]+:\s+[0-9a-f]{4}\s", l))
    with open(path, "w") as f:
        f.write("// %s: assembled by GNU as (rv32imc_zicsr), %d 16-bit instructions\n" % (name, halves))
        for lab in sorted(labels, key=labels.get):
            f.write("// label %s %08X\n" % (lab, labels[lab]))
        for w in image_words(image):
            f.write("%08X\n" % w)
    return image, labels


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

    def nonzero(self, regs):
        for r in regs:
            self.lines.append("REGNZ %d" % r)


def model_checks(vec, model, halt, trace=True):
    """Everything the model knows; tainted registers and RAM words are left out."""
    vec.regs({r: model.x[r] for r in range(1, 32) if r not in model.taint})
    vec.ram({0x20000000 | a: int.from_bytes(model.ram[a:a + 4], "little")
             for a in model.ram_written if a not in model.ram_taint})
    if not any(a < 0x1000 for a in model.ram_taint):
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

    check_decompress()
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
    vec.comment("      per load-use, no misaligned CPU bus access, no interrupt taken with a MUL or DIV")
    vec.comment("      in EX.")
    vec.comment("  REG <n> <value>      register x<n> at the end of the run")
    vec.comment("  REGNZ <n>            register x<n> is not zero (timing-dependent counter values)")
    vec.comment("  RAM <addr> <value>   RAM word")
    vec.comment("  RAMNZ <count>        number of non-zero words in 0x2000_0000 - 0x2000_0FFF")
    vec.comment("  LEDS <value>         gpio_out")
    vec.comment("  UART <byte>          next byte decoded from uart_tx (8N1, 434 cycles per bit)")
    vec.comment("  UARTN <count>        number of bytes decoded from uart_tx")
    vec.comment("  DIVS <count>         divider start pulses")
    vec.comment("  IRQHELD <count>      the interrupt was pending for at least <count> cycles while a MUL or")
    vec.comment("                       DIV was in EX (it had to wait)")
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

    # ---- Phase 10 --------------------------------------------------------------------------------
    image, listing, labels = assemble(PHASE10)
    m = Timur(image).run()
    got = [(c, e, v) for c, e, v in m.traps]
    want = [(11,), (3,), (2,), (2,), (2,), (4,), (4,), (4,), (4,), (6,), (6,), (6,)]
    if [(c,) for c, _, _ in got] != want:
        sys.exit("model: Phase 10 trap causes %s" % [c for c, _, _ in got])
    write_hex("vectors/timur_soc_phase10.hex", image, listing)
    for waits in (0, 1):
        vec.comment("==== Phase 10: CSR instructions, every trap cause, MRET, counters%s"
                    % (", with HREADY waits" if waits else ""))
        vec.prog("vectors/timur_soc_phase10.hex", 4000, labels["halt"], waits)
        model_checks(vec, m, labels["halt"])
        vec.comment("     timing-dependent counter values: hand-written checks")
        vec.regs({24: 1, 26: 4})
        vec.nonzero([22, 23, 25])

    image, listing, labels = assemble(INTERRUPT)
    write_hex("vectors/timur_soc_interrupt.hex", image, listing)
    q = [0x12345000]
    for _ in range(4):
        q.append(divide(q[-1], 7, 4))
    vec.comment("==== Phase 10: external interrupt (DMAC done) held off by a chain of DIVs, taken once")
    vec.prog("vectors/timur_soc_interrupt.hex", 3000, labels["halt"], 0)
    vec.regs({8: q[1], 9: q[2], 10: q[3], 11: q[4], 20: 1, 21: 1, 22: 0x8000000B, 23: 0x800,
              24: 0, 25: 0, 26: 1})
    vec.ram({0x20000100 + 4 * i: 0x11111111 * (i + 1) for i in range(4)})
    vec.add("RAMNZ 4")
    vec.add("DIVS 4")
    vec.add("IRQHELD 20")

    # ---- Phase 11 --------------------------------------------------------------------------------
    image, labels = gnu_program("phase11", PHASE11)
    m = Timur(image).run()
    if [c for c, _, _ in m.traps] != [3, 2, 2, 11]:
        sys.exit("model: Phase 11 trap causes %s" % [c for c, _, _ in m.traps])
    for waits in (0, 1):
        vec.comment("==== Phase 11: compressed instructions, straddling 32-bit instructions, PC + 2 links, "
                    "16-bit traps%s" % (", with HREADY waits" if waits else ""))
        vec.prog("vectors/timur_soc_phase11.hex", 4000, labels["halt"], waits)
        model_checks(vec, m, labels["halt"])

    image, labels = gnu_program("random_c", random_c_program(args.seed + 1, args.length))
    m = Timur(image).run()
    for waits in (0, 1):
        vec.comment("==== Phase 11 random program of 16-bit and 32-bit instructions, seed %d, %d instructions executed%s"
                    % (args.seed + 1, len(m.trace), ", with HREADY waits" if waits else ""))
        vec.prog("vectors/timur_soc_random_c.hex", 40 * len(m.trace) + 2000, labels["halt"], waits)
        model_checks(vec, m, labels["halt"])

    # ---- final cross-phase program (also the default ROM image) --------------------------------
    image, listing, labels = assemble(FINAL)
    m = Timur(image).run()
    for r, v in FINAL_EXPECTED.items():
        if m.x[r] != v:
            sys.exit("model: final program x%d = %08X, expected %08X" % (r, m.x[r], v))
    write_hex("rom.hex", image, listing, comments=False)
    write_banks("rom", image, "final cross-phase verification program")
    vec.comment("==== Final cross-phase program from rom.hex: ECALL round trip, x17 = cycle count")
    vec.prog("rom.hex", 3000, labels["halt"], 0)
    vec.regs(FINAL_EXPECTED)
    vec.nonzero([17])
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
        write_banks("sw/bringup/%s" % name, image, "bring-up, " + title)
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
