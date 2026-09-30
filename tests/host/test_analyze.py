"""sw/analyze.py: every analysis reports a planted defect and passes clean code."""

from __future__ import annotations

from pathlib import Path

import pytest

import analyze
from timur_tools.errors import TimurError
from timur_tools.paths import Project
from timur_tools.toolchain import Toolchain

from conftest import TOOLCHAIN_BIN, needs_toolchain

# Reads through a null pointer: every analyser must report it.
DEFECT = """
#include <stddef.h>
int timur_defect(int *p);
int timur_defect(int *p)
{
    p = NULL;
    return *p;
}
"""


@pytest.fixture
def toolchain() -> Toolchain:
    assert TOOLCHAIN_BIN is not None
    return Toolchain(str(TOOLCHAIN_BIN / "riscv-none-elf-"))


@pytest.fixture
def flawed(project: Path) -> Project:
    """The project copy with a defect planted in the runtime."""
    (project / "sw" / "runtime" / "defect.c").write_text(DEFECT)
    return Project.at(project)


@needs_toolchain
def test_gcc_analyzer_passes_the_runtime(project: Path, toolchain: Toolchain) -> None:
    assert analyze.gcc_analyzer(Project.at(project), toolchain)


@needs_toolchain
def test_gcc_analyzer_reports_a_defect(
    flawed: Project, toolchain: Toolchain, capsys: pytest.CaptureFixture[str]
) -> None:
    assert not analyze.gcc_analyzer(flawed, toolchain)
    assert "defect.c" in capsys.readouterr().err


@needs_toolchain
def test_gcc_analyzer_reports_an_assembler_warning(project: Path, toolchain: Toolchain) -> None:
    (project / "sw" / "runtime" / "warn.S").write_text('    .text\n    .warning "planted"\n')

    assert not analyze.gcc_analyzer(Project.at(project), toolchain)


@needs_toolchain
@pytest.mark.parametrize("name", ["clang-tidy", "cppcheck"])
def test_optional_analysers(
    name: str,
    project: Path,
    flawed: Project,
    toolchain: Toolchain,
    capsys: pytest.CaptureFixture[str],
) -> None:
    tool = analyze.find_tool(name)
    if tool is None:
        pytest.skip("%s is not installed" % name)

    def check(target: Project) -> bool:
        if name == "clang-tidy":
            return analyze.clang_tidy(target, toolchain, tool)
        return analyze.cppcheck(target, tool)

    assert check(flawed) is False
    assert "defect.c" in capsys.readouterr().err, "the failure must come from the defect"
    (flawed.runtime / "defect.c").unlink()
    assert check(Project.at(project)) is True


@needs_toolchain
def test_main_fails_if_any_analysis_fails(
    flawed: Project, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    assert TOOLCHAIN_BIN is not None
    monkeypatch.setenv("TIMUR_TOOLCHAIN_PREFIX", str(TOOLCHAIN_BIN / "riscv-none-elf-"))
    monkeypatch.setattr(analyze, "find_tool", lambda name: None)

    assert analyze.main(["--root", str(flawed.root)]) == 1
    out = capsys.readouterr().out
    assert "FINDINGS" in out
    assert "clang-tidy                     not installed: skipped" in out


@needs_toolchain
def test_clang_tidy_needs_its_configuration(project: Path, toolchain: Toolchain) -> None:
    """Without .clang-tidy, clang-tidy fails for a reason that is not a finding."""
    (project / ".clang-tidy").unlink()

    with pytest.raises(TimurError, match=r"\.clang-tidy is missing"):
        analyze.clang_tidy(Project.at(project), toolchain, "clang-tidy")
