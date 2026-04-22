# Timur-RV32IMC

> A fully pipelined RISC-V RV32IMC soft-core microcontroller implemented in Verilog/SystemVerilog, targeting Intel FPGAs with Quartus Prime. Capable of executing GCC-compiled C code with a complete AHB+APB bus fabric, hardware multiply/divide, and Machine Mode privilege support.

---

## Table of Contents

- [Timur-RV32IMC](#timur-rv32imc)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Architecture](#architecture)
  - [ISA Support](#isa-support)
  - [Current Status](#current-status)
  - [Module Structure](#module-structure)
    - [Phase 1 — Primitives](#phase-1--primitives)
    - [Phase 2 — Execution Datapath](#phase-2--execution-datapath)
    - [Phase 3 — State and Memory](#phase-3--state-and-memory)
    - [Phase 4 — Instruction Decode and Control](#phase-4--instruction-decode-and-control)
    - [Phase 5 — Single-Cycle Integration](#phase-5--single-cycle-integration)
    - [Phase 6 — Pipeline Registers](#phase-6--pipeline-registers)
    - [Phase 7 — Hazard Resolution](#phase-7--hazard-resolution)
    - [Phase 8 — APB Peripherals](#phase-8--apb-peripherals)
    - [Phase 9 — AHB Bus Fabric](#phase-9--ahb-bus-fabric)
    - [Phase 10 — CSR Register File and Privileged Architecture](#phase-10--csr-register-file-and-privileged-architecture)
    - [Phase 11 — C Extension Decompressor](#phase-11--c-extension-decompressor)
    - [Phase 12 — C Software Layer](#phase-12--c-software-layer)
  - [Bus Architecture & Address Map](#bus-architecture--address-map)
    - [AHB Address Map](#ahb-address-map)
    - [APB Address Map (within bridge)](#apb-address-map-within-bridge)
    - [AHB Masters](#ahb-masters)
  - [Pipeline Design](#pipeline-design)
  - [Hazard Handling](#hazard-handling)
  - [Peripherals](#peripherals)
    - [GPIO](#gpio)
    - [UART](#uart)
    - [DMAC](#dmac)
  - [Tool Stack](#tool-stack)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Cloning](#cloning)
  - [Simulation](#simulation)
  - [Building & Programming](#building--programming)
  - [C Software Layer](#c-software-layer)
  - [Project Roadmap](#project-roadmap)
  - [Directory Structure](#directory-structure)
  - [License](#license)

---

## Overview

**Timur-RV32IMC** is a from-scratch implementation of a pipelined RISC-V microcontroller built for Intel FPGAs. The design follows the classic 5-stage pipeline (IF → ID → EX → MEM → WB) and is implemented entirely in synthesizable Verilog/SystemVerilog with no IP vendor dependencies except the ALTPLL clock generator.

The goal is a complete, C-executable microcontroller — not just a CPU core. This means a full AMBA bus fabric, real memory-mapped peripherals (GPIO, UART, DMAC), a Machine Mode privileged architecture with trap/exception handling, and a C software layer (linker script, `crt0.S`, syscall stubs) that allows programs compiled with a standard RISC-V GCC toolchain to run without modification.

---

## Architecture

```text
┌───────────────────────────────────────────────────────┐
│                  AHB Bus Fabric                       │
│  ┌──────────┐  ┌──────────┐                           │
│  │   CPU    │  │  DMAC    │  ← Two AHB Masters        │
│  │(Master 0)│  │(Master 1)│                           │
│  └────┬─────┘  └────┬─────┘                           │
│  ┌────▼─────────────▼────┐                            │
│  │       AHB Arbiter     │ Fixed priority (CPU > DMAC)│
│  └──────────┬────────────┘                            │
│    ┌────────┼────────┐                                │
│  ┌─▼──┐  ┌──▼──┐  ┌──▼────────┐                       │
│  │RAM │  │ ROM │  │AHB→APB    │                       │
│  └────┘  └─────┘  │  Bridge   │                       │
│                   └──┬────────┘                       │
│              ┌───────┼──────┐                         │
│           ┌──▼──┐ ┌──▼──┐ ┌─▼───┐                     │
│           │UART │ │GPIO │ │DMAC │                     │
│           │(APB)│ │(APB)│ │Regs │                     │
│           └─────┘ └─────┘ └─────┘                     │
└───────────────────────────────────────────────────────┘
```

**Pipeline stages:** IF → ID → EX → MEM → WB\
**Bus standard:** ARM AMBA — AHB for high-speed paths, APB for peripherals\
**Target FPGA:** Intel DE1-SoC (Cyclone V) — synthesized with Quartus Prime

---

## ISA Support

| Extension | Description | Status |
| --------- | ----------- | ------ |
| **RV32I** | Base 32-bit integer instructions | ✅ Phase 2 Complete |
| **RV32M** | Hardware multiply & divide (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU) | ✅ Phase 2 Complete |
| **RV32C** | 16-bit compressed instructions | 🔜 Phase 11 |
| **Zicsr** | CSR read/write instructions (CSRRW, CSRRS, CSRRC + immediate variants) | 🔜 Phase 10 |
| **M-mode** | Machine Mode privilege: traps, exceptions, MRET, mtvec, mepc, mcause | 🔜 Phase 10 |

---

## Current Status

**Phase 2 complete — Execution Datapath fully verified.**

| Phase | Description | Status |
| ----- | ----------- | ------ |
| 1 | Foundational primitives (Mux2, Mux4, DFF, ALTPLL) | ✅ Complete |
| 2 | Execution datapath — ALU, Barrel Shifter, Multiplier, Divider, Branch Evaluator | ✅ Complete |
| 3 | State & memory — PC, Register File, ROM AHB slave, RAM AHB slave | 🔜 Next |
| 4 | Instruction decode & control — ImmGen, Parser, ALU Decoder, Main Control | 🔜 |
| 5 | Single-cycle integration (HREADY=1 assumed) | 🔜 |
| 6 | 5-stage pipelining with pipeline registers | 🔜 |
| 7 | Hazard resolution — forwarding, load-use, HREADY, div_busy, branch flush | 🔜 |
| 8 | APB peripherals — GPIO, UART, DMAC control registers, AHB-to-APB bridge | 🔜 |
| 9 | Full AHB bus fabric — arbiter, CPU master, DMAC master, top-level | 🔜 |
| 10 | CSR register file, trap mechanism, MRET | 🔜 |
| 11 | C extension — 16-bit compressed instruction decompressor | 🔜 |
| 12 | C software layer — linker script, crt0.S, syscall stubs | 🔜 |

---

## Module Structure

### Phase 1 — Primitives

- **`mux2.v`** — Parameterized 2:1 multiplexer (default WIDTH=32). Used extensively as ALUSrc mux, MemToReg mux, PC-next mux, forwarding muxes.
- **`mux4.v`** — Parameterized 4:1 multiplexer with 2-bit select. Used in the Forwarding Unit where ALU inputs may come from one of four sources.
- **`d_ff.v`** — D flip-flop with synchronous enable and asynchronous active-low reset. Foundation of all pipeline registers and state elements.
- **`cpu_pll.v`** — ALTPLL Megafunction wrapper. Takes the 50 MHz board oscillator and produces the CPU clock. (`cpu_pll_bb.v` is the black-box stub generated by Quartus for simulation.)

### Phase 2 — Execution Datapath

- **`adder_32bit.v`** — 32-bit adder/subtractor. `sub=1` inverts `b` and carries in 1, implementing two's complement subtraction. Outputs `cout` (unsigned compare) and `overflow` (signed compare).
- **`barrel_shifter.v`** — 32-bit barrel shifter using a 5-stage mux cascade. Supports SLL, SRL, and SRA. Sign fill for SRA uses the original `in[31]`, not the intermediate stage MSB.
- **`multiplier.v`** — Single-cycle multiplier for all four RV32M multiply operations (MUL, MULH, MULHSU, MULHU). Uses 33-bit sign/zero-extended operands to handle mixed signed/unsigned products. Infers Intel DSP blocks.
- **`divider.v`** — Sequential restoring divider. Processes one bit per cycle — 32 cycles total. Implements the full RV32M corner case specification (divide-by-zero, signed overflow). `busy` output feeds the Hazard Detection Unit.
- **`alu.v`** — Top-level ALU. Instantiates adder, barrel shifter, multiplier, and divider. Selects result via a 5-bit `ALUControl` (widened from 4 bits to cover M-extension opcodes). Outputs `zero`, `cout`, `overflow`, `div_busy`.
- **`branch_condition_evaluator.v`** — Branch condition evaluator. Takes ALU flags and a 3-bit `BranchType` (matching RISC-V `funct3`) and produces a single `BranchTaken` signal for all six branch instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU).

### Phase 3 — State and Memory

- **`pc.v`** — Program Counter register. 32-bit DFF with asynchronous reset to `0x00000000`. Enable input driven LOW by the combined stall signal (load-use OR !HREADY OR div_busy) from the Hazard Detection Unit.
- **`registers.v`** — 32×32-bit register file. `x0` hardwired to zero — reads always return 0, writes silently ignored. Two combinational read ports (rs1, rs2) and one synchronous write port (rd).
- **`rom_ahb.v`** — Instruction ROM as an AHB slave. Single-cycle response — `HREADY` always 1. Registers the AHB address phase on the clock edge (`HSEL=1` and `HTRANS[1]=1`), presents `HRDATA` on the following cycle. Initialized from a Quartus `.mif` file.
- **`ram_ahb.v`** — Data RAM as an AHB slave. Single-cycle response — `HREADY` always 1. Decodes `HSIZE` and `HADDR[1:0]` to generate byte-enable signals for sub-word writes. Performs sign/zero-extension on `HRDATA` for LB, LH, LBU, LHU load instructions.

### Phase 4 — Instruction Decode and Control

- **`parser.v`** — Instruction Parser. Purely combinational slicing of the 32-bit instruction word into `opcode`, `rd`, `funct3`, `rs1`, `rs2`, and `funct7` fields.
- **`imm_gen.v`** — Immediate Generator. Sign-extends all five RISC-V immediate formats (I, S, B, U, J) to 32 bits. B-type and J-type `imm[0]` hardwired to 0 to enforce 2-byte alignment.
- **`alu_decoder.v`** — ALU Decoder. Two-level control: maps 2-bit `ALUOp` + `funct3` + `funct7` to the 5-bit `ALUControl` for the ALU. Detects the M-extension by checking `funct7 == 7'b0000001`.
- **`main_control.v`** — Main Control Unit. Combinational lookup from 7-bit `opcode` (plus `funct3`/`funct7` for disambiguation) to all primary control signals: `Branch`, `MemRead`, `MemToReg`, `ALUOp`, `MemWrite`, `ALUSrc`, `RegWrite`, `CSRWrite`, `CSROp`, `IsECALL`, `IsEBREAK`, `IsMRET`. FENCE decoded as NOP.

### Phase 5 — Single-Cycle Integration

No new RTL files. Phase 5 wires all Phase 1–4 modules inside `Timur_RV32IMC.v` into a functioning single-cycle CPU. `HREADY` is assumed always 1 in this phase — the full AHB bus fabric is added in Phase 9. PC Next Logic uses two adders (PC+4 and PC+imm) feeding a mux controlled by `Branch AND BranchTaken`.

### Phase 6 — Pipeline Registers

- **`if_id_reg.v`** — IF/ID pipeline register. Holds `pc` and `instr`. `enable` input freezes the register during any stall. `flush` overrides enable and inserts a NOP (`32'h00000013`) to cancel wrongly-fetched instructions on a branch.
- **`id_ex_reg.v`** — ID/EX pipeline register. Carries all datapath values (`rs1_data`, `rs2_data`, imm, pc, register addresses) and all control signals forward. Explicitly carries `funct3` for AHB `HSIZE` encoding and reserves CSR signal fields (`CSRWrite`, `CSROp`, `csr_addr`, `IsECALL`, `IsEBREAK`, `IsMRET`) from this phase onward even before Phase 10.
- **`ex_mem_reg.v`** — EX/MEM pipeline register. `alu_result` becomes AHB `HADDR` for the data memory address phase. `rs2_data` becomes AHB `HWDATA` for the data phase of stores. Carries `BranchTaken` and `branch_target` for the branch flush logic.
- **`mem_wb_reg.v`** — MEM/WB pipeline register. Carries `mem_read_data` (sourced from AHB `HRDATA`) and `alu_result` to the writeback mux. Also carries `csr_rdata` and `CSRToReg` for CSR instruction writeback (Phase 10).

### Phase 7 — Hazard Resolution

- **`forwarding_unit.v`** — Forwarding Unit. Compares EX-stage source register addresses against MEM-stage and WB-stage destination addresses to generate 2-bit `forwardA`/`forwardB` selects for the Mux4 inputs to the ALU. EX/MEM result has priority over MEM/WB. No forwarding occurs when `rd == x0`.
- **`hazard_detection_unit.v`** — Hazard Detection Unit. Combines three independent stall sources into a single `stall` output: load-use hazard (LW in EX whose `rd` matches `rs1`/`rs2` of the instruction in ID), AHB bus wait (`!HREADY` from the address decoder), and divider busy (`div_busy` from the ALU). All three sources produce identical behaviour: PC frozen, IF/ID frozen, NOP bubble injected into ID/EX. Branch flush (IF/ID and ID/EX cleared when `BranchTaken` is asserted from EX/MEM) is implemented in the top-level datapath.

### Phase 8 — APB Peripherals

- **`gpio_apb.v`** — GPIO APB slave. Three 32-bit memory-mapped registers: `GPIO_OUT` (drives LED pins), `GPIO_IN` (reflects switch/button pins, read-only), `GPIO_DIR` (per-pin direction). `PREADY` hardwired to 1 — no wait states.
- **`uart_apb.v`** — UART APB slave. Standard 8N1 UART with a baud rate generator (`counter_max = f_sys/baud - 1`). TX state machine: IDLE → START → DATA (8 bits) → STOP. `UART_STATUS` register exposes `tx_busy` (bit 0) and `rx_valid` (bit 1) flags. `PREADY` hardwired to 1.
- **`dmac_apb.v`** — DMAC APB control registers. Five registers: `DMAC_SRC`, `DMAC_DST`, `DMAC_LEN`, `DMAC_CTRL` (bit 0 starts transfer), `DMAC_STATUS` (bit 0 busy, bit 1 done). CPU writes these to program a DMA transfer; the AHB master engine (Phase 9) executes it autonomously.
- **`ahb2apb_bridge.v`** — AHB-to-APB bridge. Acts as AHB slave and APB master simultaneously. Four-state FSM: IDLE → SETUP (`HREADY=0`, `PSEL=1`) → ACCESS (`HREADY=0`, `PENABLE=1`) → COMPLETE (`HREADY=1`, drives `HRDATA=PRDATA`). Holds `HREADY=0` for 2 cycles on every peripheral access, which the Hazard Detection Unit sees as a bus-wait stall.

### Phase 9 — AHB Bus Fabric

- **`ahb_arbiter.v`** — 2-master fixed-priority AHB arbiter. CPU (master 0) has higher priority than DMAC (master 1). Master switches only when the current slave asserts `HREADY=1` to prevent mid-transaction corruption.
- **`cpu_ahb_master.v`** — CPU AHB master interface. Translates internal CPU signals (`pc`, `alu_result`, `rs2_data`, `MemRead`, `MemWrite`, `funct3`) into AHB bus signals (`HADDR`, `HTRANS`, `HWRITE`, `HSIZE`, `HWDATA`, `HBUSREQ`). Feeds `bus_stall = !HREADY` back to the Hazard Detection Unit.
- **`ahb_decoder.v`** — AHB address decoder. Combinational logic that asserts exactly one `HSEL` based on `HADDR[31:16]`: ROM (`0x0000`), RAM (`0x2000`), APB bridge (`0x4000`). Muxes `HRDATA` and `HREADY` from the selected slave back to the active master. If no slave is selected: `HRDATA=0`, `HREADY=1`.
- **`dmac_ahb_master.v`** — DMAC AHB master engine. Executes DMA transfers autonomously once `dmac_enable` is asserted by the APB control registers. Six-state FSM (IDLE → REQUEST → `READ_ADDR` → `READ_DATA` → `WRITE_ADDR` → `WRITE_DATA` → DONE). Primary use: copy the `.data` section from ROM to RAM at boot, mirroring what `crt0.S` does in software.

### Phase 10 — CSR Register File and Privileged Architecture

- **`csr_regfile.v`** — CSR Register File. Implements the minimum M-mode CSR set: `mstatus` (MIE/MPIE bits), `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `cycle`, `time`, `instret`. Supports WRITE/SET/CLEAR operations. On `trap_en` pulse: atomically saves PC to `mepc`, writes `mcause`/`mtval`, saves MIE to MPIE, and clears MIE. `mtvec_out` and `mepc_out` feed the PC Next Logic for trap entry and MRET return. `misa` (address `0x301`) hardwired read-only to `0x40001100` (RV32IM) or `0x40001140` (RV32IMC).

### Phase 11 — C Extension Decompressor

- **`decompressor.v`** — 16-bit compressed instruction decompressor. Purely combinational. Checks `instr[1:0]` to detect a compressed instruction, then maps each C-extension encoding (C.ADDI, C.LW, C.SW, C.JAL, C.BEQZ, C.BNEZ, C.MV, C.ADD, C.LWSP, C.SWSP, etc.) to its full 32-bit RV32I equivalent. `illegal` output flags unrecognised encodings. The decompressor output is wired directly into the IF/ID register — the rest of the pipeline sees only 32-bit instructions and requires no changes. A small fetch-stage state machine (ALIGNED / UNALIGNED) handles 16-bit instruction buffering and the corner case of a 32-bit instruction spanning two ROM words.

### Phase 12 — C Software Layer

- **`sw/linker.ld`** — Linker script. Defines ROM at `0x00000000` (64 KB, rx) and RAM at `0x20000000` (64 KB, rwx). Places `.text` and `.rodata` in ROM; places `.data` and `.bss` in RAM. The `.data` section uses `AT> ROM` so its load address is in ROM and its virtual address is in RAM — `crt0.S` copies it at startup. Exports `_bss_start`, `_bss_end`, `_stack_top`, and `_data_start_rom` symbols used by startup code.
- **`sw/crt0.S`** — Startup assembly. Placed at `.text.start` so the linker positions it at address `0x00000000` — the first instruction fetched after reset. Sequence: (1) set `sp = _stack_top`, (2) zero the `.bss` section, (3) copy `.data` from ROM to RAM, (4) write trap handler address to `mtvec`, (5) call `main()`, (6) infinite loop if `main` returns. Includes a minimal trap handler that advances `mepc` past ECALL and executes MRET.
- **`sw/syscalls.c`** — Newlib/picolibc syscall stubs. Provides the low-level I/O primitives GCC's C library requires: `_write` (loops bytes to `UART_DATA`, polling `tx_busy`), `_read` (polls `rx_valid`), `_sbrk` (static heap pointer for `malloc`), `_exit` (infinite loop), and minimal stubs for `_close`, `_fstat`, `_isatty`, `_lseek`.
- **`sw/bin2mif.py`** — Python utility. Converts a raw `.bin` binary produced by `riscv-objcopy` into a Quartus `.mif` file suitable for initializing the ROM BRAM.

---

## Bus Architecture & Address Map

The system uses the AMBA bus hierarchy: AHB for high-bandwidth paths (CPU, DMA, ROM, RAM) and APB for low-speed peripherals accessed through a bridge.

### AHB Address Map

| Range | Slave | Size |
| ----- | ----- | ---- |
| `0x0000_0000 – 0x0000_FFFF` | Instruction ROM | 64 KB |
| `0x2000_0000 – 0x2000_FFFF` | Data RAM | 64 KB |
| `0x4000_0000 – 0x4000_FFFF` | AHB → APB Bridge | — |

### APB Address Map (within bridge)

| Range | Peripheral | Registers |
| ----- | ---------- | --------- |
| `0x4000_0000 – 0x4000_00FF` | UART | DATA, STATUS, CTRL |
| `0x4000_0100 – 0x4000_01FF` | GPIO | OUT, IN, DIR |
| `0x4000_0200 – 0x4000_02FF` | DMAC control | SRC, DST, LEN, CTRL, STATUS |

### AHB Masters

Two masters compete for the AHB bus through a fixed-priority arbiter:

- **Master 0 — CPU:** Instruction fetches and data load/store
- **Master 1 — DMAC:** Autonomous DMA transfers (ROM → RAM copy at boot)

Master switches only occur when `HREADY=1` to prevent mid-transaction corruption.

---

## Pipeline Design

The CPU uses the classic 5-stage RISC pipeline. Each stage boundary is a registered pipeline stage that carries both datapath values and control signals forward.

```text
┌────┐   ┌────┐   ┌────┐   ┌─────┐   ┌────┐
│ IF │──►│ ID │──►│ EX │──►│ MEM │──►│ WB │
└────┘   └────┘   └────┘   └─────┘   └────┘
   IF/ID      ID/EX      EX/MEM      MEM/WB
  (flush,    (flush,    (flush)
   stall)     stall)
```

**Key signal routing decisions:**

- `funct3` is carried through all pipeline registers to encode `HSIZE` on the AHB bus and to control load sign/zero-extension in the RAM slave
- `ALUControl` is 5 bits throughout — not truncated at any stage boundary
- CSR signals (`csr_addr`, `CSRWrite`, `CSROp`, `IsECALL`, `IsMRET`) are reserved in pipeline registers from Phase 6 onward, even before Phase 10 is implemented
- `rs2_data` in `EX/MEM` drives `HWDATA` on the AHB bus for store instructions

---

## Hazard Handling

Three independent stall sources are combined in the Hazard Detection Unit:

```text
stall = load_use_hazard OR bus_wait OR div_busy
```

| Source | Duration | Mechanism |
| ------ | -------- | --------- |
| Load-use hazard | Exactly 1 cycle | LW result not available until end of MEM; cannot be forwarded |
| AHB bus wait (`!HREADY`) | N cycles | APB bridge holds `HREADY=0` during SETUP and ACCESS phases |
| Divider busy | 32 cycles | DIV/REM sequential execution; MUL is 1-cycle (no stall) |

All three stall sources produce identical pipeline behaviour: PC frozen, IF/ID frozen, NOP bubble injected into ID/EX.

**Data forwarding** resolves RAW hazards without stalling for ALU-to-ALU and store-after-load sequences:

- `forwardA/B = 2'b10` — Forward from EX/MEM (highest priority)
- `forwardA/B = 2'b01` — Forward from MEM/WB (fallback)
- `forwardA/B = 2'b00` — Register file value (no hazard)

**Branch flush** is evaluated in EX. When `BranchTaken=1`, IF/ID and ID/EX are both flushed (NOP injected) and the PC loads the branch target — exactly 2 wrongly-fetched instructions are discarded.

---

## Peripherals

### GPIO

Three memory-mapped registers: `GPIO_OUT` (drive LEDs), `GPIO_IN` (read switches), `GPIO_DIR` (per-pin direction). Single-cycle APB slave (`PREADY` always 1).

### UART

Standard 8N1 UART with a baud rate generator derived from the system clock. TX state machine: IDLE → START → DATA (8 bits) → STOP. Status register exposes `tx_busy` and `rx_valid` flags. For a 50 MHz system clock targeting 115200 baud, the counter max is 433.

### DMAC

A two-part DMA controller: APB control registers (SRC, DST, LEN, CTRL, STATUS) that the CPU programs, and an AHB master engine that executes the transfer autonomously after `CTRL[0]` is set. Primary use: copy the `.data` section from ROM to RAM at boot — mirroring what `crt0.S` does in software.

---

## Tool Stack

| Tool | Purpose |
| ---- | ------- |
| Verilog / SystemVerilog | HDL implementation |
| Intel Quartus Prime | Synthesis, place & route, timing analysis |
| ALTPLL Megafunction | PLL / clock generation |
| ModelSim-Intel FPGA Edition | RTL simulation |
| `.qsf` | Pin assignments and device settings |
| `.mif` | ROM initialization (Quartus native BRAM format) |
| `riscv64-unknown-elf-gcc` | Cross-compiler for C software |

---

## Getting Started

### Prerequisites

- Intel Quartus Prime (tested with 21.x / 22.x)
- ModelSim-Intel FPGA Edition (bundled with Quartus)
- DE1-SoC board (Cyclone V 5CSEMA5F31C6) or compatible Intel FPGA board
- RISC-V GNU Toolchain for the C software layer (Phase 12):

  ```bash
  # Ubuntu/Debian — easiest option
  sudo apt install gcc-riscv64-unknown-elf
  
  # Or download xpack prebuilt binaries:
  # https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
  ```

### Cloning

```bash
git clone https://github.com/hikmethan/Timur-RV32IMC.git
cd Timur-RV32IMC
```

---

## Simulation

Simulation uses ModelSim-Intel FPGA Edition (bundled with Quartus). A batch regression runner auto-discovers all testbenches, compiles the full RTL, runs every test, and prints a PASSED/FAILED summary — no manual waveform inspection needed.

### Simulation Prerequisites

- `vsim` must be on your `PATH`. The easiest way is to add the ModelSim `win32aloem` (or `win64aloem`) directory from your Quartus installation:

  ```text
  C:\intelFPGA_lite\<version>\modelsim_ase\win32aloem
  ```

### Running all tests

From the repo root, double-click `run_tests.bat` or run it from a terminal:

```bat
run_tests.bat
```

This calls `vsim -c -do run_tests.tcl`. The TCL script:

1. Globs all `rtl/**/*.v` sources (excluding `*_bb.v` black-box stubs) and all `tb/*.v` testbenches.
2. Creates a fresh `work` library (`vdel` + `vlib`).
3. Compiles everything in one `vlog` pass.
4. Auto-discovers every `*_tb` module by scanning the `tb/` directory.
5. Runs each testbench with `vsim -onfinish stop` + `run -all`, then reads the testbench's internal `failed` and `total` signal counters directly (no log files).
6. Prints a regression summary:

```text
============================================
 REGRESSION COMPLETE
============================================
 PASSED : 12
 FAILED : 0
============================================
```

### Running a single testbench manually

```tcl
# From the ModelSim transcript (or vsim -c)
vlib work
vlog rtl/**/*.v tb/alu_tb.v
vsim work.alu_tb
run -all
```

### Testbench conventions

All testbenches in `tb/` follow a common pattern:

- Test vectors are read from files (no hard-coded stimulus in the HDL).
- Each testbench maintains integer `total` and `failed` counters that the regression runner reads via `examine`.
- A `$display("PASSED")` / `$display("FAILED")` line is printed at the end of each run.
- `$finish` is used to end simulation cleanly — the regression runner catches this via `-onfinish stop`.

**Note:** For combinational modules, testbenches insert a `#10` delay after driving inputs before sampling outputs to allow logic to settle.

---

## Building & Programming

1. Open `Timur_RV32IMC.qpf` in Quartus Prime
2. Verify pin assignments in `Timur_RV32IMC.qsf`
3. Run full compilation: **Processing → Start Compilation**
4. Check timing: **Tools → Timing Analyzer → Report Timing Summary**
   - All paths must have non-negative slack before programming the FPGA
5. Program: **Tools → Programmer** → select `.sof` from `output_files/`

---

## C Software Layer

Once Phases 10–12 are complete, C programs can be compiled and loaded into the ROM `.mif` file:

```bash
# Compile
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2 \
    -ffreestanding -nostdlib \
    -c main.c -o main.o

# Assemble startup code
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
    -c crt0.S -o crt0.o

# Compile syscall stubs
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 \
    -c syscalls.c -o syscalls.o

# Link
riscv64-unknown-elf-ld -T sw/linker.ld \
    crt0.o syscalls.o main.o -o program.elf

# Convert to .mif for Quartus ROM initialization
python3 sw/bin2mif.py program.bin > rtl/rom.mif
```

The memory layout follows the address map above: `.text` and `.rodata` in ROM at `0x0000_0000`, `.data` and `.bss` in RAM at `0x2000_0000`. The stack grows downward from the top of RAM. `crt0.S` handles zeroing `.bss`, copying `.data` from ROM to RAM, setting up `mtvec`, and calling `main()`.

---

## Project Roadmap

```text
Phase 1  ✅  Primitives (Mux2, Mux4, DFF, PLL)
Phase 2  ✅  Execution Datapath (ALU + M-extension)
Phase 3  🔜  PC, Register File, ROM/RAM AHB slaves
Phase 4  🔜  Decode stage (ImmGen, Parser, Control)
Phase 5  🔜  Single-cycle CPU integration
Phase 6  🔜  5-stage pipeline registers
Phase 7  🔜  Hazard resolution (forwarding, stalls, flush)
Phase 8  🔜  APB peripherals (GPIO, UART, DMAC registers)
Phase 9  🔜  Full AHB bus fabric + system top-level
Phase 10 🔜  CSR file, trap mechanism, M-mode
Phase 11 🔜  C extension decompressor (RV32IMC)
Phase 12 🔜  C software layer (linker, crt0, syscalls)
```

**End goal:** A fully functional RV32IMC microcontroller, synthesized on an Intel FPGA, capable of running GCC-compiled C code with `printf` output over UART, GPIO-driven LEDs, and hardware DMA.

---

## Directory Structure

```text
Timur-RV32IMC/
├── rtl/                  # Synthesizable Verilog/SystemVerilog source
│   ├── primitives/       # Phase 1: Mux2, Mux4, DFF, PLL wrapper
│   ├── execution/        # Phase 2: ALU, Adder, Shifter, Multiplier, Divider, BranchEval
│   ├── memory/           # Phase 3: PC, RegisterFile, ROM_AHB, RAM_AHB
│   ├── decode/           # Phase 4: Parser, ImmGen, ALUDecoder, MainControl
│   ├── pipeline/         # Phase 6: IF/ID, ID/EX, EX/MEM, MEM/WB registers
│   ├── hazard/           # Phase 7: ForwardingUnit, HazardDetectionUnit
│   ├── peripherals/      # Phase 8: GPIO, UART, DMAC_APB, AHB2APB bridge
│   ├── bus/              # Phase 9: AHB arbiter, address decoder, DMAC master
│   ├── csr/              # Phase 10: CSR register file, trap logic
│   └── top/              # Top-level integration
├── tb/                   # Testbenches and test vectors
├── sw/                   # C software layer (Phase 12)
│   ├── crt0.S
│   ├── linker.ld
│   ├── syscalls.c
│   └── bin2mif.py
├── simulation/           # ModelSim/Questa generated files (git-ignored)
├── Timur_RV32IMC.qpf     # Quartus project file
├── Timur_RV32IMC.qsf     # Quartus settings (pin assignments, device)
├── .gitignore
└── README.md
```

---

## License

This project is developed for educational purposes. See [LICENSE](LICENSE) for details.
