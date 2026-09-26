#!/usr/bin/env python3
"""Run a C program on the Timur reference model, and optionally prepare an RTL run.

Takes the .elf that sw/build.py wrote (the ROM image is the .hex next to it), runs the
image on the instruction-level model of sw/gen_soc_tests.py with interrupts and console
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

import argparse
import codecs
import os
import sys

import build
import gen_soc_tests as soc

UART_BIT = 16            # with UART_DIVIDER = 15
COUNTERS_LO = {0xB00, 0xB02, 0xC00, 0xC01, 0xC02}
COUNTERS_HI = {0xB80, 0xB82, 0xC80, 0xC81, 0xC82}


class FakeTime(soc.Timur):
    """The counters count executed instructions, and are not marked timing-dependent."""
    read_time = False

    def csr_read(self, a):
        if a in COUNTERS_LO or a in COUNTERS_HI:
            self.read_time = True
            return (self.retired >> (32 if a in COUNTERS_HI else 0)) & soc.MASK
        return soc.Timur.csr_read(self, a)


def load_words(path):
    words = []
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("//"):
            words.append(int(line.split()[0], 16))
    return words


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("elf", help="program built by sw/build.py (the .hex next to it is the image)")
    ap.add_argument("--input", default="", help="console input, with Python escapes such as \\r")
    ap.add_argument("--max", type=int, default=20000000, help="instructions to run at most")
    ap.add_argument("--fake-time", action="store_true",
                    help="let the cycle counters count instructions, so delay loops end")
    ap.add_argument("--vectors", help="write a vector file for tb/timur_soc_tb.v")
    ap.add_argument("--cycles", type=int, default=2000000,
                    help="RTL run length for a program that does not end (default 2000000)")
    args = ap.parse_args()

    hex_path = os.path.splitext(args.elf)[0] + ".hex"
    pre = build.toolchain_prefix()
    if pre is None:
        sys.exit("run_model: riscv-none-elf-nm not found (PATH or .tools/)")
    halt = build.symbols(pre, args.elf).get("_halt")
    words = load_words(hex_path)
    uart_in = codecs.escape_decode(args.input.encode())[0]

    if args.fake_time:
        soc.CSR_TIMING = set()
    model = FakeTime if args.fake_time else soc.Timur
    m = model({4 * i: w for i, w in enumerate(words)}, uart_rx=uart_in, interrupts=True, trace=False)
    ended, timing = False, None
    try:
        for _ in range(args.max):
            if m.step():
                ended = True
                break
    except soc.ModelError as e:
        timing = str(e)

    out = bytes(m.uart_tx)
    sys.stdout.write(out.decode("latin-1").replace("\r\n", "\n"))
    if out and not out.endswith(b"\n"):
        sys.stdout.write("\n")
    print("-" * 72)
    if timing:
        print("stopped: %s; the model cannot predict this program (run it on the RTL or the board)" % timing)
    elif ended and m.pc == halt:
        print("ended at _halt (%08X) after %d instructions" % (halt, m.retired))
    elif ended:
        print("stopped at a jump to itself at %08X after %d instructions (an endless loop in the program)"
              % (m.pc, m.retired))
    else:
        print("still running after %d instructions (PC %08X): an endless loop, or raise --max" % (m.retired, m.pc))
    print("LEDs %03X%s" % (m.gpio_out, "  (0x200 | exit code %d)" % (m.gpio_out & 0x1FF)
                           if ended and m.pc == halt and m.gpio_out & 0x200 else ""))
    if m.traps:
        causes = {}
        for cause, _, _ in m.traps:
            causes[cause] = causes.get(cause, 0) + 1
        print("traps: " + ", ".join("%d x mcause %X" % (n, c) for c, n in sorted(causes.items())))
    if m.uart_rx or m.rx_valid:
        print("unread console input: %d bytes" % (len(m.uart_rx) + m.rx_valid))

    if args.vectors:
        exact = ended and m.pc == halt and not timing and not getattr(m, "read_time", False)
        base = os.path.splitext(args.vectors)[0]
        out_path, in_path = base + ".out", base + ".in"
        for p in (hex_path, out_path, in_path, args.vectors):
            if len(p) >= 64:
                sys.exit("run_model: path %s is longer than the testbench's 63 characters" % p)
        with open(args.vectors, "w") as f:
            f.write("// %s: written by sw/run_model.py for tb/timur_soc_tb.v with UART_DIVIDER = 15\n" % args.elf)
            if uart_in:
                with open(in_path, "wb") as g:
                    g.write(uart_in)
                f.write("UARTIN %s\n" % in_path)
            if exact:
                with open(out_path, "wb") as g:
                    g.write(out)
                cycles = 20 * m.retired + 3 * 10 * UART_BIT * (len(out) + 3 * len(uart_in)) + 20000
                f.write("PROG %s %d %08X 0\n" % (hex_path, cycles, halt))
                f.write("UARTTEXT %s\n" % out_path)
                f.write("LEDS %03X\n" % m.gpio_out)
                f.write("DIVS %d\n" % m.divs)
            else:
                f.write("PROG %s %d FFFFFFFF 0\n" % (hex_path, args.cycles))
                f.write("UARTSHOW\n")
        if exact:
            print("wrote %s: the RTL run must print exactly %s" % (args.vectors, out_path))
        else:
            print("wrote %s: the RTL runs the program for %d cycles and shows its output (no expected"
                  " output: the program does not end, or its output depends on timing)"
                  % (args.vectors, args.cycles))


if __name__ == "__main__":
    main()
