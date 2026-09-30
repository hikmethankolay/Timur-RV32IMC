/**
 * @file timur.h
 * @brief The C interface of the Timur RV32IMC SoC and its runtime.
 *
 * Peripheral registers, CSR access, the trap interface, system calls and the
 * raw UART driver. Programs include this header; sw/build.py puts its folder
 * on the include path. The numeric constants live in timur_defs.h, which the
 * assembly sources share.
 *
 * GNU C: the CSR accessors use inline assembly and statement expressions, so
 * the runtime is built with -std=gnu11 and without -Wpedantic.
 */
#ifndef TIMUR_H
#define TIMUR_H

#include <stddef.h>
#include <stdint.h>

#include "timur_defs.h"

/* ---- Memory-mapped registers ------------------------------------------------------- */

/** The 32-bit peripheral register at an address, as an lvalue (volatile: every
 *  access reaches the bus, in program order). */
#define TIMUR_REG(addr) (*(volatile uint32_t *)(addr))

#define UART_DATA   TIMUR_REG(TIMUR_UART_BASE + UART_DATA_OFFSET) /**< byte to send / received */
#define UART_STATUS TIMUR_REG(TIMUR_UART_BASE + UART_STATUS_OFFSET) /**< UART_TX_BUSY, UART_RX_* */
#define UART_CTRL TIMUR_REG(TIMUR_UART_BASE + UART_CTRL_OFFSET) /**< UART_RX_ENABLE, UART_RX_IRQ */

#define GPIO_OUT TIMUR_REG(TIMUR_GPIO_BASE + GPIO_OUT_OFFSET) /**< LEDR[9:0] */
#define GPIO_IN  TIMUR_REG(TIMUR_GPIO_BASE + GPIO_IN_OFFSET) /**< SW[9:0] */
#define GPIO_DIR TIMUR_REG(TIMUR_GPIO_BASE + GPIO_DIR_OFFSET) /**< reserved for header pins */

#define DMAC_SRC    TIMUR_REG(TIMUR_DMAC_BASE + DMAC_SRC_OFFSET)
#define DMAC_DST    TIMUR_REG(TIMUR_DMAC_BASE + DMAC_DST_OFFSET)
#define DMAC_LEN    TIMUR_REG(TIMUR_DMAC_BASE + DMAC_LEN_OFFSET)
#define DMAC_CTRL   TIMUR_REG(TIMUR_DMAC_BASE + DMAC_CTRL_OFFSET)
#define DMAC_STATUS TIMUR_REG(TIMUR_DMAC_BASE + DMAC_STATUS_OFFSET)

/* ---- CSRs ---------------------------------------------------------------------------- */

/** Read a CSR by name, for example csr_read(mcause); evaluates to a uint32_t. */
#define csr_read(csr)                                          \
    ({                                                         \
        uint32_t csr_value_;                                   \
        __asm__ volatile("csrr %0, " #csr : "=r"(csr_value_)); \
        csr_value_;                                            \
    })
/** Write a CSR. */
#define csr_write(csr, value) __asm__ volatile("csrw " #csr ", %0" ::"rK"((uint32_t)(value)))
/** Set the bits of value in a CSR (atomically, with CSRS). */
#define csr_set(csr, value) __asm__ volatile("csrs " #csr ", %0" ::"rK"((uint32_t)(value)))
/** Clear the bits of value in a CSR (atomically, with CSRC). */
#define csr_clear(csr, value) __asm__ volatile("csrc " #csr ", %0" ::"rK"((uint32_t)(value)))

/* ---- Traps -----------------------------------------------------------------------------
 * trap_entry (trap_entry.S) saves the caller-saved registers in a struct
 * trap_frame on the interrupted stack, calls timur_trap (trap.c) with a pointer
 * to it, restores the registers and executes MRET. Traps do not nest: the
 * hardware clears mstatus.MIE on entry, and the handlers run with it clear.
 *
 *   ECALL      a system call: a7 = number, a0-a2 = arguments, result in a0
 *   interrupt  irq_handler(mcause), which must clear its source
 *   exception  exception_handler(); it returns 1 when it has handled the
 *              exception and set *mepc to the address to resume at
 * The runtime's weak defaults of both handlers report the trap on the UART and
 * stop (see timur_fatal); a program overrides them by defining its own. */

/** The caller-saved registers at the time of the trap (offsets in timur_defs.h). */
struct trap_frame {
    uint32_t ra, t0, t1, t2, a0, a1, a2, a3, a4, a5, a6, a7, t3, t4, t5, t6;
};

_Static_assert(sizeof(struct trap_frame) == TRAP_FRAME_SIZE, "trap frame size");
_Static_assert(offsetof(struct trap_frame, ra) == TRAP_FRAME_RA, "trap frame: ra");
_Static_assert(offsetof(struct trap_frame, t0) == TRAP_FRAME_T0, "trap frame: t0");
_Static_assert(offsetof(struct trap_frame, t2) == TRAP_FRAME_T2, "trap frame: t2");
_Static_assert(offsetof(struct trap_frame, a0) == TRAP_FRAME_A0, "trap frame: a0");
_Static_assert(offsetof(struct trap_frame, a7) == TRAP_FRAME_A7, "trap frame: a7");
_Static_assert(offsetof(struct trap_frame, t3) == TRAP_FRAME_T3, "trap frame: t3");
_Static_assert(offsetof(struct trap_frame, t6) == TRAP_FRAME_T6, "trap frame: t6");
_Static_assert(TRAP_FRAME_SIZE % 16 == 0, "the trap frame keeps sp 16-byte aligned");

/**
 * @brief Handle an external interrupt (UART receive or DMAC done).
 *
 * Called with interrupts disabled. It must clear the source of the interrupt
 * (read UART_DATA, write DMAC_CTRL), or the interrupt is taken again at once.
 * The runtime's weak default treats every interrupt as fatal.
 * @param mcause MCAUSE_EXTERNAL_IRQ
 */
void irq_handler(uint32_t mcause);

/**
 * @brief Handle an exception other than ECALL.
 *
 * @param frame  the saved caller-saved registers; changes are restored on return
 * @param mcause the cause (CAUSE_ILLEGAL_INSTRUCTION, CAUSE_BREAKPOINT, ...)
 * @param mepc   in: the address of the faulting instruction; out: where to resume
 * @param mtval  the faulting address, or the instruction's PC for EBREAK, or 0
 * @return 1 if the exception was handled and *mepc set, 0 to let the runtime
 *         report it and stop. The runtime's weak default returns 0.
 */
int exception_handler(struct trap_frame *frame, uint32_t mcause, uint32_t *mepc, uint32_t mtval);

/**
 * @brief Report an unhandled trap on the UART and stop.
 *
 * Uses the raw UART driver, not stdio (which may be what trapped), then ends
 * the program with exit code TIMUR_EXIT_FATAL | (mcause & 0xFF).
 */
void timur_fatal(uint32_t mcause, uint32_t mepc, uint32_t mtval) __attribute__((noreturn));

/* ---- System calls through ECALL (the RISC-V Linux numbering) ------------------------ */
#define SYS_read  63 /**< read(fd 0, buf, len) */
#define SYS_write 64 /**< write(fd 1 or 2, buf, len) */
#define SYS_exit  93 /**< exit(code): does not return */

/**
 * @brief Make a system call with ECALL.
 * @return the result, or a negative errno value (-EBADF, -ENOSYS)
 */
static inline long timur_ecall(long number, long arg0, long arg1, long arg2)
{
    register long a0 __asm__("a0") = arg0;
    register long a1 __asm__("a1") = arg1;
    register long a2 __asm__("a2") = arg2;
    register long a7 __asm__("a7") = number;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return a0;
}

/* ---- Raw UART, no stdio (safe inside a trap handler) --------------------------------
 * Blocking: the functions wait for the transmitter or receiver without a
 * timeout, so they depend on a working UART. */

/** Send one character; '\n' is sent as "\r\n". */
void uart_putc(char c);
/** Wait for a received byte and return it (0-255); enables the receiver if needed. */
int uart_getc(void);
/** Send a NUL-terminated string with uart_putc. */
void uart_puts(const char *s);
/** Send value as eight upper-case hex digits. */
void uart_puthex(uint32_t value);

/* ---- End of a program ------------------------------------------------------------------
 * _exit(code) shows TIMUR_EXIT_LEDS | (code & TIMUR_EXIT_CODE_MASK) on the LEDs
 * (LEDR9 = the program ended) and stops at _halt, a jump-to-self in crt0.S
 * that the testbenches and the reference model recognise as the end.          */
#define TIMUR_EXIT_LEDS      (1u << 9) /**< LEDR9: the program has ended */
#define TIMUR_EXIT_CODE_MASK 0x1FFu /**< exit code bits shown on LEDR[8:0] */
#define TIMUR_EXIT_FATAL     0x100 /**< exit code base of an unhandled trap */

/** The jump-to-self that ends every program. */
void _halt(void) __attribute__((noreturn));

#endif /* TIMUR_H */
