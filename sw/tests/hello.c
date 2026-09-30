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
           (misa & MISA_EXT('I')) ? "I" : "", (misa & MISA_EXT('M')) ? "M" : "",
           (misa & MISA_EXT('C')) ? "C" : "");
    printf("switches: %03lx\n", (unsigned long)(GPIO_IN & GPIO_PIN_MASK));
    return 0;
}
