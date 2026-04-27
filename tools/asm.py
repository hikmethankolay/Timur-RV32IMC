"""Tiny RV32IM encoder for the Timur testbench.

Each function returns a 32-bit unsigned int. Caller is responsible for
laying out the program in memory order.
"""

def _u(x, bits):
    return x & ((1 << bits) - 1)

def r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return (_u(funct7, 7) << 25) | (_u(rs2, 5) << 20) | (_u(rs1, 5) << 15) \
         | (_u(funct3, 3) << 12) | (_u(rd, 5) << 7)  | _u(opcode, 7)

def i_type(imm, rs1, funct3, rd, opcode):
    return (_u(imm, 12) << 20) | (_u(rs1, 5) << 15) | (_u(funct3, 3) << 12) \
         | (_u(rd, 5) << 7) | _u(opcode, 7)

def s_type(imm, rs2, rs1, funct3, opcode):
    imm = _u(imm, 12)
    return ((imm >> 5) << 25) | (_u(rs2, 5) << 20) | (_u(rs1, 5) << 15) \
         | (_u(funct3, 3) << 12) | ((imm & 0x1F) << 7) | _u(opcode, 7)

def b_type(imm, rs2, rs1, funct3, opcode):
    # imm is signed byte offset, must be even
    assert imm % 2 == 0, "B-type imm must be 2-byte aligned"
    imm = _u(imm, 13)  # 13-bit signed range, bit 0 always 0
    bit12   = (imm >> 12) & 1
    bit11   = (imm >> 11) & 1
    bits10_5 = (imm >> 5) & 0x3F
    bits4_1  = (imm >> 1) & 0xF
    return (bit12 << 31) | (bits10_5 << 25) | (_u(rs2, 5) << 20) \
         | (_u(rs1, 5) << 15) | (_u(funct3, 3) << 12) \
         | (bits4_1 << 8) | (bit11 << 7) | _u(opcode, 7)

def u_type(imm, rd, opcode):
    # imm is the 20-bit upper immediate; lower 12 bits hardwired 0
    return (_u(imm, 20) << 12) | (_u(rd, 5) << 7) | _u(opcode, 7)

def j_type(imm, rd, opcode):
    assert imm % 2 == 0, "J-type imm must be 2-byte aligned"
    imm = _u(imm, 21)
    bit20    = (imm >> 20) & 1
    bits10_1 = (imm >> 1) & 0x3FF
    bit11    = (imm >> 11) & 1
    bits19_12 = (imm >> 12) & 0xFF
    return (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) \
         | (bits19_12 << 12) | (_u(rd, 5) << 7) | _u(opcode, 7)


# === Mnemonics ===

OPC_R     = 0b0110011
OPC_IARITH = 0b0010011
OPC_LOAD  = 0b0000011
OPC_STORE = 0b0100011
OPC_BR    = 0b1100011
OPC_JAL   = 0b1101111
OPC_JALR  = 0b1100111
OPC_LUI   = 0b0110111
OPC_AUIPC = 0b0010111

# R-type RV32I
def ADD(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0b000, rd, OPC_R)
def SUB(rd, rs1, rs2):  return r_type(0x20, rs2, rs1, 0b000, rd, OPC_R)
def SLL(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0b001, rd, OPC_R)
def SLT(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0b010, rd, OPC_R)
def SLTU(rd, rs1, rs2): return r_type(0x00, rs2, rs1, 0b011, rd, OPC_R)
def XOR(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0b100, rd, OPC_R)
def SRL(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0b101, rd, OPC_R)
def SRA(rd, rs1, rs2):  return r_type(0x20, rs2, rs1, 0b101, rd, OPC_R)
def OR(rd, rs1, rs2):   return r_type(0x00, rs2, rs1, 0b110, rd, OPC_R)
def AND(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0b111, rd, OPC_R)

# M-extension
def MUL(rd, rs1, rs2):    return r_type(0x01, rs2, rs1, 0b000, rd, OPC_R)
def MULH(rd, rs1, rs2):   return r_type(0x01, rs2, rs1, 0b001, rd, OPC_R)
def MULHSU(rd, rs1, rs2): return r_type(0x01, rs2, rs1, 0b010, rd, OPC_R)
def MULHU(rd, rs1, rs2):  return r_type(0x01, rs2, rs1, 0b011, rd, OPC_R)
def DIV(rd, rs1, rs2):    return r_type(0x01, rs2, rs1, 0b100, rd, OPC_R)
def DIVU(rd, rs1, rs2):   return r_type(0x01, rs2, rs1, 0b101, rd, OPC_R)
def REM(rd, rs1, rs2):    return r_type(0x01, rs2, rs1, 0b110, rd, OPC_R)
def REMU(rd, rs1, rs2):   return r_type(0x01, rs2, rs1, 0b111, rd, OPC_R)

# I-type arith
def ADDI(rd, rs1, imm):   return i_type(imm, rs1, 0b000, rd, OPC_IARITH)
def SLTI(rd, rs1, imm):   return i_type(imm, rs1, 0b010, rd, OPC_IARITH)
def SLTIU(rd, rs1, imm):  return i_type(imm, rs1, 0b011, rd, OPC_IARITH)
def XORI(rd, rs1, imm):   return i_type(imm, rs1, 0b100, rd, OPC_IARITH)
def ORI(rd, rs1, imm):    return i_type(imm, rs1, 0b110, rd, OPC_IARITH)
def ANDI(rd, rs1, imm):   return i_type(imm, rs1, 0b111, rd, OPC_IARITH)
def SLLI(rd, rs1, sh):    return i_type(sh & 0x1F, rs1, 0b001, rd, OPC_IARITH)
def SRLI(rd, rs1, sh):    return i_type(sh & 0x1F, rs1, 0b101, rd, OPC_IARITH)
def SRAI(rd, rs1, sh):    return i_type((sh & 0x1F) | (0x20 << 5), rs1, 0b101, rd, OPC_IARITH)

# Loads
def LB(rd, rs1, imm):     return i_type(imm, rs1, 0b000, rd, OPC_LOAD)
def LH(rd, rs1, imm):     return i_type(imm, rs1, 0b001, rd, OPC_LOAD)
def LW(rd, rs1, imm):     return i_type(imm, rs1, 0b010, rd, OPC_LOAD)
def LBU(rd, rs1, imm):    return i_type(imm, rs1, 0b100, rd, OPC_LOAD)
def LHU(rd, rs1, imm):    return i_type(imm, rs1, 0b101, rd, OPC_LOAD)

# Stores
def SB(rs2, rs1, imm):    return s_type(imm, rs2, rs1, 0b000, OPC_STORE)
def SH(rs2, rs1, imm):    return s_type(imm, rs2, rs1, 0b001, OPC_STORE)
def SW(rs2, rs1, imm):    return s_type(imm, rs2, rs1, 0b010, OPC_STORE)

# Branches
def BEQ(rs1, rs2, imm):   return b_type(imm, rs2, rs1, 0b000, OPC_BR)
def BNE(rs1, rs2, imm):   return b_type(imm, rs2, rs1, 0b001, OPC_BR)
def BLT(rs1, rs2, imm):   return b_type(imm, rs2, rs1, 0b100, OPC_BR)
def BGE(rs1, rs2, imm):   return b_type(imm, rs2, rs1, 0b101, OPC_BR)
def BLTU(rs1, rs2, imm):  return b_type(imm, rs2, rs1, 0b110, OPC_BR)
def BGEU(rs1, rs2, imm):  return b_type(imm, rs2, rs1, 0b111, OPC_BR)

# Jumps
def JAL(rd, imm):         return j_type(imm, rd, OPC_JAL)
def JALR(rd, rs1, imm):   return i_type(imm, rs1, 0b000, rd, OPC_JALR)

# Upper imm
def LUI(rd, imm20):       return u_type(imm20, rd, OPC_LUI)
def AUIPC(rd, imm20):     return u_type(imm20, rd, OPC_AUIPC)

# Pseudo
def NOP():                return ADDI(0, 0, 0)
