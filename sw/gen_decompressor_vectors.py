#!/usr/bin/env python3
"""Exhaustive decompressor vectors from the GNU toolchain (Phase 11).

Writes vectors/decompressor_vectors.txt: every 16-bit encoding with
instr[1:0] != 11 (49152 of them), its 32-bit expansion and the illegal flag.

The oracle is independent of the RTL and of the Python model:
  1. riscv-none-elf-as places every encoding with .insn and
     riscv-none-elf-objdump -M no-aliases decodes it for rv32imc_zicsr;
  2. each decoded c.* instruction is rewritten as its RV32I expansion from the
     table in the RISC-V specification (operands are taken verbatim from
     objdump, so immediates and register fields are decoded by binutils);
  3. riscv-none-elf-as assembles the expansions without the C extension.
objdump accepts a few encodings that the specification reserves; the
RESERVED rules below mark them illegal. An illegal encoding expands to
00000000, the word main_control_unit decodes as illegal.

Usage:  python3 sw/gen_decompressor_vectors.py [--prefix riscv-none-elf-]
The prefix may include a directory; by default the script looks on PATH and
in .tools/xpack-*/bin.
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile


def find_prefix(given):
    if given:
        return given
    if shutil.which("riscv-none-elf-as"):
        return "riscv-none-elf-"
    for d in sorted(glob.glob(".tools/xpack-riscv-none-elf-gcc-*/bin")):
        return os.path.join(d, "riscv-none-elf-")
    sys.exit("riscv-none-elf toolchain not found; pass --prefix")


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit("command failed: %s\n%s" % (" ".join(cmd), r.stderr[:2000]))
    return r.stdout


def reserved(v):
    """Encodings objdump decodes but the specification reserves (or leaves to
    custom extensions on RV32); Timur treats them as illegal."""
    q, f3 = v & 3, v >> 13
    if q == 1 and f3 == 3 and ((v >> 7) & 31) == 2:          # C.ADDI16SP, nzimm = 0
        nzimm = ((v >> 12) & 1) << 9 | ((v >> 3) & 3) << 7 | ((v >> 5) & 1) << 6 | ((v >> 2) & 1) << 5 | ((v >> 6) & 1) << 4
        if nzimm == 0:
            return True
    if q == 1 and f3 == 4 and ((v >> 10) & 3) in (0, 1) and (v >> 12) & 1:   # C.SRLI/C.SRAI shamt[5]
        return True
    if q == 2 and f3 == 0 and (v >> 12) & 1:                  # C.SLLI shamt[5]
        return True
    return False


def expansion(mnem, ops, addr):
    """RV32I assembly text for a decoded compressed instruction, or None."""
    o = [x.strip() for x in ops.split(",")] if ops else []

    def off(target):          # objdump prints branch and jump targets as absolute addresses
        return ".%+d" % (int(target.split()[0], 16) - addr)

    table = {
        "c.addi4spn": lambda: "addi %s,%s,%s" % (o[0], o[1], o[2]),
        "c.lw":       lambda: "lw %s,%s" % (o[0], o[1]),
        "c.sw":       lambda: "sw %s,%s" % (o[0], o[1]),
        "c.nop":      lambda: "addi zero,zero,0",
        "c.addi":     lambda: "addi %s,%s,%s" % (o[0], o[0], o[1]),
        "c.jal":      lambda: "jal ra,%s" % off(o[0]),
        "c.li":       lambda: "addi %s,zero,%s" % (o[0], o[1]),
        "c.addi16sp": lambda: "addi sp,sp,%s" % o[1],
        "c.lui":      lambda: "lui %s,%s" % (o[0], o[1]),
        "c.srli":     lambda: "srli %s,%s,%s" % (o[0], o[0], o[1]),
        "c.srli64":   lambda: "srli %s,%s,0" % (o[0], o[0]),
        "c.srai":     lambda: "srai %s,%s,%s" % (o[0], o[0], o[1]),
        "c.srai64":   lambda: "srai %s,%s,0" % (o[0], o[0]),
        "c.andi":     lambda: "andi %s,%s,%s" % (o[0], o[0], o[1]),
        "c.sub":      lambda: "sub %s,%s,%s" % (o[0], o[0], o[1]),
        "c.xor":      lambda: "xor %s,%s,%s" % (o[0], o[0], o[1]),
        "c.or":       lambda: "or %s,%s,%s" % (o[0], o[0], o[1]),
        "c.and":      lambda: "and %s,%s,%s" % (o[0], o[0], o[1]),
        "c.j":        lambda: "jal zero,%s" % off(o[0]),
        "c.beqz":     lambda: "beq %s,zero,%s" % (o[0], off(o[1])),
        "c.bnez":     lambda: "bne %s,zero,%s" % (o[0], off(o[1])),
        "c.slli":     lambda: "slli %s,%s,%s" % (o[0], o[0], o[1]),
        "c.slli64":   lambda: "slli %s,%s,0" % (o[0], o[0]),
        "c.lwsp":     lambda: "lw %s,%s" % (o[0], o[1]),
        "c.swsp":     lambda: "sw %s,%s" % (o[0], o[1]),
        "c.jr":       lambda: "jalr zero,0(%s)" % o[0],
        "c.mv":       lambda: "add %s,zero,%s" % (o[0], o[1]),
        "c.ebreak":   lambda: "ebreak",
        "c.jalr":     lambda: "jalr ra,0(%s)" % o[0],
        "c.add":      lambda: "add %s,%s,%s" % (o[0], o[0], o[1]),
    }
    f = table.get(mnem)
    return f() if f else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--prefix")
    args = ap.parse_args()
    pre = find_prefix(args.prefix)
    values = [v for v in range(0x10000) if v & 3 != 3]

    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "c.s")
        obj = os.path.join(tmp, "c.o")
        with open(src, "w") as f:
            f.write(".option rvc\n")
            for v in values:
                f.write(".insn 2, 0x%04x\n" % v)
        run([pre + "as", "-march=rv32imc_zicsr", "-o", obj, src])
        dump = run([pre + "objdump", "-d", "-M", "no-aliases", obj])

        decoded = {}
        for line in dump.splitlines():
            m = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]{4})\s+(\S+)\s*(.*)", line)
            if not m:
                continue
            addr, word, mnem, ops = int(m.group(1), 16), int(m.group(2), 16), m.group(3), m.group(4)
            ops = ops.split("#")[0].strip()
            decoded[word] = (addr, mnem, ops)
        if len(decoded) != len(values):
            sys.exit("objdump decoded %d of %d encodings" % (len(decoded), len(values)))

        texts, legal = {}, {}
        for v in values:
            addr, mnem, ops = decoded[v]
            text = None if (mnem in (".insn", "c.unimp") or reserved(v)) else expansion(mnem, ops, addr)
            if text is None and mnem not in (".insn", "c.unimp") and not reserved(v):
                sys.exit("no expansion rule for %04X: %s %s" % (v, mnem, ops))
            legal[v] = text is not None
            if text:
                texts[v] = text

        src2 = os.path.join(tmp, "x.s")
        obj2 = os.path.join(tmp, "x.o")
        order = sorted(texts)
        with open(src2, "w") as f:
            f.write(".option norvc\n")
            for v in order:
                f.write("%s\n" % texts[v])
        run([pre + "as", "-march=rv32im_zicsr", "-o", obj2, src2])
        dump2 = run([pre + "objdump", "-d", obj2])
        words = [int(m.group(1), 16) for m in re.finditer(r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s", dump2, re.M)]
        if len(words) != len(order):
            sys.exit("expansions: %d words for %d instructions" % (len(words), len(order)))
        expanded = dict(zip(order, words))

    lines = [
        "// decompressor test vectors, generated by sw/gen_decompressor_vectors.py from the GNU",
        "// toolchain (binutils decodes every encoding, the expansions are assembled without C).",
        "// format: instr16(hex) instr32(hex) illegal(bin); every encoding with instr[1:0] != 11.",
        "// Illegal and reserved encodings expand to 00000000 (decoded as illegal).",
    ]
    for v in values:
        lines.append("%04X %08X %d" % (v, expanded.get(v, 0), 0 if legal[v] else 1))
    with open("vectors/decompressor_vectors.txt", "w") as f:
        f.write("\n".join(lines) + "\n")
    print("%d encodings, %d legal, %d illegal" % (len(values), sum(legal.values()),
                                                  len(values) - sum(legal.values())))


if __name__ == "__main__":
    main()
