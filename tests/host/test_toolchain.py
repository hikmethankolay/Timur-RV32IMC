"""Finding and running the RISC-V GNU toolchain (timur_tools.toolchain)."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

from timur_tools.toolchain import (
    ENV_PREFIX,
    Toolchain,
    ToolchainError,
    find_toolchain,
    require_toolchain,
)


def make_fake_toolchain(bin_dir: Path, version: str = "14.2.0") -> None:
    """A directory with a riscv-none-elf-gcc that only answers -dumpversion."""
    bin_dir.mkdir(parents=True)
    script = bin_dir / "riscv-none-elf-gcc"
    script.write_text("#!/bin/sh\necho %s\n" % version)
    script.chmod(0o755)


@pytest.fixture
def clean_environment(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> Path:
    """No toolchain on PATH or in the environment; returns an empty project root."""
    monkeypatch.delenv(ENV_PREFIX, raising=False)
    monkeypatch.setenv("PATH", str(tmp_path / "empty"))
    return tmp_path


def test_no_toolchain_is_none_or_a_clear_error(clean_environment: Path) -> None:
    assert find_toolchain(clean_environment) is None
    with pytest.raises(ToolchainError, match="riscv-none-elf-gcc not found"):
        require_toolchain(clean_environment)


@pytest.mark.skipif(sys.platform == "win32", reason="uses a shell script as the fake compiler")
def test_search_order_is_argument_environment_path_tools(
    clean_environment: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = clean_environment
    tools = root / ".tools" / "xpack-riscv-none-elf-gcc-14.2.0-3" / "bin"
    make_fake_toolchain(tools)
    found = find_toolchain(root)
    assert found is not None and found.prefix == str(tools / "riscv-none-elf-")

    on_path = root / "onpath"
    make_fake_toolchain(on_path)
    monkeypatch.setenv("PATH", str(on_path))
    found = find_toolchain(root)
    assert found is not None and found.prefix == "riscv-none-elf-"

    monkeypatch.setenv(ENV_PREFIX, "/opt/env/riscv-none-elf-")
    found = find_toolchain(root)
    assert found is not None and found.prefix == "/opt/env/riscv-none-elf-"

    found = find_toolchain(root, prefix="/opt/arg/riscv32-")
    assert found is not None and found.prefix == "/opt/arg/riscv32-"


@pytest.mark.skipif(sys.platform == "win32", reason="uses a shell script as the fake compiler")
def test_newest_unpacked_toolchain_wins(clean_environment: Path) -> None:
    for version in ("9.3.0-1", "14.2.0-3", "13.2.0-2"):
        make_fake_toolchain(
            clean_environment / ".tools" / ("xpack-riscv-none-elf-gcc-" + version) / "bin"
        )

    found = find_toolchain(clean_environment)

    assert found is not None and "gcc-14.2.0-3" in found.prefix


@pytest.mark.skipif(sys.platform == "win32", reason="uses a shell script as the fake compiler")
def test_run_returns_stdout_and_reports_failures(tmp_path: Path) -> None:
    make_fake_toolchain(tmp_path / "bin", version="1.2.3")
    failing = tmp_path / "bin" / "riscv-none-elf-objdump"
    failing.write_text("#!/bin/sh\necho 'no such file' >&2\nexit 3\n")
    failing.chmod(0o755)
    toolchain = Toolchain(str(tmp_path / "bin" / "riscv-none-elf-"))

    assert toolchain.gcc_version() == "1.2.3"
    with pytest.raises(ToolchainError) as error:
        toolchain.run("objdump", "-h", "missing.elf")
    assert "objdump -h missing.elf" in str(error.value)
    assert "no such file" in str(error.value)


def test_a_missing_tool_is_a_toolchain_error(tmp_path: Path) -> None:
    with pytest.raises(ToolchainError, match="cannot run"):
        Toolchain(str(tmp_path / "nothing-")).run("gcc", "--version")
