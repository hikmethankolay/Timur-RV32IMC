"""Building C programs (timur_tools.builder, sw/build.py, sw/bin2mem.py)."""

from __future__ import annotations

from pathlib import Path

import pytest

import bin2mem
import build
from timur_tools import builder, cli
from timur_tools.builder import BuildError, Section, check_layout
from timur_tools.paths import Project

from conftest import REPO, TOOLCHAIN_BIN, needs_toolchain

TEXT = Section(".text", 0x100, 0, 0, "CONTENTS, ALLOC, LOAD, READONLY, CODE")
DATA = Section(".data", 0x10, 0x20000000, 0x100, "CONTENTS, ALLOC, LOAD, DATA")
BSS = Section(".bss", 0x40, 0x20000010, 0x110, "ALLOC")


def test_a_valid_layout_passes() -> None:
    check_layout([TEXT, DATA, BSS])


@pytest.mark.parametrize(
    ("sections", "message"),
    [
        ([DATA], r"\.text does not start at address 0"),
        ([Section(".text", 4, 4, 4, "ALLOC, LOAD")], r"\.text does not start"),
        ([TEXT, Section(".big", 0x100, 0xFF80, 0xFF80, "ALLOC, LOAD")], "outside the 64 KB ROM"),
        ([TEXT, Section(".far", 4, 0x30000000, 0x200, "ALLOC, LOAD")], "outside RAM"),
        ([TEXT, Section(".data", 4, 0x200, 0x200, "ALLOC, LOAD")], "must run in RAM"),
    ],
)
def test_bad_layouts_are_rejected(sections: list[Section], message: str) -> None:
    with pytest.raises(BuildError, match=message):
        check_layout(sections)


def test_an_unknown_isa_is_rejected() -> None:
    with pytest.raises(BuildError, match="unsupported -march=rv32gc"):
        builder.build([REPO / "sw" / "tests" / "hello.c"], march="rv32gc")


@pytest.fixture
def toolchain_env(monkeypatch: pytest.MonkeyPatch) -> None:
    assert TOOLCHAIN_BIN is not None
    monkeypatch.setenv("TIMUR_TOOLCHAIN_PREFIX", str(TOOLCHAIN_BIN / "riscv-none-elf-"))


@needs_toolchain
@pytest.mark.usefixtures("toolchain_env")
@pytest.mark.parametrize("march", sorted(builder.MARCHES))
def test_build_hello(tmp_path: Path, march: str) -> None:
    result = builder.build([REPO / "sw" / "tests" / "hello.c"], march, tmp_path, "hi.there")

    assert result.multilib == builder.MARCHES[march]
    assert result.elf == tmp_path / "hi.there.elf"
    assert result.size_bytes == result.binary.stat().st_size
    assert result.symbol("_start") == 0
    assert result.symbol("_stack_top") == 0x20010000
    assert (tmp_path / "hi.there_lo.mif").exists()
    assert (tmp_path / "hi.there.map").exists()
    with pytest.raises(BuildError, match="no symbol not_there"):
        result.symbol("not_there")


@needs_toolchain
@pytest.mark.usefixtures("toolchain_env")
def test_build_script_install_and_stack_size(
    project: Path, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    status = build.main(
        ["--root", str(project), "--out", str(tmp_path), "--stack-size", "4096", "--install",
         "--extra=-DUNUSED", str(project / "sw" / "tests" / "hello.c")]
    )  # fmt: skip

    assert status == 0
    out = capsys.readouterr().out
    assert "stack 4096 bytes below 20010000" in out
    assert "installed as rom.hex" in out
    assert (project / "rom.hex").read_text() == (tmp_path / "hello.hex").read_text()


@needs_toolchain
@pytest.mark.usefixtures("toolchain_env")
def test_a_compile_error_is_a_toolchain_error(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    bad = tmp_path / "bad.c"
    bad.write_text("int main(void) { return undeclared; }\n")

    status = cli.run(build.main, "build", ["--out", str(tmp_path / "out"), str(bad)])

    assert status == 1
    assert "build: command failed" in capsys.readouterr().err


def test_bin2mem_main(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    binary = tmp_path / "p.bin"
    binary.write_bytes(bytes(8))

    assert bin2mem.main([str(binary), "-o", str(tmp_path / "p"), "--title", "t"]) == 0
    assert "(2 of 16384 words used)" in capsys.readouterr().out


def test_project_must_be_a_timur_tree(tmp_path: Path) -> None:
    with pytest.raises(Exception, match="is not a Timur project directory"):
        Project.at(tmp_path)


def test_cli_reports_file_errors(capsys: pytest.CaptureFixture[str], tmp_path: Path) -> None:
    status = cli.run(bin2mem.main, "bin2mem", [str(tmp_path / "missing.bin")])

    assert status == 1
    assert capsys.readouterr().err.startswith("bin2mem: [Errno 2]")
