/**
 * @file syscalls.c
 * @brief newlib system calls of the Timur runtime, and the raw UART driver.
 *
 * The UART is the console: stdout and stderr write to it, stdin reads from
 * it. Output turns '\n' into "\r\n" and input turns '\r' (what a terminal
 * sends for Enter) into '\n', so a terminal at 115200 8N1 needs no settings.
 * The heap grows from _end to _heap_end (linker.ld); the stack lives above
 * it. stdio reports the console as a character device, so stdout is line
 * buffered and stdin is read a line at a time.
 */

#include <errno.h>
#include <stdint.h>

#include "timur_runtime.h"

/* ---- console ------------------------------------------------------------------------ */

/** Send one byte as it is, once the transmitter is free. */
static void uart_send(uint8_t byte)
{
    while (UART_STATUS & UART_TX_BUSY)
        ;
    UART_DATA = byte;
}

void uart_putc(char c)
{
    if (c == '\n')
        uart_send('\r');
    uart_send((uint8_t)c);
}

void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

void uart_puthex(uint32_t value)
{
    for (int shift = 28; shift >= 0; shift -= 4)
        uart_send((uint8_t)"0123456789ABCDEF"[(value >> shift) & 15u]);
}

int uart_getc(void)
{
    if (!(UART_CTRL & UART_RX_ENABLE))      /* the receiver resets disabled */
        UART_CTRL |= UART_RX_ENABLE;
    while (!(UART_STATUS & UART_RX_VALID))
        ;
    return (int)(UART_DATA & 0xFFu);
}

/* ---- newlib stubs --------------------------------------------------------------------- */

/** Write len bytes to stdout or stderr. */
int _write(int fd, const char *buf, int len)
{
    if (fd != 1 && fd != 2) {
        errno = EBADF;
        return -1;
    }
    for (int i = 0; i < len; i++)
        uart_putc(buf[i]);
    return len;
}

/** Read from stdin: waits for the first byte, then returns after a newline or len bytes. */
int _read(int fd, char *buf, int len)
{
    int n = 0;

    if (fd != 0) {
        errno = EBADF;
        return -1;
    }
    while (n < len) {
        int c = uart_getc();
        if (c == '\r')
            c = '\n';
        buf[n++] = (char)c;
        if (c == '\n')
            break;
    }
    return n;
}

/** malloc's memory: fails with ENOMEM instead of growing into the stack. */
void *_sbrk(ptrdiff_t increment)
{
    static uintptr_t brk = (uintptr_t)_end;
    uintptr_t old = brk;

    if ((increment > 0 && (uintptr_t)increment > (uintptr_t)_heap_end - brk) ||
        (increment < 0 && (uintptr_t)-increment > brk - (uintptr_t)_end)) {
        errno = ENOMEM;
        return (void *)-1;
    }
    brk += (uintptr_t)increment;
    return (void *)old;
}

/** Shows TIMUR_EXIT_LEDS | code on the LEDs and stops. */
void _exit(int code)
{
    GPIO_OUT = TIMUR_EXIT_LEDS | ((uint32_t)code & TIMUR_EXIT_CODE_MASK);
    _halt();
}

int _close(int fd)
{
    (void)fd;
    errno = EBADF;
    return -1;
}

int _lseek(int fd, int offset, int whence)
{
    (void)fd;
    (void)offset;
    (void)whence;
    return 0;
}

int _fstat(int fd, struct stat *st)
{
    (void)fd;
    *st = (struct stat){ .st_mode = S_IFCHR };   /* st_blksize 0: stdio uses BUFSIZ */
    return 0;
}

int _isatty(int fd)
{
    (void)fd;
    return 1;
}

int _kill(int pid, int sig)
{
    (void)pid;
    (void)sig;
    errno = EINVAL;
    return -1;
}

int _getpid(void)
{
    return 1;
}
