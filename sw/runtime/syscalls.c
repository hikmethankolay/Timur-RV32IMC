/**
 * @file syscalls.c
 * @brief newlib system calls of the Timur runtime.
 *
 * The UART is the console: stdout and stderr write to it, stdin reads from
 * it (uart.c). Output turns '\n' into "\r\n" and input turns '\r' (what a
 * terminal sends for Enter) into '\n', so a terminal at 115200 8N1 needs no
 * settings. The console, file descriptors 0-2, is the only file: every other
 * descriptor fails with EBADF, and the console cannot be closed or seeked.
 * stdio sees a character device, so stdout is line buffered and stdin is read
 * a line at a time.
 *
 * The heap grows from _end to _heap_end (linker.ld); the stack lives above
 * it, so malloc fails with ENOMEM instead of growing into the stack.
 */

#include <errno.h>
#include <stdint.h>

#include "timur_runtime.h"

/** True for stdin, stdout and stderr: the console. */
static int is_console(int fd)
{
    return fd >= TIMUR_FD_STDIN && fd <= TIMUR_FD_STDERR;
}

/** Write len bytes to stdout or stderr; returns len. */
int _write(int fd, const char *buf, int len)
{
    if (fd != TIMUR_FD_STDOUT && fd != TIMUR_FD_STDERR) {
        errno = EBADF;
        return -1;
    }
    if (len < 0) {
        errno = EINVAL;
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

    if (fd != TIMUR_FD_STDIN) {
        errno = EBADF;
        return -1;
    }
    if (len < 0) {
        errno = EINVAL;
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

/** Move the end of the heap by increment bytes; returns the old end, or
 *  (void *)-1 with errno ENOMEM if the heap would leave [_end, _heap_end]. */
void *_sbrk(ptrdiff_t increment)
{
    static uintptr_t brk = (uintptr_t)_end;
    const uintptr_t old = brk;
    /* the magnitude in unsigned arithmetic: -increment overflows for PTRDIFF_MIN */
    const uintptr_t magnitude = increment < 0 ? (uintptr_t)0 - (uintptr_t)increment
                                              : (uintptr_t)increment;
    const uintptr_t room = increment < 0 ? brk - (uintptr_t)_end : (uintptr_t)_heap_end - brk;

    if (magnitude > room) {
        errno = ENOMEM;
        return (void *)-1;
    }
    brk = increment < 0 ? brk - magnitude : brk + magnitude;
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

/** The console has no position: 0 for it, EBADF for anything else. */
int _lseek(int fd, int offset, int whence)
{
    (void)offset;
    (void)whence;
    if (!is_console(fd)) {
        errno = EBADF;
        return -1;
    }
    return 0;
}

int _fstat(int fd, struct stat *st)
{
    if (!is_console(fd)) {
        errno = EBADF;
        return -1;
    }
    *st = (struct stat){ .st_mode = S_IFCHR }; /* st_blksize 0: stdio uses BUFSIZ */
    return 0;
}

int _isatty(int fd)
{
    if (!is_console(fd)) {
        errno = EBADF;
        return 0;
    }
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
