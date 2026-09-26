/* The first C program: printf over the UART, a CSR read and the switches.
 * On the board: the banner at 115200 8N1, then the LEDs mirror SW[8:0] with
 * LEDR9 lit (exit code 0 shown by _exit is replaced by the switch value). */
#include <stdio.h>
#include "timur.h"

int main(void)
{
    uint32_t misa = csr_read(misa);

    printf("Hello from Timur RV32IMC!\n");
    printf("misa %08lx: RV32%s%s%s, machine mode\n", (unsigned long)misa,
           (misa & (1u << 8)) ? "I" : "", (misa & (1u << 12)) ? "M" : "",
           (misa & (1u << 2)) ? "C" : "");
    printf("switches: %03lx\n", (unsigned long)(GPIO_IN & 0x3FFu));
    return 0;
}
