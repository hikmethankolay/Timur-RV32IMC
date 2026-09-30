"""RV32IMC instruction formats: opcodes, field encoders and immediate decoders.

Shared by the assembler (asm), the expansion of 16-bit instructions (rvc) and
the reference model (model).
"""

from __future__ import annotations

MASK = 0xFFFF_FFFF  # 32 bits
SIGN_BIT = 0x8000_0000

# ---- major opcodes (instruction bits [6:0]) ----------------------------------
OP_LOAD = 0x03
OP_MISC_MEM = 0x0F  # FENCE, FENCE.I
OP_IMM = 0x13
OP_AUIPC = 0x17
OP_STORE = 0x23
OP_REG = 0x33
OP_LUI = 0x37
OP_BRANCH = 0x63
OP_JALR = 0x67
OP_JAL = 0x6F
OP_SYSTEM = 0x73

# ---- funct7 ------------------------------------------------------------------
F7_BASE = 0x00
F7_MULDIV = 0x01  # the M extension
F7_ALT = 0x20  # SUB, SRA, SRAI

# ---- funct3 of OP_REG / OP_IMM -------------------------------------------------
F3_ADD_SUB, F3_SLL, F3_SLT, F3_SLTU, F3_XOR, F3_SRL_SRA, F3_OR, F3_AND = range(8)
# ---- funct3 with F7_MULDIV -----------------------------------------------------
F3_MUL, F3_MULH, F3_MULHSU, F3_MULHU, F3_DIV, F3_DIVU, F3_REM, F3_REMU = range(8)
# ---- funct3 of loads and stores: bits [1:0] are the size, bit 2 means unsigned -
F3_BYTE, F3_HALF, F3_WORD = 0, 1, 2
F3_SIZE_MASK = 3
F3_LBU, F3_LHU = 4, 5
# ---- funct3 of OP_SYSTEM -------------------------------------------------------
F3_PRIV = 0  # ECALL, EBREAK, MRET, WFI
F3_CSRRW, F3_CSRRS, F3_CSRRC = 1, 2, 3
F3_CSR_IMMEDIATE = 4  # bit 2: the source is a 5-bit immediate, not rs1

# ---- funct12 of the privileged instructions (OP_SYSTEM, funct3 = 0) ------------
F12_ECALL = 0x000
F12_EBREAK = 0x001
F12_WFI = 0x105
F12_MRET = 0x302

# ---- fixed encodings -----------------------------------------------------------
INSTR_NOP = 0x0000_0013  # addi x0, x0, 0
INSTR_ECALL = 0x0000_0073
INSTR_EBREAK = 0x0010_0073
INSTR_MRET = 0x3020_0073
INSTR_WFI = 0x1050_0073
INSTR_FENCE = 0x0FF0_000F  # fence iorw, iorw
INSTR_HALT = 0x0000_006F  # jal x0, 0: the jump-to-self that ends a program

REG_ZERO, REG_RA, REG_SP = 0, 1, 2


def s32(value: int) -> int:
    """value as a signed 32-bit integer."""
    value &= MASK
    return value - (1 << 32) if value & SIGN_BIT else value


def sign_extend(value: int, bits: int) -> int:
    """The bits-wide two's complement number value as an integer."""
    return value - (1 << bits) if (value >> (bits - 1)) & 1 else value


# ---- encoders --------------------------------------------------------------------
def enc_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    """R-type instruction."""
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    """I-type instruction; imm is truncated to 12 bits."""
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    """S-type instruction (a store)."""
    return (
        (((imm >> 5) & 0x7F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | ((imm & 0x1F) << 7)
        | OP_STORE
    )


def enc_b(imm: int, rs2: int, rs1: int, funct3: int) -> int:
    """B-type instruction (a branch); imm is the byte offset."""
    return (
        (((imm >> 12) & 1) << 31)
        | (((imm >> 5) & 0x3F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (((imm >> 1) & 0xF) << 8)
        | (((imm >> 11) & 1) << 7)
        | OP_BRANCH
    )


def enc_u(imm20: int, rd: int, opcode: int) -> int:
    """U-type instruction (LUI, AUIPC); imm20 is the upper 20 bits."""
    return ((imm20 << 12) & MASK) | (rd << 7) | opcode


def enc_j(imm: int, rd: int) -> int:
    """J-type instruction (JAL); imm is the byte offset."""
    return (
        (((imm >> 20) & 1) << 31)
        | (((imm >> 1) & 0x3FF) << 21)
        | (((imm >> 11) & 1) << 20)
        | (((imm >> 12) & 0xFF) << 12)
        | (rd << 7)
        | OP_JAL
    )


# ---- immediate decoders (signed) ----------------------------------------------------
def imm_i(ins: int) -> int:
    """Immediate of an I-type instruction."""
    return s32(ins) >> 20


def imm_s(ins: int) -> int:
    """Immediate of an S-type instruction."""
    return (s32(ins) >> 25 << 5) | ((ins >> 7) & 0x1F)


def imm_b(ins: int) -> int:
    """Byte offset of a B-type instruction."""
    return (
        ((s32(ins) >> 31) << 12)
        | (((ins >> 7) & 1) << 11)
        | (((ins >> 25) & 0x3F) << 5)
        | (((ins >> 8) & 0xF) << 1)
    )


def imm_j(ins: int) -> int:
    """Byte offset of a J-type instruction."""
    return (
        ((s32(ins) >> 31) << 20)
        | (((ins >> 12) & 0xFF) << 12)
        | (((ins >> 20) & 1) << 11)
        | (((ins >> 21) & 0x3FF) << 1)
    )
