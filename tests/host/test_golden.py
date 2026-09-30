"""Characterization tests: the generators reproduce the committed files exactly.

The vector files, ROM images and expected UART outputs in the repository are
what the Verilog testbenches check the RTL against, so a change in the Python
tools must not change a single byte of them unless the change is intended (and
then the regenerated files are part of the same commit).
"""

from __future__ import annotations

from pathlib import Path

from conftest import assert_matches_repository, needs_pinned_toolchain, run_script

# Every file these generators write; removed first so that an identical result
# proves the file was really written again.
ALWAYS_REWRITTEN = (
    "vectors/csr_file_vectors.txt",
    "vectors/trap_unit_vectors.txt",
    "vectors/timur_soc_vectors.txt",
    "vectors/timur_soc_phase5.hex",
    "vectors/timur_soc_phase6.hex",
    "vectors/timur_soc_phase7.hex",
    "vectors/timur_soc_random.hex",
    "vectors/timur_soc_system.hex",
    "vectors/timur_soc_phase10.hex",
    "vectors/timur_soc_interrupt.hex",
    "vectors/timur_sw_vectors.txt",
    "vectors/timur_sw_io.in",
    "rom.hex",
    "rom_lo.hex",
    "rom_hi.hex",
    "rom_lo.mif",
    "rom_hi.mif",
)
REWRITTEN_WITH_TOOLCHAIN = (
    "vectors/decompressor_vectors.txt",
    "vectors/timur_soc_phase11.hex",
    "vectors/timur_soc_random_c.hex",
)


def _remove(project: Path, names: tuple[str, ...]) -> None:
    for name in names:
        (project / name).unlink()


def _run_ok(project: Path, script: str, with_toolchain: bool) -> None:
    result = run_script(project, script, with_toolchain=with_toolchain)
    assert result.returncode == 0, "%s failed:\n%s%s" % (script, result.stdout, result.stderr)


@needs_pinned_toolchain
def test_generators_reproduce_committed_files_with_toolchain(project: Path) -> None:
    _remove(project, ALWAYS_REWRITTEN + REWRITTEN_WITH_TOOLCHAIN)
    for path in (project / "vectors").glob("timur_sw_*_rv32im*"):
        path.unlink()
    for path in (project / "sw" / "bringup").iterdir():
        path.unlink()

    for script in (
        "gen_unit_vectors.py",
        "gen_decompressor_vectors.py",
        "gen_soc_tests.py",
        "gen_sw_tests.py",
    ):
        _run_ok(project, script, with_toolchain=True)

    assert_matches_repository(project)


def test_generators_reproduce_committed_files_without_toolchain(project: Path) -> None:
    """Without the toolchain the committed images are read back and only the
    expectations are regenerated; those must not change either."""
    _remove(project, ALWAYS_REWRITTEN)
    for path in (project / "vectors").glob("timur_sw_*.out"):
        path.unlink()

    for script in ("gen_unit_vectors.py", "gen_soc_tests.py", "gen_sw_tests.py"):
        _run_ok(project, script, with_toolchain=False)

    assert_matches_repository(project)
