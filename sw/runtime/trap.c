/**
 * @file trap.c
 * @brief Trap dispatch of the Timur runtime (the C part; the entry is trap_entry).
 *
 * trap_entry saves the caller-saved registers and calls timur_trap with
 * mstatus.MIE = 0 (the hardware cleared it), so traps do not nest.
 *   ECALL      system call a7 with arguments a0-a2, checked before use; the
 *              result goes into the saved a0 and mepc advances by 4
 *   interrupt  irq_handler(mcause), which must clear its source
 *   exception  exception_handler(); if it returns 0, timur_fatal
 * The weak defaults below make any interrupt or exception fatal.
 */

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>

#include "timur_runtime.h"

/** Length of ECALL: it has no 16-bit form. */
#define ECALL_LENGTH 4u

/** Largest length a read or write system call accepts: the stubs take an int. */
#define SYSCALL_MAX_LENGTH 0x7FFFFFFFu

/** True if [address, address + length) lies inside [base, base + size); overflow-safe. */
static bool in_memory(uint32_t address, uint32_t length, uint32_t base, uint32_t size)
{
    return address >= base && address - base <= size && length <= size - (address - base);
}

/** A buffer the program may send from: ROM or RAM. */
static bool readable(uint32_t address, uint32_t length)
{
    return in_memory(address, length, TIMUR_ROM_BASE, TIMUR_ROM_SIZE) ||
           in_memory(address, length, TIMUR_RAM_BASE, TIMUR_RAM_SIZE);
}

/** A buffer the program may receive into: RAM only (ROM ignores writes, and the
 *  peripheral registers must not be overwritten by console input). */
static bool writable(uint32_t address, uint32_t length)
{
    return in_memory(address, length, TIMUR_RAM_BASE, TIMUR_RAM_SIZE);
}

/**
 * The system call behind an ECALL. The arguments come straight from the
 * program's registers, so they are checked before they are used: an unknown
 * file descriptor gives -EBADF, a length above SYSCALL_MAX_LENGTH -EINVAL, and
 * a buffer outside the memories it may use -EFAULT (a zero length needs no
 * buffer).
 */
static long timur_syscall(uint32_t number, uint32_t arg0, uint32_t arg1, uint32_t arg2)
{
    switch (number) {
    case SYS_write:
        if (arg0 != TIMUR_FD_STDOUT && arg0 != TIMUR_FD_STDERR)
            return -EBADF;
        if (arg2 > SYSCALL_MAX_LENGTH)
            return -EINVAL;
        if (arg2 != 0 && !readable(arg1, arg2))
            return -EFAULT;
        return _write((int)arg0, (const char *)(uintptr_t)arg1, (int)arg2);
    case SYS_read:
        if (arg0 != TIMUR_FD_STDIN)
            return -EBADF;
        if (arg2 > SYSCALL_MAX_LENGTH)
            return -EINVAL;
        if (arg2 != 0 && !writable(arg1, arg2))
            return -EFAULT;
        return _read((int)arg0, (char *)(uintptr_t)arg1, (int)arg2);
    case SYS_exit:
        _exit((int)arg0);
    default:
        return -ENOSYS;
    }
}

void timur_trap(struct trap_frame *frame)
{
    uint32_t mcause = csr_read(mcause);
    uint32_t mepc = csr_read(mepc);
    uint32_t mtval = csr_read(mtval);

    if (mcause == CAUSE_ECALL) {
        frame->a0 = (uint32_t)timur_syscall(frame->a7, frame->a0, frame->a1, frame->a2);
        csr_write(mepc, mepc + ECALL_LENGTH);
    } else if (mcause & MCAUSE_INTERRUPT) {
        irq_handler(mcause);
        /* The weak exception_handler below returns 0, which a program's own replaces. */
        /* cppcheck-suppress knownConditionTrueFalse */
    } else if (exception_handler(frame, mcause, &mepc, mtval)) {
        csr_write(mepc, mepc);
    } else {
        timur_fatal(mcause, mepc, mtval);
    }
}

__attribute__((weak)) void irq_handler(uint32_t mcause)
{
    timur_fatal(mcause, csr_read(mepc), csr_read(mtval));
}

__attribute__((weak)) int exception_handler(struct trap_frame *frame, uint32_t mcause,
                                            uint32_t *mepc, uint32_t mtval)
{
    (void)frame;
    (void)mcause;
    (void)mepc;
    (void)mtval;
    return 0;
}

/* One line per cause, as a table. */
/* clang-format off */
static const char *cause_name(uint32_t mcause)
{
    switch (mcause) {
    case CAUSE_ILLEGAL_INSTRUCTION: return "illegal instruction";
    case CAUSE_BREAKPOINT:          return "breakpoint";
    case CAUSE_LOAD_MISALIGNED:     return "misaligned load";
    case CAUSE_STORE_MISALIGNED:    return "misaligned store";
    case CAUSE_ECALL:               return "environment call";
    case MCAUSE_EXTERNAL_IRQ:       return "external interrupt";
    default:                        return "unknown cause";
    }
}
/* clang-format on */

void timur_fatal(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    uart_puts("\n*** unhandled trap: ");
    uart_puts(cause_name(mcause));
    uart_puts("\n    mcause ");
    uart_puthex(mcause);
    uart_puts("  mepc ");
    uart_puthex(mepc);
    uart_puts("  mtval ");
    uart_puthex(mtval);
    uart_putc('\n');
    _exit(TIMUR_EXIT_FATAL | (int)(mcause & 0xFFu));
}
