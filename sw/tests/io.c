/* UART input and external interrupts.
 * Part 1 reads the console with stdio: fgets and sscanf, then getchar (the
 * receiver is polled by _read; Enter arrives as '\r' and reads as '\n').
 * Part 2 is interrupt driven, with irq_handler below:
 *   - a DMA copy from ROM to RAM that ends with the DMAC's done interrupt;
 *   - a second copy with mstatus.MIE = 0: the request stays pending in
 *     mip.MEIP until MIE is set, then the interrupt is taken once;
 *   - a line received by the UART's receive interrupt, one byte per interrupt.
 * On the board, type the three lines at the prompts, then a fourth line. */
#include <stdio.h>
#include <string.h>
#include "timur.h"

#define WORDS 64

static const uint32_t rom_table[WORDS] = {
#define ROW(n) 0x9E3779B9u * (n + 1u), 0x7F4A7C15u ^ (n * 0x01010101u), 0xDEAD0000u | (n), ~(uint32_t)(n)
    ROW(0u), ROW(1u), ROW(2u), ROW(3u), ROW(4u), ROW(5u), ROW(6u), ROW(7u),
    ROW(8u), ROW(9u), ROW(10u), ROW(11u), ROW(12u), ROW(13u), ROW(14u), ROW(15u),
#undef ROW
};
static uint32_t copy[WORDS];
static uint32_t copy2[16];

static volatile int dma_irqs, uart_irqs, rx_len;
static volatile char rx_line[40];

void irq_handler(uint32_t mcause)
{
    (void)mcause;
    if ((DMAC_STATUS & DMAC_DONE) && (DMAC_CTRL & DMAC_IRQ)) {
        DMAC_CTRL = 0;                          /* clears done and irq_enable: the request drops */
        dma_irqs++;
    }
    if ((UART_CTRL & UART_RX_IRQ) && (UART_STATUS & UART_RX_VALID)) {
        char c = (char)UART_DATA;               /* reading DATA clears rx_valid */
        if (rx_len < (int)sizeof rx_line)
            rx_line[rx_len++] = c;
        uart_irqs++;
    }
}

static void dma(const void *src, void *dst, uint32_t words, uint32_t ctrl)
{
    DMAC_SRC = (uint32_t)(uintptr_t)src;
    DMAC_DST = (uint32_t)(uintptr_t)dst;
    DMAC_LEN = words;
    DMAC_CTRL = DMAC_START | ctrl;
}

static void strip(char *s)
{
    s[strcspn(s, "\n")] = '\0';
}

int main(void)
{
    char line[64], reversed[64];
    int a = 0, b = 0, n = 0, c;

    printf("Timur UART input and interrupts\n");
    printf("two numbers: ");
    if (fgets(line, sizeof line, stdin) && sscanf(line, "%d %d", &a, &b) == 2) {
        strip(line);
        printf("%s\n  %d + %d = %d, %d * %d = %d, %d / %d = %d\n", line, a, b, a + b, a, b, a * b, a, b,
               b ? a / b : 0);
    }
    printf("your name: ");
    if (fgets(line, sizeof line, stdin)) {
        strip(line);
        printf("%s\n  hello, %s (%u characters)\n", line, line, (unsigned)strlen(line));
    }
    printf("a word to reverse: ");
    fflush(stdout);
    while ((c = getchar()) != EOF && c != '\n' && n < (int)sizeof line - 1)
        line[n++] = (char)c;
    line[n] = '\0';
    for (int i = 0; i < n; i++)
        reversed[i] = line[n - 1 - i];
    reversed[n] = '\0';
    printf("%s\n  reversed: %s\n", line, reversed);

    /* ---- part 2: interrupts ---- */
    csr_set(mie, MIE_MEIE);
    csr_set(mstatus, MSTATUS_MIE);
    dma(rom_table, copy, WORDS, DMAC_IRQ);
    while (dma_irqs == 0)
        __asm__ volatile ("wfi");               /* a NOP on Timur */
    printf("dma: %d words copied from ROM to RAM %s, done interrupt taken %d time(s)\n", WORDS,
           memcmp(copy, rom_table, sizeof copy) ? "WRONGLY" : "correctly", dma_irqs);

    csr_clear(mstatus, MSTATUS_MIE);
    dma(copy, copy2, 16, DMAC_IRQ);
    while (!(DMAC_STATUS & DMAC_DONE))
        ;
    printf("dma with mstatus.MIE = 0: done, mip.MEIP = %d, interrupts taken so far %d\n",
           (csr_read(mip) & MIP_MEIP) != 0, dma_irqs);
    csr_set(mstatus, MSTATUS_MIE);
    while (dma_irqs < 2)
        ;
    printf("  after setting MIE: interrupts taken %d, mip.MEIP = %d, copy %s\n", dma_irqs,
           (csr_read(mip) & MIP_MEIP) != 0, memcmp(copy2, rom_table, sizeof copy2) ? "WRONG" : "correct");

    printf("a line received by interrupt: ");
    fflush(stdout);
    UART_CTRL = UART_RX_ENABLE | UART_RX_IRQ;
    while (rx_len == 0 || rx_line[rx_len - 1] != '\r')
        if (rx_len == (int)sizeof rx_line)
            break;
    UART_CTRL = UART_RX_ENABLE;
    csr_clear(mstatus, MSTATUS_MIE);
    /* the handler is done with rx_line: copy it out of the volatile buffer for printf */
    for (int i = 0; i < rx_len; i++)
        line[i] = rx_line[i];
    printf("%.*s\n  %d bytes, %d receive interrupts\n", rx_len - 1, line, rx_len, uart_irqs);
    return 0;
}
