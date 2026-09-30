"""Expansion of the 16-bit (C extension) instructions of RV32IMC.

The reference model executes a compressed instruction as its 32-bit expansion,
as the decompressor in rtl/decode/decompressor.v does. This table is checked
against vectors/decompressor_vectors.txt, which sw/gen_decompressor_vectors.py
derives from the GNU toolchain for all 49152 encodings.
"""

from __future__ import annotations

from .isa import (
    F7_ALT,
    F7_BASE,
    INSTR_EBREAK,
    OP_IMM,
    OP_JALR,
    OP_LOAD,
    OP_LUI,
    OP_REG,
    REG_RA,
    REG_SP,
    REG_ZERO,
    enc_b,
    enc_i,
    enc_j,
    enc_r,
    enc_s,
    enc_u,
    sign_extend,
)

#: What an illegal or reserved 16-bit encoding expands to: the all-zero word,
#: which main_control_unit decodes as an illegal instruction.
ILLEGAL = 0

#: Instructions whose bits [1:0] are 11 are 32 bits long.
QUADRANT_32BIT = 3

# funct3 values used with the expansions
_F3_ADD, _F3_SLL, _F3_WORD, _F3_XOR, _F3_SRL, _F3_OR, _F3_AND = 0, 1, 2, 4, 5, 6, 7
_F3_BEQ, _F3_BNE = 0, 1
# C.SUB, C.XOR, C.OR, C.AND by instruction bits [6:5]: (funct3, funct7)
_CA_OPS = ((_F3_ADD, F7_ALT), (_F3_XOR, F7_BASE), (_F3_OR, F7_BASE), (_F3_AND, F7_BASE))
_SRAI_IMM_BIT = 0x400  # funct7 = 0x20 in the I-type immediate of SRAI


def is_compressed(halfword: int) -> bool:
    """True if the instruction that starts with this halfword is 16 bits long."""
    return halfword & 3 != QUADRANT_32BIT


def decompress(halfword: int) -> int:
    """32-bit expansion of a 16-bit instruction; ILLEGAL for illegal and reserved
    encodings."""
    quadrant, funct3 = halfword & 3, (halfword >> 13) & 7
    rd, rs2 = (halfword >> 7) & 31, (halfword >> 2) & 31
    # the 3-bit register fields address x8-x15
    rd_prime, rs1_prime = 8 + ((halfword >> 2) & 7), 8 + ((halfword >> 7) & 7)

    def bit(index: int) -> int:
        return (halfword >> index) & 1

    def bits(high: int, low: int) -> int:
        return (halfword >> low) & ((1 << (high - low + 1)) - 1)

    if quadrant == 0:
        offset = bit(5) << 6 | bits(12, 10) << 3 | bit(6) << 2
        if funct3 == 0:  # C.ADDI4SPN
            nzuimm = bits(10, 7) << 6 | bits(12, 11) << 4 | bit(5) << 3 | bit(6) << 2
            return enc_i(nzuimm, REG_SP, _F3_ADD, rd_prime, OP_IMM) if nzuimm else ILLEGAL
        if funct3 == 2:  # C.LW
            return enc_i(offset, rs1_prime, _F3_WORD, rd_prime, OP_LOAD)
        if funct3 == 6:  # C.SW
            return enc_s(offset, rd_prime, rs1_prime, _F3_WORD)
        return ILLEGAL

    if quadrant == 1:
        imm6 = sign_extend(bit(12) << 5 | bits(6, 2), 6)
        if funct3 == 0:  # C.ADDI, C.NOP
            return enc_i(imm6, rd, _F3_ADD, rd, OP_IMM)
        if funct3 in (1, 5):  # C.JAL (links ra), C.J
            offset = sign_extend(
                bit(12) << 11
                | bit(8) << 10
                | bits(10, 9) << 8
                | bit(6) << 7
                | bit(7) << 6
                | bit(2) << 5
                | bit(11) << 4
                | bits(5, 3) << 1,
                12,
            )
            return enc_j(offset, REG_RA if funct3 == 1 else REG_ZERO)
        if funct3 == 2:  # C.LI
            return enc_i(imm6, REG_ZERO, _F3_ADD, rd, OP_IMM)
        if funct3 == 3:
            if rd == REG_SP:  # C.ADDI16SP
                nzimm = sign_extend(
                    bit(12) << 9 | bits(4, 3) << 7 | bit(5) << 6 | bit(2) << 5 | bit(6) << 4, 10
                )
                return enc_i(nzimm, REG_SP, _F3_ADD, REG_SP, OP_IMM) if nzimm else ILLEGAL
            nzimm = bit(12) << 5 | bits(6, 2)  # C.LUI
            return enc_u(sign_extend(nzimm, 6), rd, OP_LUI) if nzimm else ILLEGAL
        if funct3 == 4:
            kind, shamt = bits(11, 10), bits(6, 2)
            if kind in (0, 1):  # C.SRLI, C.SRAI: shamt[5] must be 0 on RV32
                if bit(12):
                    return ILLEGAL
                imm = (_SRAI_IMM_BIT if kind else 0) | shamt
                return enc_i(imm, rs1_prime, _F3_SRL, rs1_prime, OP_IMM)
            if kind == 2:  # C.ANDI
                return enc_i(imm6, rs1_prime, _F3_AND, rs1_prime, OP_IMM)
            if bit(12):  # C.SUBW, C.ADDW: RV64 only
                return ILLEGAL
            reg_funct3, funct7 = _CA_OPS[bits(6, 5)]
            return enc_r(funct7, rd_prime, rs1_prime, reg_funct3, rs1_prime, OP_REG)
        # C.BEQZ (funct3 6), C.BNEZ (7)
        offset = sign_extend(
            bit(12) << 8 | bits(6, 5) << 6 | bit(2) << 5 | bits(11, 10) << 3 | bits(4, 3) << 1, 9
        )
        return enc_b(offset, REG_ZERO, rs1_prime, _F3_BEQ if funct3 == 6 else _F3_BNE)

    if quadrant == 2:
        if funct3 == 0:  # C.SLLI: shamt[5] must be 0 on RV32
            return ILLEGAL if bit(12) else enc_i(bits(6, 2), rd, _F3_SLL, rd, OP_IMM)
        if funct3 == 2:  # C.LWSP: rd = x0 is reserved
            offset = bits(3, 2) << 6 | bit(12) << 5 | bits(6, 4) << 2
            return enc_i(offset, REG_SP, _F3_WORD, rd, OP_LOAD) if rd else ILLEGAL
        if funct3 == 4:
            if not bit(12):
                if rs2 == 0:  # C.JR: rs1 = x0 is reserved
                    return enc_i(0, rd, 0, REG_ZERO, OP_JALR) if rd else ILLEGAL
                return enc_r(F7_BASE, rs2, REG_ZERO, _F3_ADD, rd, OP_REG)  # C.MV
            if rs2 == 0:  # C.EBREAK, C.JALR
                return INSTR_EBREAK if rd == 0 else enc_i(0, rd, 0, REG_RA, OP_JALR)
            return enc_r(F7_BASE, rs2, rd, _F3_ADD, rd, OP_REG)  # C.ADD
        if funct3 == 6:  # C.SWSP
            return enc_s(bits(8, 7) << 6 | bits(12, 9) << 2, rs2, REG_SP, _F3_WORD)
        return ILLEGAL

    return ILLEGAL
