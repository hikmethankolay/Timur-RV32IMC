#!/usr/bin/env python3
"""Timur SoC system tests: run the directed and random programs on the model, write the vectors.

Writes, relative to the project root:
  vectors/timur_soc_<name>.hex   ROM images (32-bit words) loaded by tb/timur_soc_tb.v
  vectors/timur_soc_vectors.txt  programs and expected results for that testbench
  rom.hex                        default ROM image, 32-bit words (testbenches)
  rom_lo.hex, rom_hi.hex,        the same image as the two 16-bit ROM banks: the
  rom_lo.mif, rom_hi.mif         simulation and synthesis initialisation of rom_ahb
  sw/bringup/*.hex, *_lo.mif, *_hi.mif   hardware bring-up programs (Phase 9)

The programs are the assembly sources in sw/programs/. Most are assembled by
the small assembler in sw/timur_tools/asm.py. The Phase 11 programs, which
need real 16-bit encodings, are assembled with the GNU toolchain; without it
the committed images in vectors/ are used, so the expectations can still be
regenerated.

The reference model (sw/timur_tools/model.py) executes the programs on the
Timur memory map. Values the model cannot know (the cycle and instret
counters, mip) taint the registers and RAM words derived from them; those are
left out of the automatic checks and given hand-written ones, as are programs
whose results depend on timing (UART busy flags, DMAC polling, interrupts).

The Phase 7 random program is generated from --seed; the seed is recorded in
the vector file so a failing run can be reproduced.

Usage:  python3 sw/gen_soc_tests.py [--seed N] [--length N] [--root DIR]
"""

from __future__ import annotations

import argparse
import logging
import re
import sys
import tempfile
from collections.abc import Mapping, Sequence
from pathlib import Path

from timur_tools import cli, memmap, paths, romimage
from timur_tools.asm import Assembly, assemble
from timur_tools.errors import GenerationError
from timur_tools.isa import F3_DIV
from timur_tools.model import TimurModel, divide
from timur_tools.paths import Project
from timur_tools.randprog import random_c_program, random_program
from timur_tools.rvc import decompress
from timur_tools.toolchain import Toolchain, find_toolchain, warn_if_not_pinned
from timur_tools.vectors import NO_HALT, Vectors, model_checks

LOG = logging.getLogger("timur.gen_soc_tests")

DEFAULT_SEED = 20260926
DEFAULT_LENGTH = 600

GNU_MARCH = "rv32imc_zicsr"
VECTOR_FILE = paths.VECTORS + "/timur_soc_vectors.txt"
DEFAULT_ROM = "rom"  # rom.hex, rom_lo/_hi .hex/.mif in the project root
WITH_WAITS = ", with HREADY waits"

# ---- expectations that do not come from the model ---------------------------------------
# Reference encoding of the Phase 5 program, from the build guide.
PHASE5_WORDS = [
    0x00500093, 0x00300113, 0x002081B3, 0x40208233, 0x0020F2B3, 0x0020E333,
    0x20000537, 0x00352023, 0x00108663, 0xDEADC3B7, 0xDEADC3B7, 0x00100393,
    0x12345437, 0x00001497, 0xFFB00593, 0x02800613, 0x008006EF, 0x00100713,
    0x0000006F,
]  # fmt: skip
PHASE5_EXPECTED = {
    1: 5, 2: 3, 3: 8, 4: 2, 5: 1, 6: 7, 7: 1, 8: 0x12345000, 9: 0x1034,
    10: 0x20000000, 11: 0xFFFFFFFB, 12: 0x28, 13: 0x44, 14: 0,
}  # fmt: skip

# The system test polls the UART and the DMAC, so its end state is written by hand.
SYSTEM_EXPECTED = {
    1: 0x2A5, 2: 0x2A5, 3: memmap.TB_SWITCHES, 4: 0x3FF, 5: 0x3FF, 6: 0xC3, 7: 0x3C3, 8: 0x03,
    9: 0x4B, 10: 1, 11: 0x56, 12: 0, 13: 1, 14: 1, 15: 0x40000200, 16: 0x1000,
    17: 0x20000100, 18: 8, 19: 1, 20: 0x20000000, 21: 0x40000000, 22: 0x2A5,
    23: 0x22222222, 24: 0x22222222, 25: 2, 26: 0, 27: 0, 28: 0, 29: 2, 30: 0, 31: 0,
}  # fmt: skip
SYSTEM_LEDS = 0x3C3
DMA_DESTINATION = memmap.RAM_BASE + 0x100


def dma_table(words: int) -> dict[int, int]:
    """RAM contents after the DMA copy of the programs' ROM table (11111111, 22222222, ...)."""
    return {DMA_DESTINATION + 4 * i: 0x11111111 * (i + 1) for i in range(words)}


SYSTEM_RAM = {
    memmap.RAM_BASE: 0x2A5,
    memmap.RAM_BASE + 4: 0x2A5,
    memmap.RAM_BASE + 8: 0x22222222,
    **dma_table(8),
}

# Trap causes the Phase 10 and Phase 11 programs must raise, in order.
PHASE10_CAUSES = [11, 3, 2, 2, 2, 4, 4, 4, 4, 6, 6, 6]
PHASE11_CAUSES = [3, 2, 2, 11]

# Final program: the ECALL traps to the handler at 0x100 (x22 = mcause = 11,
# x23 = mepc + 4 = 0x78); x17 holds a cycle count and is checked for non-zero.
FINAL_EXPECTED = {
    1: 10, 2: 1, 3: 10, 4: 11, 5: 10, 6: 10, 7: 42, 10: 0x55, 11: 0x40000200,
    12: 0x1000, 13: 0x20000100, 14: 4, 15: 1, 16: 0, 18: 0x100, 19: 99,
    20: 0x20000000, 21: 0x40000000, 22: 11, 23: 0x78,
}  # fmt: skip
FINAL_RAM = {memmap.RAM_BASE: 10, **dma_table(4)}
FINAL_LEDS = 42

BRINGUP_CHECKSUM = 0xAAAAAAAA
# (program, description written into the .mif headers)
BRINGUP_PROGRAMS = [
    ("bringup_1_gpio", "GPIO: LEDs mirror the switches"),
    ("bringup_2_uart", "UART: 'U' in a loop"),
    ("bringup_3_dma", "DMA copy of four ROM words, checksum on the LEDs"),
]

VECTOR_FILE_HELP = """\
Directives, one per line:
  PROG <image> <max_cycles> <halt_pc> <hready_waits>  load the image into the ROM, clear the
      RAM, reset, run until the instruction at halt_pc leaves EX, drain the pipeline and
      wait for the UART. halt_pc FFFFFFFF: no halt expected, run max_cycles (endless loops).
      hready_waits = 1: HREADY is forced low for three cycles in the
      data phase of every RAM load, with garbage on HRDATA until the last cycle.
      After each PROG the testbench also checks: halt reached,
      fetch word = ROM[PC] and IF/ID word = ROM[IF/ID pc] every cycle, one multiplier
      start and one stall cycle per MUL, exactly one divider start per DIV, one bubble
      per load-use, no misaligned CPU bus access, no interrupt taken with a MUL or DIV
      in EX.
  REG <n> <value>      register x<n> at the end of the run
  REGNZ <n>            register x<n> is not zero (timing-dependent counter values)
  RAM <addr> <value>   RAM word
  RAMNZ <count>        number of non-zero words in 0x2000_0000 - 0x2000_0FFF
  LEDS <value>         gpio_out
  UART <byte>          next byte decoded from uart_tx (8N1, 434 cycles per bit)
  UARTN <count>        number of bytes decoded from uart_tx
  DIVS <count>         divider start pulses
  IRQHELD <count>      the interrupt was pending for at least <count> cycles while a MUL or
                       DIV was in EX (it had to wait)
  RETIRED <count>      instructions that left EX, up to and including the first halt
  TRACE <pc>           next PC in the order instructions left EX
"""


def image_name(program: str) -> str:
    """Root-relative name of a system-test ROM image, as written into PROG lines."""
    return "%s/timur_soc_%s.hex" % (paths.VECTORS, program)


def bringup_name(program: str) -> str:
    """Root-relative name of a bring-up ROM image."""
    return "%s/%s.hex" % (paths.BRINGUP, program)


def program_source(project: Project, name: str) -> str:
    """The assembly source sw/programs/<name>.s."""
    return (project.programs / (name + ".s")).read_text(encoding="utf-8")


def assemble_program(project: Project, name: str) -> Assembly:
    """Assemble sw/programs/<name>.s with the mini assembler."""
    return assemble(program_source(project, name))


def check_decompress(project: Project) -> None:
    """The model's expansion of 16-bit instructions must match the toolchain's for
    every encoding (vectors/decompressor_vectors.txt, if it exists)."""
    path = project.vectors / "decompressor_vectors.txt"
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) == 3 and not line.startswith("//"):
            halfword, word = int(fields[0], 16), int(fields[1], 16)
            if decompress(halfword) != word:
                raise GenerationError(
                    "model decompressor: %04X -> %08X, toolchain %08X"
                    % (halfword, decompress(halfword), word)
                )


def check_registers(model: TimurModel, expected: Mapping[int, int], program: str) -> None:
    """The model must agree with the hand-written end state of a program."""
    for register, value in expected.items():
        if model.x[register] != value:
            raise GenerationError(
                "model: %s x%d = %08X, expected %08X"
                % (program, register, model.x[register], value)
            )


def check_trap_causes(model: TimurModel, expected: Sequence[int], program: str) -> None:
    """The model must take exactly the traps the program is written to raise."""
    causes = [cause for cause, _, _ in model.traps]
    if causes != list(expected):
        raise GenerationError("model: %s trap causes %s" % (program, causes))


def write_hex(path: Path, assembly: Assembly, comments: bool = True) -> None:
    """Write a word hex image, each instruction followed by its source text."""
    notes = {address: text for address, _, text in assembly.listing}
    lines = []
    for index, word in enumerate(romimage.image_words(assembly.image)):
        address = 4 * index
        if comments and address in notes:
            lines.append("%08X  // %04X: %s" % (word, address, notes[address]))
        else:
            lines.append("%08X" % word)
    romimage.write_lines(path, lines)


def gnu_program(
    project: Project, toolchain: Toolchain | None, name: str, source: str
) -> tuple[dict[int, int], dict[str, int]]:
    """Assemble with GNU as for rv32imc_zicsr (16-bit forms wherever possible), link at
    address 0, write vectors/timur_soc_<name>.hex with the labels as comments, and return
    (image, labels). Without the toolchain the committed file is read back instead."""
    path = project.path(image_name(name))
    if toolchain is None:
        LOG.info("no toolchain: reusing the committed image %s", image_name(name))
        committed = romimage.read_word_hex(path)
        return committed.memory(), committed.tags
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        src, obj, elf, binary = (work / ("p" + ext) for ext in (".s", ".o", ".elf", ".bin"))
        src.write_text(source, encoding="utf-8")
        toolchain.run("as", "-march=" + GNU_MARCH, "-mabi=ilp32", "-mno-relax", "-o", obj, src)
        toolchain.run("ld", "-m", "elf32lriscv", "-Ttext=0", "-e", "0", "-o", elf, obj)
        toolchain.run("objcopy", "-O", "binary", "-j", ".text", elf, binary)
        words = romimage.words_from_binary(binary.read_bytes())
        labels = {}
        for line in toolchain.run("nm", elf).splitlines():
            fields = line.split()
            if len(fields) == 3 and fields[1] in "tT" and not fields[2].startswith((".", "_")):
                labels[fields[2]] = int(fields[0], 16)
        listing = toolchain.run("objdump", "-d", "-M", "no-aliases", elf)
    compressed = sum(
        1 for line in listing.splitlines() if re.match(r"\s+[0-9a-f]+:\s+[0-9a-f]{4}\s", line)
    )
    lines = [
        "// %s: assembled by GNU as (%s), %d 16-bit instructions" % (name, GNU_MARCH, compressed)
    ]
    for label in sorted(labels, key=labels.__getitem__):
        lines.append("// label %s %08X" % (label, labels[label]))
    lines += ["%08X" % word for word in words]
    romimage.write_lines(path, lines)
    return romimage.memory_from_words(words), labels


# ---- the sections of the vector file -----------------------------------------------------
def add_header(vec: Vectors, seed: int) -> None:
    """The description of the file format."""
    vec.comment("timur_soc test vectors, generated by sw/gen_soc_tests.py (random seed %d)" % seed)
    for line in VECTOR_FILE_HELP.splitlines():
        vec.comment(line)
    vec.comment("")


def add_modelled(
    vec: Vectors, project: Project, name: str, titles: Sequence[str], max_cycles: int
) -> None:
    """Assemble a program, run it on the model and add PROGs with the model's end
    state: titles[0] without and, if given, titles[1] with HREADY wait states."""
    assembly = assemble_program(project, name)
    model = TimurModel(assembly.image).run()
    write_hex(project.path(image_name(name)), assembly)
    for with_waits, title in enumerate(titles):
        vec.comment("==== " + title)
        vec.prog(image_name(name), max_cycles, assembly.labels["halt"], with_waits)
        model_checks(vec, model)


def add_phase5(vec: Vectors, project: Project) -> None:
    """Phase 5: the first program, checked against its reference encoding."""
    assembly = assemble_program(project, "phase5")
    if [assembly.image[4 * i] for i in range(len(PHASE5_WORDS))] != PHASE5_WORDS:
        raise GenerationError("Phase 5 program does not match its reference encoding")
    model = TimurModel(assembly.image).run()
    check_registers(model, PHASE5_EXPECTED, "Phase 5")
    write_hex(project.path(image_name("phase5")), assembly)
    vec.comment("==== Phase 5 test program (no loads)")
    vec.prog(image_name("phase5"), 2000, assembly.labels["t48"], 0)
    model_checks(vec, model)


def add_random(vec: Vectors, project: Project, seed: int, length: int) -> int:
    """The Phase 7 random program; returns the number of instructions it executed."""
    assembly = assemble(random_program(seed, length))
    model = TimurModel(assembly.image).run()
    write_hex(project.path(image_name("random")), assembly)
    executed = len(model.trace)
    for with_waits in (0, 1):
        vec.comment(
            "==== Phase 7 random dependency-dense program, seed %d, %d instructions executed%s"
            % (seed, executed, WITH_WAITS if with_waits else "")
        )
        vec.prog(image_name("random"), 40 * executed + 2000, assembly.labels["halt"], with_waits)
        model_checks(vec, model)
    return executed


def add_system(vec: Vectors, project: Project) -> None:
    """Phase 9 system test: timing-dependent, so the checks are hand-written."""
    assembly = assemble_program(project, "system")
    write_hex(project.path(image_name("system")), assembly)
    vec.comment(
        "==== Phase 9 system test: GPIO, UART, DMA while the CPU runs loads and stores, "
        "default slave"
    )
    vec.prog(image_name("system"), 20000, assembly.labels["halt"], 0)
    vec.regs(SYSTEM_EXPECTED)
    vec.ram(SYSTEM_RAM)
    vec.add("RAMNZ %d" % len(SYSTEM_RAM))
    vec.add("LEDS %03X" % SYSTEM_LEDS)
    vec.add("UART 55")
    vec.add("UART 4B")
    vec.add("UARTN 2")
    vec.add("DIVS 0")


def add_phase10(vec: Vectors, project: Project) -> None:
    """Phase 10: CSR instructions and traps, then the external interrupt."""
    assembly = assemble_program(project, "phase10")
    model = TimurModel(assembly.image).run()
    check_trap_causes(model, PHASE10_CAUSES, "Phase 10")
    write_hex(project.path(image_name("phase10")), assembly)
    for with_waits in (0, 1):
        vec.comment(
            "==== Phase 10: CSR instructions, every trap cause, MRET, counters%s"
            % (WITH_WAITS if with_waits else "")
        )
        vec.prog(image_name("phase10"), 4000, assembly.labels["halt"], with_waits)
        model_checks(vec, model)
        vec.comment("     timing-dependent counter values: hand-written checks")
        vec.regs({24: 1, 26: 4})
        vec.nonzero([22, 23, 25])

    assembly = assemble_program(project, "interrupt")
    write_hex(project.path(image_name("interrupt")), assembly)
    quotients = [0x12345000]  # the program divides this by 7 four times
    for _ in range(4):
        quotients.append(divide(quotients[-1], 7, F3_DIV))
    vec.comment(
        "==== Phase 10: external interrupt (DMAC done) held off by a chain of DIVs, taken once"
    )
    vec.prog(image_name("interrupt"), 3000, assembly.labels["halt"], 0)
    vec.regs(
        {
            8: quotients[1],
            9: quotients[2],
            10: quotients[3],
            11: quotients[4],
            20: 1,
            21: 1,
            22: memmap.CAUSE_EXTERNAL_INTERRUPT,
            23: memmap.MIP_MEIP,
            24: 0,
            25: 0,
            26: 1,
        }
    )
    vec.ram(dma_table(4))
    vec.add("RAMNZ 4")
    vec.add("DIVS 4")
    vec.add("IRQHELD 20")


def add_phase11(
    vec: Vectors, project: Project, toolchain: Toolchain | None, seed: int, length: int
) -> None:
    """Phase 11: the directed and the random program of compressed instructions."""
    image, labels = gnu_program(project, toolchain, "phase11", program_source(project, "phase11"))
    model = TimurModel(image).run()
    check_trap_causes(model, PHASE11_CAUSES, "Phase 11")
    for with_waits in (0, 1):
        vec.comment(
            "==== Phase 11: compressed instructions, straddling 32-bit instructions, PC + 2 links, "
            "16-bit traps%s" % (WITH_WAITS if with_waits else "")
        )
        vec.prog(image_name("phase11"), 4000, labels["halt"], with_waits)
        model_checks(vec, model)

    image, labels = gnu_program(project, toolchain, "random_c", random_c_program(seed, length))
    model = TimurModel(image).run()
    executed = len(model.trace)
    for with_waits in (0, 1):
        vec.comment(
            "==== Phase 11 random program of 16-bit and 32-bit instructions, seed %d, "
            "%d instructions executed%s" % (seed, executed, WITH_WAITS if with_waits else "")
        )
        vec.prog(image_name("random_c"), 40 * executed + 2000, labels["halt"], with_waits)
        model_checks(vec, model)


def add_final(vec: Vectors, project: Project) -> None:
    """The final cross-phase program, which is also the default ROM image."""
    assembly = assemble_program(project, "final")
    model = TimurModel(assembly.image).run()
    check_registers(model, FINAL_EXPECTED, "final program")
    write_hex(project.root / (DEFAULT_ROM + ".hex"), assembly, comments=False)
    romimage.write_banks(
        project.root / DEFAULT_ROM,
        romimage.image_words(assembly.image),
        "final cross-phase verification program",
    )
    vec.comment("==== Final cross-phase program from rom.hex: ECALL round trip, x17 = cycle count")
    vec.prog(DEFAULT_ROM + ".hex", 3000, assembly.labels["halt"], 0)
    vec.regs(FINAL_EXPECTED)
    vec.nonzero([17])
    vec.ram(FINAL_RAM)
    vec.add("RAMNZ %d" % len(FINAL_RAM))
    vec.add("LEDS %03X" % FINAL_LEDS)
    vec.add("UART 55")
    vec.add("UARTN 1")
    vec.add("DIVS 1")


def add_bringup(vec: Vectors, project: Project) -> None:
    """The hardware bring-up programs (Phase 9) and their ROM images."""
    project.bringup.mkdir(parents=True, exist_ok=True)
    assemblies = {}
    for name, title in BRINGUP_PROGRAMS:
        assembly = assemblies[name] = assemble_program(project, name)
        write_hex(project.path(bringup_name(name)), assembly, comments=False)
        romimage.write_banks(
            project.bringup / name, romimage.image_words(assembly.image), "bring-up, " + title
        )
    vec.comment("==== Hardware bring-up 1: LEDs mirror the switches (endless loop)")
    vec.prog(bringup_name("bringup_1_gpio"), 300, NO_HALT, 0)
    vec.add("LEDS %03X" % memmap.TB_SWITCHES)
    vec.comment("==== Hardware bring-up 2: 'U' in a loop (endless loop)")
    three_frames = 3 * memmap.UART_FRAME_BITS * memmap.UART_CYCLES_PER_BIT
    vec.prog(bringup_name("bringup_2_uart"), three_frames, NO_HALT, 0)
    vec.add("UART 55")
    vec.add("UART 55")
    dma = assemblies["bringup_3_dma"]
    model = TimurModel(dma.image).run()
    vec.comment("==== Hardware bring-up 3: DMA copy, checksum AAAAAAAA on the LEDs")
    vec.prog(bringup_name("bringup_3_dma"), 2000, dma.labels["halt"], 0)
    vec.regs({5: BRINGUP_CHECKSUM})
    vec.ram(dma_table(4))
    vec.add("LEDS %03X" % (BRINGUP_CHECKSUM & memmap.GPIO_MASK))
    if model.x[5] != BRINGUP_CHECKSUM:
        raise GenerationError("model: bring-up checksum %08X" % model.x[5])


def generate(project: Project, seed: int, length: int, toolchain: Toolchain | None) -> int:
    """Write every image and the vector file; returns the number of instructions
    the random program executed."""
    check_decompress(project)
    vec = Vectors()
    add_header(vec, seed)
    add_phase5(vec, project)
    add_modelled(
        vec, project, "phase6",
        ["Phase 6: loads and stores of every size, links, LUI/AUIPC, register-file bypass"], 2000,
    )  # fmt: skip
    add_modelled(
        vec, project, "phase7",
        ["Phase 7: hazards",
         "Phase 7: hazards, HREADY forced low for three cycles during every RAM load"], 5000,
    )  # fmt: skip
    executed = add_random(vec, project, seed, length)
    add_system(vec, project)
    add_phase10(vec, project)
    add_phase11(vec, project, toolchain, seed + 1, length)
    add_final(vec, project)
    add_bringup(vec, project)
    vec.write(project.path(VECTOR_FILE))
    return executed


def main(argv: Sequence[str] | None = None) -> int:
    """Generate the system tests; returns the exit status."""
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n")[0])
    parser.add_argument(
        "--seed", type=int, default=DEFAULT_SEED, help="seed of the random programs"
    )
    parser.add_argument(
        "--length", type=cli.positive_int, default=DEFAULT_LENGTH,
        help="number of generated items in each random program",
    )  # fmt: skip
    cli.add_common_arguments(parser)
    args = parser.parse_args(argv)
    project = cli.project_from(args)

    toolchain = find_toolchain(project.root)
    if toolchain is not None:
        warn_if_not_pinned(toolchain)
    executed = generate(project, args.seed, args.length, toolchain)
    print("random program: seed %d, %d instructions executed" % (args.seed, executed))
    return 0


if __name__ == "__main__":
    sys.exit(cli.run(main, "gen_soc_tests"))
