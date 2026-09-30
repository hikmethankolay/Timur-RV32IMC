"""Finding and running the RISC-V GNU toolchain (xPack riscv-none-elf-gcc).

Search order, the same for every tool:
  1. a prefix given on the command line
  2. $TIMUR_TOOLCHAIN_PREFIX, for example /opt/riscv/bin/riscv-none-elf-
  3. riscv-none-elf-gcc on PATH
  4. the newest release unpacked in <project>/.tools/xpack-riscv-none-elf-gcc-*/
"""

from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from .errors import TimurError

LOG = logging.getLogger("timur.toolchain")

#: Environment variable holding the tool prefix, including any directory.
ENV_PREFIX = "TIMUR_TOOLCHAIN_PREFIX"
DEFAULT_PREFIX = "riscv-none-elf-"
UNPACKED_GLOB = "xpack-riscv-none-elf-gcc-*/bin"

#: The compiler release the committed images in vectors/ were built with.
#: Other releases work, but may generate different (equally correct) code.
PINNED_GCC_VERSION = "14.2.0"

#: Characters of a failed command's output that are shown to the user.
ERROR_OUTPUT_LIMIT = 4000


class ToolchainError(TimurError):
    """The toolchain is missing, or one of its tools failed."""


@dataclass(frozen=True)
class Toolchain:
    """A GNU toolchain, identified by the prefix of its tool names."""

    prefix: str

    def tool(self, name: str) -> str:
        """The command for a tool: 'gcc', 'as', 'ld', 'objdump', 'objcopy', 'nm'."""
        return self.prefix + name

    def run(self, name: str, *args: str | Path) -> str:
        """Run a tool and return its stdout; warnings on stderr are passed on.

        Raises ToolchainError if the tool cannot be started or fails.
        """
        command = [self.tool(name), *(str(arg) for arg in args)]
        LOG.debug("running: %s", " ".join(command))
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=False)
        except OSError as error:
            raise ToolchainError("cannot run %s: %s" % (command[0], error)) from error
        if result.returncode:
            output = (result.stderr or result.stdout)[:ERROR_OUTPUT_LIMIT]
            raise ToolchainError("command failed: %s\n%s" % (" ".join(command), output))
        if result.stderr:
            sys.stderr.write(result.stderr)
        return result.stdout

    def gcc_version(self) -> str:
        """The compiler release, for example '14.2.0'."""
        return self.run("gcc", "-dumpversion").strip()


def _release_key(bin_dir: Path) -> tuple[int, ...]:
    """Sort key of an unpacked release: the numbers in its directory name."""
    return tuple(int(number) for number in re.findall(r"\d+", bin_dir.parent.name))


def find_toolchain(root: Path, prefix: str | None = None) -> Toolchain | None:
    """The toolchain to use for the project at root, or None if there is none."""
    if prefix:
        return Toolchain(prefix)
    from_environment = os.environ.get(ENV_PREFIX)
    if from_environment:
        return Toolchain(from_environment)
    if shutil.which(DEFAULT_PREFIX + "gcc"):
        return Toolchain(DEFAULT_PREFIX)
    unpacked = sorted((root / ".tools").glob(UNPACKED_GLOB), key=_release_key, reverse=True)
    for bin_dir in unpacked:
        if shutil.which(DEFAULT_PREFIX + "gcc", path=str(bin_dir)):
            return Toolchain(str(bin_dir / DEFAULT_PREFIX))
    return None


def require_toolchain(root: Path, prefix: str | None = None) -> Toolchain:
    """Like find_toolchain, but a missing toolchain is an error."""
    toolchain = find_toolchain(root, prefix)
    if toolchain is None:
        raise ToolchainError(
            "%sgcc not found (looked at $%s, PATH and %s)"
            % (DEFAULT_PREFIX, ENV_PREFIX, root / ".tools" / UNPACKED_GLOB)
        )
    return toolchain
