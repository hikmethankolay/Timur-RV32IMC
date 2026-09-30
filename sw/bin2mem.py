#!/usr/bin/env python3
"""Timur binary-to-memory converter: a raw ROM binary -> the ROM initialisation files.

Writes, for an output prefix P (default "rom", the files in the project root):
  P.hex                  one 32-bit little-endian word per line (testbenches)
  P_lo.hex, P_hi.hex     the two 16-bit ROM banks, one halfword per line (simulation)
  P_lo.mif, P_hi.mif     the same banks as Quartus memory files, 16384 x 16 (synthesis)
The LO bank holds the halfwords at byte offsets 0 mod 4, HI those at 2 mod 4.
Unused ROM reads as 0000, which the CPU decodes as an illegal instruction, in
both the .hex files (rom_ahb zero-fills before loading) and the .mif files.

Usage:  python3 sw/bin2mem.py program.bin [-o PREFIX] [--title TEXT]
Stops with an error if the binary is larger than the 64 KB ROM; the usual
cause is a section with contents linked into RAM, for which objcopy emits a
gap of about 512 MB between ROM and RAM.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from timur_tools import cli, romimage


def main(argv: Sequence[str] | None = None) -> int:
    """Convert one binary; returns the exit status."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument("binary", type=Path, help="raw binary from objcopy -O binary")
    parser.add_argument(
        "-o", "--prefix", type=Path, default=Path("rom"), help="output prefix (default: rom)"
    )
    parser.add_argument("--title", help="description written into the .mif headers")
    args = parser.parse_args(argv)

    data = args.binary.read_bytes()
    words = romimage.convert(data, args.prefix, args.title or str(args.binary))
    print(
        "%s: %d bytes -> %s.hex, %s_lo/_hi .hex/.mif (%d of %d words used)"
        % (args.binary, len(data), args.prefix, args.prefix, len(words), romimage.BANK_DEPTH)
    )
    return 0


if __name__ == "__main__":
    sys.exit(cli.run(main, "bin2mem"))
