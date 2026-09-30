/**
 * @file uart.c
 * @brief Raw UART driver of the Timur runtime: polled, blocking, no buffering.
 *
 * Safe to call from a trap handler (it keeps no state and does not use stdio).
 * The console conventions: '\n' goes out as "\r\n"; the receiver resets
 * disabled and is enabled by the first uart_getc.
 *
 * Timing: at 115200 baud a byte takes about 87 us (4340 clock cycles); the
 * functions wait for the hardware without a timeout.
 */

#include <stdint.h>

#include "timur_runtime.h"

/** Mask of the received byte in UART_DATA. */
#define UART_DATA_MASK 0xFFu

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
    static const char digits[] = "0123456789ABCDEF";

    for (int shift = 28; shift >= 0; shift -= 4)
        uart_send((uint8_t)digits[(value >> shift) & 15u]);
}

int uart_getc(void)
{
    if (!(UART_CTRL & UART_RX_ENABLE)) /* the receiver resets disabled */
        UART_CTRL |= UART_RX_ENABLE;
    while (!(UART_STATUS & UART_RX_VALID))
        ;
    return (int)(UART_DATA & UART_DATA_MASK);
}
