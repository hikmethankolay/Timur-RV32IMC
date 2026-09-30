"""Vector files for tb/timur_soc_tb.v: programs to run and what to check afterwards.

One directive per line; // starts a comment. sw/gen_soc_tests.py writes the
full description of the directives into the head of vectors/timur_soc_vectors.txt.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from pathlib import Path

from . import memmap
from .isa import MASK
from .model import TimurModel
from .romimage import write_lines

#: halt_pc of a PROG that is not expected to halt: run for max_cycles.
NO_HALT = 0xFFFF_FFFF

#: Words of RAM the RAMNZ directive counts non-zero words in (the first 4 KB).
RAMNZ_BYTES = 0x1000

# Cycle budget of a C program on the RTL, from its run on the model:
_CYCLES_PER_INSTRUCTION = 20  # generous: stalls, flushes, bus waits
_UART_MARGIN = 3  # each byte is given three frame times
_RX_FRAMES_PER_BYTE = 3  # the testbench waits for the receiver before each byte
_SLACK_CYCLES = 20_000  # reset, pipeline drain, the last UART frame


def prog_cycle_budget(retired: int, uart_out: int, uart_in: int, cycles_per_bit: int) -> int:
    """max_cycles for a PROG: enough clock cycles for a program that executed
    `retired` instructions, sent uart_out bytes and received uart_in bytes."""
    uart_frames = uart_out + _RX_FRAMES_PER_BYTE * uart_in
    return (
        _CYCLES_PER_INSTRUCTION * retired
        + _UART_MARGIN * memmap.UART_FRAME_BITS * cycles_per_bit * uart_frames
        + _SLACK_CYCLES
    )


class Vectors:
    """The lines of one vector file."""

    def __init__(self) -> None:
        self.lines: list[str] = []

    def comment(self, text: str = "") -> None:
        """A comment line."""
        self.lines.append("//" + (" " + text if text else ""))

    def add(self, text: str) -> None:
        """Any directive."""
        self.lines.append(text)

    def prog(self, image_file: str, max_cycles: int, halt: int, hready_waits: int) -> None:
        """PROG: load image_file (relative to the project root) and run it."""
        self.lines.append("PROG %s %d %08X %d" % (image_file, max_cycles, halt, hready_waits))

    def regs(self, values: Mapping[int, int]) -> None:
        """REG: expected values of registers x1..x31."""
        for register in range(1, 32):
            if register in values:
                self.lines.append("REG %d %08X" % (register, values[register] & MASK))

    def nonzero(self, registers: Iterable[int]) -> None:
        """REGNZ: registers that must not be zero (timing-dependent values)."""
        for register in registers:
            self.lines.append("REGNZ %d" % register)

    def ram(self, words: Mapping[int, int]) -> None:
        """RAM: expected RAM words by address."""
        for address in sorted(words):
            self.lines.append("RAM %08X %08X" % (address, words[address]))

    def write(self, path: Path) -> None:
        """Write the file."""
        write_lines(path, self.lines)


def model_checks(vec: Vectors, model: TimurModel) -> None:
    """Add everything the model knows about the end state of a run, including
    the order in which the instructions were executed; registers and RAM words
    that hold timing-dependent values are left out."""
    vec.regs({r: model.x[r] for r in range(1, 32) if r not in model.taint})
    vec.ram(
        {
            memmap.RAM_BASE | offset: int.from_bytes(model.ram[offset : offset + 4], "little")
            for offset in model.ram_written
            if offset not in model.ram_taint
        }
    )
    if not any(offset < RAMNZ_BYTES for offset in model.ram_taint):
        nonzero = sum(
            1 for offset in range(0, RAMNZ_BYTES, 4) if any(model.ram[offset : offset + 4])
        )
        vec.add("RAMNZ %d" % nonzero)
    vec.add("LEDS %03X" % model.gpio_out)
    for byte in model.uart_tx:
        vec.add("UART %02X" % byte)
    vec.add("UARTN %d" % len(model.uart_tx))
    vec.add("DIVS %d" % model.divs)
    vec.add("RETIRED %d" % len(model.trace))
    for pc in model.trace:
        vec.add("TRACE %08X" % pc)
