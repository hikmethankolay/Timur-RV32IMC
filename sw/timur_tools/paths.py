"""Where the files of a Timur project live.

The vector files name ROM images and text files relative to the project root
("vectors/timur_soc_phase5.hex"), because the testbenches open them from
there. The tools therefore keep two things apart: the *relative name* that is
written into a file, and the *path* it resolves to under the project root.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from .errors import TimurError

#: Environment variable that overrides the project root.
ENV_ROOT = "TIMUR_ROOT"

#: Directory names relative to the project root, as written into vector files.
VECTORS = "vectors"
BRINGUP = "sw/bringup"


def suffixed(prefix: Path, suffix: str) -> Path:
    """prefix with suffix appended to its name: ('out/prog', '_lo.hex') -> out/prog_lo.hex.

    Unlike Path.with_suffix this never replaces part of a name that contains a dot.
    """
    return prefix.parent / (prefix.name + suffix)


def default_root() -> Path:
    """The project root: $TIMUR_ROOT, or the project these tools are part of."""
    override = os.environ.get(ENV_ROOT)
    if override:
        return Path(override).resolve()
    return Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Project:
    """The directories of one project tree."""

    root: Path

    @classmethod
    def at(cls, root: Path | str | None = None) -> Project:
        """The project at root (default: default_root()); checks that it is one."""
        resolved = Path(root).resolve() if root is not None else default_root()
        project = cls(resolved)
        for required in (project.sw, project.vectors):
            if not required.is_dir():
                raise TimurError(
                    "%s is not a Timur project directory (%s is missing)"
                    % (resolved, required.relative_to(resolved))
                )
        return project

    def path(self, relative: str) -> Path:
        """The path of a root-relative name such as 'vectors/x.hex'."""
        return self.root / relative

    @property
    def sw(self) -> Path:
        """Software: tools, runtime, programs."""
        return self.root / "sw"

    @property
    def vectors(self) -> Path:
        """Test vectors and ROM images read by the testbenches."""
        return self.root / VECTORS

    @property
    def bringup(self) -> Path:
        """ROM images of the hardware bring-up programs."""
        return self.root / BRINGUP

    @property
    def runtime(self) -> Path:
        """C runtime: startup code, system calls, trap handler, linker script."""
        return self.sw

    @property
    def include(self) -> Path:
        """Headers of the C runtime."""
        return self.sw

    @property
    def tests(self) -> Path:
        """C test programs."""
        return self.sw / "tests"

    @property
    def programs(self) -> Path:
        """Directed assembly test programs."""
        return self.sw / "programs"

    @property
    def build(self) -> Path:
        """Build output of C programs (not committed)."""
        return self.sw / "build"

    @property
    def tools(self) -> Path:
        """Locally unpacked toolchains (not committed)."""
        return self.root / ".tools"
