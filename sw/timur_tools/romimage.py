"""ROM image files of the Timur SoC.

A program image exists in three forms, all holding the same bytes:

  P.hex                 one 32-bit little-endian word per line; read by the
                        testbenches, optionally with // comments
  P_lo.hex, P_hi.hex    the two 16-bit ROM banks, one halfword per line
                        (simulation: $readmemh in rtl/memory/rom_ahb.v)
  P_lo.mif, P_hi.mif    the same banks as Quartus memory files (synthesis)

The LO bank holds the halfwords at byte offsets 0 mod 4, HI those at 2 mod 4.
Unused ROM reads as 0000, which the CPU decodes as an illegal instruction.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path

from . import memmap
from .errors import TimurError
from .paths import suffixed

WORD_BYTES = 4
ROM_BYTES = memmap.ROM_SIZE
#: Words per bank: each bank holds one halfword of every 32-bit ROM word.
BANK_DEPTH = ROM_BYTES // WORD_BYTES
BANK_WIDTH = 16
#: (bank name, bit offset of its halfword in the word, byte offset mod 4)
BANKS = (("lo", 0, 0), ("hi", 16, 2))

_TAG = re.compile(r"//\s*(?:symbol|label)\s+(\S+)\s+([0-9A-Fa-f]{8})\s*$")


class ConvertError(TimurError):
    """A binary does not fit the ROM, or an image file cannot be read."""


@dataclass(frozen=True)
class HexImage:
    """A word hex file: the ROM words and the addresses named in its comments."""

    words: list[int]
    tags: dict[str, int] = field(default_factory=dict)

    def memory(self) -> dict[int, int]:
        """The image as {byte address: word}."""
        return memory_from_words(self.words)


def memory_from_words(words: Sequence[int]) -> dict[int, int]:
    """{byte address: word} for words stored from address 0."""
    return {WORD_BYTES * index: word for index, word in enumerate(words)}


def image_words(image: Mapping[int, int]) -> list[int]:
    """The words of {byte address: word} from address 0 to the last one, gaps as 0."""
    last = max(image) // WORD_BYTES
    return [image.get(WORD_BYTES * index, 0) for index in range(last + 1)]


def words_from_binary(data: bytes) -> list[int]:
    """Little-endian 32-bit words of a ROM binary (padded with zeros to a word)."""
    if len(data) > ROM_BYTES:
        raise ConvertError(
            "the binary is %d bytes, larger than the %d-byte ROM (is a section "
            "with contents linked into RAM?)" % (len(data), ROM_BYTES)
        )
    padded = bytes(data) + b"\0" * (-len(data) % WORD_BYTES)
    return [
        int.from_bytes(padded[offset : offset + WORD_BYTES], "little")
        for offset in range(0, len(padded), WORD_BYTES)
    ]


def write_lines(path: Path, lines: Iterable[str]) -> None:
    """Write text lines with LF endings on every platform (the files are compared
    byte for byte)."""
    with path.open("w", encoding="utf-8", newline="\n") as file:
        for line in lines:
            file.write(line + "\n")


def write_word_hex(path: Path, words: Iterable[int]) -> None:
    """One 32-bit word per line."""
    write_lines(path, ("%08X" % word for word in words))


def write_banks(prefix: Path, words: Sequence[int], title: str) -> None:
    """Write <prefix>_lo/_hi .hex (one halfword per line) and .mif."""
    if len(words) > BANK_DEPTH:
        raise ConvertError("image exceeds %d KB" % (ROM_BYTES // 1024))
    for bank, shift, byte_offset in BANKS:
        halves = [(word >> shift) & 0xFFFF for word in words]
        write_lines(suffixed(prefix, "_%s.hex" % bank), ("%04X" % half for half in halves))
        mif = [
            "-- Timur RV32IMC instruction ROM, %s bank (halfwords at byte offset %d mod 4): %s"
            % (bank.upper(), byte_offset, title),
            "-- %d x %d-bit words; unused words are 0000 (illegal instruction)"
            % (BANK_DEPTH, BANK_WIDTH),
            "",
            "DEPTH = %d;" % BANK_DEPTH,
            "WIDTH = %d;" % BANK_WIDTH,
            "ADDRESS_RADIX = HEX;",
            "DATA_RADIX = HEX;",
            "",
            "CONTENT BEGIN",
        ]
        mif += ["    %04X : %04X;" % (index, half) for index, half in enumerate(halves)]
        if len(halves) < BANK_DEPTH:
            mif.append("    [%04X..%04X] : 0000;" % (len(halves), BANK_DEPTH - 1))
        mif.append("END;")
        write_lines(suffixed(prefix, "_%s.mif" % bank), mif)


def convert(data: bytes, prefix: Path, title: str) -> list[int]:
    """Write all five image files for a raw ROM binary; returns its words."""
    words = words_from_binary(data)
    write_word_hex(suffixed(prefix, ".hex"), words)
    write_banks(prefix, words, title)
    return words


def read_word_hex(path: Path) -> HexImage:
    """Read a word hex file.

    Lines hold one hex word, optionally followed by a comment; comment lines
    of the form '// symbol NAME 0000ABCD' or '// label NAME 0000ABCD' name
    addresses (written by sw/gen_sw_tests.py and sw/gen_soc_tests.py).
    """
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ConvertError("cannot read the image %s: %s" % (path, error)) from error
    words: list[int] = []
    tags: dict[str, int] = {}
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("//"):
            tag = _TAG.match(stripped)
            if tag:
                tags[tag.group(1)] = int(tag.group(2), 16)
            continue
        try:
            words.append(int(stripped.split()[0], 16))
        except ValueError:
            raise ConvertError("%s:%d: not a hex word: %r" % (path, number, stripped)) from None
    return HexImage(words, tags)
