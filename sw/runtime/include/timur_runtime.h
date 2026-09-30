/**
 * @file timur_runtime.h
 * @brief Internal interface between the parts of the Timur C runtime.
 *
 * Shared by crt0.S, trap_entry.S, syscalls.c, uart.c and trap.c; programs
 * include timur.h instead. Declares the newlib system-call stubs (so that each
 * has one prototype), the linker-script symbols and the C trap entry point.
 */
#ifndef TIMUR_RUNTIME_H
#define TIMUR_RUNTIME_H

#include <stddef.h>
#include <sys/stat.h>

#include "timur.h"

/* ---- Symbols of linker.ld ------------------------------------------------------------- */
extern char _end[];       /**< first byte after .bss: the start of the heap */
extern char _heap_end[];  /**< end of the heap: the lowest address of the stack region */
extern char _stack_top[]; /**< initial stack pointer: the end of RAM */

/* ---- newlib system-call stubs (syscalls.c) ----------------------------------------------
 * The console is the UART: fd 0 is stdin, 1 and 2 are stdout and stderr. Errors
 * set errno and return -1, as newlib expects.                                     */
int _read(int fd, char *buf, int len);
int _write(int fd, const char *buf, int len);
void _exit(int code) __attribute__((noreturn));
void *_sbrk(ptrdiff_t increment);
int _close(int fd);
int _lseek(int fd, int offset, int whence);
int _fstat(int fd, struct stat *st);
int _isatty(int fd);
int _kill(int pid, int sig);
int _getpid(void);

/* ---- Traps ---------------------------------------------------------------------------- */
/** Dispatch a trap (trap.c); called by trap_entry with the saved registers. */
void timur_trap(struct trap_frame *frame);

#endif /* TIMUR_RUNTIME_H */
