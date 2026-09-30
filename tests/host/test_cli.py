"""The command-line entry points in sw/, run the way a user runs them."""

from __future__ import annotations

from pathlib import Path

import pytest

from conftest import REPO, assert_matches_repository, needs_toolchain, run_script

HELLO = str(REPO / "sw" / "tests" / "hello.c")


@pytest.mark.parametrize("script", ["gen_unit_vectors.py", "gen_soc_tests.py"])
def test_generators_do_not_depend_on_the_working_directory(
    project: Path, tmp_path: Path, script: str
) -> None:
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()

    result = run_script(project, script, with_toolchain=False, cwd=elsewhere)

    assert result.returncode == 0, result.stderr
    assert not list(elsewhere.iterdir()), "files were written into the working directory"
    assert_matches_repository(project)


def test_root_option_selects_the_project_to_generate_into(project: Path, tmp_path: Path) -> None:
    (project / "vectors" / "csr_file_vectors.txt").unlink()
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()

    # the repository's script, pointed at the scratch copy
    result = run_script(
        REPO, "gen_unit_vectors.py", "--root", str(project), with_toolchain=False, cwd=elsewhere
    )

    assert result.returncode == 0, result.stderr
    assert_matches_repository(project)


@pytest.mark.parametrize("size", ["-5", "0", "65536", "lots"])
def test_build_rejects_an_impossible_stack_size(project: Path, size: str) -> None:
    result = run_script(project, "build.py", "--stack-size", size, HELLO, with_toolchain=False)

    assert result.returncode == 2
    assert "--stack-size" in result.stderr


def test_build_rejects_an_unknown_optimisation_level(project: Path) -> None:
    result = run_script(project, "build.py", "-O", "banana", HELLO, with_toolchain=False)

    assert result.returncode == 2
    assert "-O" in result.stderr


def test_build_without_toolchain_reports_one_line(project: Path) -> None:
    result = run_script(project, "build.py", HELLO, with_toolchain=False)

    assert result.returncode == 1
    assert "riscv-none-elf-gcc not found" in result.stderr
    assert "Traceback" not in result.stderr


def test_missing_committed_image_is_reported_without_a_traceback(project: Path) -> None:
    (project / "vectors" / "timur_sw_hello_rv32im.hex").unlink()

    result = run_script(project, "gen_sw_tests.py", with_toolchain=False)

    assert result.returncode == 1
    assert "Traceback" not in result.stderr
    assert "timur_sw_hello_rv32im.hex" in result.stderr


@needs_toolchain
def test_run_model_reports_a_missing_program_without_a_traceback(project: Path) -> None:
    result = run_script(project, "run_model.py", "no_such_program.elf", with_toolchain=True)

    assert result.returncode == 1
    assert "Traceback" not in result.stderr
    assert "no_such_program" in result.stderr


@pytest.mark.parametrize("option", ["--max", "--cycles"])
def test_run_model_rejects_non_positive_limits(project: Path, option: str) -> None:
    result = run_script(project, "run_model.py", "x.elf", option, "0", with_toolchain=False)

    assert result.returncode == 2
    assert option in result.stderr


def test_bin2mem_rejects_an_oversized_binary(project: Path, tmp_path: Path) -> None:
    binary = tmp_path / "big.bin"
    binary.write_bytes(bytes(0x10004))

    result = run_script(
        project, "bin2mem.py", str(binary), "-o", str(tmp_path / "big"), with_toolchain=False
    )

    assert result.returncode == 1
    assert "larger than the 65536-byte ROM" in result.stderr
    assert not (tmp_path / "big.hex").exists()


def test_bin2mem_writes_the_word_image_and_both_banks(project: Path, tmp_path: Path) -> None:
    binary = tmp_path / "p.bin"
    binary.write_bytes(bytes.fromhex("78563412efcdab"))

    result = run_script(
        project, "bin2mem.py", str(binary), "-o", str(tmp_path / "p"), with_toolchain=False
    )

    assert result.returncode == 0, result.stderr
    assert (tmp_path / "p.hex").read_text() == "12345678\n00ABCDEF\n"
    assert (tmp_path / "p_lo.hex").read_text() == "5678\nCDEF\n"
    assert (tmp_path / "p_hi.hex").read_text() == "1234\n00AB\n"
    mif = (tmp_path / "p_hi.mif").read_text()
    assert "    0001 : 00AB;\n    [0002..3FFF] : 0000;\nEND;\n" in mif
