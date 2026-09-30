"""Shared fixtures for the host-side tests of the Timur software tools.

The tests never write into the repository: generators run in a scratch copy of
the project (``sw/``, ``vectors/`` and the ROM images in the project root).
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]

#: The compiler release the committed ROM images in vectors/ were built with.
#: Another release may generate different code, so byte-for-byte comparisons of
#: compiled images are only meaningful with this one.
PINNED_GCC_VERSION = "14.2.0"

ROOT_IMAGES = ("rom.hex", "rom_lo.hex", "rom_hi.hex", "rom_lo.mif", "rom_hi.mif")
ROOT_CONFIG = (".clang-tidy", ".clang-format")
GENERATED_DIRS = ("vectors", "sw/bringup")


def _toolchain_bin() -> Path | None:
    """Directory holding riscv-none-elf-gcc: on PATH, or unpacked in .tools/."""
    on_path = shutil.which("riscv-none-elf-gcc")
    if on_path:
        return Path(on_path).parent
    candidates = sorted((REPO / ".tools").glob("xpack-riscv-none-elf-gcc-*/bin"))
    return candidates[-1] if candidates else None


def _gcc_version(bin_dir: Path) -> str:
    out = subprocess.run(
        [str(bin_dir / "riscv-none-elf-gcc"), "-dumpversion"],
        capture_output=True,
        text=True,
        check=True,
    )
    return out.stdout.strip()


TOOLCHAIN_BIN = _toolchain_bin()
HAVE_PINNED_TOOLCHAIN = (
    TOOLCHAIN_BIN is not None and _gcc_version(TOOLCHAIN_BIN) == PINNED_GCC_VERSION
)

needs_toolchain = pytest.mark.skipif(
    TOOLCHAIN_BIN is None, reason="the RISC-V GNU toolchain is not installed"
)
needs_pinned_toolchain = pytest.mark.skipif(
    not HAVE_PINNED_TOOLCHAIN,
    reason="byte-for-byte image comparison needs riscv-none-elf-gcc %s" % PINNED_GCC_VERSION,
)


def copy_project(destination: Path) -> Path:
    """Copy the parts of the project the generators read and write."""
    shutil.copytree(
        REPO / "sw",
        destination / "sw",
        ignore=shutil.ignore_patterns("build", "__pycache__", "*.pyc"),
    )
    shutil.copytree(REPO / "vectors", destination / "vectors")
    for name in ROOT_IMAGES + ROOT_CONFIG:
        shutil.copy2(REPO / name, destination / name)
    return destination


def environment(with_toolchain: bool) -> dict[str, str]:
    """Process environment with the toolchain on PATH, or guaranteed absent."""
    env = dict(os.environ)
    env.pop("TIMUR_ROOT", None)
    env.pop("TIMUR_TOOLCHAIN_PREFIX", None)
    entries = [
        entry
        for entry in env.get("PATH", "").split(os.pathsep)
        if entry and not (Path(entry) / "riscv-none-elf-gcc").exists()
    ]
    if with_toolchain:
        assert TOOLCHAIN_BIN is not None
        entries.insert(0, str(TOOLCHAIN_BIN))
    env["PATH"] = os.pathsep.join(entries)
    return env


def run_script(
    project: Path,
    script: str,
    *args: str,
    with_toolchain: bool,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run sw/<script> of the project copy the way a user would."""
    return subprocess.run(
        [sys.executable, str(project / "sw" / script), *args],
        cwd=str(cwd or project),
        env=environment(with_toolchain),
        capture_output=True,
        text=True,
        check=False,
    )


def generated_files(root: Path) -> dict[str, bytes]:
    """Contents of every generated file below root, keyed by its relative path."""
    files = {name: (root / name).read_bytes() for name in ROOT_IMAGES if (root / name).exists()}
    for directory in GENERATED_DIRS:
        for path in sorted((root / directory).rglob("*")):
            if path.is_file():
                files[path.relative_to(root).as_posix()] = path.read_bytes()
    return files


def assert_matches_repository(project: Path) -> None:
    """Every generated file of the copy equals the committed one, byte for byte."""
    expected = generated_files(REPO)
    actual = generated_files(project)
    assert sorted(actual) == sorted(expected), "the set of generated files changed"
    differing = [name for name in expected if actual[name] != expected[name]]
    assert not differing, "regenerated files differ from the committed ones: %s" % differing


@pytest.fixture
def project(tmp_path: Path) -> Path:
    """A scratch copy of the project."""
    return copy_project(tmp_path / "project")
