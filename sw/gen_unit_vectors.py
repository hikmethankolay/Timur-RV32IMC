#!/usr/bin/env python3
"""Vector files for the Phase 10 unit testbenches, from reference models.

Writes, relative to the project root:
  vectors/csr_file_vectors.txt    tb/csr_file_tb.v
  vectors/trap_unit_vectors.txt   tb/trap_unit_tb.v

The models below follow the RISC-V privileged specification and the CSR set
of the build guide; they are written independently of the RTL, so a mistake
has to be made twice to go unnoticed. Random sections use a fixed seed, so the
files are reproducible.

Usage:  python3 sw/gen_unit_vectors.py [--root DIR]
"""

from __future__ import annotations

import argparse
import random
import sys
from collections.abc import Sequence
from dataclasses import dataclass

from timur_tools import cli, memmap, paths
from timur_tools.isa import MASK
from timur_tools.paths import Project
from timur_tools.romimage import write_lines

SEED = 20260927
COUNTER_MASK = (1 << 64) - 1

CSR_VECTOR_FILE = paths.VECTORS + "/csr_file_vectors.txt"
TRAP_VECTOR_FILE = paths.VECTORS + "/trap_unit_vectors.txt"

# ---------------------------------------------------------------------------
# CSR file
# ---------------------------------------------------------------------------
MSTATUS, MISA, MIE, MTVEC = memmap.CSR_MSTATUS, memmap.CSR_MISA, memmap.CSR_MIE, memmap.CSR_MTVEC
MSCRATCH, MEPC, MCAUSE = memmap.CSR_MSCRATCH, memmap.CSR_MEPC, memmap.CSR_MCAUSE
MTVAL, MIP = memmap.CSR_MTVAL, memmap.CSR_MIP
MCYCLE, MINSTRET = memmap.CSR_MCYCLE, memmap.CSR_MINSTRET
MCYCLEH, MINSTRETH = memmap.CSR_MCYCLEH, memmap.CSR_MINSTRETH
CYCLE, TIME, INSTRET = memmap.CSR_CYCLE, memmap.CSR_TIME, memmap.CSR_INSTRET
CYCLEH, TIMEH, INSTRETH = memmap.CSR_CYCLEH, memmap.CSR_TIMEH, memmap.CSR_INSTRETH
IDS = (memmap.CSR_MVENDORID, memmap.CSR_MARCHID, memmap.CSR_MIMPID, memmap.CSR_MHARTID)
IMPLEMENTED = memmap.CSR_IMPLEMENTED
UNIMPLEMENTED = (0x000, 0x001, 0x302, 0x303, 0x7C0, 0xB01, 0xB03, 0xC03, 0xF15, 0xFFF, 0x7B0)

# csr_op of the CSR file
WRITE, SET, CLEAR = 0, 1, 2


@dataclass(frozen=True)
class CsrInputs:
    """Inputs of csr_file for one clock cycle (names as in rtl/csr/csr_file.v)."""

    rst_n: int = 1
    addr: int = 0
    op: int = WRITE
    wdata: int = 0
    attempt: int = 0  # the instruction is a CSR access (legality is checked)
    we: int = 0  # the access writes
    trap: int = 0
    cause: int = 0
    epc: int = 0
    val: int = 0
    mret: int = 0
    retire: int = 0
    irq: int = 0  # two interrupt lines

    def as_vector(self) -> str:
        """The input columns of a vector line."""
        return "%d %03X %d%d %08X %d %d %d %08X %08X %08X %d %d %d%d" % (
            self.rst_n, self.addr, self.op >> 1, self.op & 1, self.wdata, self.attempt,
            self.we, self.trap, self.cause, self.epc, self.val, self.mret, self.retire,
            self.irq >> 1, self.irq & 1,
        )  # fmt: skip


class CsrModel:
    """The machine-mode CSRs of the build guide, cycle by cycle."""

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        """Reset values: everything 0 (mstatus.MPP reads 11 regardless)."""
        self.mie = self.mpie = self.meie = 0
        self.mtvec = self.mscratch = self.mepc = self.mcause = self.mtval = 0
        self.mcycle = self.minstret = 0

    def read(self, addr: int, irq: int) -> int:
        """csr_rdata for an address (0 for unimplemented ones)."""
        values = {
            MSTATUS: memmap.MSTATUS_MPP_MACHINE | (self.mpie << 7) | (self.mie << 3),
            MISA: memmap.MISA_VALUE,
            MIE: self.meie << 11,
            MTVEC: self.mtvec,
            MSCRATCH: self.mscratch,
            MEPC: self.mepc,
            MCAUSE: self.mcause,
            MTVAL: self.mtval,
            MIP: int(irq != 0) << 11,  # MEIP: the OR of the interrupt lines
            MCYCLE: self.mcycle & MASK,
            CYCLE: self.mcycle & MASK,
            TIME: self.mcycle & MASK,
            MCYCLEH: self.mcycle >> 32,
            CYCLEH: self.mcycle >> 32,
            TIMEH: self.mcycle >> 32,
            MINSTRET: self.minstret & MASK,
            INSTRET: self.minstret & MASK,
            MINSTRETH: self.minstret >> 32,
            INSTRETH: self.minstret >> 32,
        }
        for addr_id in IDS:
            values[addr_id] = 0
        return values.get(addr, 0)

    def outputs(self, inputs: CsrInputs) -> tuple[int, int, int, int, int]:
        """Combinational outputs: rdata, illegal, mtvec, mepc, irq_pending."""
        rdata = self.read(inputs.addr, inputs.irq)
        writes_read_only = inputs.attempt and (inputs.addr >> 10) == memmap.CSR_READ_ONLY_SPACE
        illegal = int(inputs.addr not in IMPLEMENTED or bool(writes_read_only))
        irq_pending = int(bool(self.mie and self.meie and inputs.irq != 0))
        return rdata, illegal, self.mtvec, self.mepc, irq_pending

    def clock(self, inputs: CsrInputs) -> None:
        """The rising clock edge."""
        if not inputs.rst_n:
            self.reset()
            return
        old = self.read(inputs.addr, inputs.irq)
        new = {
            WRITE: inputs.wdata,
            SET: old | inputs.wdata,
            CLEAR: old & ~inputs.wdata & MASK,
        }.get(inputs.op, inputs.wdata)
        addr, we = inputs.addr, inputs.we
        if inputs.trap:  # a trap wins over a CSR write in the same cycle
            self.mepc = inputs.epc & ~1 & MASK
            self.mcause, self.mtval = inputs.cause, inputs.val
            self.mpie, self.mie = self.mie, 0
        elif inputs.mret:  # so does MRET
            self.mie, self.mpie = self.mpie, 1
        elif we:
            self._write(addr, new)
        if we and addr in (MCYCLE, MCYCLEH):  # a write replaces the increment
            if addr == MCYCLE:
                self.mcycle = (self.mcycle >> 32) << 32 | new
            else:
                self.mcycle = new << 32 | (self.mcycle & MASK)
        else:
            self.mcycle = (self.mcycle + 1) & COUNTER_MASK
        if we and addr in (MINSTRET, MINSTRETH):
            if addr == MINSTRET:
                self.minstret = (self.minstret >> 32) << 32 | new
            else:
                self.minstret = new << 32 | (self.minstret & MASK)
        elif inputs.retire:
            self.minstret = (self.minstret + 1) & COUNTER_MASK

    def _write(self, addr: int, new: int) -> None:
        if addr == MSTATUS:
            self.mie, self.mpie = (new >> 3) & 1, (new >> 7) & 1
        elif addr == MIE:
            self.meie = (new >> 11) & 1
        elif addr == MTVEC:
            self.mtvec = new & ~3 & MASK
        elif addr == MSCRATCH:
            self.mscratch = new
        elif addr == MEPC:
            self.mepc = new & ~1 & MASK
        elif addr == MCAUSE:
            self.mcause = new
        elif addr == MTVAL:
            self.mtval = new


def csr_vectors() -> list[str]:
    """The csr_file vector lines: directed sections, then a random sequence."""
    model = CsrModel()
    lines: list[str] = []

    def cycle(comment: str | None = None, **fields: int) -> None:
        inputs = CsrInputs(**fields)
        if comment:
            lines.append("// " + comment)
        columns = inputs.as_vector()
        if inputs.rst_n:
            rdata, illegal, mtvec, mepc, irq_pending = model.outputs(inputs)
            lines.append(
                "%s  %08X %d %08X %08X %d 0" % (columns, rdata, illegal, mtvec, mepc, irq_pending)
            )
        else:
            lines.append("%s  xxxxxxxx x xxxxxxxx xxxxxxxx x 0" % columns)
        model.clock(inputs)
        lines.append("%s  xxxxxxxx x xxxxxxxx xxxxxxxx x 1" % columns)

    def read(addr: int, comment: str | None = None, irq: int = 0) -> None:
        cycle(comment, addr=addr, irq=irq)

    def write(
        addr: int, value: int, op: int = WRITE, comment: str | None = None, we: int = 1
    ) -> None:
        cycle(comment, addr=addr, op=op, wdata=value, attempt=1, we=we)

    cycle("reset", rst_n=0)
    cycle(rst_n=0)
    read(MSTATUS, "reset values: mstatus = MPP 11 only; misa; everything else 0")
    for addr in (MISA, MIE, MTVEC, MSCRATCH, MEPC, MCAUSE, MTVAL, MIP, *IDS):
        read(addr)
    read(MCYCLE, "mcycle counts every cycle after reset; minstret counts nothing yet")
    read(MCYCLE)
    read(MINSTRET)
    read(MCYCLEH)

    lines.append("// WRITE, SET, CLEAR on every writable CSR; unused bits read 0")
    for addr, pattern in (
        (MSTATUS, MASK), (MIE, MASK), (MTVEC, MASK), (MSCRATCH, 0xA5A55A5A),
        (MEPC, 0x12345677), (MCAUSE, 0x8000000B), (MTVAL, 0xDEADBEEF),
    ):  # fmt: skip
        write(addr, pattern)
        read(addr)
        write(addr, 0x00F0F00F, SET)
        read(addr)
        write(addr, 0xFFFF0000, CLEAR)
        read(addr)
        write(addr, 0)
    write(MSTATUS, 0x88, comment="mstatus: MIE and MPIE are the only writable bits")
    read(MSTATUS)
    write(MSTATUS, 0x80, CLEAR)
    read(MSTATUS)
    write(MSTATUS, 0)

    lines.append("// misa and mip ignore writes, which are legal (not in the read-only space)")
    write(MISA, 0)
    read(MISA)
    write(MIP, MASK)
    read(MIP)
    read(MIP, "mip.MEIP follows the interrupt lines", irq=1)
    read(MIP, irq=2)
    read(MIP, irq=3)

    lines.append("// read-only space [11:10] = 11: a write attempt is illegal, a plain read is not")
    for addr in (CYCLE, INSTRETH, memmap.CSR_MHARTID):
        cycle(addr=addr, op=SET, wdata=0, attempt=0)
        cycle(addr=addr, op=WRITE, wdata=0x55, attempt=1, we=0)
    lines.append("// unimplemented addresses are illegal and read 0")
    for addr in UNIMPLEMENTED:
        read(addr)
    lines.append("// attempt without we: legality only, no write")
    write(MSCRATCH, 0x11111111)
    write(MSCRATCH, 0x22222222, we=0)
    read(MSCRATCH)

    lines.append("// trap entry: mepc (low bits dropped), mcause, mtval; MPIE <- MIE, MIE <- 0")
    write(MSTATUS, 0x8)
    write(MIE, 0x800)
    read(MSTATUS)
    cycle(trap=1, cause=11, epc=0x00000077, val=0)
    read(MSTATUS)
    read(MEPC)
    read(MCAUSE)
    read(MTVAL)
    lines.append("// MRET: MIE <- MPIE, MPIE <- 1")
    cycle(mret=1)
    read(MSTATUS)
    cycle("a trap with MIE = 0 leaves MPIE = 0", trap=1, cause=2, epc=0x1000, val=0)
    write(MSTATUS, 0, CLEAR, we=0)
    cycle(trap=1, cause=4, epc=0x2004, val=0x20000001)
    read(MSTATUS)
    read(MTVAL)
    cycle(mret=1)
    read(MSTATUS)
    lines.append("// priority: trap over a CSR write in the same cycle, MRET over a CSR write")
    cycle(addr=MSCRATCH, wdata=0x33333333, attempt=1, we=1, trap=1, cause=3, epc=0x44, val=0x44)
    read(MSCRATCH)
    read(MCAUSE)
    cycle(addr=MSCRATCH, wdata=0x44444444, attempt=1, we=1, mret=1)
    read(MSCRATCH)

    lines.append("// irq_pending = MIE AND MEIE AND MEIP")
    for mie in (0, 1):
        for meie in (0, 1):
            write(MSTATUS, mie << 3)
            write(MIE, meie << 11)
            for irq in (0, 1, 2):
                read(MSTATUS, irq=irq)

    lines.append(
        "// counters: writes to either half replace it and suppress the increment in that cycle"
    )
    write(MCYCLE, 0xFFFFFFFE)
    read(MCYCLE)
    read(MCYCLE)
    read(MCYCLEH)
    read(CYCLEH)
    read(TIMEH)
    write(MCYCLEH, 0x00000007)
    read(MCYCLEH)
    read(CYCLE)
    read(TIME)
    write(MINSTRET, 0xFFFFFFFF)
    read(MINSTRET)
    cycle(addr=MINSTRET, retire=1)
    read(MINSTRETH)
    read(INSTRETH)
    for _ in range(3):
        cycle(addr=INSTRET, retire=1)
    read(INSTRET)
    write(MINSTRETH, 0x00000100)
    cycle(addr=MINSTRETH, attempt=1, we=1, op=WRITE, wdata=0x00000200, retire=1)
    read(MINSTRETH)
    read(MINSTRET)

    lines.append("// random sequence")
    rnd = random.Random(SEED)
    addrs = [*sorted(IMPLEMENTED), 0x000, 0x302, 0x7C0, 0xC03]
    for _ in range(600):
        kind = rnd.random()
        addr = rnd.choice(addrs)
        op = rnd.choice([WRITE, SET, CLEAR])
        wdata = rnd.choice([rnd.getrandbits(32), 0, MASK, 1 << rnd.randrange(32)])
        attempt = int(rnd.random() < 0.6)
        writable = addr in IMPLEMENTED and (addr >> 10) != memmap.CSR_READ_ONLY_SPACE
        we = int(attempt and rnd.random() < 0.8 and writable)
        trap = int(kind < 0.05)
        mret = int(0.05 <= kind < 0.09)
        cycle(
            addr=addr, op=op, wdata=wdata, attempt=attempt, we=we, trap=trap,
            cause=rnd.choice([0, 2, 3, 4, 6, 11, memmap.CAUSE_EXTERNAL_INTERRUPT]),
            epc=rnd.getrandbits(32), val=rnd.getrandbits(32), mret=mret,
            retire=int(rnd.random() < 0.5), irq=rnd.randrange(4),
        )  # fmt: skip
    return lines


CSR_HEADER = [
    "// csr_file test vectors (generated by sw/gen_unit_vectors.py)",
    "// format: rst_n addr(hex) op(bin) wdata(hex) attempt we trap_take trap_cause(hex) trap_epc(hex)",  # noqa: E501
    "//         trap_val(hex) mret_take retire irq_lines(bin)",
    "//         expected: csr_rdata(hex) csr_illegal mtvec_out(hex) mepc_out(hex) irq_pending, then wait_type",  # noqa: E501
    "// Each clock cycle is two lines: wait_type 0 checks the combinational outputs for the",
    "// cycle's inputs, wait_type 1 applies the rising edge with the same inputs (x = don't care).",
    "// op: 00 WRITE, 01 SET, 10 CLEAR. mcycle counts every edge after reset.",
]  # fmt: skip


# ---------------------------------------------------------------------------
# Trap unit
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class TrapInputs:
    """Inputs of trap_unit for one instruction (names as in rtl/csr/trap_unit.v)."""

    valid: int = 1
    pc: int = 0x100
    illegal: int = 0
    ecall: int = 0
    ebreak: int = 0
    csr: int = 0
    csr_illegal: int = 0
    rd: int = 0  # mem_read
    wr: int = 0  # mem_write
    funct3: int = 2
    addr_lo: int = 0  # the low address bits from the fast adder
    addr: int = 0x20000000
    irq: int = 0
    irq_ok: int = 1

    def as_vector(self) -> str:
        """The input columns of a vector line."""
        return "%d %08X %d %d %d %d %d %d %d %d%d%d %d%d %08X %d %d" % (
            self.valid, self.pc, self.illegal, self.ecall, self.ebreak, self.csr,
            self.csr_illegal, self.rd, self.wr, self.funct3 >> 2, (self.funct3 >> 1) & 1,
            self.funct3 & 1, self.addr_lo >> 1, self.addr_lo & 1, self.addr, self.irq,
            self.irq_ok,
        )  # fmt: skip


def trap_model(inputs: TrapInputs) -> tuple[int, int] | None:
    """(cause, mtval) of the trap the instruction described by inputs raises, or None."""
    size = inputs.funct3 & 3
    low = inputs.addr_lo
    misaligned = (size == 2 and low != 0) or (size == 1 and low & 1)
    if not inputs.valid:
        return None
    if inputs.irq and inputs.irq_ok:
        return memmap.CAUSE_EXTERNAL_INTERRUPT, 0
    if inputs.illegal or (inputs.csr and inputs.csr_illegal):
        return memmap.CAUSE_ILLEGAL_INSTRUCTION, 0
    if inputs.ebreak:
        return memmap.CAUSE_BREAKPOINT, inputs.pc
    if inputs.ecall:
        return memmap.CAUSE_ECALL_M, 0
    if inputs.rd and misaligned:
        return memmap.CAUSE_LOAD_MISALIGNED, inputs.addr
    if inputs.wr and misaligned:
        return memmap.CAUSE_STORE_MISALIGNED, inputs.addr
    return None


def trap_vectors() -> list[str]:
    """The trap_unit vector lines: directed cases, then random ones."""
    rnd = random.Random(SEED + 1)
    lines: list[str] = []

    def vec(comment: str | None = None, **fields: int) -> None:
        inputs = TrapInputs(**fields)
        if comment:
            lines.append("// " + comment)
        trap = trap_model(inputs)
        expected = "1 %08X %08X" % trap if trap else "0 xxxxxxxx xxxxxxxx"
        lines.append("%s  %s" % (inputs.as_vector(), expected))

    vec("no trap: an ordinary instruction")
    vec("bubble: nothing traps, whatever the controls say", valid=0, ecall=1, irq=1)
    vec("illegal instruction, cause 2, mtval 0", illegal=1)
    vec("CSR access to an illegal CSR", csr=1, csr_illegal=1)
    vec("csr_illegal without a CSR access does not trap", csr=0, csr_illegal=1)
    vec("EBREAK, cause 3, mtval = PC", ebreak=1, pc=0x1234)
    vec("ECALL, cause 11 (machine mode, never 8)", ecall=1)
    lines.append(
        "// loads and stores: word needs addr[1:0] = 0, halfword addr[0] = 0, bytes never trap"
    )
    for rd, wr in ((1, 0), (0, 1)):
        for funct3 in (0, 1, 2, 4, 5):
            if wr and funct3 > 2:
                continue
            for low in range(4):
                vec(rd=rd, wr=wr, funct3=funct3, addr_lo=low, addr=0x20000100 | low)
    vec(
        "the misalignment check uses addr_lo, the fast adder output",
        rd=1, funct3=2, addr_lo=1, addr=0x20000100,
    )  # fmt: skip
    vec(rd=1, funct3=2, addr_lo=0, addr=0x20000101)
    lines.append("// interrupt: taken when allowed, before any exception of the same instruction")
    vec(irq=1)
    vec(irq=1, irq_ok=0)
    vec(irq=1, ecall=1)
    vec(irq=1, irq_ok=0, ecall=1)
    vec(irq=1, illegal=1)
    vec(irq=1, rd=1, funct3=2, addr_lo=1)
    vec(valid=0, irq=1)
    lines.append("// random")
    for _ in range(400):
        vec(
            valid=int(rnd.random() < 0.9), pc=rnd.getrandbits(32) & ~1,
            illegal=int(rnd.random() < 0.1), ecall=int(rnd.random() < 0.1),
            ebreak=int(rnd.random() < 0.1), csr=int(rnd.random() < 0.2),
            csr_illegal=int(rnd.random() < 0.3), rd=int(rnd.random() < 0.3),
            wr=int(rnd.random() < 0.3), funct3=rnd.choice([0, 1, 2, 4, 5]),
            addr_lo=rnd.randrange(4), addr=rnd.getrandbits(32), irq=int(rnd.random() < 0.2),
            irq_ok=int(rnd.random() < 0.7),
        )  # fmt: skip
    return lines


TRAP_HEADER = [
    "// trap_unit test vectors (generated by sw/gen_unit_vectors.py)",
    "// format: valid pc(hex) illegal is_ecall is_ebreak csr_access csr_illegal mem_read mem_write",
    "//         funct3(bin) mem_addr_lo(bin) mem_addr(hex) irq_pending irq_allowed",
    "//         expected: trap_req trap_cause(hex) trap_val(hex)   (x = don't care)",
    "// Combinational: apply, wait 10 ns, compare.",
]


def generate(project: Project) -> None:
    """Write both vector files."""
    write_lines(project.path(CSR_VECTOR_FILE), CSR_HEADER + csr_vectors())
    write_lines(project.path(TRAP_VECTOR_FILE), TRAP_HEADER + trap_vectors())


def main(argv: Sequence[str] | None = None) -> int:
    """Generate the unit-test vectors; returns the exit status."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    cli.add_common_arguments(parser)
    args = parser.parse_args(argv)
    generate(cli.project_from(args))
    return 0


if __name__ == "__main__":
    sys.exit(cli.run(main, "gen_unit_vectors"))
