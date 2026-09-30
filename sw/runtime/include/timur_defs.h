/**
 * @file timur_defs.h
 * @brief Hardware constants of the Timur RV32IMC SoC, shared by C and assembly.
 *
 * Only preprocessor definitions, so that the assembly sources of the runtime
 * (crt0.S, trap_entry.S) can include it as well as C code. C code normally
 * includes timur.h, which includes this file.
 *
 * The Python tools keep the same facts in sw/timur_tools/memmap.py, and the
 * linker script the memory sizes in sw/runtime/linker.ld;
 * tests/host/test_memmap.py checks that all three agree.
 *
 * Hardware assumptions:
 *   - one RV32IMC hart in machine mode only (MPP always reads 11), no PMP;
 *   - a 50 MHz clock (the PLL's output, see rtl/primitives/cpu_pll.v);
 *   - peripherals on APB, 32-bit registers, no byte strobes: every store to a
 *     peripheral register writes the whole register;
 *   - word accesses to peripheral registers only.
 */
#ifndef TIMUR_DEFS_H
#define TIMUR_DEFS_H

/** Unsigned integer constant in C (@c 12u), plain number in assembly. */
#ifdef __ASSEMBLER__
#define TIMUR_U(value) value
#else
#define TIMUR_U(value) value##u
#endif

/* ---- Memory map -------------------------------------------------------------------
 *   0x0000_0000  ROM, 64 KB: code, constants, initial values of .data. Instructions
 *                are fetched through its fetch port; loads and the DMAC read it
 *                through its AHB port; writes are ignored.
 *   0x2000_0000  RAM, 64 KB, byte-addressable
 *   0x4000_0000  APB peripherals: UART +0x000, GPIO +0x100, DMAC +0x200
 *   elsewhere    the default slave: loads read 0, stores are ignored            */
#define TIMUR_ROM_BASE  TIMUR_U(0x00000000)
#define TIMUR_ROM_SIZE  TIMUR_U(0x00010000)
#define TIMUR_RAM_BASE  TIMUR_U(0x20000000)
#define TIMUR_RAM_SIZE  TIMUR_U(0x00010000)
#define TIMUR_APB_BASE  TIMUR_U(0x40000000)
#define TIMUR_UART_BASE (TIMUR_APB_BASE + TIMUR_U(0x000))
#define TIMUR_GPIO_BASE (TIMUR_APB_BASE + TIMUR_U(0x100))
#define TIMUR_DMAC_BASE (TIMUR_APB_BASE + TIMUR_U(0x200))

/** Clock frequency of the CPU and the peripherals, in Hz. */
#define TIMUR_CLOCK_HZ 50000000

/* ---- UART: 115200 8N1, one byte of transmit and one of receive buffer -------------- */
#define UART_DATA_OFFSET   TIMUR_U(0x00) /**< write: send; read: receive, clears RX_* */
#define UART_STATUS_OFFSET TIMUR_U(0x04)
#define UART_CTRL_OFFSET   TIMUR_U(0x08)
#define UART_BAUD          115200
#define UART_TX_BUSY       (TIMUR_U(1) << 0) /**< STATUS: a byte is being sent (writes ignored) */
#define UART_RX_VALID      (TIMUR_U(1) << 1) /**< STATUS: a byte was received and not read */
#define UART_RX_OVERRUN    (TIMUR_U(1) << 2) /**< STATUS: a byte arrived while RX_VALID was set */
#define UART_RX_ENABLE     (TIMUR_U(1) << 0) /**< CTRL: receiver on (resets off)   */
#define UART_RX_IRQ        (TIMUR_U(1) << 1) /**< CTRL: interrupt while RX_VALID   */

/* ---- GPIO: the DE10-Lite's LEDR[9:0] and SW[9:0] ----------------------------------- */
#define GPIO_OUT_OFFSET TIMUR_U(0x00) /**< LEDR[9:0] */
#define GPIO_IN_OFFSET  TIMUR_U(0x04) /**< SW[9:0], read only */
#define GPIO_DIR_OFFSET TIMUR_U(0x08) /**< reserved for header pins; LEDs and switches are fixed */
#define GPIO_WIDTH      10
#define GPIO_PIN_MASK   ((TIMUR_U(1) << GPIO_WIDTH) - TIMUR_U(1))

/* ---- DMAC: copies 32-bit words from ROM or RAM to RAM ------------------------------ */
#define DMAC_SRC_OFFSET    TIMUR_U(0x00) /**< word-aligned byte address, ROM or RAM */
#define DMAC_DST_OFFSET    TIMUR_U(0x04) /**< word-aligned byte address in RAM      */
#define DMAC_LEN_OFFSET    TIMUR_U(0x08) /**< number of 32-bit words                */
#define DMAC_CTRL_OFFSET   TIMUR_U(0x0C) /**< any write clears STATUS.DONE          */
#define DMAC_STATUS_OFFSET TIMUR_U(0x10)
#define DMAC_START         (TIMUR_U(1) << 0) /**< CTRL: start (ignored while busy)  */
#define DMAC_IRQ           (TIMUR_U(1) << 1) /**< CTRL: interrupt while DONE        */
#define DMAC_BUSY          (TIMUR_U(1) << 0) /**< STATUS                            */
#define DMAC_DONE          (TIMUR_U(1) << 1) /**< STATUS, sticky                    */

/* ---- CSR fields ----------------------------------------------------------------------- */
#define MSTATUS_MIE  (TIMUR_U(1) << 3)
#define MSTATUS_MPIE (TIMUR_U(1) << 7)
#define MIE_MEIE     (TIMUR_U(1) << 11) /**< machine external interrupt enable  */
#define MIP_MEIP     (TIMUR_U(1) << 11) /**< machine external interrupt pending */
#define MISA_VALUE   TIMUR_U(0x40001104) /**< RV32 with extensions C, I and M   */
/** The misa bit of the extension with the given letter, for example MISA_EXT('M'). */
#define MISA_EXT(letter) (TIMUR_U(1) << ((letter) - 'A'))

/* ---- Trap causes (mcause) ------------------------------------------------------------- */
#define MCAUSE_INTERRUPT          TIMUR_U(0x80000000) /**< set for interrupts        */
#define MCAUSE_EXTERNAL_IRQ       TIMUR_U(0x8000000B) /**< UART receive or DMAC done */
#define CAUSE_ILLEGAL_INSTRUCTION TIMUR_U(2)
#define CAUSE_BREAKPOINT          TIMUR_U(3)
#define CAUSE_LOAD_MISALIGNED     TIMUR_U(4)
#define CAUSE_STORE_MISALIGNED    TIMUR_U(6)
#define CAUSE_ECALL               TIMUR_U(11) /**< ECALL from machine mode */

/* ---- Trap frame --------------------------------------------------------------------------
 * trap_entry (trap_entry.S) saves the caller-saved registers on the interrupted
 * stack at these offsets; struct trap_frame (timur.h) is the C view of the same
 * memory, and static assertions there keep the two in step. The size keeps sp
 * 16-byte aligned, as the RISC-V calling convention requires.                     */
#define TRAP_FRAME_RA   0
#define TRAP_FRAME_T0   4
#define TRAP_FRAME_T1   8
#define TRAP_FRAME_T2   12
#define TRAP_FRAME_A0   16
#define TRAP_FRAME_A1   20
#define TRAP_FRAME_A2   24
#define TRAP_FRAME_A3   28
#define TRAP_FRAME_A4   32
#define TRAP_FRAME_A5   36
#define TRAP_FRAME_A6   40
#define TRAP_FRAME_A7   44
#define TRAP_FRAME_T3   48
#define TRAP_FRAME_T4   52
#define TRAP_FRAME_T5   56
#define TRAP_FRAME_T6   60
#define TRAP_FRAME_SIZE 64

#endif /* TIMUR_DEFS_H */
