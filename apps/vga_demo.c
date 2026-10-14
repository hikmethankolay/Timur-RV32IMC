/* vga_demo.c: the VGA output on the DE10-Lite.
 * printf goes to the monitor as well as the UART, the 16 standard colours are
 * drawn as swatches, then a square bounces forever, moved once per frame.
 * The switches pick its colour. */

#include <stdio.h> /* printf (newlib-nano) */
#include "timur.h" /* vga_*, GPIO_IN */

#define SIZE 12 /* the bouncing square, in framebuffer pixels */

int main(void)
{
    vga_console_init(VGA_WHITE, VGA_BLUE);
    printf("Timur RV32IMC on VGA\n");
    printf("320 x 240, 16 colours, 40 x 30 text\n\n");

    for (int c = 0; c < VGA_COLOURS; c++) {
        vga_fill_rect(8 + 19 * c, 32, 16, 16, (uint8_t)c);
        vga_draw_char(12 + 19 * c, 52, "0123456789ABCDEF"[c], VGA_WHITE, VGA_BLUE);
    }

    vga_set_cursor(0, 9);
    printf("Switches pick the colour of the square.\n");

    int x = 40, y = 120, dx = 2, dy = 1;
    for (;;) {
        uint8_t colour = (uint8_t)(GPIO_IN & 0xF);
        vga_wait_vblank(); /* move while the beam is outside the picture */
        vga_fill_rect(x, y, SIZE, SIZE, VGA_BLUE);
        if (x + dx < 0 || x + dx + SIZE > VGA_WIDTH)
            dx = -dx;
        if (y + dy < 88 || y + dy + SIZE > VGA_HEIGHT)
            dy = -dy;
        x += dx;
        y += dy;
        vga_fill_rect(x, y, SIZE, SIZE, colour ? colour : VGA_YELLOW);
    }
}
