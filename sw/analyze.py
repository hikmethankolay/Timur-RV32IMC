#!/usr/bin/env python3
"""Static analysis of the Timur C runtime and the C test programs.

  gcc -fanalyzer  the runtime and sw/tests/*.c, with the runtime's strict
                  warnings as errors (GCC's own analyzer: always available)
  assembler       the runtime's .S files with --fatal-warnings
  clang-tidy      the runtime, with the checks of .clang-tidy (if installed)
  cppcheck        the runtime (if installed)

The test programs are analysed by GCC only: they call the C library, recurse and
use fixed addresses on purpose, which clang-tidy's style checks report.

Usage:  python3 sw/analyze.py [--root DIR]      (make analyze)
Exits with 1 if any tool reports a finding.
"""

from __future__ import annotations

import argparse
import logging
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable, Sequence
from pathlib import Path

from timur_tools import builder, cli
from timur_tools.paths import Project
from timur_tools.toolchain import Toolchain, ToolchainError, require_toolchain

LOG = logging.getLogger("timur.analyze")

MARCH = builder.DEFAULT_MARCH


def find_tool(name: str) -> str | None:
    """A host tool on PATH or next to this Python (a virtual environment's bin/)."""
    return shutil.which(name) or shutil.which(name, path=str(Path(sys.executable).parent))


def c_sources(project: Project) -> tuple[list[Path], list[Path]]:
    """(runtime .c files, test program .c files)."""
    return sorted(project.runtime.glob("*.c")), sorted(project.tests.glob("*.c"))


def gcc_analyzer(project: Project, toolchain: Toolchain) -> bool:
    """GCC's static analyzer and the strict warnings; True if clean."""
    flags = builder.compile_flags(project, MARCH, "-O2")
    runtime, tests = c_sources(project)
    checks = [
        [*builder.STRICT_WARNINGS, "-Werror", "-fanalyzer", str(source)]
        for source in [*runtime, *tests]
    ]
    checks += [
        ["-Wa,--fatal-warnings", str(source)] for source in sorted(project.runtime.glob("*.S"))
    ]
    clean = True
    with tempfile.TemporaryDirectory() as tmp:
        for options in checks:
            try:
                toolchain.run("gcc", *flags, "-c", "-o", str(Path(tmp) / "out.o"), *options)
            except ToolchainError as error:
                print(error, file=sys.stderr)
                clean = False
    return clean


def cross_include_flags(toolchain: Toolchain) -> list[str]:
    """Header search paths of the cross compiler (newlib-nano first), for host tools."""
    sysroot = Path(toolchain.run("gcc", "-print-sysroot").strip())
    internal = Path(toolchain.run("gcc", "-print-file-name=include").strip())
    return [
        "-nostdinc",
        "-isystem", str(internal),
        "-isystem", str(sysroot / "include" / "newlib-nano"),
        "-isystem", str(sysroot / "include"),
    ]  # fmt: skip


def clang_tidy(project: Project, toolchain: Toolchain, tool: str) -> bool:
    """clang-tidy with the project's .clang-tidy; True if clean."""
    runtime, _ = c_sources(project)
    command = [
        tool, "--quiet", *map(str, runtime), "--",
        "--target=riscv32-unknown-elf", "-march=" + MARCH, "-mabi=" + builder.ABI,
        "-std=" + builder.C_STANDARD, *cross_include_flags(toolchain),
        "-I", str(project.include),
    ]  # fmt: skip
    return _run_host_tool(command)


def cppcheck(project: Project, tool: str) -> bool:
    """cppcheck on the runtime; True if clean."""
    runtime, _ = c_sources(project)
    command = [
        tool, "--std=c11", "--enable=warning,style,performance,portability",
        "--error-exitcode=1", "--inline-suppr", "--quiet",
        "--suppress=missingIncludeSystem", "-I", str(project.include),
        "-D__riscv", "-D__riscv_xlen=32", *map(str, runtime),
    ]  # fmt: skip
    return _run_host_tool(command)


def _run_host_tool(command: list[str]) -> bool:
    LOG.debug("running: %s", " ".join(command))
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    output = (result.stdout + result.stderr).strip()
    if output:
        print(output, file=sys.stderr)
    return result.returncode == 0


def main(argv: Sequence[str] | None = None) -> int:
    """Run every available analysis; returns 1 if any reports a finding."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    cli.add_common_arguments(parser)
    args = parser.parse_args(argv)
    project = cli.project_from(args)
    toolchain = require_toolchain(project.root)

    results = {"gcc -fanalyzer and assembler": gcc_analyzer(project, toolchain)}
    optional: dict[str, Callable[[str], bool]] = {
        "clang-tidy": lambda tool: clang_tidy(project, toolchain, tool),
        "cppcheck": lambda tool: cppcheck(project, tool),
    }
    for name, analysis in optional.items():
        tool = find_tool(name)
        if tool is None:
            print("%-30s not installed: skipped" % name)
            continue
        results[name] = analysis(tool)
    for name, clean in results.items():
        print("%-30s %s" % (name, "clean" if clean else "FINDINGS (see above)"))
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(cli.run(main, "analyze"))
