"""Random, dependency-dense test programs for the system testbench.

Both generators are driven by one seeded random.Random, so a seed names a
program: the seed is recorded in the vector file and a failing run can be
reproduced. The order of the random draws is part of that contract: changing
it changes every generated program.

Control flow is forward only, so every program terminates at its halt loop.
"""

from __future__ import annotations

import itertools
import random

INDENT = "        "

# Registers of random_program
_RAM_BASE_REG = 31
_APB_BASE_REG = 30
_SCRATCH_REG = 29  # JALR bases and unmapped addresses
_DATA_BASE_REG = 28  # a RAM address that moves during the program
_DATA_POOL = list(range(1, 21))  # x1..x20 carry the random data flow

# APB register offsets the random loads and stores use: UART CTRL, GPIO OUT/IN/DIR and an
# unmapped GPIO offset, DMAC SRC/DST/LEN, an unmapped page, the UART's unmapped 0x14
_APB_LOAD_OFFSETS = [0x008, 0x100, 0x104, 0x108, 0x10C, 0x200, 0x204, 0x208, 0x300, 0x014]
_APB_STORE_OFFSETS = [0x008, 0x100, 0x108, 0x10C, 0x200, 0x204, 0x208, 0x300]
_UNMAPPED_UPPER = [0x10000, 0x30000, 0x60000]  # LUI values of addresses no slave decodes

_BRANCHES = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]


def _load_constant(register: int, value: int) -> list[str]:
    """LUI + ADDI that load a 32-bit constant."""
    upper, lower = ((value + 0x800) >> 12) & 0xFFFFF, value & 0xFFF
    if lower & 0x800:
        lower -= 0x1000
    return [
        INDENT + "lui   x%d, 0x%05X" % (register, upper),
        INDENT + "addi  x%d, x%d, %d" % (register, register, lower),
    ]


def random_program(seed: int, length: int) -> str:
    """A program of 32-bit instructions for the mini assembler (Phase 7 checklist).

    x31 = RAM base, x30 = APB base, x29 = JALR base, x28 = computed address base,
    x1..x20 carry the random data flow. Loads and stores mix RAM, APB registers
    (GPIO OUT/IN/DIR, UART CTRL, DMAC SRC/DST/LEN, unmapped APB offsets), the ROM
    data port and unmapped addresses; DIV/REM include divide-by-zero and
    signed-overflow operands.
    """
    rnd = random.Random(seed)
    out = [
        "# Phase 7 random program, seed %d" % seed,
        INDENT + "lui   x31, 0x20000",
        INDENT + "lui   x30, 0x40000",
        INDENT + "addi  x28, x31, 0",
    ]
    pool = _DATA_POOL
    for register in pool:
        out += _load_constant(register, rnd.getrandbits(32))
    recent: list[int] = []  # recently written registers: preferred sources
    label_numbers = itertools.count(1)

    def emit(text: str) -> None:
        out.append(INDENT + text)

    def src() -> int:
        if recent and rnd.random() < 0.7:
            return rnd.choice(recent[-3:])
        return rnd.choice([*pool, 0])

    def dst() -> int:
        return rnd.choice(pool)

    def wrote(register: int) -> None:
        recent.append(register)
        del recent[:-6]

    def three_register(op: str, rd: int) -> None:
        emit("%-5s x%d, x%d, x%d" % (op, rd, src(), src()))
        wrote(rd)

    def simple() -> None:
        kind = rnd.random()
        if kind < 0.20:
            op = rnd.choice(["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"])
            three_register(op, dst())
        elif kind < 0.36:
            op = rnd.choice(
                ["addi", "slti", "sltiu", "xori", "ori", "andi", "slli", "srli", "srai"]
            )
            is_shift = op in ("slli", "srli", "srai")
            imm = rnd.randint(0, 31) if is_shift else rnd.randint(-2048, 2047)
            rd = dst()
            emit("%-5s x%d, x%d, %d" % (op, rd, src(), imm))
            wrote(rd)
        elif kind < 0.40:
            op = rnd.choice(["lui", "auipc"])
            rd = dst()
            emit("%-5s x%d, 0x%05X" % (op, rd, rnd.getrandbits(20)))
            wrote(rd)
        elif kind < 0.48:
            op = rnd.choice(["mul", "mulh", "mulhsu", "mulhu"])
            three_register(op, dst())
        elif kind < 0.56:
            op = rnd.choice(["div", "divu", "rem", "remu"])
            case = rnd.random()
            if case < 0.15:  # divide by zero
                rd = dst()
                emit("%-5s x%d, x%d, x0" % (op, rd, src()))
                wrote(rd)
            elif case < 0.25:  # signed overflow operands
                dividend, divisor = rnd.sample(pool, 2)
                emit("lui   x%d, 0x80000" % dividend)
                emit("addi  x%d, x0, -1" % divisor)
                rd = dst()
                emit("%-5s x%d, x%d, x%d" % (op, rd, dividend, divisor))
                wrote(rd)
            else:
                three_register(op, dst())
        elif kind < 0.67:  # RAM load
            op = rnd.choice(["lw", "lh", "lhu", "lb", "lbu"])
            base = rnd.choice([_RAM_BASE_REG, _DATA_BASE_REG])
            size = {"lw": 4, "lh": 2, "lhu": 2}.get(op, 1)
            rd = dst()
            emit("%-5s x%d, %d(x%d)" % (op, rd, rnd.randrange(0, 256, size), base))
            wrote(rd)
        elif kind < 0.77:  # RAM store
            op = rnd.choice(["sw", "sh", "sb"])
            base = rnd.choice([_RAM_BASE_REG, _DATA_BASE_REG])
            size = {"sw": 4, "sh": 2}.get(op, 1)
            emit("%-5s x%d, %d(x%d)" % (op, src(), rnd.randrange(0, 256, size), base))
        elif kind < 0.83:  # APB load
            op = rnd.choice(["lw", "lw", "lh", "lbu", "lb"])
            offset = rnd.choice(_APB_LOAD_OFFSETS)
            if op in ("lb", "lbu"):
                offset += rnd.choice([0, 1, 2, 3])
            elif op == "lh":
                offset += rnd.choice([0, 2])
            rd = dst()
            emit("%-5s x%d, %d(x%d)" % (op, rd, offset, _APB_BASE_REG))
            wrote(rd)
        elif kind < 0.87:  # APB store: whole-register writes
            op = rnd.choice(["sw", "sw", "sh", "sb"])
            offset = rnd.choice(_APB_STORE_OFFSETS)
            if op == "sb":
                offset += rnd.choice([0, 1, 2, 3])
            elif op == "sh":
                offset += rnd.choice([0, 2])
            emit("%-5s x%d, %d(x%d)" % (op, src(), offset, _APB_BASE_REG))
        elif kind < 0.89:  # ROM data port: read back program words
            op = rnd.choice(["lw", "lhu", "lb"])
            size = {"lw": 4, "lhu": 2}.get(op, 1)
            rd = dst()
            emit("%-5s x%d, %d(x0)" % (op, rd, rnd.randrange(0, 512, size)))
            wrote(rd)
        elif kind < 0.90:  # default slave and ROM writes: ignored, loads read 0
            if rnd.random() < 0.5:
                emit("lui   x%d, 0x%05X" % (_SCRATCH_REG, rnd.choice(_UNMAPPED_UPPER)))
                emit("sw    x%d, 0(x%d)" % (src(), _SCRATCH_REG))
                rd = dst()
                emit("lw    x%d, 0(x%d)" % (rd, _SCRATCH_REG))
                wrote(rd)
            else:
                emit("sw    x%d, %d(x0)" % (src(), rnd.randrange(0, 256, 4)))
        else:  # new data base in RAM, used by later loads and stores
            emit("addi  x%d, x%d, %d" % (_DATA_BASE_REG, _RAM_BASE_REG, rnd.randrange(0, 1024, 4)))

    def skipped_block(target: str) -> None:
        """Up to three instructions that the preceding jump may skip, then its target."""
        for _ in range(rnd.randint(0, 3)):
            simple()
        out.append(target + ":")

    for _ in range(length):
        kind = rnd.random()
        if kind < 0.10:
            target = "L%d" % next(label_numbers)
            op = rnd.choice(_BRANCHES)
            emit("%-5s x%d, x%d, %s" % (op, src(), src(), target))
            skipped_block(target)
        elif kind < 0.13:
            target = "L%d" % next(label_numbers)
            rd = rnd.choice([*pool, 0])
            emit("jal   x%d, %s" % (rd, target))
            if rd:
                wrote(rd)
            skipped_block(target)
        elif kind < 0.16:
            skip = rnd.randint(0, 3)
            rd = rnd.choice([*pool, 0])
            emit("auipc x%d, 0" % _SCRATCH_REG)
            emit("jalr  x%d, %d(x%d)" % (rd, 8 + 4 * skip, _SCRATCH_REG))
            if rd:
                wrote(rd)
            for _ in range(skip):
                simple()
        else:
            simple()
    out.append("halt:   jal   x0, halt")
    return "\n".join(out) + "\n"


# Registers of random_c_program
_C_RAM_BASE_REG = 9
_C_PRIME_REGS = [8, 10, 11, 12, 13, 14, 15]  # reachable by the 3-bit register fields
_C_ALL_REGS = [*_C_PRIME_REGS, 1, 16, 17, 18, 19, 20, 21, 22]
_C_LUI_VALUES = list(range(1, 32)) + list(range(0xFFFE0, 0x100000))  # nonzero 6-bit, sign-extended
_C_NONZERO_IMM6 = [value for value in range(-32, 32) if value]
_C_APB_OFFSETS = [0x100, 0x104, 0x108, 0x200, 0x204]


def random_c_program(seed: int, length: int) -> str:
    """A program of 16-bit instructions mixed with 32-bit ones, for GNU as (Phase 11).

    x9 = RAM base and x2 = sp (RAM + 0x800) stay fixed; x8 and x10-x15 carry the data
    flow of the 3-bit register fields, x1 and x16-x22 that of the full ones. Control
    flow is forward only (compressed branches and jumps, C.JAL, C.JR/C.JALR through
    x5), so every program terminates; 32-bit instructions land at both alignments.
    """
    rnd = random.Random(seed)
    prime, every = _C_PRIME_REGS, _C_ALL_REGS
    out = [
        "# Phase 11 random program of compressed and 32-bit instructions, seed %d" % seed,
        INDENT + ".option rvc",
        INDENT + "lui   x9, 0x20000",
        INDENT + "lui   x2, 0x20001",
        INDENT + "addi  x2, x2, -0x800",
        INDENT + "lui   x30, 0x40000",
    ]
    for register in every:
        out += _load_constant(register, rnd.getrandbits(32))
    label_numbers = itertools.count(1)

    def emit(text: str) -> None:
        out.append(INDENT + text)

    def one() -> None:
        kind = rnd.random()
        d, d2, a, a2 = rnd.choice(prime), rnd.choice(prime), rnd.choice(every), rnd.choice(every)
        if kind < 0.07:
            emit("c.addi  x%d, %d" % (a, rnd.choice(_C_NONZERO_IMM6)))
        elif kind < 0.12:
            emit("c.li    x%d, %d" % (a, rnd.randint(-32, 31)))
        elif kind < 0.15:
            emit("c.lui   x%d, 0x%x" % (a, rnd.choice(_C_LUI_VALUES)))
        elif kind < 0.19:
            emit("c.slli  x%d, %d" % (a, rnd.randint(1, 31)))
        elif kind < 0.23:
            emit("c.%s  x%d, %d" % (rnd.choice(["srli", "srai"]), d, rnd.randint(1, 31)))
        elif kind < 0.26:
            emit("c.andi  x%d, %d" % (d, rnd.randint(-32, 31)))
        elif kind < 0.31:
            emit("c.mv    x%d, x%d" % (a, a2))
        elif kind < 0.36:
            emit("c.add   x%d, x%d" % (a, a2))
        elif kind < 0.44:
            emit("c.%s   x%d, x%d" % (rnd.choice(["sub", "xor", "or", "and"]), d, d2))
        elif kind < 0.50:
            emit("c.lw    x%d, %d(x%d)" % (d, rnd.randrange(0, 128, 4), _C_RAM_BASE_REG))
        elif kind < 0.55:
            emit("c.sw    x%d, %d(x%d)" % (d, rnd.randrange(0, 128, 4), _C_RAM_BASE_REG))
        elif kind < 0.59:
            emit("c.lwsp  x%d, %d(x2)" % (a, rnd.randrange(0, 256, 4)))
        elif kind < 0.63:
            emit("c.swsp  x%d, %d(x2)" % (a, rnd.randrange(0, 256, 4)))
        elif kind < 0.67:
            op = rnd.choice(["lb", "lbu", "lh", "lhu"])
            offset = rnd.randrange(0, 128, 2 if op in ("lh", "lhu") else 1)
            emit("%-6s x%d, %d(x%d)" % (op, a, offset, _C_RAM_BASE_REG))
        elif kind < 0.70:
            op = rnd.choice(["sb", "sh"])
            offset = rnd.randrange(0, 128, 2 if op == "sh" else 1)
            emit("%-6s x%d, %d(x%d)" % (op, a, offset, _C_RAM_BASE_REG))
        elif kind < 0.76:
            op = rnd.choice(["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"])
            emit("%-6s x%d, x%d, x%d" % (op, a, a2, rnd.choice(every)))
        elif kind < 0.82:
            op = rnd.choice(["add", "sub", "xor", "or", "and", "sll", "srl", "sra", "slt", "sltu"])
            emit("%-6s x%d, x%d, x%d" % (op, a, a2, rnd.choice(every)))
        elif kind < 0.86:
            op = rnd.choice(["addi", "xori", "ori", "andi", "slti", "sltiu"])
            emit("%-6s x%d, x%d, %d" % (op, a, a2, rnd.randint(-2048, 2047)))
        elif kind < 0.88:
            emit("lw     x%d, %d(x30)" % (a, rnd.choice(_C_APB_OFFSETS)))
        else:
            emit("sw     x%d, %d(x%d)" % (a, rnd.randrange(128, 256, 4), _C_RAM_BASE_REG))

    def skipped_block(target: str) -> None:
        for _ in range(rnd.randint(0, 3)):
            one()
        out.append(target + ":")

    for _ in range(length):
        kind = rnd.random()
        if kind < 0.08:
            target = "C%d" % next(label_numbers)
            emit("c.%s  x%d, %s" % (rnd.choice(["beqz", "bnez"]), rnd.choice(prime), target))
            skipped_block(target)
        elif kind < 0.11:
            target = "C%d" % next(label_numbers)
            op = rnd.choice(_BRANCHES)
            emit("%-6s x%d, x%d, %s" % (op, rnd.choice(every), rnd.choice(every), target))
            skipped_block(target)
        elif kind < 0.13:
            target = "C%d" % next(label_numbers)
            emit("c.%s    %s" % (rnd.choice(["j", "jal"]), target))
            skipped_block(target)
        elif kind < 0.15:
            target = "C%d" % next(label_numbers)
            emit("la     x5, %s" % target)
            emit("c.%s   x5" % rnd.choice(["jr", "jalr"]))
            skipped_block(target)
        else:
            one()
    out.append("halt:   c.j    halt")
    return "\n".join(out) + "\n"
