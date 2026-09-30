#!/usr/bin/env python3
"""Build a C program for Timur: compile, link, check the layout, convert to ROM images.

Compiles the program with the runtime (crt0.S, syscalls.c, trap.c) and the
memory layout linker.ld, then writes into the output directory (default
sw/build/<name>/):
  <name>.elf, <name>.map, <name>.lst   program, link map, disassembly
  <name>.bin                           raw ROM binary (objcopy -O binary)
  <name>.hex, <name>_lo/_hi .hex/.mif  ROM images (sw/bin2mem.py)
With --install the images are also written to the project root as rom.hex and
rom_lo/_hi .hex/.mif: the ROM that simulation loads and that Quartus builds
into the FPGA image (recompile afterwards).

Checks: the C library matches the ISA (never the default rv32imac library,
which contains A-extension instructions), .text starts at 0, .data runs in
RAM and loads from ROM, and nothing else with contents lies outside the ROM.

Usage:  python3 sw/build.py [--march rv32imc_zicsr] [-O2] [--name NAME] [--out DIR]
                            [--stack-size BYTES] [--extra=OPTION ...] [--install]
                            source.c [more sources]
--extra passes one more option to gcc, after the sources: --extra=-lm links the maths
library, --extra=-Wl,-u,_printf_float enables %f in printf, --extra=-DDEBUG defines a
macro.
The toolchain is xPack riscv-none-elf-gcc: $TIMUR_TOOLCHAIN_PREFIX, on PATH, or
unpacked in .tools/.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from timur_tools import builder, cli, memmap


def stack_size(text: str) -> int:
    """argparse type: a stack size that leaves room for it in RAM."""
    size = cli.positive_int(text)
    if size >= memmap.RAM_SIZE:
        raise argparse.ArgumentTypeError(
            "must be smaller than the %d-byte RAM, not %d" % (memmap.RAM_SIZE, size)
        )
    return size


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    """The command line of build.py."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument(
        "sources", nargs="+", type=Path, help="C or assembly sources of the program"
    )
    parser.add_argument("--march", default=builder.DEFAULT_MARCH, choices=sorted(builder.MARCHES))
    parser.add_argument(
        "-O", dest="opt", default="2", choices=builder.OPT_LEVELS,
        help="optimisation level (default 2)",
    )  # fmt: skip
    parser.add_argument("--name", help="output name (default: the first source's name)")
    parser.add_argument("--out", type=Path, help="output directory (default: sw/build/<name>)")
    parser.add_argument(
        "--stack-size", type=stack_size, metavar="BYTES",
        help="bytes reserved for the stack below the end of RAM (default %d)"
        % builder.DEFAULT_STACK_SIZE,
    )  # fmt: skip
    parser.add_argument(
        "--extra", action="append", default=[], metavar="OPTION",
        help="one more gcc option, written as --extra=OPTION (repeatable)",
    )  # fmt: skip
    parser.add_argument(
        "--install", action="store_true",
        help="also write rom.hex and rom_lo/_hi .hex/.mif in the project root",
    )  # fmt: skip
    cli.add_common_arguments(parser)
    return parser.parse_args(argv)


def print_summary(result: builder.BuildResult) -> None:
    """Sections, memory use and output files of a finished build."""
    print("%s: -march=%s, C library %s" % (result.elf, result.march, result.multilib))
    for section in result.sections:
        if section.size:
            where = "load %08X" % section.lma if section.loaded else "no contents"
            print(
                "  %-12s %6d bytes  run %08X  %s" % (section.name, section.size, section.vma, where)
            )
    heap_start, heap_end = result.symbol("_end"), result.symbol("_heap_end")
    stack_top = result.symbol("_stack_top")
    print(
        "  ROM image %d of %d bytes; heap %d bytes (%08X-%08X); stack %d bytes below %08X"
        % (result.size_bytes, memmap.ROM_SIZE, heap_end - heap_start, heap_start, heap_end,
           stack_top - heap_end, stack_top)
    )  # fmt: skip
    print("  _halt (end of program) at %08X" % result.symbol("_halt"))
    print("  images: %s.hex, %s_lo/_hi .hex/.mif" % (result.prefix, result.prefix))


def main(argv: Sequence[str] | None = None) -> int:
    """Build one program; returns the exit status."""
    args = parse_args(argv)
    project = cli.project_from(args)
    extra = list(args.extra)
    if args.stack_size:
        extra.append("-Wl,--defsym=__stack_size=%d" % args.stack_size)
    result = builder.build(
        args.sources, args.march, args.out, args.name, "-O" + args.opt, extra=extra, project=project
    )
    print_summary(result)
    if args.install:
        builder.install(result, project)
        print("  installed as rom.hex, rom_lo/_hi .hex/.mif in %s" % project.root)
        print(
            "  Quartus: Processing > Update Memory Initialization File, then Processing > Start >"
            " Start Assembler (or a full compilation); then program the .sof"
        )
    return 0


if __name__ == "__main__":
    sys.exit(cli.run(main, "build"))
