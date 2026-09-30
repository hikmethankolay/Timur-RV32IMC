"""The generators, called in-process on a scratch copy of the project."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from pathlib import Path

import pytest

import gen_decompressor_vectors
import gen_soc_tests
import gen_sw_tests
import gen_unit_vectors
from timur_tools import cli
from timur_tools.errors import GenerationError
from timur_tools.model import TimurModel
from timur_tools.paths import Project

from conftest import (
    TOOLCHAIN_BIN,
    assert_matches_repository,
    environment,
    needs_pinned_toolchain,
)

Main = Callable[[Sequence[str] | None], int]


@pytest.fixture
def no_toolchain(monkeypatch: pytest.MonkeyPatch) -> None:
    for name, value in environment(with_toolchain=False).items():
        monkeypatch.setenv(name, value)
    monkeypatch.delenv("TIMUR_TOOLCHAIN_PREFIX", raising=False)


@pytest.fixture
def pinned_toolchain(monkeypatch: pytest.MonkeyPatch) -> None:
    assert TOOLCHAIN_BIN is not None
    monkeypatch.setenv("TIMUR_TOOLCHAIN_PREFIX", str(TOOLCHAIN_BIN / "riscv-none-elf-"))


def run_main(main: Main, project: Path, *args: str) -> None:
    assert main(["--root", str(project), *args]) == 0


@pytest.mark.usefixtures("no_toolchain")
def test_all_generators_without_toolchain(
    project: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    run_main(gen_unit_vectors.main, project)
    run_main(gen_soc_tests.main, project)
    run_main(gen_sw_tests.main, project)

    assert_matches_repository(project)
    out = capsys.readouterr().out
    assert "random program: seed 20260926" in out
    assert "selftest  rv32imc_zicsr" in out


@needs_pinned_toolchain
@pytest.mark.usefixtures("pinned_toolchain")
def test_all_generators_with_toolchain(project: Path, capsys: pytest.CaptureFixture[str]) -> None:
    run_main(gen_decompressor_vectors.main, project)
    run_main(gen_soc_tests.main, project)
    run_main(gen_sw_tests.main, project)

    assert_matches_repository(project)
    assert "49152 encodings, " in capsys.readouterr().out


@pytest.mark.usefixtures("no_toolchain")
def test_another_seed_gives_another_random_program(project: Path) -> None:
    vectors = project / "vectors" / "timur_soc_vectors.txt"
    before = vectors.read_text()

    run_main(gen_soc_tests.main, project, "--seed", "7", "--length", "50")

    after = vectors.read_text()
    assert after != before
    assert "random seed 7)" in after


def test_decompressor_vectors_need_the_toolchain(
    project: Path, no_toolchain: None, capsys: pytest.CaptureFixture[str]
) -> None:
    status = cli.run(gen_decompressor_vectors.main, "gen", ["--root", str(project)])

    assert status == 1
    assert "riscv-none-elf-gcc not found" in capsys.readouterr().err


def test_a_model_that_disagrees_with_the_expectation_is_reported(project: Path) -> None:
    source = project / "sw" / "programs" / "phase5.s"
    source.write_text(source.read_text().replace("addi  x2, x0, 3", "addi  x2, x0, 4"))

    with pytest.raises(GenerationError, match="reference encoding"):
        gen_soc_tests.generate(Project.at(project), 1, 10, toolchain=None)


def test_a_failing_c_program_is_reported(project: Path) -> None:
    test = gen_sw_tests.TESTS[0]
    image = gen_sw_tests.build_image(Project.at(project), None, test.name, "rv32imc_zicsr")
    wrong = gen_sw_tests.SwTest(**{**test.__dict__, "leds": 0x201})

    with pytest.raises(GenerationError, match="ends with LEDs 200, expected 201"):
        gen_sw_tests.run_on_model(wrong, "rv32imc_zicsr", image)


def test_decompressor_reserved_rules() -> None:
    assert gen_decompressor_vectors.reserved(0x6101)  # C.ADDI16SP with nzimm = 0
    assert gen_decompressor_vectors.reserved(0x9005)  # C.SRLI with shamt[5] = 1
    assert gen_decompressor_vectors.reserved(0x1002)  # C.SLLI with shamt[5] = 1
    assert not gen_decompressor_vectors.reserved(0x0505)  # C.ADDI x10, 1
    assert gen_decompressor_vectors.expansion("c.j", "10 <x>", 0x4) == "jal zero,.+12"
    assert gen_decompressor_vectors.expansion("c.frob", "", 0) is None


def test_unit_models() -> None:
    model = gen_unit_vectors.CsrModel()
    inputs = gen_unit_vectors.CsrInputs(addr=gen_unit_vectors.MISA)
    assert model.outputs(inputs)[:2] == (0x40001104, 0)
    trap = gen_unit_vectors.TrapInputs(ebreak=1, pc=0x1234)
    assert gen_unit_vectors.trap_model(trap) == (3, 0x1234)
    assert gen_unit_vectors.trap_model(gen_unit_vectors.TrapInputs(valid=0, ecall=1)) is None


def test_dma_and_interrupt_programs_on_the_model(project: Path) -> None:
    """The interrupt program is checked by hand-written values in the vector file;
    the model must at least take the interrupt once and halt."""
    assembly = gen_soc_tests.assemble_program(Project.at(project), "interrupt")

    model = TimurModel(assembly.image, interrupts=True).run()

    assert [cause for cause, _, _ in model.traps] == [0x8000000B]
    assert model.x[26] == 1
