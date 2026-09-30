#!/usr/bin/env python3
"""Run a C program on the Timur reference model, and optionally prepare an RTL run.

Takes the .elf that sw/build.py wrote (the ROM image is the .hex next to it), runs the
image on the instruction-level model (sw/timur_tools/model.py) with interrupts and console
input modelled, and prints the program's UART output, the number of instructions, the
LEDs at the end and how the program ended. The model runs about 300,000 instructions per
second, so this is the quickest way to try a program.

With --vectors FILE it also writes a vector file for tb/timur_soc_tb.v, with the model's
output as the expected UART text (FILE's name with .out) and the console input (.in), so
the same program can run on the RTL and be compared byte for byte:

    RTL=$(ls rtl/*/*.v | grep -v -e cpu_pll -e _bb.v -e Timur_RV32IMC.v)
    iverilog -g2001 -s timur_soc_tb -o sim.vvp -Ptimur_soc_tb.UART_DIVIDER=15 \\
        -Ptimur_soc_tb.VECTORS='"FILE"' tb/timur_soc_tb.v $RTL && vvp -n sim.vvp

For that comparison the program must end (return from main, or call exit) and must not
print anything that depends on timing: the model sends UART bytes and copies DMA blocks at
once and cannot know the cycle counters. For any other program the vector file runs it on
the RTL for --cycles clock cycles and shows what it printed, without a comparison. Keep
every path under 64 characters (the testbench's file-name limit) and run from the project
root.

The model stops at the first cycle-counter value that decides a branch, since it cannot
know it. --fake-time lets the counters count executed instructions instead, so delay loops
end (much sooner or later than on the board) and the output after them can be seen.

Usage:  python3 sw/run_model.py PROGRAM.elf [--input TEXT] [--max N] [--fake-time]
                                [--vectors FILE] [--cycles N]
        --input takes Python escapes: --input '12 30\\rTimur\\r' types two lines.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from timur_tools import builder, cli, memmap, romimage
from timur_tools.errors import TimurError
from timur_tools.model import TimingDependentError, TimurModel
from timur_tools.toolchain import require_toolchain
from timur_tools.vectors import NO_HALT, prog_cycle_budget

UART_CYCLES_PER_BIT = memmap.TB_SW_UART_CYCLES_PER_BIT  # with UART_DIVIDER = 15
DEFAULT_MAX_INSTRUCTIONS = 20_000_000
DEFAULT_RTL_CYCLES = 2_000_000
EXIT_CODE_LEDS = 0x200  # _exit shows 0x200 | code on the LEDs
EXIT_CODE_MASK = 0x1FF
_NOT_ESCAPES = re.compile(r"\\\\|\\(?=[uUN])")


@dataclass(frozen=True)
class Outcome:
    """How a run on the model ended."""

    ended: bool  # reached a jump-to-self
    timing: str | None  # why the model had to stop, if it could not predict the program
    halt: int | None  # address of _halt

    @property
    def at_halt(self) -> bool:
        """The program ended normally, at _halt."""
        return self.ended and self.halt is not None


def parse_console_input(text: str) -> bytes:
    """--input with Python escapes (\\r, \\n, \\x41, \\101, \\\\) as the bytes to send;
    other characters are sent as UTF-8. As in a Python bytes literal, \\u, \\U and
    \\N{...} are not escapes: they are sent as written."""
    # double the backslash of \\u, \\U and \\N, but not one that is itself escaped
    kept = _NOT_ESCAPES.sub(
        lambda match: match.group(0) if len(match.group(0)) == 2 else "\\\\", text
    )
    try:
        return kept.encode("utf-8").decode("unicode_escape").encode("latin-1")
    except UnicodeError as error:
        raise TimurError("--input: %s" % error) from error


def run(model: TimurModel, limit: int, halt: int | None) -> Outcome:
    """Run at most limit instructions."""
    try:
        for _ in range(limit):
            if model.step():
                return Outcome(True, None, halt if model.pc == halt else None)
    except TimingDependentError as error:
        return Outcome(False, str(error), None)
    return Outcome(False, None, None)


def print_report(model: TimurModel, outcome: Outcome) -> None:
    """The program's output and how it ended."""
    out = bytes(model.uart_tx)
    sys.stdout.write(out.decode("latin-1").replace("\r\n", "\n"))
    if out and not out.endswith(b"\n"):
        sys.stdout.write("\n")
    print("-" * 72)
    if outcome.timing:
        print(
            "stopped: %s; the model cannot predict this program (run it on the RTL or the board)"
            % outcome.timing
        )
    elif outcome.at_halt:
        print("ended at _halt (%08X) after %d instructions" % (model.pc, model.retired))
    elif outcome.ended:
        print(
            "stopped at a jump to itself at %08X after %d instructions (an endless loop in the "
            "program)" % (model.pc, model.retired)
        )
    else:
        print(
            "still running after %d instructions (PC %08X): an endless loop, or raise --max"
            % (model.retired, model.pc)
        )
    exit_code = ""
    if outcome.at_halt and model.gpio_out & EXIT_CODE_LEDS:
        exit_code = "  (0x200 | exit code %d)" % (model.gpio_out & EXIT_CODE_MASK)
    print("LEDs %03X%s" % (model.gpio_out, exit_code))
    if model.traps:
        causes = Counter(cause for cause, _, _ in model.traps)
        print("traps: " + ", ".join("%d x mcause %X" % (causes[c], c) for c in sorted(causes)))
    if model.uart_rx or model.rx_valid:
        print("unread console input: %d bytes" % (len(model.uart_rx) + model.rx_valid))


def write_vector_file(
    args: argparse.Namespace, hex_path: str, uart_in: bytes, model: TimurModel, outcome: Outcome
) -> None:
    """A vector file for tb/timur_soc_tb.v: with the expected output if the model's run
    predicts the RTL's, otherwise one that only shows what the RTL prints."""
    # the address the RTL run must halt at, if the model's run predicts it
    exact_halt = outcome.halt if outcome.at_halt and not model.read_time else None
    vectors = args.vectors
    # the names go into the vector file as the user spelled them
    base = os.path.splitext(vectors)[0]  # noqa: PTH122
    out_path, in_path = base + ".out", base + ".in"
    for path in (hex_path, out_path, in_path, vectors):
        if len(path) > memmap.TB_PATH_LIMIT:
            raise TimurError(
                "path %s is longer than the testbench's %d characters"
                % (path, memmap.TB_PATH_LIMIT)
            )
    lines = [
        "// %s: written by sw/run_model.py for tb/timur_soc_tb.v with UART_DIVIDER = 15" % args.elf
    ]
    if uart_in:
        Path(in_path).write_bytes(uart_in)
        lines.append("UARTIN %s" % in_path)
    if exact_halt is not None:
        out = bytes(model.uart_tx)
        Path(out_path).write_bytes(out)
        cycles = prog_cycle_budget(model.retired, len(out), len(uart_in), UART_CYCLES_PER_BIT)
        lines.append("PROG %s %d %08X 0" % (hex_path, cycles, exact_halt))
        lines.append("UARTTEXT %s" % out_path)
        lines.append("LEDS %03X" % model.gpio_out)
        lines.append("DIVS %d" % model.divs)
    else:
        lines.append("PROG %s %d %08X 0" % (hex_path, args.cycles, NO_HALT))
        lines.append("UARTSHOW")
    romimage.write_lines(Path(vectors), lines)
    if exact_halt is not None:
        print("wrote %s: the RTL run must print exactly %s" % (vectors, out_path))
    else:
        print(
            "wrote %s: the RTL runs the program for %d cycles and shows its output (no expected"
            " output: the program does not end, or its output depends on timing)"
            % (vectors, args.cycles)
        )


def main(argv: Sequence[str] | None = None) -> int:
    """Run one program on the model; returns the exit status."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument(
        "elf", type=Path, help="program built by sw/build.py (the .hex next to it is the image)"
    )
    parser.add_argument(
        "--input", default="", help="console input, with Python escapes such as \\r"
    )
    parser.add_argument(
        "--max", type=cli.positive_int, default=DEFAULT_MAX_INSTRUCTIONS,
        help="instructions to run at most (default %d)" % DEFAULT_MAX_INSTRUCTIONS,
    )  # fmt: skip
    parser.add_argument(
        "--fake-time", action="store_true",
        help="let the cycle counters count instructions, so delay loops end",
    )  # fmt: skip
    parser.add_argument("--vectors", help="write a vector file for tb/timur_soc_tb.v")
    parser.add_argument(
        "--cycles", type=cli.positive_int, default=DEFAULT_RTL_CYCLES,
        help="RTL run length for a program that does not end (default %d)" % DEFAULT_RTL_CYCLES,
    )  # fmt: skip
    cli.add_common_arguments(parser)
    args = parser.parse_args(argv)
    project = cli.project_from(args)

    if not args.elf.is_file():
        raise TimurError("%s does not exist (build the program with sw/build.py)" % args.elf)
    hex_path = os.path.splitext(str(args.elf))[0] + ".hex"  # noqa: PTH122 (as spelled)
    toolchain = require_toolchain(project.root)
    halt = builder.read_symbols(toolchain, args.elf).get("_halt")
    image = romimage.read_word_hex(Path(hex_path))
    uart_in = parse_console_input(args.input)

    model = TimurModel(
        image.memory(), uart_rx=uart_in, interrupts=True, trace=False, fake_time=args.fake_time
    )
    outcome = run(model, args.max, halt)
    print_report(model, outcome)
    if args.vectors:
        write_vector_file(args, hex_path, uart_in, model, outcome)
    return 0


if __name__ == "__main__":
    sys.exit(cli.run(main, "run_model"))
