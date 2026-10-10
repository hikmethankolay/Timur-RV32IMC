/**
 * @file vga.c
 * @brief VGA driver of the Timur runtime: drawing into the framebuffer and a text console.
 *
 * The framebuffer holds 320 x 240 pixels of 4 bits, two per byte, the left
 * pixel in the low nibble (timur_defs.h). The hardware shows framebuffer row
 * VGA_SCROLL at the top of the screen, so the driver translates every screen
 * row through the scroll position it last set; the console scrolls by moving
 * that position eight rows and clearing one text row, never by copying.
 *
 * Programs that use none of these functions do not carry them: the runtime is
 * linked with --gc-sections, and _write only reaches vga_putc through
 * timur_console_hook, which vga_console_init sets.
 *
 * Timing: a console character is eight word stores; vga_clear and a full-screen
 * vga_show_image write 9600 words.
 */

#include <stdint.h>

#include "timur_runtime.h"

#define FB       ((volatile uint8_t *)TIMUR_VGA_FB_BASE)
#define FB_WORDS ((volatile uint32_t *)TIMUR_VGA_FB_BASE)

#define COLOUR_MASK     0xFu
#define CELL            8u /* console cell: 8 x 8 pixels, one framebuffer word per row */
#define PIXELS_PER_WORD 8u
#define FB_WORD_COUNT   (TIMUR_VGA_FB_SIZE / 4u)

/** Mirror of VGA_SCROLL: the framebuffer row at the top of the screen. */
static uint32_t scroll_row;

/** Framebuffer row of screen row y (0 <= y < VGA_HEIGHT). */
static uint32_t fb_row(uint32_t y)
{
    const uint32_t row = y + scroll_row;
    return row >= VGA_HEIGHT ? row - VGA_HEIGHT : row;
}

static volatile uint8_t *fb_line(uint32_t y)
{
    return FB + fb_row(y) * VGA_ROW_BYTES;
}

static int on_screen(int x, int y)
{
    return x >= 0 && x < VGA_WIDTH && y >= 0 && y < VGA_HEIGHT;
}

static void set_scroll(uint32_t row)
{
    scroll_row = row;
    VGA_SCROLL = row;
}

/** Eight pixels of one colour in a framebuffer word. */
static uint32_t splat(uint8_t colour)
{
    return (colour & COLOUR_MASK) * 0x11111111u;
}

static void set_nibble(volatile uint8_t *line, uint32_t x, uint8_t colour)
{
    volatile uint8_t *byte = &line[x / 2u];
    const uint32_t value = colour & COLOUR_MASK;
    if (x & 1u)
        *byte = (uint8_t)((*byte & 0x0Fu) | (value << 4));
    else
        *byte = (uint8_t)((*byte & 0xF0u) | value);
}

static uint8_t get_nibble(const volatile uint8_t *line, uint32_t x)
{
    const uint32_t byte = line[x / 2u];
    return (uint8_t)((x & 1u) ? byte >> 4 : byte & COLOUR_MASK);
}

void vga_clear(uint8_t colour)
{
    const uint32_t word = splat(colour);
    set_scroll(0);
    for (uint32_t i = 0; i < FB_WORD_COUNT; i++)
        FB_WORDS[i] = word;
}

void vga_set_pixel(int x, int y, uint8_t colour)
{
    if (on_screen(x, y))
        set_nibble(fb_line((uint32_t)y), (uint32_t)x, colour);
}

uint8_t vga_get_pixel(int x, int y)
{
    if (!on_screen(x, y))
        return 0;
    return get_nibble(fb_line((uint32_t)y), (uint32_t)x);
}

/** Clip [*start, *start + length) to [0, limit); returns the end, or 0 if empty. */
static int clip(int *start, int length, int limit)
{
    int end = *start + length;
    if (*start < 0)
        *start = 0;
    if (end > limit)
        end = limit;
    return end > *start ? end : 0;
}

void vga_fill_rect(int x, int y, int w, int h, uint8_t colour)
{
    const int x_end = clip(&x, w, VGA_WIDTH);
    const int y_end = clip(&y, h, VGA_HEIGHT);
    const uint8_t pair = (uint8_t)((colour & COLOUR_MASK) * 0x11u);

    if (!x_end || !y_end)
        return;
    for (int row = y; row < y_end; row++) {
        volatile uint8_t *line = fb_line((uint32_t)row);
        uint32_t px = (uint32_t)x;
        if (px & 1u)
            set_nibble(line, px++, colour);
        for (; px + 1u < (uint32_t)x_end; px += 2u)
            line[px / 2u] = pair;
        if (px < (uint32_t)x_end)
            set_nibble(line, px, colour);
    }
}

void vga_blit(int x, int y, int w, int h, const uint8_t *pixels)
{
    const uint32_t stride = ((uint32_t)w + 1u) / 2u;

    if (w <= 0 || h <= 0)
        return;
    for (int row = 0; row < h; row++) {
        const uint8_t *source = pixels + (uint32_t)row * stride;
        for (int column = 0; column < w; column++) {
            const uint32_t byte = source[(uint32_t)column / 2u];
            const uint8_t colour = (uint8_t)((column & 1) ? byte >> 4 : byte & COLOUR_MASK);
            vga_set_pixel(x + column, y + row, colour);
        }
    }
}

void vga_show_image(const void *image)
{
    set_scroll(0);
    DMAC_SRC = (uint32_t)(uintptr_t)image;
    DMAC_DST = TIMUR_VGA_FB_BASE;
    DMAC_LEN = FB_WORD_COUNT;
    DMAC_CTRL = DMAC_START;
    while (!(DMAC_STATUS & DMAC_DONE))
        ;
    DMAC_CTRL = 0; /* clears DONE */
}

void vga_set_palette(int index, uint32_t rgb)
{
    if (index >= 0 && index < VGA_COLOURS)
        VGA_PALETTE(index) = rgb & 0xFFFu;
}

void vga_wait_vblank(void)
{
    const uint32_t frame = VGA_FRAME;
    while (VGA_FRAME == frame)
        ;
}

/* ---- characters --------------------------------------------------------------------- */

/** spread[n]: the 16-bit mask of four pixels whose glyph bits are n (bit 3 = left). */
static const uint16_t spread[16] = {
    0x0000, 0xF000, 0x0F00, 0xFF00, 0x00F0, 0xF0F0, 0x0FF0, 0xFFF0,
    0x000F, 0xF00F, 0x0F0F, 0xFF0F, 0x00FF, 0xF0FF, 0x0FFF, 0xFFFF,
};

/** Drawn for characters outside the font. */
static const uint8_t box[VGA_FONT_ROWS] = { 0x00, 0x7C, 0x44, 0x44, 0x44, 0x44, 0x7C, 0x00 };

static const uint8_t *glyph(char c)
{
    const uint32_t code = (uint8_t)c;
    if (code < VGA_FONT_FIRST || code >= VGA_FONT_FIRST + VGA_FONT_GLYPHS)
        return box;
    return vga_font[code - VGA_FONT_FIRST];
}

void vga_draw_char(int x, int y, char c, uint8_t fg, uint8_t bg)
{
    const uint8_t *rows = glyph(c);

    if ((x & (int)(CELL - 1u)) == 0 && on_screen(x, y) && y + (int)CELL <= VGA_HEIGHT) {
        /* aligned: one framebuffer word per glyph row */
        const uint32_t fg_word = splat(fg);
        const uint32_t bg_word = splat(bg);
        const uint32_t word = (uint32_t)x / PIXELS_PER_WORD;
        for (uint32_t r = 0; r < CELL; r++) {
            const uint32_t mask = spread[rows[r] >> 4] | ((uint32_t)spread[rows[r] & 0xFu] << 16);
            const uint32_t index = fb_row((uint32_t)y + r) * (VGA_ROW_BYTES / 4u) + word;
            FB_WORDS[index] = (fg_word & mask) | (bg_word & ~mask);
        }
        return;
    }
    for (int r = 0; r < (int)CELL; r++)
        for (int column = 0; column < (int)CELL; column++)
            vga_set_pixel(x + column, y + r, ((uint32_t)rows[r] >> (7 - column)) & 1u ? fg : bg);
}

/* ---- console ------------------------------------------------------------------------- */

static int con_column, con_row;
static uint8_t con_fg = VGA_WHITE, con_bg = VGA_BLACK;

static void new_line(void)
{
    con_column = 0;
    if (con_row < VGA_CONSOLE_ROWS - 1) {
        con_row++;
        return;
    }
    /* the top text row becomes the bottom one */
    set_scroll(fb_row(CELL));
    vga_fill_rect(0, (VGA_CONSOLE_ROWS - 1) * (int)CELL, VGA_WIDTH, (int)CELL, con_bg);
}

void vga_console_init(uint8_t fg, uint8_t bg)
{
    vga_set_colours(fg, bg);
    vga_clear(bg);
    con_column = con_row = 0;
    timur_console_hook = vga_putc;
}

void vga_putc(char c)
{
    switch (c) {
    case '\n':
        new_line();
        break;
    case '\r':
        con_column = 0;
        break;
    case '\b':
        if (con_column > 0)
            con_column--;
        break;
    case '\t':
        con_column = (con_column + (int)CELL) & ~(int)(CELL - 1u);
        if (con_column >= VGA_CONSOLE_COLUMNS)
            new_line();
        break;
    default:
        if (con_column >= VGA_CONSOLE_COLUMNS) /* wrap only when a character follows */
            new_line();
        vga_draw_char(con_column * (int)CELL, con_row * (int)CELL, c, con_fg, con_bg);
        con_column++;
        break;
    }
}

void vga_puts(const char *s)
{
    while (*s)
        vga_putc(*s++);
}

void vga_set_colours(uint8_t fg, uint8_t bg)
{
    con_fg = (uint8_t)(fg & COLOUR_MASK);
    con_bg = (uint8_t)(bg & COLOUR_MASK);
}

static int clamp(int value, int high)
{
    return value < 0 ? 0 : value > high ? high : value;
}

void vga_set_cursor(int column, int row)
{
    con_column = clamp(column, VGA_CONSOLE_COLUMNS - 1);
    con_row = clamp(row, VGA_CONSOLE_ROWS - 1);
}
