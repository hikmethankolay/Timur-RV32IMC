"""The instruction-level reference model of the SoC (timur_tools.model)."""

from __future__ import annotations

import pytest
from timur_tools.asm import assemble
from timur_tools.isa import MASK
from timur_tools.model import HaltNotReached, TimingDependent, TimurModel, divide
from timur_tools.rvc import decompress

from conftest import REPO
from timur_tools import memmap

PREAMBLE = """
        lui   x31, 0x20000         # RAM base
        lui   x30, 0x40000         # APB base
"""
HALT = "halt:   jal   x0, halt\n"


def run(body: str, **options: object) -> TimurModel:
    return TimurModel(assemble(PREAMBLE + body + HALT).image, **options).run()  # type: ignore[arg-type]


def test_arithmetic_and_x0() -> None:
    m = run(
        """
        addi  x1, x0, -5
        addi  x2, x0, 3
        add   x3, x1, x2
        sub   x4, x2, x1
        slt   x5, x1, x2
        sltu  x6, x1, x2
        sra   x7, x1, x2
        srl   x8, x1, x2
        mulh  x9, x1, x2
        mulhu x10, x1, x2
        addi  x0, x0, 7
        add   x11, x0, x0
        """
    )

    assert m.x[3] == 0xFFFFFFFE
    assert m.x[4] == 8
    assert (m.x[5], m.x[6]) == (1, 0)
    assert m.x[7] == 0xFFFFFFFF
    assert m.x[8] == 0x1FFFFFFF
    assert m.x[9] == 0xFFFFFFFF
    assert m.x[10] == 2
    assert m.x[0] == 0 and m.x[11] == 0


@pytest.mark.parametrize(
    ("a", "b", "op", "expected"),
    [
        (7, 0, 4, MASK),  # DIV by zero: all ones
        (7, 0, 5, MASK),  # DIVU by zero
        (7, 0, 6, 7),  # REM by zero: the dividend
        (7, 0, 7, 7),  # REMU by zero
        (0x80000000, MASK, 4, 0x80000000),  # signed overflow: DIV
        (0x80000000, MASK, 6, 0),  # signed overflow: REM
        ((-7) & MASK, 2, 4, (-3) & MASK),  # truncation towards zero
        ((-7) & MASK, 2, 6, (-1) & MASK),  # the remainder has the dividend's sign
        (7, (-2) & MASK, 4, (-3) & MASK),
        (7, (-2) & MASK, 6, 1),
        (0xFFFFFFFF, 2, 5, 0x7FFFFFFF),
        (0xFFFFFFFF, 2, 7, 1),
    ],
)
def test_divide_follows_the_m_extension(a: int, b: int, op: int, expected: int) -> None:
    assert divide(a, b, op) == expected


def test_loads_and_stores_of_every_size() -> None:
    m = run(
        """
        lui   x1, 0x80FF8
        addi  x1, x1, 0x17F        # 80FF817F
        sw    x1, 0(x31)
        lb    x2, 1(x31)           # FFFFFF81
        lbu   x3, 1(x31)           # 00000081
        lh    x4, 2(x31)           # FFFF80FF
        lhu   x5, 2(x31)           # 000080FF
        sb    x0, 1(x31)           # 80FF007F
        sh    x0, 2(x31)           # 0000007F
        lw    x6, 0(x31)
        lw    x7, 0(x0)            # ROM data port: the first program word
        """
    )

    assert [m.x[r] for r in range(2, 7)] == [0xFFFFFF81, 0x81, 0xFFFF80FF, 0x80FF, 0x7F]
    assert m.x[7] == 0x20000FB7
    assert m.ram_written == {0}


def test_misaligned_accesses_trap_and_write_nothing() -> None:
    m = run(
        """
        addi  x1, x0, handler
        csrrw x0, mtvec, x1
        lw    x2, 1(x31)
        sh    x1, 1(x31)
        jal   x0, halt
handler:
        csrrs x5, mepc, x0
        addi  x5, x5, 4
        csrrw x0, mepc, x5
        mret
        """
    )

    assert [(cause, tval) for cause, _, tval in m.traps] == [
        (memmap.CAUSE_LOAD_MISALIGNED, memmap.RAM_BASE + 1),
        (memmap.CAUSE_STORE_MISALIGNED, memmap.RAM_BASE + 1),
    ]
    assert m.x[2] == 0 and not m.ram_written


def test_ecall_ebreak_illegal_and_csr_traps() -> None:
    m = run(
        """
        addi  x1, x0, handler
        csrrw x0, mtvec, x1
        ecall
        ebreak
        .word 0x00000000
        csrrw x0, cycle, x1        # write to the read-only space
        csrrs x2, 0x7C0, x0        # not implemented
        csrrs x3, misa, x0
        jal   x0, halt
handler:
        csrrs x5, mepc, x0
        addi  x5, x5, 4
        csrrw x0, mepc, x5
        mret
        """
    )

    assert [cause for cause, _, _ in m.traps] == [11, 3, 2, 2, 2]
    assert m.traps[1][2] == m.traps[1][1], "EBREAK: mtval is the PC"
    assert m.x[3] == memmap.MISA_VALUE
    assert m.mpie == 1 and m.mie == 0


def test_uart_gpio_and_dmac() -> None:
    m = run(
        """
        addi  x1, x0, 0x55
        sw    x1, 0(x30)           # UART_DATA
        addi  x1, x0, 0x2A5
        sw    x1, 0x100(x30)       # GPIO_OUT
        lw    x2, 0x104(x30)       # GPIO_IN: the switches
        addi  x3, x30, 0x200       # DMAC
        sw    x0, 0(x3)            # SRC = 0 (ROM)
        addi  x4, x31, 0x40
        sw    x4, 4(x3)            # DST
        addi  x5, x0, 2
        sw    x5, 8(x3)            # LEN = 2 words
        addi  x5, x0, 1
        sw    x5, 12(x3)           # start
        lw    x6, 16(x3)           # STATUS: done
        lw    x7, 0x40(x31)
        """
    )

    assert bytes(m.uart_tx) == b"U"
    assert m.gpio_out == 0x2A5
    assert m.x[2] == memmap.TB_SWITCHES
    assert m.x[6] == 2
    assert m.x[7] == 0x20000FB7
    assert m.divs == 0


def test_console_input_and_interrupt() -> None:
    body = """
        addi  x1, x0, handler
        csrrw x0, mtvec, x1
        addi  x1, x0, 3
        sw    x1, 8(x30)           # UART_CTRL: rx_enable, rx_irq_enable
        addi  x1, x0, 1
        slli  x1, x1, 11
        csrrs x0, mie, x1          # MEIE
        csrrsi x0, mstatus, 8      # MIE
wait:   beq   x20, x0, wait
        jal   x0, halt
handler:
        csrrs x21, mcause, x0
        lw    x22, 0(x30)          # UART_DATA: clears rx_valid
        addi  x20, x0, 1
        mret
        """

    m = run(body, uart_rx=b"A", interrupts=True)

    assert m.x[21] == memmap.CAUSE_EXTERNAL_INTERRUPT
    assert m.x[22] == ord("A")
    assert [cause for cause, _, _ in m.traps] == [memmap.CAUSE_EXTERNAL_INTERRUPT]
    assert not m.uart_rx and not m.rx_valid


def test_trace_and_retired_count() -> None:
    m = run("addi x1, x0, 1\n")

    assert m.trace == [0, 4, 8, 12]
    assert m.retired == 4
    assert TimurModel(assemble(HALT).image, trace=False).run().trace == []


def test_program_without_halt_is_reported() -> None:
    image = assemble("loop: addi x1, x1, 1\n      beq x0, x0, loop").image

    with pytest.raises(HaltNotReached):
        TimurModel(image).run(limit=100)


def test_counter_values_taint_and_cannot_steer_the_program() -> None:
    tainted = run("csrrs x5, cycle, x0\nadd x6, x5, x5\naddi x7, x0, 1\n")
    assert tainted.taint == {5, 6}

    with pytest.raises(TimingDependent):
        run("csrrs x5, cycle, x0\nskip: beq x5, x0, skip\n")


def test_fake_time_is_a_property_of_one_model_not_of_the_module() -> None:
    """--fake-time used to clear a module-level set, changing every later model."""
    program = "csrrs x5, instret, x0\nsk: beq x5, x0, sk\n"

    fake = run(program, fake_time=True)
    assert fake.x[5] == 2, "the counter counts executed instructions"
    assert fake.read_time and not fake.taint

    with pytest.raises(TimingDependent):
        run(program)


def test_decompressor_matches_the_toolchain_for_every_encoding() -> None:
    lines = (REPO / "vectors" / "decompressor_vectors.txt").read_text().splitlines()
    cases = [line.split() for line in lines if line and not line.startswith("//")]

    assert len(cases) == 49152
    wrong = [c[0] for c in cases if decompress(int(c[0], 16)) != int(c[1], 16)]
    assert not wrong
    assert all((int(c[1], 16) == 0) == (c[2] == "1") for c in cases)
