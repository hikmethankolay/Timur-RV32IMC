"""Instruction-level reference model of the Timur SoC.

The model executes a ROM image on the Timur memory map in machine mode with
precise traps: illegal encodings, ECALL, EBREAK and misaligned loads and
stores trap to mtvec; MRET returns; WFI and FENCE are NOPs; 16-bit
instructions execute as their 32-bit expansion.

What the model cannot know
--------------------------
It counts instructions, not clock cycles. Values that depend on timing (the
cycle and instret counters, mip) *taint* the registers and RAM words derived
from them; tainted values are left out of the generated checks, and a tainted
value that would steer the program (a branch, an address, a CSR write) stops
the model with TimingDependentError.

Peripherals are modelled without delay: the UART sends a byte at once (it is
never busy) and the DMAC copies a block at once. A program whose output
depends on those delays prints something else on the RTL.

With fake_time the counters count executed instructions instead and taint
nothing, so that delay loops end; the model's output is then not a prediction
of the RTL's.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from . import memmap
from .errors import TimurError
from .isa import (
    F3_BYTE,
    F3_CSR_IMMEDIATE,
    F3_CSRRC,
    F3_CSRRS,
    F3_CSRRW,
    F3_DIV,
    F3_DIVU,
    F3_HALF,
    F3_LBU,
    F3_LHU,
    F3_MUL,
    F3_MULH,
    F3_MULHSU,
    F3_PRIV,
    F3_REM,
    F3_REMU,
    F3_SIZE_MASK,
    F3_WORD,
    F7_ALT,
    F7_BASE,
    F7_MULDIV,
    F12_EBREAK,
    F12_ECALL,
    F12_MRET,
    F12_WFI,
    INSTR_HALT,
    MASK,
    OP_AUIPC,
    OP_BRANCH,
    OP_IMM,
    OP_JAL,
    OP_JALR,
    OP_LOAD,
    OP_LUI,
    OP_MISC_MEM,
    OP_REG,
    OP_STORE,
    OP_SYSTEM,
    SIGN_BIT,
    imm_b,
    imm_i,
    imm_j,
    imm_s,
    s32,
)
from .rvc import decompress, is_compressed

DEFAULT_RUN_LIMIT = 200_000

# The address decoder looks at the upper 16 address bits; each memory is 64 KB.
_REGION_SHIFT = 16
_ROM_REGION = memmap.ROM_BASE >> _REGION_SHIFT
_RAM_REGION = memmap.RAM_BASE >> _REGION_SHIFT
_APB_REGION = memmap.APB_BASE >> _REGION_SHIFT
_WORD_INDEX_MASK = 0xFFFC  # word-aligned offset within a 64 KB memory

# APB: PADDR[15:8] selects the peripheral, PADDR[7:2] the register.
_PAGE_UART = (memmap.UART_BASE - memmap.APB_BASE) >> 8
_PAGE_GPIO = (memmap.GPIO_BASE - memmap.APB_BASE) >> 8
_PAGE_DMAC = (memmap.DMAC_BASE - memmap.APB_BASE) >> 8
_UART_DATA, _UART_STATUS, _UART_CTRL = (
    offset >> 2 for offset in (memmap.UART_DATA, memmap.UART_STATUS, memmap.UART_CTRL)
)
_GPIO_OUT, _GPIO_IN, _GPIO_DIR = (
    offset >> 2 for offset in (memmap.GPIO_OUT, memmap.GPIO_IN, memmap.GPIO_DIR)
)
_DMAC_SRC, _DMAC_DST, _DMAC_LEN, _DMAC_CTRL, _DMAC_STATUS = (
    offset >> 2
    for offset in (
        memmap.DMAC_SRC,
        memmap.DMAC_DST,
        memmap.DMAC_LEN,
        memmap.DMAC_CTRL,
        memmap.DMAC_STATUS,
    )
)

_BYTE_ENABLE_WORD = 0b1111

#: CSRs whose value depends on timing: reading one taints the destination.
CSR_TIMING = frozenset({memmap.CSR_MIP}) | memmap.CSR_COUNTERS

_LEGAL_PRIV = frozenset({F12_ECALL, F12_EBREAK, F12_MRET, F12_WFI})
_DIVIDE_OPS = frozenset({F3_DIV, F3_DIVU, F3_REM, F3_REMU})


class ModelError(TimurError):
    """The model cannot run the program to the end."""


class TimingDependentError(ModelError):
    """A value the model cannot know (a counter, mip) decides what happens next."""


class HaltNotReachedError(ModelError):
    """The program did not reach its halt loop within the instruction limit."""


@dataclass
class DmacState:
    """Registers of the DMA controller."""

    src: int = 0
    dst: int = 0
    length: int = 0  # words
    irq_enable: int = 0
    done: int = 0


def is_legal(ins: int) -> bool:
    """Mirror of main_control_unit's illegal-instruction rules."""
    opcode, funct3, funct7, rs2 = ins & 0x7F, (ins >> 12) & 7, ins >> 25, (ins >> 20) & 31
    if opcode == OP_REG:
        return funct7 in (F7_BASE, F7_MULDIV) or (funct7 == F7_ALT and funct3 in (0, 5))
    if opcode == OP_IMM:
        return not (
            (funct3 == 1 and funct7 != F7_BASE) or (funct3 == 5 and funct7 not in (F7_BASE, F7_ALT))
        )
    if opcode == OP_LOAD:
        return funct3 not in (3, 6, 7)
    if opcode == OP_STORE:
        return funct3 < 3
    if opcode == OP_BRANCH:
        return funct3 not in (2, 3)
    if opcode == OP_JALR:
        return funct3 == 0
    if opcode in (OP_JAL, OP_LUI, OP_AUIPC):
        return True
    if opcode == OP_MISC_MEM:
        return funct3 in (0, 1)
    if opcode == OP_SYSTEM:
        if funct3 == F3_PRIV:
            return ((funct7 << 5) | rs2) in _LEGAL_PRIV
        return funct3 != F3_CSR_IMMEDIATE
    return False


def divide(a: int, b: int, funct3: int) -> int:
    """Result of DIV, DIVU, REM or REMU (selected by funct3) as the M extension
    defines it, including division by zero and the signed overflow."""
    signed = funct3 in (F3_DIV, F3_REM)
    wants_quotient = funct3 in (F3_DIV, F3_DIVU)
    if b == 0:
        return MASK if wants_quotient else a
    if signed and a == SIGN_BIT and b == MASK:
        return SIGN_BIT if wants_quotient else 0
    if signed:
        quotient = abs(s32(a)) // abs(s32(b))
        if (s32(a) < 0) != (s32(b) < 0):
            quotient = -quotient
        return (quotient if wants_quotient else s32(a) - quotient * s32(b)) & MASK
    return a // b if wants_quotient else a % b


def source_registers(ins: int) -> set[int]:
    """Registers an instruction actually reads."""
    opcode, funct3 = ins & 0x7F, (ins >> 12) & 7
    rs1, rs2 = (ins >> 15) & 31, (ins >> 20) & 31
    if opcode in (OP_REG, OP_STORE, OP_BRANCH):
        return {rs1, rs2} - {0}
    if opcode in (OP_IMM, OP_LOAD, OP_JALR) or (
        opcode == OP_SYSTEM and funct3 in (F3_CSRRW, F3_CSRRS, F3_CSRRC)
    ):
        return {rs1} - {0}
    return set()


def alu(funct3: int, a: int, b: int, alt: bool) -> int:
    """The base-ISA operation funct3 on 32-bit operands; alt selects SUB and SRA."""
    if funct3 == 0:
        return (a - b if alt else a + b) & MASK
    if funct3 == 1:
        return (a << (b & 31)) & MASK
    if funct3 == 2:
        return int(s32(a) < s32(b))
    if funct3 == 3:
        return int(a < b)
    if funct3 == 4:
        return a ^ b
    if funct3 == 5:
        return (s32(a) >> (b & 31)) & MASK if alt else a >> (b & 31)
    if funct3 == 6:
        return a | b
    return a & b


def multiply(a: int, b: int, funct3: int) -> int:
    """Result of MUL, MULH, MULHSU or MULHU (selected by funct3)."""
    if funct3 == F3_MUL:
        return (a * b) & MASK
    if funct3 == F3_MULH:
        return (s32(a) * s32(b)) >> 32
    if funct3 == F3_MULHSU:
        return (s32(a) * b) >> 32
    return (a * b) >> 32


def _misaligned(funct3: int, address: int) -> bool:
    size = funct3 & F3_SIZE_MASK
    return bool((size == F3_WORD and address & 3) or (size == F3_HALF and address & 1))


class TimurModel:
    """Instruction-level model of the Timur SoC (machine mode, precise traps).

    image        ROM contents as {byte address: 32-bit word}
    uart_rx      the byte stream a terminal sends: each byte arrives once the
                 receiver is enabled and the previous byte was read
    interrupts   take the external interrupt (DMAC done with irq_enable, UART
                 rx_valid with rx_irq_enable) before an instruction whenever
                 mstatus.MIE and mie.MEIE are set
    trace        record the PC of every executed instruction in self.trace
    fake_time    the counters count executed instructions (see the module text)

    After a run: x (registers), pc, ram, uart_tx, gpio_out, traps
    (cause, pc, mtval), divs (DIV/REM instructions executed), retired.
    """

    def __init__(
        self,
        image: Mapping[int, int],
        uart_rx: bytes = b"",
        interrupts: bool = False,
        trace: bool = True,
        fake_time: bool = False,
    ) -> None:
        self.rom = dict(image)
        self.ram = bytearray(memmap.RAM_SIZE)
        self.ram_written: set[int] = set()  # word offsets written by the program
        self.ram_taint: set[int] = set()  # word offsets holding timing-dependent values
        self.x = [0] * 32
        self.taint: set[int] = set()  # registers holding timing-dependent values
        self.pc = 0
        self.gpio_out = self.gpio_dir = self.uart_ctrl = 0
        self.uart_tx: list[int] = []
        self.uart_rx = list(uart_rx)
        self.rx_valid = self.rx_data = 0
        self.interrupts = interrupts
        self.keep_trace = trace
        self.fake_time = fake_time
        self.read_time = False  # with fake_time: a counter was read
        self.timing_csrs: frozenset[int] = frozenset() if fake_time else CSR_TIMING
        self.retired = 0
        self.dmac = DmacState()
        self.trace: list[int] = []
        self.traps: list[tuple[int, int, int]] = []
        self.divs = 0
        self.mie = self.mpie = self.meie = 0
        self.mtvec = self.mscratch = self.mepc = self.mcause = self.mtval = 0

    # ---- CSRs --------------------------------------------------------------
    def csr_read(self, address: int) -> int:
        """Value of an implemented CSR (the counters read 0 unless fake_time)."""
        if self.fake_time and address in memmap.CSR_COUNTERS:
            self.read_time = True
            shift = 32 if address in memmap.CSR_COUNTERS_HIGH else 0
            return (self.retired >> shift) & MASK
        if address == memmap.CSR_MIP and self.interrupts:  # MEIP: the OR of the interrupt lines
            return memmap.MIP_MEIP if self.irq_line() else 0
        if address == memmap.CSR_MSTATUS:
            return memmap.MSTATUS_MPP_MACHINE | (self.mpie << 7) | (self.mie << 3)
        if address == memmap.CSR_MISA:
            return memmap.MISA_VALUE
        if address == memmap.CSR_MIE:
            return self.meie << 11
        if address == memmap.CSR_MTVEC:
            return self.mtvec
        if address == memmap.CSR_MSCRATCH:
            return self.mscratch
        if address == memmap.CSR_MEPC:
            return self.mepc
        if address == memmap.CSR_MCAUSE:
            return self.mcause
        if address == memmap.CSR_MTVAL:
            return self.mtval
        return 0

    def csr_write(self, address: int, value: int) -> None:
        """Write a CSR; misa, mip and the counters ignore writes."""
        if address == memmap.CSR_MSTATUS:
            self.mie, self.mpie = (value >> 3) & 1, (value >> 7) & 1
        elif address == memmap.CSR_MIE:
            self.meie = (value >> 11) & 1
        elif address == memmap.CSR_MTVEC:
            self.mtvec = value & ~3 & MASK
        elif address == memmap.CSR_MSCRATCH:
            self.mscratch = value
        elif address == memmap.CSR_MEPC:
            self.mepc = value & ~1 & MASK
        elif address == memmap.CSR_MCAUSE:
            self.mcause = value
        elif address == memmap.CSR_MTVAL:
            self.mtval = value

    def trap(self, cause: int, tval: int) -> None:
        """Enter the trap handler: save the PC and the cause, clear MIE."""
        self.traps.append((cause, self.pc, tval))
        self.mepc, self.mcause, self.mtval = self.pc & ~1 & MASK, cause, tval & MASK
        self.mpie, self.mie = self.mie, 0
        self.pc = self.mtvec

    # ---- memory ------------------------------------------------------------
    def read_word(self, address: int) -> int:
        """The aligned 32-bit word containing address, as the bus returns it."""
        region = address >> _REGION_SHIFT
        if region == _ROM_REGION:
            return self.rom.get(address & _WORD_INDEX_MASK, 0)
        if region == _RAM_REGION:
            index = address & _WORD_INDEX_MASK
            return int.from_bytes(self.ram[index : index + 4], "little")
        if region == _APB_REGION:
            return self._read_apb((address >> 8) & 0xFF, (address >> 2) & 0x3F)
        return 0  # default slave

    def _read_apb(self, page: int, reg: int) -> int:
        if page == _PAGE_UART:  # the model sends at once: tx is never busy
            self.uart_deliver()
            if reg == _UART_DATA:
                self.rx_valid = 0
                return self.rx_data
            if reg == _UART_STATUS:
                return memmap.UART_STATUS_RX_VALID if self.rx_valid else 0
            return self.uart_ctrl if reg == _UART_CTRL else 0
        if page == _PAGE_GPIO:
            return {
                _GPIO_OUT: self.gpio_out,
                _GPIO_IN: memmap.TB_SWITCHES,
                _GPIO_DIR: self.gpio_dir,
            }.get(reg, 0)
        if page == _PAGE_DMAC:
            dmac = self.dmac
            return {
                _DMAC_SRC: dmac.src,
                _DMAC_DST: dmac.dst,
                _DMAC_LEN: dmac.length,
                _DMAC_CTRL: memmap.DMAC_CTRL_IRQ if dmac.irq_enable else 0,
                _DMAC_STATUS: memmap.DMAC_STATUS_DONE if dmac.done else 0,
            }.get(reg, 0)
        return 0

    def uart_deliver(self) -> None:
        """Move the next console byte into the receiver if it is enabled and empty."""
        if self.uart_ctrl & memmap.UART_CTRL_RX_ENABLE and not self.rx_valid and self.uart_rx:
            self.rx_data, self.rx_valid = self.uart_rx.pop(0), 1

    def irq_line(self) -> bool:
        """True while a peripheral requests the external interrupt."""
        self.uart_deliver()
        return bool(
            (self.dmac.irq_enable and self.dmac.done)
            or (self.rx_valid and self.uart_ctrl & memmap.UART_CTRL_RX_IRQ)
        )

    def write_ram_word(self, address: int, data: int, byte_enable: int) -> None:
        """Write the enabled byte lanes of the RAM word containing address."""
        index = address & _WORD_INDEX_MASK
        for lane in range(4):
            if byte_enable >> lane & 1:
                self.ram[index + lane] = (data >> (8 * lane)) & 0xFF
        self.ram_written.add(index)

    def store(self, address: int, funct3: int, value: int) -> None:
        """A store of the size in funct3; ROM and unmapped addresses ignore it."""
        size = funct3 & F3_SIZE_MASK
        if size == F3_BYTE:  # the store aligner replicates the byte or halfword
            data = (value & 0xFF) * 0x01010101
        elif size == F3_HALF:
            data = (value & 0xFFFF) * 0x00010001
        else:
            data = value
        region = address >> _REGION_SHIFT
        if region == _RAM_REGION:
            if size == F3_BYTE:
                byte_enable = 1 << (address & 3)
            elif size == F3_HALF:
                byte_enable = 0b1100 if address & 2 else 0b0011
            else:
                byte_enable = _BYTE_ENABLE_WORD
            self.write_ram_word(address, data, byte_enable)
        elif region == _APB_REGION:
            # APB has no byte strobes: every store writes the whole register
            self._write_apb((address >> 8) & 0xFF, (address >> 2) & 0x3F, data)

    def _write_apb(self, page: int, reg: int, data: int) -> None:
        if page == _PAGE_UART:
            if reg == _UART_DATA:
                self.uart_tx.append(data & 0xFF)
            elif reg == _UART_CTRL:
                self.uart_ctrl = data & memmap.UART_CTRL_MASK
        elif page == _PAGE_GPIO:
            if reg == _GPIO_OUT:
                self.gpio_out = data & memmap.GPIO_MASK
            elif reg == _GPIO_DIR:
                self.gpio_dir = data & memmap.GPIO_MASK
        elif page == _PAGE_DMAC:
            dmac = self.dmac
            if reg == _DMAC_SRC:
                dmac.src = data
            elif reg == _DMAC_DST:
                dmac.dst = data
            elif reg == _DMAC_LEN:
                dmac.length = data
            elif reg == _DMAC_CTRL:  # any CTRL write clears done
                dmac.irq_enable, dmac.done = (data >> 1) & 1, 0
                if data & memmap.DMAC_CTRL_START:
                    self._dma_copy()

    def _dma_copy(self) -> None:
        """The whole transfer at once (the SoC takes many cycles); only RAM is written."""
        dmac = self.dmac
        for index in range(dmac.length):
            dst = (dmac.dst + 4 * index) & MASK
            if dst >> _REGION_SHIFT == _RAM_REGION:
                word = self.read_word((dmac.src + 4 * index) & MASK)
                self.write_ram_word(dst, word, _BYTE_ENABLE_WORD)
        dmac.done = 1

    def load(self, address: int, funct3: int) -> int:
        """A load of the size and signedness in funct3."""
        word = self.read_word(address)
        byte = (word >> (8 * (address & 3))) & 0xFF
        half = (word >> (16 * ((address >> 1) & 1))) & 0xFFFF
        if funct3 == F3_BYTE:
            return byte | (0xFFFFFF00 if byte & 0x80 else 0)
        if funct3 == F3_HALF:
            return half | (0xFFFF0000 if half & 0x8000 else 0)
        if funct3 == F3_LBU:
            return byte
        if funct3 == F3_LHU:
            return half
        return word

    # ---- one instruction ---------------------------------------------------
    def fetch_half(self, address: int) -> int:
        """The 16 bits of ROM at a halfword-aligned address."""
        word = self.rom.get(address & _WORD_INDEX_MASK, 0)
        return (word >> (16 * ((address >> 1) & 1))) & 0xFFFF

    def step(self) -> bool:
        """Execute one instruction or take one trap; True at the halt loop."""
        pc = self.pc
        if self.interrupts and self.mie and self.meie and self.irq_line():
            self.trap(memmap.CAUSE_EXTERNAL_INTERRUPT, 0)
            return False
        low = self.fetch_half(pc)
        if is_compressed(low):  # execute the expansion
            ins, length = decompress(low), 2
        else:
            ins, length = low | self.fetch_half(pc + 2) << 16, 4
        if not is_legal(ins):
            self.trap(memmap.CAUSE_ILLEGAL_INSTRUCTION, 0)
            return False

        opcode, rd, funct3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
        rs1, rs2 = (ins >> 15) & 31, (ins >> 20) & 31
        a, b = self.x[rs1], self.x[rs2]
        funct7 = ins >> 25
        next_pc = (pc + length) & MASK
        result: int | None = None
        result_taint = False
        tainted = bool(source_registers(ins) & self.taint)
        if (
            tainted
            and opcode in (OP_LOAD, OP_STORE, OP_BRANCH, OP_JALR)
            and not (opcode == OP_STORE and rs1 not in self.taint)  # tainted store data is fine
        ):
            raise TimingDependentError(
                "0x%04X: a timing-dependent value controls an address or a branch" % pc
            )

        if opcode == OP_REG:
            result_taint = tainted
            if funct7 == F7_MULDIV:
                if funct3 in _DIVIDE_OPS:
                    result = divide(a, b, funct3)
                    self.divs += 1
                else:
                    result = multiply(a, b, funct3)
            else:
                result = alu(funct3, a, b, funct7 == F7_ALT)
        elif opcode == OP_IMM:
            result_taint = tainted
            imm = imm_i(ins) & MASK
            if funct3 in (1, 5):  # shifts: the amount is imm[4:0], imm[10] selects SRAI
                result = alu(funct3, a, imm & 31, funct7 == F7_ALT)
            else:
                result = alu(funct3, a, imm, False)
        elif opcode == OP_LOAD:
            address = (a + imm_i(ins)) & MASK
            if _misaligned(funct3, address):
                self.trap(memmap.CAUSE_LOAD_MISALIGNED, address)
                return False
            result = self.load(address, funct3)
            result_taint = (
                address >> _REGION_SHIFT == _RAM_REGION
                and (address & _WORD_INDEX_MASK) in self.ram_taint
            )
        elif opcode == OP_STORE:
            address = (a + imm_s(ins)) & MASK
            if _misaligned(funct3, address):
                self.trap(memmap.CAUSE_STORE_MISALIGNED, address)
                return False
            self.store(address, funct3, b)
            if address >> _REGION_SHIFT == _RAM_REGION:
                if rs2 in self.taint:
                    self.ram_taint.add(address & _WORD_INDEX_MASK)
                elif funct3 & F3_SIZE_MASK == F3_WORD:  # a whole clean word
                    self.ram_taint.discard(address & _WORD_INDEX_MASK)
        elif opcode == OP_BRANCH:
            if _branch_taken(funct3, a, b):
                next_pc = (pc + imm_b(ins)) & MASK
        elif opcode == OP_JAL:
            result, next_pc = (pc + length) & MASK, (pc + imm_j(ins)) & MASK
        elif opcode == OP_JALR:
            result, next_pc = (pc + length) & MASK, (a + imm_i(ins)) & MASK & ~1
        elif opcode == OP_LUI:
            result = ins & 0xFFFFF000
        elif opcode == OP_AUIPC:
            result = (pc + (ins & 0xFFFFF000)) & MASK
        elif opcode == OP_SYSTEM and funct3 != F3_PRIV:
            csr_result = self._csr_instruction(ins, pc, funct3, rs1, a)
            if csr_result is None:
                return False
            result, result_taint = csr_result
        elif opcode == OP_SYSTEM:
            funct12 = ins >> 20
            if funct12 == F12_ECALL:
                self.trap(memmap.CAUSE_ECALL_M, 0)
                return False
            if funct12 == F12_EBREAK:
                self.trap(memmap.CAUSE_BREAKPOINT, pc)
                return False
            if funct12 == F12_MRET:
                next_pc = self.mepc
                self.mie, self.mpie = self.mpie, 1
            # WFI: nothing to wait for
        # OP_MISC_MEM (FENCE): a NOP

        if result is not None and rd:
            self.x[rd] = result & MASK
            if result_taint:
                self.taint.add(rd)
            else:
                self.taint.discard(rd)
        if self.keep_trace:
            self.trace.append(pc)
        self.retired += 1
        self.pc = next_pc
        return ins == INSTR_HALT

    def _csr_instruction(
        self, ins: int, pc: int, funct3: int, rs1: int, a: int
    ) -> tuple[int, bool] | None:
        """CSRRW/S/C and their immediate forms: (old value, its taint), or None
        if the instruction trapped."""
        address, kind, immediate_form = ins >> 20, funct3 & 3, funct3 & F3_CSR_IMMEDIATE
        # CSRRS/CSRRC with rs1 = x0 (or a zero immediate) only read
        writes = not (kind in (F3_CSRRS, F3_CSRRC) and rs1 == 0)
        read_only = address >> 10 == memmap.CSR_READ_ONLY_SPACE
        if address not in memmap.CSR_IMPLEMENTED or (writes and read_only):
            self.trap(memmap.CAUSE_ILLEGAL_INSTRUCTION, 0)
            return None
        if writes and not immediate_form and rs1 in self.taint:
            raise TimingDependentError("0x%04X: a timing-dependent value is written to a CSR" % pc)
        source = rs1 if immediate_form else a
        old = self.csr_read(address)
        if writes:
            if kind == F3_CSRRW:
                new = source
            elif kind == F3_CSRRS:
                new = old | source
            else:
                new = old & ~source & MASK
            self.csr_write(address, new)
        # with interrupts modelled, mip is known: it is the OR of the modelled lines
        taint = address in self.timing_csrs and not (address == memmap.CSR_MIP and self.interrupts)
        return old, taint

    def run(self, limit: int = DEFAULT_RUN_LIMIT) -> TimurModel:
        """Run to the halt loop; HaltNotReachedError after limit instructions."""
        for _ in range(limit):
            if self.step():
                return self
        raise HaltNotReachedError(
            "the program did not reach its halt loop in %d instructions (PC %08X)"
            % (limit, self.pc)
        )


def _branch_taken(funct3: int, a: int, b: int) -> bool:
    if funct3 == 0:
        return a == b
    if funct3 == 1:
        return a != b
    if funct3 == 4:
        return s32(a) < s32(b)
    if funct3 == 5:
        return s32(a) >= s32(b)
    if funct3 == 6:
        return a < b
    return a >= b
