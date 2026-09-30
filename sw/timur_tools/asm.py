"""Two-pass assembler for the directed test programs in sw/programs/.

A deliberately small dialect of RISC-V assembly, enough for the RV32IM and
Zicsr programs of the system tests (programs that need 16-bit encodings are
assembled by GNU as instead):

  label:  mnemonic operands        # comment
  registers        x0 .. x31 only (no ABI names)
  values           integer literals, labels, and sums and differences of them
  memory operands  offset(xN)
  CSRs             by name (mstatus, mepc, ...) or number
  directives       .org ADDRESS, .word VALUE

Every instruction is 4 bytes; branch and jump targets are absolute labels.
tests/host/test_asm.py checks the encodings against GNU as.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import NamedTuple

from . import isa, memmap
from .errors import TimurError

INSTRUCTION_BYTES = 4
REGISTER_COUNT = 32

# mnemonic -> (funct7, funct3)
R_OPS = {
    "add": (isa.F7_BASE, 0), "sub": (isa.F7_ALT, 0), "sll": (isa.F7_BASE, 1),
    "slt": (isa.F7_BASE, 2), "sltu": (isa.F7_BASE, 3), "xor": (isa.F7_BASE, 4),
    "srl": (isa.F7_BASE, 5), "sra": (isa.F7_ALT, 5), "or": (isa.F7_BASE, 6),
    "and": (isa.F7_BASE, 7), "mul": (isa.F7_MULDIV, 0), "mulh": (isa.F7_MULDIV, 1),
    "mulhsu": (isa.F7_MULDIV, 2), "mulhu": (isa.F7_MULDIV, 3), "div": (isa.F7_MULDIV, 4),
    "divu": (isa.F7_MULDIV, 5), "rem": (isa.F7_MULDIV, 6), "remu": (isa.F7_MULDIV, 7),
}  # fmt: skip
SHIFT_I = {"slli": (isa.F7_BASE, 1), "srli": (isa.F7_BASE, 5), "srai": (isa.F7_ALT, 5)}
# mnemonic -> funct3
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}
CSR_OPS = {"csrrw": 1, "csrrs": 2, "csrrc": 3, "csrrwi": 5, "csrrsi": 6, "csrrci": 7}
UPPER = {"lui": isa.OP_LUI, "auipc": isa.OP_AUIPC}
# mnemonic -> the whole instruction
FIXED = {
    "nop": isa.INSTR_NOP, "ecall": isa.INSTR_ECALL, "ebreak": isa.INSTR_EBREAK,
    "mret": isa.INSTR_MRET, "wfi": isa.INSTR_WFI, "fence": isa.INSTR_FENCE,
}  # fmt: skip

IMM12_MIN, IMM12_MAX = -2048, 2047
BRANCH_MIN, BRANCH_MAX = -4096, 4094
JUMP_MIN, JUMP_MAX = -(1 << 20), (1 << 20) - 2
UPPER_MAX = 0xFFFFF
SHAMT_MAX = 31
UIMM5_MAX = 31

Labels = Mapping[str, int]


class AsmError(TimurError):
    """A source line cannot be assembled."""


class Assembly(NamedTuple):
    """Result of assemble()."""

    image: dict[int, int]  # byte address -> 32-bit word
    listing: list[tuple[int, int, str]]  # (address, word, normalised source text)
    labels: dict[str, int]


def _reg(token: str) -> int:
    token = token.strip()
    number = token[1:]
    if not (token.startswith("x") and number.isdigit() and int(number) < REGISTER_COUNT):
        raise AsmError("bad register %r" % token)
    return int(number)


def _value(token: str, labels: Labels) -> int:
    """Integer literal, label, or label/literal +/- label/literal."""
    token = token.replace(" ", "")
    for index in range(len(token) - 1, 0, -1):
        if token[index] in "+-" and token[index - 1] not in "+-":
            left, right = token[:index], token[index + 1 :]
            if left and right:
                left_value, right_value = _value(left, labels), _value(right, labels)
                return left_value + right_value if token[index] == "+" else left_value - right_value
    if token in labels:
        return labels[token]
    try:
        return int(token, 0)
    except ValueError:
        raise AsmError("bad value %r" % token) from None


def _mem(token: str, labels: Labels) -> tuple[int, int]:
    """'imm(xN)' -> (imm, N)."""
    token = token.strip()
    if not token.endswith(")") or "(" not in token:
        raise AsmError("bad memory operand %r" % token)
    imm, reg = token[:-1].split("(", 1)
    return (_value(imm, labels) if imm else 0), _reg(reg)


def _check(value: int, low: int, high: int, what: str) -> int:
    if not low <= value <= high:
        raise AsmError("%s %d out of range" % (what, value))
    return value


def _operands(mnemonic: str, operands: list[str], count: int) -> list[str]:
    if len(operands) != count:
        raise AsmError(
            "%s takes %d operand%s, not %d"
            % (mnemonic, count, "" if count == 1 else "s", len(operands))
        )
    return operands


def encode(text: str, pc: int, labels: Labels) -> int:
    """The 32-bit word for one source statement at address pc."""
    mnemonic, _, rest = text.partition(" ")
    mnemonic = mnemonic.lower()
    ops = [operand.strip() for operand in rest.split(",")] if rest.strip() else []
    if mnemonic == ".word":
        (operand,) = _operands(mnemonic, ops, 1)
        return _value(operand, labels) & isa.MASK
    if mnemonic in FIXED:
        return FIXED[mnemonic]
    if mnemonic in R_OPS:
        rd, rs1, rs2 = _operands(mnemonic, ops, 3)
        funct7, funct3 = R_OPS[mnemonic]
        return isa.enc_r(funct7, _reg(rs2), _reg(rs1), funct3, _reg(rd), isa.OP_REG)
    if mnemonic in I_OPS:
        rd, rs1, imm = _operands(mnemonic, ops, 3)
        value = _check(_value(imm, labels), IMM12_MIN, IMM12_MAX, "immediate")
        return isa.enc_i(value, _reg(rs1), I_OPS[mnemonic], _reg(rd), isa.OP_IMM)
    if mnemonic in SHIFT_I:
        rd, rs1, amount = _operands(mnemonic, ops, 3)
        funct7, funct3 = SHIFT_I[mnemonic]
        shamt = _check(_value(amount, labels), 0, SHAMT_MAX, "shift amount")
        return isa.enc_i((funct7 << 5) | shamt, _reg(rs1), funct3, _reg(rd), isa.OP_IMM)
    if mnemonic in LOADS:
        rd, address = _operands(mnemonic, ops, 2)
        offset, base = _mem(address, labels)
        _check(offset, IMM12_MIN, IMM12_MAX, "offset")
        return isa.enc_i(offset, base, LOADS[mnemonic], _reg(rd), isa.OP_LOAD)
    if mnemonic in STORES:
        rs2, address = _operands(mnemonic, ops, 2)
        offset, base = _mem(address, labels)
        _check(offset, IMM12_MIN, IMM12_MAX, "offset")
        return isa.enc_s(offset, _reg(rs2), base, STORES[mnemonic])
    if mnemonic in BRANCHES:
        rs1, rs2, target = _operands(mnemonic, ops, 3)
        offset = _check(_value(target, labels) - pc, BRANCH_MIN, BRANCH_MAX, "branch offset")
        return isa.enc_b(offset, _reg(rs2), _reg(rs1), BRANCHES[mnemonic])
    if mnemonic == "jal":
        rd, target = _operands(mnemonic, ops, 2)
        offset = _check(_value(target, labels) - pc, JUMP_MIN, JUMP_MAX, "jump offset")
        return isa.enc_j(offset, _reg(rd))
    if mnemonic == "jalr":
        rd, address = _operands(mnemonic, ops, 2)
        offset, base = _mem(address, labels)
        _check(offset, IMM12_MIN, IMM12_MAX, "offset")
        return isa.enc_i(offset, base, 0, _reg(rd), isa.OP_JALR)
    if mnemonic in UPPER:
        rd, imm = _operands(mnemonic, ops, 2)
        value = _check(_value(imm, labels), 0, UPPER_MAX, "upper immediate")
        return isa.enc_u(value, _reg(rd), UPPER[mnemonic])
    if mnemonic in CSR_OPS:
        rd, csr_name, source = _operands(mnemonic, ops, 3)
        csr = memmap.CSRS[csr_name] if csr_name in memmap.CSRS else _value(csr_name, labels)
        funct3 = CSR_OPS[mnemonic]
        if funct3 & isa.F3_CSR_IMMEDIATE:
            src = _check(_value(source, labels), 0, UIMM5_MAX, "uimm")
        else:
            src = _reg(source)
        return isa.enc_i(csr, src, funct3, _reg(rd), isa.OP_SYSTEM)
    raise AsmError("unknown mnemonic %r" % mnemonic)


def assemble(source: str) -> Assembly:
    """Assemble a program; raises AsmError naming the address and the line."""
    statements: list[tuple[int, str]] = []
    labels: dict[str, int] = {}
    address = 0
    for raw in source.splitlines():
        text = raw.split("#", 1)[0].strip()
        while ":" in text:
            label, text = text.split(":", 1)
            labels[label.strip()] = address
            text = text.strip()
        if not text:
            continue
        if text.startswith(".org"):
            fields = text.split()
            if len(fields) != 2:
                raise AsmError("0x%04X %s: .org takes one address" % (address, text))
            address = _value(fields[1], labels)
            continue
        statements.append((address, text))
        address += INSTRUCTION_BYTES

    image: dict[int, int] = {}
    listing: list[tuple[int, int, str]] = []
    for address, text in statements:
        try:
            word = encode(text, address, labels)
        except AsmError as error:
            raise AsmError("0x%04X %s: %s" % (address, text, error)) from error
        if address in image:
            raise AsmError("0x%04X: overlapping code" % address)
        image[address] = word
        listing.append((address, word, " ".join(text.split())))
    return Assembly(image, listing, labels)
