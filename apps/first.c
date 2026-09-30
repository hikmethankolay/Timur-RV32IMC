/* first.c: my first Timur program.
* Prints a greeting, then shows the switches on the LEDs 20 times and ends. */

#include <stdio.h> /* printf, puts, getchar, fgets ... (newlib-nano) */
#include "timur.h" /* Timur's registers: GPIO_OUT, GPIO_IN, UART_*, DMAC_*, CSRs */

int main(void)
{
    printf("Hello, this is my first program on Timur!\n");

    for (int i = 0; i < 20; i++) {
        uint32_t sw = GPIO_IN & GPIO_PIN_MASK; /* SW9..SW0 */
        GPIO_OUT = sw; /* LEDR9..LEDR0 */
        printf("round %2d: switches %03lx\n", i, (unsigned long)sw);
    }

    printf("done\n");

    return 0; /* ends the program: LEDs show 0x200 (LEDR9 = finished) */
}