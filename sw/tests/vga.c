/* The VGA controller and driver: registers after reset, the palette and SCROLL
 * ranges, framebuffer stores of every size and the bytes beyond its end, the
 * drawing functions checked pixel by pixel, characters against the font, a DMA
 * copy from ROM into the framebuffer, and the console (printf on the screen,
 * line wrap, hardware scrolling). Nothing here waits for the beam: the
 * reference model has no beam, so STATUS and FRAME are not read. */
#include <stdio.h>
#include "timur.h"

extern const uint8_t vga_font[95][8]; /* the runtime's console font */

static int checks, failures;

static void check_eq(const char *what, uint32_t got, uint32_t expected)
{
    checks++;
    if (got != expected) {
        failures++;
        printf("FAIL %s: got %08lx, expected %08lx\n", what, (unsigned long)got,
               (unsigned long)expected);
    }
}

#define FB32 ((volatile uint32_t *)TIMUR_VGA_FB_BASE)
#define FB16 ((volatile uint16_t *)TIMUR_VGA_FB_BASE)

static const uint16_t reset_palette[16] = {
    0x000, 0x00A, 0x0A0, 0x0AA, 0xA00, 0xA0A, 0xA50, 0xAAA,
    0x555, 0x55F, 0x5F5, 0x5FF, 0xF55, 0xF5F, 0xFF5, 0xFFF,
};

static void registers(void)
{
    check_eq("CTRL after reset", VGA_CTRL, VGA_ENABLE);
    check_eq("SCROLL after reset", VGA_SCROLL, 0);
    for (int i = 0; i < 16; i++)
        check_eq("palette after reset", VGA_PALETTE(i), reset_palette[i]);

    VGA_PALETTE(3) = 0xFFFFF123u;
    check_eq("palette keeps 12 bits", VGA_PALETTE(3), 0x123);
    vga_set_palette(3, reset_palette[3]);
    vga_set_palette(16, 0x777); /* ignored: there is no entry 16 */
    check_eq("palette restored", VGA_PALETTE(3), reset_palette[3]);

    VGA_SCROLL = 239;
    check_eq("SCROLL 239", VGA_SCROLL, 239);
    VGA_SCROLL = 240;
    check_eq("SCROLL 240 ignored", VGA_SCROLL, 239);
    VGA_SCROLL = 0;

    VGA_CTRL = 0;
    check_eq("CTRL off", VGA_CTRL, 0);
    VGA_CTRL = VGA_ENABLE;
}

static void stores(void)
{
    FB32[0] = 0x11223344u;
    check_eq("word store", FB32[0], 0x11223344u);
    VGA_FRAMEBUFFER[5] = 0xAB;
    FB16[3] = 0xBEEF;
    check_eq("byte and halfword stores", FB32[1] & 0xFFFFFF00u, 0xBEEFAB00u);
    check_eq("byte load", VGA_FRAMEBUFFER[6], 0xEF);
    check_eq("halfword load", FB16[0], 0x3344);

    VGA_FRAMEBUFFER[TIMUR_VGA_FB_SIZE - 1u] = 0x5A;
    check_eq("last byte", VGA_FRAMEBUFFER[TIMUR_VGA_FB_SIZE - 1u], 0x5A);
    FB32[TIMUR_VGA_FB_SIZE / 4u] = 0xDEADBEEFu; /* beyond the end: ignored */
    check_eq("beyond the end reads 0", FB32[TIMUR_VGA_FB_SIZE / 4u], 0);
    check_eq("no aliasing", FB32[0], 0x11223344u);
}

static void drawing(void)
{
    vga_clear(VGA_BLUE);
    check_eq("clear: first word", FB32[0], 0x11111111u);
    check_eq("clear: last word", FB32[TIMUR_VGA_FB_SIZE / 4u - 1u], 0x11111111u);
    check_eq("clear resets SCROLL", VGA_SCROLL, 0);

    vga_set_pixel(0, 0, VGA_WHITE);
    vga_set_pixel(319, 239, VGA_YELLOW);
    vga_set_pixel(320, 0, VGA_RED); /* clipped */
    vga_set_pixel(-1, 5, VGA_RED);
    check_eq("pixel (0,0) is the low nibble", VGA_FRAMEBUFFER[0], 0x1F);
    check_eq("pixel (319,239) is the last high nibble",
             VGA_FRAMEBUFFER[TIMUR_VGA_FB_SIZE - 1u], 0xE1);
    check_eq("get_pixel", vga_get_pixel(319, 239), VGA_YELLOW);
    check_eq("get_pixel outside", vga_get_pixel(320, 0), 0);

    /* a rectangle with odd edges, and one partly off the screen */
    vga_fill_rect(3, 10, 6, 3, VGA_RED);
    vga_fill_rect(315, 236, 20, 20, VGA_GREEN);
    int bad = 0;
    for (int y = 8; y < 14; y++)
        for (int x = 0; x < 12; x++) {
            int inside = x >= 3 && x < 9 && y >= 10 && y < 13;
            bad += vga_get_pixel(x, y) != (inside ? VGA_RED : VGA_BLUE);
        }
    check_eq("fill_rect with odd edges", (uint32_t)bad, 0);
    check_eq("fill_rect clipped", vga_get_pixel(319, 239), VGA_GREEN);
    check_eq("fill_rect clipped edge", vga_get_pixel(314, 239), VGA_BLUE);

    /* a 3 x 2 image at an odd x: rows of two bytes, the left pixel low */
    static const uint8_t image[] = { 0x21, 0x03, 0x54, 0x06 };
    vga_blit(101, 50, 3, 2, image);
    check_eq("blit row 0", (uint32_t)(vga_get_pixel(101, 50) | vga_get_pixel(102, 50) << 4 |
                                      vga_get_pixel(103, 50) << 8), 0x321);
    check_eq("blit row 1", (uint32_t)(vga_get_pixel(101, 51) | vga_get_pixel(102, 51) << 4 |
                                      vga_get_pixel(103, 51) << 8), 0x654);
    check_eq("blit leaves its neighbours", vga_get_pixel(104, 50), VGA_BLUE);
}

/* The number of pixels of character c at (x, y) that differ from the font. */
static uint32_t char_errors(int x, int y, char c, uint8_t fg, uint8_t bg)
{
    uint32_t bad = 0;
    for (int r = 0; r < 8; r++)
        for (int col = 0; col < 8; col++) {
            int on = (vga_font[c - 0x20][r] >> (7 - col)) & 1;
            bad += vga_get_pixel(x + col, y + r) != (on ? fg : bg);
        }
    return bad;
}

static void characters(void)
{
    vga_draw_char(16, 24, 'A', VGA_YELLOW, VGA_BLACK);   /* aligned: word stores */
    vga_draw_char(37, 41, 'g', VGA_LIGHT_CYAN, VGA_RED); /* unaligned: pixel by pixel */
    check_eq("aligned character", char_errors(16, 24, 'A', VGA_YELLOW, VGA_BLACK), 0);
    check_eq("unaligned character", char_errors(37, 41, 'g', VGA_LIGHT_CYAN, VGA_RED), 0);
    check_eq("font: 'A' row 3", vga_font['A' - 0x20][3], 0x7C);
}

/* A DMA copy from ROM straight into the framebuffer. */
static const uint32_t rom_words[16] = {
    0x01234567, 0x89ABCDEF, 0xFEDCBA98, 0x76543210, 1, 2, 3, 4,
    0x11111111, 0x22222222, 0x33333333, 0x44444444, 0xA5A5A5A5, 0x5A5A5A5A, 0, 0xFFFFFFFF,
};

static void dma(void)
{
    DMAC_SRC = (uint32_t)(uintptr_t)rom_words;
    DMAC_DST = TIMUR_VGA_FB_BASE + VGA_ROW_BYTES * 100u;
    DMAC_LEN = 16;
    DMAC_CTRL = DMAC_START;
    while (!(DMAC_STATUS & DMAC_DONE))
        ;
    DMAC_CTRL = 0;
    uint32_t bad = 0;
    for (int i = 0; i < 16; i++)
        bad += FB32[VGA_ROW_BYTES / 4 * 100 + i] != rom_words[i];
    check_eq("DMA from ROM into the framebuffer", bad, 0);
}

static void console(void)
{
    vga_console_init(VGA_WHITE, VGA_BLUE);
    printf("Hi\tVGA\n"); /* on the screen and on the UART */
    check_eq("console 'H'", char_errors(0, 0, 'H', VGA_WHITE, VGA_BLUE), 0);
    check_eq("console 'i'", char_errors(8, 0, 'i', VGA_WHITE, VGA_BLUE), 0);
    check_eq("console tab", char_errors(64, 0, 'V', VGA_WHITE, VGA_BLUE), 0);

    /* 41 characters: the 41st wraps to the next row */
    vga_set_colours(VGA_YELLOW, VGA_BLUE);
    for (int i = 0; i < 40; i++)
        vga_putc('=');
    vga_putc('#');
    check_eq("40 columns", char_errors(312, 8, '=', VGA_YELLOW, VGA_BLUE), 0);
    check_eq("wrap", char_errors(0, 16, '#', VGA_YELLOW, VGA_BLUE), 0);

    /* a new line on the last row scrolls the screen up by one row of 8 pixels */
    vga_set_colours(VGA_WHITE, VGA_BLUE);
    vga_set_cursor(0, 29);
    vga_puts("last\nnew");
    check_eq("scrolled one row", VGA_SCROLL, 8);
    check_eq("previous row moved up", char_errors(0, 224, 'l', VGA_WHITE, VGA_BLUE), 0);
    check_eq("new bottom row", char_errors(0, 232, 'n', VGA_WHITE, VGA_BLUE), 0);
    check_eq("rest of the bottom row cleared", vga_get_pixel(200, 236), VGA_BLUE);
    check_eq("top row is the old row 1", char_errors(0, 0, '=', VGA_YELLOW, VGA_BLUE), 0);
}

int main(void)
{
    registers();
    stores();
    drawing();
    characters();
    dma();
    console();
    if (failures)
        printf("\nvga: %d of %d checks failed\n", failures, checks);
    else
        printf("\nvga: all %d checks passed\n", checks);
    return failures != 0;
}
