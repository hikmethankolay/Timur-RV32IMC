"""Builds test_rom.hex for the Timur RV32IM testbench.

Run: python tools/test_program.py
Writes test_rom.hex (one 8-hex-digit instruction per line, lower-case
unimportant) and prints expected register/memory state.
"""

import os
from asm import (ADDI, ADD, SUB, AND, OR, XOR, SLLI, SRAI, SLT, SLTU,
                 SW, LW, MUL, DIV, REM, DIVU,
                 BEQ, JAL, JALR, LUI, AUIPC, NOP)

# Reserved registers:
#   x29 = RAM base (0x20000000)
#   x31 = sentinel (every "should not execute" instruction targets x31)

prog = []  # list of (pc, instr, comment)

def emit(instr, comment=""):
    pc = 4 * len(prog)
    prog.append((pc, instr, comment))

def at(pc):
    """Sanity check: assert next emit will land at this PC."""
    assert 4 * len(prog) == pc, f"layout drift: next PC = {4*len(prog):#x}, expected {pc:#x}"

# --- A: Setup constants --------------------------------------------
emit(ADDI(1, 0, 5),         "x1 = 5")
emit(ADDI(2, 0, -3),        "x2 = -3 = 0xFFFFFFFD")
emit(LUI(29, 0x20000),      "x29 = 0x20000000  (RAM base)")

# --- B: R-type + forwarding ----------------------------------------
emit(ADD(3, 1, 2),          "x3 = x1 + x2 = 2  (forwarding)")
emit(SUB(4, 1, 2),          "x4 = x1 - x2 = 8")
emit(AND(5, 3, 4),          "x5 = x3 & x4 = 0  (EX/MEM fwd x4, MEM/WB fwd x3)")
emit(OR (6, 1, 2),          "x6 = x1 | x2 = 0xFFFFFFFD")
emit(XOR(7, 1, 2),          "x7 = x1 ^ x2 = 0xFFFFFFF8")

# --- C: Shifts + SLT -----------------------------------------------
emit(SLLI(8, 1, 4),         "x8 = 5 << 4 = 0x50")
emit(SRAI(9, 2, 1),         "x9 = -3 >>> 1 = 0xFFFFFFFE (-2)")
emit(SLT (10, 2, 1),        "x10 = (-3 < 5) signed = 1")
emit(SLTU(11, 2, 1),        "x11 = (-3 < 5) unsigned = 0")

# --- D: Store + load + load-use ------------------------------------
emit(SW(1, 29, 0),          "MEM[0x20000000] = 5")
emit(LW(12, 29, 0),         "x12 = MEM[0x20000000] = 5")
emit(ADDI(13, 12, 7),       "x13 = x12 + 7 = 12  (load-use stall + MEM/WB fwd)")

# --- E: Multiply (no stall) ----------------------------------------
emit(MUL(14, 1, 1),         "x14 = 5 * 5 = 25 = 0x19")

# --- F: Divide (32-cycle stall) + corner case ----------------------
emit(DIV (15, 4, 1),        "x15 = 8 / 5 = 1")
emit(REM (16, 4, 1),        "x16 = 8 % 5 = 3")
emit(DIVU(17, 1, 0),        "x17 = 5 / 0 = 0xFFFFFFFF (div-by-zero)")

# --- G: Branch not taken -------------------------------------------
emit(BEQ(1, 2, 8),          "BEQ x1,x2,+8: 5 != -3 -> NOT taken")
emit(ADDI(18, 0, 99),       "x18 = 99  (executes; BEQ fell through)")

# --- H: Branch taken — verify 2 sentinels skipped ------------------
beq_pc = 4 * len(prog)
emit(BEQ(1, 1, 12),         "BEQ x1,x1,+12 -> taken (PC -> beq_pc + 12)")
emit(LUI(31, 0xDEADC),      "SENTINEL — must not execute")
emit(LUI(31, 0xDEADC),      "SENTINEL — must not execute")
at(beq_pc + 12)
emit(ADDI(19, 0, 7),        "x19 = 7  (branch target)")

# --- I: JAL forward — verify it actually jumps ---------------------
jal_pc = 4 * len(prog)
emit(JAL(20, 12),           "JAL x20, +12 -> x20 = PC+4, jump over sentinels")
emit(LUI(31, 0xDEADC),      "SENTINEL — must not execute")
emit(LUI(31, 0xDEADC),      "SENTINEL — must not execute")
at(jal_pc + 12)
emit(ADDI(21, 0, 11),       "x21 = 11  (JAL target)")

# --- J: JALR — call+return pattern ---------------------------------
auipc_pc = 4 * len(prog)
# We will call into the "function" placed AFTER the halt below.
# Layout (computed below):
#   auipc_pc + 0   AUIPC x22, 0
#   auipc_pc + 4   ADDI  x22, x22, FUNC_OFFSET
#   auipc_pc + 8   JALR  x23, 0(x22)        -> jumps to function
#   auipc_pc + 12  ADDI  x26, x0, 22        <- return point
#   auipc_pc + 16  JAL   x0, 0              <- HALT (infinite loop)
#   auipc_pc + 20  (sentinel — never executed because halt loops)
#   auipc_pc + 24  ADDI  x27, x0, 13        <- function entry
#   auipc_pc + 28  JALR  x0, 0(x23)         <- return

FUNC_OFFSET = 24            # function entry is auipc_pc + 24

emit(AUIPC(22, 0),          "x22 = auipc_pc")
emit(ADDI(22, 22, FUNC_OFFSET), "x22 += 24 -> function entry")
jalr_call_pc = 4 * len(prog)
emit(JALR(23, 22, 0),       "JALR x23, 0(x22): x23 = PC+4 (return), jump to function")
ret_target_pc = 4 * len(prog)
emit(ADDI(26, 0, 22),       "x26 = 22  (return point — runs after function returns)")
halt_pc = 4 * len(prog)
emit(JAL(0, 0),             "HALT: JAL x0, 0  (infinite loop)")
emit(LUI(31, 0xDEADB),      "SENTINEL — never executed (halt loops)")
func_pc = 4 * len(prog)
assert func_pc == auipc_pc + FUNC_OFFSET, f"function alignment: {func_pc:#x} vs {auipc_pc + FUNC_OFFSET:#x}"
emit(ADDI(27, 0, 13),       "x27 = 13  (function body)")
emit(JALR(0, 23, 0),        "RET: JALR x0, 0(x23) -> jumps to ret_target_pc")

# --- Emit hex file -------------------------------------------------
out_path = os.path.join(os.path.dirname(__file__), "..", "test_rom.hex")
out_path = os.path.abspath(out_path)

with open(out_path, "w") as f:
    for pc, instr, _ in prog:
        f.write(f"{instr & 0xFFFFFFFF:08X}\n")

print(f"Wrote {out_path}  ({len(prog)} instructions)\n")
print("PC    Encoding   Comment")
print("-" * 70)
for pc, instr, comment in prog:
    print(f"{pc:04X}  {instr & 0xFFFFFFFF:08X}   {comment}")

print()
print("Expected final state:")
print(f"  x1  = 0x00000005 (5)")
print(f"  x2  = 0xFFFFFFFD (-3)")
print(f"  x3  = 0x00000002 (2)")
print(f"  x4  = 0x00000008 (8)")
print(f"  x5  = 0x00000000 (0)")
print(f"  x6  = 0xFFFFFFFD")
print(f"  x7  = 0xFFFFFFF8")
print(f"  x8  = 0x00000050 (80)")
print(f"  x9  = 0xFFFFFFFE (-2)")
print(f"  x10 = 0x00000001")
print(f"  x11 = 0x00000000")
print(f"  x12 = 0x00000005 (loaded from RAM)")
print(f"  x13 = 0x0000000C (12)")
print(f"  x14 = 0x00000019 (25)")
print(f"  x15 = 0x00000001 (8/5)")
print(f"  x16 = 0x00000003 (8%5)")
print(f"  x17 = 0xFFFFFFFF (div-by-zero)")
print(f"  x18 = 0x00000063 (99)")
print(f"  x19 = 0x00000007")
print(f"  x20 = 0x{jal_pc + 4:08X} (JAL link)")
print(f"  x21 = 0x0000000B (11)")
print(f"  x22 = 0x{auipc_pc + FUNC_OFFSET:08X} (function pointer)")
print(f"  x23 = 0x{ret_target_pc:08X} (JALR return link)")
print(f"  x26 = 0x00000016 (22)")
print(f"  x27 = 0x0000000D (13)")
print(f"  x31 = 0x00000000 (sentinels never executed)")
print(f"  MEM[0x20000000] = 0x00000005")
