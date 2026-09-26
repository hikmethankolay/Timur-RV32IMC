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
The toolchain is xPack riscv-none-elf-gcc (on PATH or unpacked in .tools/).
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys

import bin2mem

SW = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SW)
RUNTIME = [os.path.join(SW, f) for f in ("crt0.S", "syscalls.c", "trap.c")]
MARCHES = {"rv32im_zicsr": "rv32im/ilp32", "rv32imc_zicsr": "rv32imc/ilp32"}
ROM_END, RAM_BASE, RAM_END = 0x10000, 0x20000000, 0x20010000


class BuildError(Exception):
    pass


def toolchain_prefix():
    if shutil.which("riscv-none-elf-gcc"):
        return "riscv-none-elf-"
    for d in sorted(glob.glob(os.path.join(ROOT, ".tools", "xpack-riscv-none-elf-gcc-*", "bin"))):
        return os.path.join(d, "riscv-none-elf-")
    return None


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        raise BuildError("command failed: %s\n%s" % (" ".join(cmd), (r.stderr or r.stdout)[:4000]))
    if r.stderr:                          # compiler warnings
        sys.stderr.write(r.stderr)
    return r.stdout


def cflags(march, opt):
    return ["-march=" + march, "-mabi=ilp32", opt, "-g", "-Wall", "-Wextra",
            "-ffunction-sections", "-fdata-sections", "-I", SW]


def check_multilib(pre, march):
    got = run([pre + "gcc", "-march=" + march, "-mabi=ilp32", "-print-multi-directory"]).strip()
    if got != MARCHES[march]:
        raise BuildError("-march=%s links the C library in '%s', expected '%s'" % (march, got, MARCHES[march]))
    return got


def sections(pre, elf):
    """(name, size, vma, lma, flags) of every section with ALLOC, from objdump -h."""
    out = run([pre + "objdump", "-h", elf]).splitlines()
    result = []
    for i, line in enumerate(out):
        m = re.match(r"\s*\d+\s+(\S+)\s+([0-9a-f]{8})\s+([0-9a-f]{8})\s+([0-9a-f]{8})", line)
        if m and i + 1 < len(out) and "ALLOC" in out[i + 1]:
            result.append((m.group(1), int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16),
                           out[i + 1].strip()))
    return result


def check_layout(secs):
    by_name = {s[0]: s for s in secs}
    if ".text" not in by_name or by_name[".text"][2] != 0:
        raise BuildError(".text does not start at address 0")
    for name, size, vma, lma, flags in secs:
        if size == 0 or "LOAD" not in flags:
            continue
        if lma + size > ROM_END:
            raise BuildError("section %s (%d bytes) loads from %08X, outside the 64 KB ROM" % (name, size, lma))
        if vma != lma and not (RAM_BASE <= vma and vma + size <= RAM_END):
            raise BuildError("section %s runs at %08X, outside RAM" % (name, vma))
    if ".data" in by_name:
        _, size, vma, lma, _ = by_name[".data"]
        if size and not (vma >= RAM_BASE and lma < ROM_END):
            raise BuildError(".data must run in RAM and load from ROM (VMA %08X, LMA %08X)" % (vma, lma))


def symbols(pre, elf):
    table = {}
    for line in run([pre + "nm", elf]).splitlines():
        f = line.split()
        if len(f) == 3:
            table[f[2]] = int(f[0], 16)
    return table


def build(sources, march="rv32imc_zicsr", out_dir=None, name=None, opt="-O2", title=None, extra=()):
    """Build and convert; returns a dict with the paths, the ROM words and the symbols."""
    pre = toolchain_prefix()
    if pre is None:
        raise BuildError("riscv-none-elf-gcc not found (PATH or .tools/xpack-riscv-none-elf-gcc-*)")
    if march not in MARCHES:
        raise BuildError("unsupported -march=%s (use %s)" % (march, " or ".join(MARCHES)))
    name = name or os.path.splitext(os.path.basename(sources[0]))[0]
    out_dir = out_dir or os.path.join(SW, "build", name)
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.join(out_dir, name)
    elf, binary = base + ".elf", base + ".bin"

    libdir = check_multilib(pre, march)
    run([pre + "gcc"] + cflags(march, opt) +
        ["-nostartfiles", "-T", os.path.join(SW, "linker.ld"), "--specs=nano.specs",
         "-Wl,--gc-sections", "-Wl,-Map=" + base + ".map", "-o", elf] + RUNTIME + list(sources) +
        list(extra))          # after the sources, so that libraries such as -lm resolve
    secs = sections(pre, elf)
    check_layout(secs)
    with open(base + ".lst", "w") as f:
        f.write(run([pre + "objdump", "-d", "-S", elf]))
    run([pre + "objcopy", "-O", "binary", elf, binary])
    with open(binary, "rb") as f:
        data = f.read()
    words = bin2mem.convert(data, base, title or "%s (%s)" % (name, march))
    return {"name": name, "elf": elf, "bin": binary, "prefix": base, "words": words, "bytes": len(data),
            "symbols": symbols(pre, elf), "sections": secs, "libdir": libdir}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("sources", nargs="+", help="C or assembly sources of the program")
    ap.add_argument("--march", default="rv32imc_zicsr", choices=sorted(MARCHES))
    ap.add_argument("-O", dest="opt", default="2", help="optimisation level (default 2)")
    ap.add_argument("--name", help="output name (default: the first source's name)")
    ap.add_argument("--out", help="output directory (default: sw/build/<name>)")
    ap.add_argument("--stack-size", type=int,
                    help="bytes reserved for the stack below the end of RAM (default 8192)")
    ap.add_argument("--extra", action="append", default=[], metavar="OPTION",
                    help="one more gcc option, written as --extra=OPTION (repeatable)")
    ap.add_argument("--install", action="store_true",
                    help="also write rom.hex and rom_lo/_hi .hex/.mif in the project root")
    args = ap.parse_args()
    try:
        extra = list(args.extra)
        if args.stack_size:
            extra.append("-Wl,--defsym=__stack_size=%d" % args.stack_size)
        r = build(args.sources, args.march, args.out, args.name, "-O" + args.opt, extra=extra)
    except (BuildError, bin2mem.ConvertError) as e:
        sys.exit("build: %s" % e)

    sym = r["symbols"]
    print("%s: -march=%s, C library %s" % (r["elf"], args.march, r["libdir"]))
    for name, size, vma, lma, flags in r["sections"]:
        if size:
            print("  %-12s %6d bytes  run %08X  %s" % (name, size, vma,
                                                       "load %08X" % lma if "LOAD" in flags else "no contents"))
    print("  ROM image %d of 65536 bytes; heap %d bytes (%08X-%08X); stack %d bytes below %08X"
          % (r["bytes"], sym["_heap_end"] - sym["_end"], sym["_end"], sym["_heap_end"],
             sym["_stack_top"] - sym["_heap_end"], sym["_stack_top"]))
    print("  _halt (end of program) at %08X" % sym["_halt"])
    print("  images: %s.hex, %s_lo/_hi .hex/.mif" % (r["prefix"], r["prefix"]))
    if args.install:
        bin2mem.convert(open(r["bin"], "rb").read(), os.path.join(ROOT, "rom"),
                        "%s (%s)" % (r["name"], args.march))
        print("  installed as rom.hex, rom_lo/_hi .hex/.mif in %s" % ROOT)
        print("  Quartus: Processing > Update Memory Initialization File, then Processing > Start >"
              " Start Assembler (or a full compilation); then program the .sof")


if __name__ == "__main__":
    main()
