"""Build a C program for Timur: compile, link, check the layout, convert to ROM images.

The program is compiled with the runtime (startup code, system calls, trap
handler) and the memory layout of the linker script. The checks make sure
that the C library matches the ISA (never the default rv32imac library, which
contains A-extension instructions), that .text starts at the reset address,
that .data runs in RAM and loads from ROM, and that nothing else with contents
lies outside the ROM.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from . import memmap, romimage
from .errors import TimurError
from .paths import Project, suffixed
from .toolchain import Toolchain, require_toolchain

#: -march values and the multilib directory of the C library each must select.
MARCHES = {"rv32im_zicsr": "rv32im/ilp32", "rv32imc_zicsr": "rv32imc/ilp32"}
DEFAULT_MARCH = "rv32imc_zicsr"
ABI = "ilp32"
OPT_LEVELS = ("0", "1", "2", "3", "s", "g", "z", "fast")
DEFAULT_OPT = "-O2"
DEFAULT_STACK_SIZE = 8192  # sw/linker.ld: __stack_size

#: Sources of the runtime in sw/runtime/, in link order (crt0.S first).
RUNTIME_SOURCES = ("crt0.S", "trap_entry.S", "uart.c", "syscalls.c", "trap.c")
LINKER_SCRIPT = "linker.ld"

#: GNU C: the runtime uses inline assembly and statement expressions.
C_STANDARD = "gnu11"
#: Warnings for every program.
WARNINGS = ("-Wall", "-Wextra")
#: Warnings for the runtime (always, as errors) and for programs built with strict=True.
STRICT_WARNINGS = (
    *WARNINGS, "-Wshadow", "-Wconversion", "-Wsign-conversion", "-Wstrict-prototypes",
    "-Wmissing-prototypes", "-Wmissing-declarations", "-Wundef", "-Wcast-qual", "-Wcast-align",
    "-Wformat=2", "-Wdouble-promotion", "-Wimplicit-fallthrough", "-Wredundant-decls",
    "-Wwrite-strings", "-Wpointer-arith", "-Wnull-dereference", "-Wswitch-enum",
)  # fmt: skip

ROM_END = memmap.ROM_BASE + memmap.ROM_SIZE
RAM_END = memmap.RAM_BASE + memmap.RAM_SIZE

_SECTION = re.compile(r"\s*\d+\s+(\S+)\s+([0-9a-f]{8})\s+([0-9a-f]{8})\s+([0-9a-f]{8})")


class BuildError(TimurError):
    """The program cannot be built, or its layout does not fit the SoC."""


@dataclass(frozen=True)
class Section:
    """An allocated ELF section, from objdump -h."""

    name: str
    size: int
    vma: int  # run address
    lma: int  # load address
    flags: str

    @property
    def loaded(self) -> bool:
        """True if the section has contents in the image."""
        return "LOAD" in self.flags


@dataclass(frozen=True)
class BuildResult:
    """What build() produced."""

    name: str
    march: str
    elf: Path
    binary: Path
    prefix: Path  # <prefix>.hex, <prefix>_lo/_hi .hex/.mif
    words: list[int]
    size_bytes: int
    symbols: dict[str, int]
    sections: list[Section]
    multilib: str

    def symbol(self, name: str) -> int:
        """Address of a symbol the runtime or the linker script defines."""
        return lookup_symbol(self.symbols, name, self.elf)


def lookup_symbol(symbols: dict[str, int], name: str, elf: Path) -> int:
    """symbols[name], or a BuildError that says what is wrong with the program."""
    try:
        return symbols[name]
    except KeyError:
        raise BuildError(
            "%s has no symbol %s: it was not linked with the Timur runtime and %s"
            % (elf, name, LINKER_SCRIPT)
        ) from None


def compile_flags(project: Project, march: str, opt: str) -> list[str]:
    """Compiler options shared by every source file (without warnings).

    -ffile-prefix-map keeps the checkout location out of the debug information
    and out of __FILE__, so the same sources give the same program anywhere.
    """
    return [
        "-march=" + march, "-mabi=" + ABI, opt, "-g", "-std=" + C_STANDARD,
        "--specs=nano.specs", "-ffunction-sections", "-fdata-sections",
        "-ffile-prefix-map=%s=." % project.root,
        "-I", str(project.include),
    ]  # fmt: skip


def compile_runtime(
    toolchain: Toolchain, project: Project, flags: Sequence[str], obj_dir: Path
) -> list[Path]:
    """Compile the runtime with every warning enabled and treated as an error,
    assembler warnings included; returns the object files in link order."""
    obj_dir.mkdir(parents=True, exist_ok=True)
    objects = []
    for source in RUNTIME_SOURCES:
        obj = obj_dir / (source + ".o")
        toolchain.run(
            "gcc",
            *flags,
            *STRICT_WARNINGS,
            "-Werror",
            "-Wa,--fatal-warnings",
            "-c",
            "-o",
            obj,
            project.runtime / source,
        )
        objects.append(obj)
    return objects


def check_multilib(toolchain: Toolchain, march: str) -> str:
    """The C library gcc links for march; an error if it is not the one for that ISA."""
    selected = toolchain.run(
        "gcc", "-march=" + march, "-mabi=" + ABI, "-print-multi-directory"
    ).strip()
    if selected != MARCHES[march]:
        raise BuildError(
            "-march=%s links the C library in '%s', expected '%s'"
            % (march, selected, MARCHES[march])
        )
    return selected


def read_sections(toolchain: Toolchain, elf: Path) -> list[Section]:
    """Every section with the ALLOC flag."""
    lines = toolchain.run("objdump", "-h", elf).splitlines()
    sections = []
    for index, line in enumerate(lines[:-1]):
        header = _SECTION.match(line)
        if header and "ALLOC" in lines[index + 1]:
            size, vma, lma = (int(header.group(n), 16) for n in (2, 3, 4))
            sections.append(Section(header.group(1), size, vma, lma, lines[index + 1].strip()))
    return sections


def check_layout(sections: Sequence[Section]) -> None:
    """Raise BuildError unless the sections fit the ROM and RAM of the SoC."""
    by_name = {section.name: section for section in sections}
    if ".text" not in by_name or by_name[".text"].vma != memmap.ROM_BASE:
        raise BuildError(".text does not start at address 0")
    for section in sections:
        if section.size == 0 or not section.loaded:
            continue
        if section.lma + section.size > ROM_END:
            raise BuildError(
                "section %s (%d bytes) loads from %08X, outside the %d KB ROM"
                % (section.name, section.size, section.lma, memmap.ROM_SIZE // 1024)
            )
        runs_in_ram = section.vma >= memmap.RAM_BASE and section.vma + section.size <= RAM_END
        if section.vma != section.lma and not runs_in_ram:
            raise BuildError("section %s runs at %08X, outside RAM" % (section.name, section.vma))
    data = by_name.get(".data")
    if data and data.size and not (data.vma >= memmap.RAM_BASE and data.lma < ROM_END):
        raise BuildError(
            ".data must run in RAM and load from ROM (VMA %08X, LMA %08X)" % (data.vma, data.lma)
        )


def read_symbols(toolchain: Toolchain, elf: Path) -> dict[str, int]:
    """{name: address} of the program's symbols, from nm."""
    symbols = {}
    for line in toolchain.run("nm", elf).splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = int(fields[0], 16)
    return symbols


def build(
    sources: Sequence[Path | str],
    march: str = DEFAULT_MARCH,
    out_dir: Path | None = None,
    name: str | None = None,
    opt: str = DEFAULT_OPT,
    title: str | None = None,
    extra: Sequence[str] = (),
    *,
    strict: bool = False,
    project: Project | None = None,
    toolchain: Toolchain | None = None,
) -> BuildResult:
    """Build and convert a program.

    sources   C or assembly files of the program (the runtime is added)
    out_dir   where <name>.elf/.map/.lst/.bin/.hex and the banks are written
              (default: sw/build/<name>)
    name      output name (default: the first source's stem)
    extra     further gcc options, placed after the sources so that libraries
              such as -lm resolve
    strict    compile the program with the runtime's warnings, as errors
    Raises BuildError or ToolchainError.
    """
    if not sources:
        raise BuildError("no source files")
    if march not in MARCHES:
        raise BuildError("unsupported -march=%s (use %s)" % (march, " or ".join(MARCHES)))
    project = project or Project.at()
    toolchain = toolchain or require_toolchain(project.root)
    source_paths = [Path(source) for source in sources]
    name = name or source_paths[0].stem
    out_dir = out_dir or project.build / name
    out_dir.mkdir(parents=True, exist_ok=True)
    base = out_dir / name
    elf, binary = suffixed(base, ".elf"), suffixed(base, ".bin")

    multilib = check_multilib(toolchain, march)
    flags = compile_flags(project, march, opt)
    runtime_objects = compile_runtime(toolchain, project, flags, out_dir / "obj")
    warnings = [*STRICT_WARNINGS, "-Werror"] if strict else list(WARNINGS)
    toolchain.run(
        "gcc", *flags, *warnings,
        "-nostartfiles", "-T", project.runtime / LINKER_SCRIPT,
        "-Wl,--gc-sections", "-Wl,-Map=" + str(suffixed(base, ".map")), "-o", elf,
        *runtime_objects, *source_paths, *extra,
    )  # fmt: skip
    sections = read_sections(toolchain, elf)
    check_layout(sections)
    listing = toolchain.run("objdump", "-d", "-S", elf)
    suffixed(base, ".lst").write_text(listing, encoding="utf-8")
    toolchain.run("objcopy", "-O", "binary", elf, binary)
    data = binary.read_bytes()
    words = romimage.convert(data, base, title or "%s (%s)" % (name, march))
    return BuildResult(
        name=name,
        march=march,
        elf=elf,
        binary=binary,
        prefix=base,
        words=words,
        size_bytes=len(data),
        symbols=read_symbols(toolchain, elf),
        sections=sections,
        multilib=multilib,
    )


def install(result: BuildResult, project: Project) -> None:
    """Make the program the ROM image of the project: rom.hex, rom_lo/_hi .hex/.mif
    in the project root, which simulation loads and Quartus builds into the FPGA."""
    romimage.convert(
        result.binary.read_bytes(), project.root / "rom", "%s (%s)" % (result.name, result.march)
    )
