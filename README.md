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
  - [Bus Architecture \& Address Map](#bus-architecture--address-map)
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
  - [Building \& Programming](#building--programming)
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

```
┌──────────────────────────────────────────────────────┐
│                  AHB Bus Fabric                      │
│  ┌──────────┐  ┌──────────┐                         │
│  │   CPU    │  │  DMAC    │  ← Two AHB Masters      │
│  │(Master 0)│  │(Master 1)│                         │
│  └────┬─────┘  └────┬─────┘                         │
│  ┌────▼─────────────▼────┐                           │
│  │       AHB Arbiter     │  Fixed priority (CPU > DMAC)
│  └──────────┬────────────┘                           │
│    ┌────────┼────────┬─────────────┐                 │
│  ┌─▼──┐  ┌──▼──┐  ┌──▼────────┐   │                 │
│  │RAM │  │ ROM │  │AHB→APB    │                     │
│  └────┘  └─────┘  │  Bridge   │                     │
│                   └──┬────────┘                      │
│              ┌───────┼──────┐                        │
│           ┌──▼──┐ ┌──▼──┐ ┌─▼───┐                   │
│           │UART │ │GPIO │ │DMAC │                   │
│           │(APB)│ │(APB)│ │Regs │                   │
└──────────────────────────────────────────────────────┘
```

**Pipeline stages:** IF → ID → EX → MEM → WB  
**Bus standard:** ARM AMBA — AHB for high-speed paths, APB for peripherals  
**Target FPGA:** Intel DE1-SoC (Cyclone V) — synthesized with Quartus Prime

---

## ISA Support

| Extension | Description | Status |
|-----------|-------------|--------|
| **RV32I** | Base 32-bit integer instructions | ✅ Phase 2 Complete |
| **RV32M** | Hardware multiply & divide (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU) | ✅ Phase 2 Complete |
| **RV32C** | 16-bit compressed instructions | 🔜 Phase 11 |
| **Zicsr** | CSR read/write instructions (CSRRW, CSRRS, CSRRC + immediate variants) | 🔜 Phase 10 |
| **M-mode** | Machine Mode privilege: traps, exceptions, MRET, mtvec, mepc, mcause | 🔜 Phase 10 |

---

## Current Status

**Phase 2 complete — Execution Datapath fully verified.**

| Phase | Description | Status |
|-------|-------------|--------|
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
- **`dff.v`** — D flip-flop with synchronous enable and asynchronous active-low reset. Foundation of all pipeline registers and state elements.
- **`pll_wrapper.v`** — ALTPLL Megafunction wrapper. Takes the 50 MHz board oscillator and produces the CPU clock.

### Phase 2 — Execution Datapath
- **`adder.v`** — 32-bit adder/subtractor. `sub=1` inverts `b` and carries in 1, implementing two's complement subtraction. Outputs `cout` (unsigned compare) and `overflow` (signed compare).
- **`barrel_shifter.v`** — 32-bit barrel shifter using a 5-stage mux cascade. Supports SLL, SRL, and SRA. Sign fill for SRA uses the original `in[31]`, not the intermediate stage MSB.
- **`multiplier.v`** — Single-cycle multiplier for all four RV32M multiply operations (MUL, MULH, MULHSU, MULHU). Uses 33-bit sign/zero-extended operands to handle mixed signed/unsigned products. Infers Intel DSP blocks.
- **`divider.v`** — Sequential restoring divider. Processes one bit per cycle — 32 cycles total. Implements the full RV32M corner case specification (divide-by-zero, signed overflow). `busy` output feeds the Hazard Detection Unit.
- **`alu.v`** — Top-level ALU. Instantiates adder, barrel shifter, multiplier, and divider. Selects result via a 5-bit `ALUControl` (widened from 4 bits to cover M-extension opcodes). Outputs `zero`, `cout`, `overflow`, `div_busy`.
- **`branch_eval.v`** — Branch condition evaluator. Takes ALU flags and a 3-bit `BranchType` (matching RISC-V `funct3`) and produces a single `BranchTaken` signal for all six branch instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU).

---

## Bus Architecture & Address Map

The system uses the AMBA bus hierarchy: AHB for high-bandwidth paths (CPU, DMA, ROM, RAM) and APB for low-speed peripherals accessed through a bridge.

### AHB Address Map

| Range | Slave | Size |
|-------|-------|------|
| `0x0000_0000 – 0x0000_FFFF` | Instruction ROM | 64 KB |
| `0x2000_0000 – 0x2000_FFFF` | Data RAM | 64 KB |
| `0x4000_0000 – 0x4000_FFFF` | AHB → APB Bridge | — |

### APB Address Map (within bridge)

| Range | Peripheral | Registers |
|-------|------------|-----------|
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

```
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

```
stall = load_use_hazard OR bus_wait OR div_busy
```

| Source | Duration | Mechanism |
|--------|----------|-----------|
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
|------|---------|
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

Simulation is handled through Quartus's NativeLink integration with ModelSim-Intel. Launch from:

> **Quartus → Tools → Run Simulation Tool → RTL Simulation**

Or run `.do` scripts directly in ModelSim:

```tcl
# From ModelSim transcript
do simulation/questa/Timur_RV32IMC_run_msim_rtl_verilog.do
```

Individual module testbenches are located in `tb/`. Each testbench reads test vectors from a file, applies them to the DUT, and auto-compares outputs — no manual waveform inspection needed for pass/fail determination.

**Important:** Insert a `#10` delay after changing inputs before sampling outputs — combinational logic needs time to settle.

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

```
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

```
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