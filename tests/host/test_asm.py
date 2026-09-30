"""The two-pass assembler for the directed test programs (timur_tools.asm)."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from timur_tools.asm import AsmError, assemble

from conftest import REPO, TOOLCHAIN_BIN, needs_toolchain

# Reference encodings of the Phase 5 program, from the build guide.
PHASE5_WORDS = [
    0x00500093, 0x00300113, 0x002081B3, 0x40208233, 0x0020F2B3, 0x0020E333,
    0x20000537, 0x00352023, 0x00108663, 0xDEADC3B7, 0xDEADC3B7, 0x00100393,
    0x12345437, 0x00001497, 0xFFB00593, 0x02800613, 0x008006EF, 0x00100713,
    0x0000006F,
]  # fmt: skip

# Programs the mini assembler and GNU as must encode identically. GNU as rejects
# the others: a label as an ADDI immediate (phase10, interrupt) and a label
# difference as a JALR offset (phase7).
GNU_COMPATIBLE = [
    "phase5", "phase6", "system", "final", "bringup_1_gpio", "bringup_2_uart", "bringup_3_dma",
]  # fmt: skip


def program_source(name: str) -> str:
    return (REPO / "sw" / "programs" / (name + ".s")).read_text()


def test_phase5_program_matches_its_reference_encoding() -> None:
    image, listing, labels = assemble(program_source("phase5"))

    assert [image[4 * i] for i in range(len(PHASE5_WORDS))] == PHASE5_WORDS
    assert labels == {"t2c": 0x2C, "t48": 0x48}
    assert listing[0] == (0, 0x00500093, "addi x1, x0, 5")


def test_labels_expressions_org_and_word() -> None:
    assembly = assemble(
        """
        start:  jal   x0, end          # forward reference
                .word 0xDEADBEEF
                .org  0x20
        data:   .word end - start
        end:    addi  x1, x0, data+4
        """
    )

    assert assembly.labels == {"start": 0, "data": 0x20, "end": 0x24}
    assert assembly.image[4] == 0xDEADBEEF
    assert assembly.image[0x20] == 0x24
    assert assembly.image[0x24] == 0x02400093  # addi x1, x0, 0x24
    assert sorted(assembly.image) == [0, 4, 0x20, 0x24]


@pytest.mark.parametrize(
    ("line", "word"),
    [
        ("sub x4, x1, x2", 0x40208233),
        ("mulhsu x5, x6, x7", 0x027322B3),
        ("remu x5, x6, x7", 0x027372B3),
        ("srai x5, x6, 31", 0x41F35293),
        ("lbu x4, 1(x31)", 0x001FC203),
        ("sh x15, 10(x31)", 0x00FF9523),
        ("bgeu x1, x2, 0", 0x0020F063),
        ("jalr x22, 12(x21)", 0x00CA8B67),
        ("auipc x9, 0x1", 0x00001497),
        ("csrrw x0, mtvec, x1", 0x30509073),
        ("csrrsi x0, mstatus, 8", 0x30046073),
        ("csrrs x0, 0x7C0, x0", 0x7C002073),
        ("ecall", 0x00000073),
        ("ebreak", 0x00100073),
        ("mret", 0x30200073),
        ("wfi", 0x10500073),
        ("nop", 0x00000013),
    ],
)
def test_single_instruction_encodings(line: str, word: int) -> None:
    assert assemble(line).image[0] == word


@pytest.mark.parametrize(
    ("line", "message"),
    [
        ("add x1, x2", "add"),  # formerly an IndexError
        ("lw x1", "lw"),
        ("jal", "jal"),
        ("csrrw x1, mtvec", "csrrw"),
        (".word", ".word"),
        ("frobnicate x1", "unknown mnemonic"),
        ("add x1, x2, x32", "bad register"),
        ("add x1, x2, y3", "bad register"),
        ("addi x1, x0, 2048", "out of range"),
        ("slli x1, x1, 32", "out of range"),
        ("lw x1, 4[x2]", "bad memory operand"),
        ("addi x1, x0, nowhere", "bad value"),
        ("csrrwi x1, mscratch, 32", "out of range"),
    ],
)
def test_errors_are_asm_errors_with_the_source_line(line: str, message: str) -> None:
    with pytest.raises(AsmError) as error:
        assemble("nop\n" + line)

    text = str(error.value)
    assert message in text
    assert "0x0004" in text, "the address of the offending line is reported"


def test_overlapping_code_is_rejected() -> None:
    with pytest.raises(AsmError, match="overlapping"):
        assemble("nop\n.org 0\nnop")


@needs_toolchain
@pytest.mark.parametrize("name", GNU_COMPATIBLE)
def test_directed_programs_match_gnu_as(name: str, tmp_path: Path) -> None:
    """The mini assembler is checked against an independent one."""
    assert TOOLCHAIN_BIN is not None
    prefix = str(TOOLCHAIN_BIN / "riscv-none-elf-")
    source = tmp_path / "p.s"
    source.write_text(program_source(name))
    obj, elf, binary = tmp_path / "p.o", tmp_path / "p.elf", tmp_path / "p.bin"
    for command in (
        [prefix + "as", "-march=rv32im_zicsr", "-mabi=ilp32", "-mno-relax", "-o", str(obj),
         str(source)],
        [prefix + "ld", "-m", "elf32lriscv", "-Ttext=0", "-e", "0", "-o", str(elf), str(obj)],
        [prefix + "objcopy", "-O", "binary", "-j", ".text", str(elf), str(binary)],
    ):  # fmt: skip
        subprocess.run(command, check=True, capture_output=True)
    data = binary.read_bytes()
    gnu = {a: int.from_bytes(data[a : a + 4], "little") for a in range(0, len(data), 4)}

    image = assemble(program_source(name)).image

    assert {a: w for a, w in gnu.items() if w or a in image} == image
