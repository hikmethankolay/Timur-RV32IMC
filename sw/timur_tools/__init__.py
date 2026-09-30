"""Host-side tools of the Timur RV32IMC SoC.

Reusable modules behind the scripts in sw/:

  paths       where the files of a project live
  memmap      memory map, CSR addresses and trap causes (the Python copy of
              sw/runtime/include/timur_defs.h and sw/runtime/linker.ld)
  toolchain   finding and running the RISC-V GNU toolchain
  romimage    ROM image files: word hex, 16-bit banks, Quartus .mif
  builder     compile, link and check a C program
  isa         RV32IMC instruction formats
  asm         two-pass assembler for the directed test programs
  rvc         expansion of 16-bit instructions
  model       instruction-level reference model of the SoC
  randprog    random test programs
  vectors     vector files for tb/timur_soc_tb.v
  cli         what the command-line entry points share
"""
