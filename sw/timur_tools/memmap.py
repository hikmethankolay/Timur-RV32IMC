"""Memory map, CSR addresses and trap causes of the Timur SoC.

The Python copy of the hardware facts that C and assembly code take from
sw/runtime/include/timur_defs.h and the linker from sw/runtime/linker.ld;
tests/host/test_memmap.py checks that the three agree.
"""

from __future__ import annotations

# ---- memories ---------------------------------------------------------------
ROM_BASE = 0x0000_0000
ROM_SIZE = 0x1_0000  # 64 KB: code, constants, initial values of .data
RAM_BASE = 0x2000_0000
RAM_SIZE = 0x1_0000  # 64 KB: .data, .bss, heap, stack

# ---- APB peripherals --------------------------------------------------------
APB_BASE = 0x4000_0000
UART_BASE = APB_BASE + 0x000
GPIO_BASE = APB_BASE + 0x100
DMAC_BASE = APB_BASE + 0x200

# register offsets from the peripheral's base
UART_DATA, UART_STATUS, UART_CTRL = 0x00, 0x04, 0x08
GPIO_OUT, GPIO_IN, GPIO_DIR = 0x00, 0x04, 0x08
DMAC_SRC, DMAC_DST, DMAC_LEN, DMAC_CTRL, DMAC_STATUS = 0x00, 0x04, 0x08, 0x0C, 0x10

UART_STATUS_TX_BUSY = 1 << 0
UART_STATUS_RX_VALID = 1 << 1
UART_CTRL_RX_ENABLE = 1 << 0
UART_CTRL_RX_IRQ = 1 << 1
UART_CTRL_MASK = UART_CTRL_RX_ENABLE | UART_CTRL_RX_IRQ
DMAC_CTRL_START = 1 << 0
DMAC_CTRL_IRQ = 1 << 1
DMAC_STATUS_BUSY = 1 << 0
DMAC_STATUS_DONE = 1 << 1

GPIO_WIDTH = 10  # LEDR[9:0] and SW[9:0] of the DE10-Lite
GPIO_MASK = (1 << GPIO_WIDTH) - 1

# ---- clock and UART ---------------------------------------------------------
CLOCK_HZ = 50_000_000
UART_BAUD = 115_200
UART_CYCLES_PER_BIT = 434  # CLOCK_HZ / UART_BAUD; the SoC's UART_DIVIDER is one less
UART_FRAME_BITS = 10  # 8N1: start, eight data bits, stop

# ---- testbench conventions ---------------------------------------------------
TB_SWITCHES = 0x15A  # switch value tb/timur_soc_tb.v drives on gpio_in
TB_SW_UART_CYCLES_PER_BIT = 16  # tb/timur_sw_tb.v: UART_DIVIDER = 15
TB_PATH_LIMIT = 63  # longest file name tb/timur_soc_tb.v can read

# ---- CSRs -------------------------------------------------------------------
CSR_MSTATUS, CSR_MISA, CSR_MIE, CSR_MTVEC = 0x300, 0x301, 0x304, 0x305
CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP = 0x340, 0x341, 0x342, 0x343, 0x344
CSR_MCYCLE, CSR_MINSTRET, CSR_MCYCLEH, CSR_MINSTRETH = 0xB00, 0xB02, 0xB80, 0xB82
CSR_CYCLE, CSR_TIME, CSR_INSTRET = 0xC00, 0xC01, 0xC02
CSR_CYCLEH, CSR_TIMEH, CSR_INSTRETH = 0xC80, 0xC81, 0xC82
CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID = 0xF11, 0xF12, 0xF13, 0xF14

#: Assembler names of the implemented CSRs.
CSRS = {
    "mstatus": CSR_MSTATUS, "misa": CSR_MISA, "mie": CSR_MIE, "mtvec": CSR_MTVEC,
    "mscratch": CSR_MSCRATCH, "mepc": CSR_MEPC, "mcause": CSR_MCAUSE, "mtval": CSR_MTVAL,
    "mip": CSR_MIP, "mcycle": CSR_MCYCLE, "minstret": CSR_MINSTRET, "mcycleh": CSR_MCYCLEH,
    "minstreth": CSR_MINSTRETH, "cycle": CSR_CYCLE, "time": CSR_TIME, "instret": CSR_INSTRET,
    "cycleh": CSR_CYCLEH, "timeh": CSR_TIMEH, "instreth": CSR_INSTRETH,
    "mvendorid": CSR_MVENDORID, "marchid": CSR_MARCHID, "mimpid": CSR_MIMPID,
    "mhartid": CSR_MHARTID,
}  # fmt: skip
CSR_IMPLEMENTED = frozenset(CSRS.values())

#: Low and high halves of the cycle, time and retired-instruction counters.
CSR_COUNTERS_LOW = frozenset({CSR_MCYCLE, CSR_MINSTRET, CSR_CYCLE, CSR_TIME, CSR_INSTRET})
CSR_COUNTERS_HIGH = frozenset({CSR_MCYCLEH, CSR_MINSTRETH, CSR_CYCLEH, CSR_TIMEH, CSR_INSTRETH})
CSR_COUNTERS = CSR_COUNTERS_LOW | CSR_COUNTERS_HIGH

CSR_READ_ONLY_SPACE = 3  # address bits [11:10] = 11: writes are illegal

MISA_VALUE = 0x4000_1104  # RV32IMC: MXL = 1 (32 bit), extensions C, I, M

MSTATUS_MIE = 1 << 3
MSTATUS_MPIE = 1 << 7
MSTATUS_MPP_MACHINE = 3 << 11  # the only privilege mode: MPP reads 11
MIE_MEIE = 1 << 11
MIP_MEIP = 1 << 11

# ---- trap causes (mcause) ---------------------------------------------------
CAUSE_ILLEGAL_INSTRUCTION = 2
CAUSE_BREAKPOINT = 3
CAUSE_LOAD_MISALIGNED = 4
CAUSE_STORE_MISALIGNED = 6
CAUSE_ECALL_M = 11
CAUSE_EXTERNAL_INTERRUPT = 0x8000_000B
