"""Vector-file writing (timur_tools.vectors) and the model runner (sw/run_model.py)."""

from __future__ import annotations

from pathlib import Path

import pytest

import run_model
from timur_tools.asm import assemble
from timur_tools.errors import TimurError
from timur_tools.model import TimurModel
from timur_tools.vectors import Vectors, model_checks, prog_cycle_budget

from conftest import REPO, TOOLCHAIN_BIN, needs_toolchain


def test_cycle_budget() -> None:
    # 20 cycles per instruction, three frame times per byte, 20000 cycles of slack
    assert prog_cycle_budget(100, 0, 0, 16) == 22000
    assert prog_cycle_budget(0, 2, 1, 16) == 3 * 10 * 16 * (2 + 3) + 20000


def test_model_checks_leave_out_timing_dependent_values() -> None:
    program = """
        lui   x31, 0x20000
        csrrs x5, cycle, x0        # tainted
        sw    x5, 0(x31)           # tainted RAM word
        addi  x6, x0, 7
        sw    x6, 4(x31)
halt:   jal   x0, halt
    """
    model = TimurModel(assemble(program).image).run()
    vec = Vectors()

    model_checks(vec, model)

    assert "REG 6 00000007" in vec.lines
    assert not any(line.startswith("REG 5 ") for line in vec.lines)
    assert "RAM 20000004 00000007" in vec.lines
    assert not any(line.startswith("RAM 20000000") for line in vec.lines)
    assert not any(line.startswith("RAMNZ") for line in vec.lines)
    assert vec.lines[-7:] == ["RETIRED 6"] + ["TRACE %08X" % (4 * i) for i in range(6)]


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("12 30\\rTimur\\r", b"12 30\rTimur\r"),
        ("\\x41\\101\\\\", b"AA\\"),
        ("plain", b"plain"),
        # \u, \U and \N are not escapes here, as with the old codecs.escape_decode
        ("\\u0041", b"\\u0041"),
        ("\\N{DIGIT ONE}", b"\\N{DIGIT ONE}"),
        ("\\\\u", b"\\u"),
        ("é", "é".encode()),
    ],
)
def test_console_input_escapes(text: str, expected: bytes) -> None:
    assert run_model.parse_console_input(text) == expected


def test_console_input_rejects_a_bad_escape() -> None:
    with pytest.raises(TimurError, match="--input"):
        run_model.parse_console_input("\\x4")


@pytest.fixture
def hello_elf(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    from timur_tools import builder

    assert TOOLCHAIN_BIN is not None
    monkeypatch.setenv("TIMUR_TOOLCHAIN_PREFIX", str(TOOLCHAIN_BIN / "riscv-none-elf-"))
    monkeypatch.chdir(tmp_path)
    builder.build([REPO / "sw" / "tests" / "hello.c"], out_dir=Path("p"))
    return Path("p") / "hello.elf"


@needs_toolchain
def test_run_model_writes_an_exact_vector_file(
    hello_elf: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert run_model.main([str(hello_elf), "--vectors", "v.txt"]) == 0

    out = capsys.readouterr().out
    assert "Hello from Timur RV32IMC!" in out
    assert "LEDs 200  (0x200 | exit code 0)" in out
    lines = Path("v.txt").read_text().splitlines()
    assert lines[1].startswith("PROG p/hello.hex ")
    assert lines[2:4] == ["UARTTEXT v.out", "LEDS 200"]
    assert lines[4].startswith("DIVS ")
    assert Path("v.out").read_bytes().startswith(b"Hello from Timur RV32IMC!\r\n")


@needs_toolchain
def test_run_model_stops_early_and_writes_a_show_only_vector_file(
    hello_elf: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert (
        run_model.main([str(hello_elf), "--max", "10", "--vectors", "v.txt", "--cycles", "99"]) == 0
    )

    assert "still running after 10 instructions" in capsys.readouterr().out
    assert Path("v.txt").read_text().splitlines()[1:] == [
        "PROG p/hello.hex 99 FFFFFFFF 0",
        "UARTSHOW",
    ]


@needs_toolchain
def test_run_model_rejects_paths_the_testbench_cannot_open(hello_elf: Path) -> None:
    with pytest.raises(TimurError, match="longer than the testbench's 63 characters"):
        run_model.main([str(hello_elf), "--vectors", "x" * 70 + ".txt"])
