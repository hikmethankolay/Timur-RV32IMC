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

import argparse
import sys

ROM_BYTES = 0x10000
BANK_DEPTH = ROM_BYTES // 4


class ConvertError(Exception):
    pass


def words_from_binary(data):
    """Little-endian 32-bit words of a ROM binary (padded with zeros to a word)."""
    if len(data) > ROM_BYTES:
        raise ConvertError("the binary is %d bytes, larger than the %d-byte ROM (is a section "
                           "with contents linked into RAM?)" % (len(data), ROM_BYTES))
    data = bytes(data) + b"\0" * (-len(data) % 4)
    return [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]


def write_word_hex(path, words):
    with open(path, "w") as f:
        for w in words:
            f.write("%08X\n" % w)


def write_banks(prefix, words, title):
    """<prefix>_lo / _hi .hex (one 16-bit word per line) and .mif (16384 x 16)."""
    if len(words) > BANK_DEPTH:
        raise ConvertError("image exceeds 64 KB")
    for bank, shift in (("lo", 0), ("hi", 16)):
        halves = [(w >> shift) & 0xFFFF for w in words]
        with open("%s_%s.hex" % (prefix, bank), "w") as f:
            for h in halves:
                f.write("%04X\n" % h)
        with open("%s_%s.mif" % (prefix, bank), "w") as f:
            f.write("-- Timur RV32IMC instruction ROM, %s bank (halfwords at byte offset %d mod 4): %s\n"
                    % (bank.upper(), 0 if bank == "lo" else 2, title))
            f.write("-- 16384 x 16-bit words; unused words are 0000 (illegal instruction)\n\n")
            f.write("DEPTH = 16384;\nWIDTH = 16;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n\nCONTENT BEGIN\n")
            for i, h in enumerate(halves):
                f.write("    %04X : %04X;\n" % (i, h))
            if len(halves) < BANK_DEPTH:
                f.write("    [%04X..3FFF] : 0000;\n" % len(halves))
            f.write("END;\n")


def convert(data, prefix, title):
    words = words_from_binary(data)
    write_word_hex(prefix + ".hex", words)
    write_banks(prefix, words, title)
    return words


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("binary", help="raw binary from objcopy -O binary")
    ap.add_argument("-o", "--prefix", default="rom", help="output prefix (default: rom)")
    ap.add_argument("--title", help="description written into the .mif headers")
    args = ap.parse_args()
    with open(args.binary, "rb") as f:
        data = f.read()
    try:
        words = convert(data, args.prefix, args.title or args.binary)
    except ConvertError as e:
        sys.exit("bin2mem: %s" % e)
    print("%s: %d bytes -> %s.hex, %s_lo/_hi .hex/.mif (%d of %d words used)"
          % (args.binary, len(data), args.prefix, args.prefix, len(words), BANK_DEPTH))


if __name__ == "__main__":
    main()
