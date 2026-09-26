/* Timur RV32IMC: peripheral registers, CSR access and the trap interface of the
 * C runtime (Phase 12). Included by the runtime (crt0.S, syscalls.c, trap.c) and
 * by programs. */
#ifndef TIMUR_H
#define TIMUR_H

#include <stdint.h>

#define TIMUR_REG(addr) (*(volatile uint32_t *)(addr))

/* ---- UART, APB 0x4000_0000 (115200 8N1 at 50 MHz) ------------------------ */
#define UART_DATA       TIMUR_REG(0x40000000u)  /* write: byte to send (ignored while tx_busy)  */
                                                /* read : received byte, clears rx_valid        */
#define UART_STATUS     TIMUR_REG(0x40000004u)
#define UART_CTRL       TIMUR_REG(0x40000008u)  /* resets to 0: the receiver starts disabled    */
#define UART_TX_BUSY    (1u << 0)               /* STATUS                                       */
#define UART_RX_VALID   (1u << 1)
#define UART_RX_OVERRUN (1u << 2)
#define UART_RX_ENABLE  (1u << 0)               /* CTRL                                         */
#define UART_RX_IRQ     (1u << 1)               /* interrupt while rx_valid                     */

/* ---- GPIO, APB 0x4000_0100 ----------------------------------------------- */
#define GPIO_OUT        TIMUR_REG(0x40000100u)  /* LEDR[9:0]                                    */
#define GPIO_IN         TIMUR_REG(0x40000104u)  /* SW[9:0]                                      */
#define GPIO_DIR        TIMUR_REG(0x40000108u)

/* ---- DMAC, APB 0x4000_0200 ----------------------------------------------- */
#define DMAC_SRC        TIMUR_REG(0x40000200u)  /* word-aligned byte address, ROM or RAM        */
#define DMAC_DST        TIMUR_REG(0x40000204u)  /* word-aligned byte address in RAM             */
#define DMAC_LEN        TIMUR_REG(0x40000208u)  /* number of 32-bit words                       */
#define DMAC_CTRL       TIMUR_REG(0x4000020Cu)  /* any write clears STATUS.done                 */
#define DMAC_STATUS     TIMUR_REG(0x40000210u)
#define DMAC_START      (1u << 0)               /* CTRL: start (ignored while busy)             */
#define DMAC_IRQ        (1u << 1)               /* CTRL: interrupt while done                   */
#define DMAC_BUSY       (1u << 0)               /* STATUS                                       */
#define DMAC_DONE       (1u << 1)               /* STATUS, sticky                               */

/* ---- CSRs ----------------------------------------------------------------- */
#define csr_read(csr)                                                   \
    ({ uint32_t csr_value_;                                             \
       __asm__ volatile ("csrr %0, " #csr : "=r"(csr_value_));         \
       csr_value_; })
#define csr_write(csr, v) __asm__ volatile ("csrw " #csr ", %0" :: "rK"((uint32_t)(v)))
#define csr_set(csr, v)   __asm__ volatile ("csrs " #csr ", %0" :: "rK"((uint32_t)(v)))
#define csr_clear(csr, v) __asm__ volatile ("csrc " #csr ", %0" :: "rK"((uint32_t)(v)))

#define MSTATUS_MIE     (1u << 3)
#define MIE_MEIE        (1u << 11)

#define MCAUSE_INTERRUPT          0x80000000u
#define MCAUSE_EXTERNAL_IRQ       0x8000000Bu   /* UART rx or DMAC done */
#define CAUSE_ILLEGAL_INSTRUCTION 2u
#define CAUSE_BREAKPOINT          3u
#define CAUSE_LOAD_MISALIGNED     4u
#define CAUSE_STORE_MISALIGNED    6u
#define CAUSE_ECALL               11u

/* ---- Traps ------------------------------------------------------------------
 * trap_entry (crt0.S) saves the caller-saved registers in this order, calls
 * timur_trap (trap.c) with a pointer to them, restores them and executes MRET.
 * ECALL is a system call: a7 = number, a0-a2 = arguments, result in a0.
 * An external interrupt calls irq_handler, which must clear its source.
 * Any other exception calls exception_handler; it returns 1 when it has handled
 * the exception and set *mepc to the address to resume at. The runtime's weak
 * defaults report the trap on the UART and stop: see timur_fatal. */
struct trap_frame {
    uint32_t ra, t0, t1, t2, a0, a1, a2, a3, a4, a5, a6, a7, t3, t4, t5, t6;
};

void irq_handler(uint32_t mcause);
int  exception_handler(struct trap_frame *frame, uint32_t mcause, uint32_t *mepc, uint32_t mtval);
void timur_fatal(uint32_t mcause, uint32_t mepc, uint32_t mtval) __attribute__((noreturn));

/* System-call numbers for ECALL (the RISC-V Linux numbering) */
#define SYS_read  63
#define SYS_write 64
#define SYS_exit  93

static inline long timur_ecall(long number, long arg0, long arg1, long arg2)
{
    register long a0 __asm__("a0") = arg0;
    register long a1 __asm__("a1") = arg1;
    register long a2 __asm__("a2") = arg2;
    register long a7 __asm__("a7") = number;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return a0;
}

/* ---- Raw UART, no stdio (safe inside a trap handler) ------------------------ */
void uart_putc(char c);           /* '\n' is sent as "\r\n" */
int  uart_getc(void);             /* waits for a byte; enables the receiver     */
void uart_puts(const char *s);
void uart_puthex(uint32_t value); /* eight hex digits                           */

/* ---- Exit --------------------------------------------------------------------
 * _exit(code) shows 0x200 | (code & 0x1FF) on the LEDs (LEDR9 = program ended)
 * and stops at _halt, a jump-to-self in crt0.S. */
void _halt(void) __attribute__((noreturn));

#endif /* TIMUR_H */
