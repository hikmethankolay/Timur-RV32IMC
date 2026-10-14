/* showcase.c: a tour of what Timur can do on the DE10-Lite, on a VGA monitor.
 * Seven scenes of about ten seconds each, repeated forever:
 *   1 console   printf on the screen, the console scrolled by the hardware
 *   2 plasma    a sine plasma drawn once and animated only through the palette
 *   3 fractal   a Mandelbrot set in fixed point (MUL), timed with mcycle
 *   4 cube      a rotating wireframe cube: MUL, DIV and line drawing
 *   5 balls     sprites moved in step with the vertical blank
 *   6 dma       a picture moved by the DMA controller every frame, CPU vs DMA copy
 *   7 scroller  a text roller moved only by the SCROLL register
 * Switches: SW9 up holds the current scene; SW0 and SW1 set the speed (1-4).
 * LEDs: LEDR0-6 show the scene, LEDR8 is lit while SW9 holds it.
 * The UART log names each scene as it starts. */

#include <stdio.h>  /* printf, snprintf (newlib-nano) */
#include <stdlib.h> /* abs */
#include "timur.h"

#ifndef FIRST_SCENE
#define FIRST_SCENE 0 /* -DFIRST_SCENE=n starts at another scene */
#endif

#define FRAMES_PER_SCENE 600 /* 60 frames per second: 10 s */
#define LED_HOLD         (1u << 8)
#define TOP              10 /* the title bar: rows 0-9 */
#define BOTTOM           230 /* the hint bar: rows 230-239 */
#define FB_WORDS         ((volatile uint32_t *)TIMUR_VGA_FB_BASE)
#define ROW_WORDS        (VGA_ROW_BYTES / 4)

/* ---- helpers ------------------------------------------------------------------------- */

/** 127 * sin(2 pi i / 256). */
static const int8_t sine[256] = {
    0, 3, 6, 9, 12, 16, 19, 22, 25, 28, 31, 34, 37, 40, 43, 46,
    49, 51, 54, 57, 60, 63, 65, 68, 71, 73, 76, 78, 81, 83, 85, 88,
    90, 92, 94, 96, 98, 100, 102, 104, 106, 107, 109, 111, 112, 113, 115, 116,
    117, 118, 120, 121, 122, 122, 123, 124, 125, 125, 126, 126, 126, 127, 127, 127,
    127, 127, 127, 127, 126, 126, 126, 125, 125, 124, 123, 122, 122, 121, 120, 118,
    117, 116, 115, 113, 112, 111, 109, 107, 106, 104, 102, 100, 98, 96, 94, 92,
    90, 88, 85, 83, 81, 78, 76, 73, 71, 68, 65, 63, 60, 57, 54, 51,
    49, 46, 43, 40, 37, 34, 31, 28, 25, 22, 19, 16, 12, 9, 6, 3,
    0, -3, -6, -9, -12, -16, -19, -22, -25, -28, -31, -34, -37, -40, -43, -46,
    -49, -51, -54, -57, -60, -63, -65, -68, -71, -73, -76, -78, -81, -83, -85, -88,
    -90, -92, -94, -96, -98, -100, -102, -104, -106, -107, -109, -111, -112, -113, -115, -116,
    -117, -118, -120, -121, -122, -122, -123, -124, -125, -125, -126, -126, -126, -127, -127, -127,
    -127, -127, -127, -127, -126, -126, -126, -125, -125, -124, -123, -122, -122, -121, -120, -118,
    -117, -116, -115, -113, -112, -111, -109, -107, -106, -104, -102, -100, -98, -96, -94, -92,
    -90, -88, -85, -83, -81, -78, -76, -73, -71, -68, -65, -63, -60, -57, -54, -51,
    -49, -46, -43, -40, -37, -34, -31, -28, -25, -22, -19, -16, -12, -9, -6, -3,
};

static int isin(int angle) { return sine[angle & 255]; }
static int icos(int angle) { return sine[(angle + 64) & 255]; }

/** The palette after reset (rtl/periph/vga.v). */
static const uint16_t standard_palette[VGA_COLOURS] = {
    0x000, 0x00A, 0x0A0, 0x0AA, 0xA00, 0xA0A, 0xA50, 0xAAA,
    0x555, 0x55F, 0x5F5, 0x5FF, 0xF55, 0xF5F, 0xFF5, 0xFFF,
};

static void reset_palette(void)
{
    for (int i = 0; i < VGA_COLOURS; i++)
        vga_set_palette(i, standard_palette[i]);
}

/** A colour wheel of 96 steps, as 0xRGB. */
static uint32_t hue(int h)
{
    const uint32_t f = (uint32_t)(h % 16), seg = (uint32_t)(h / 16) % 6;
    /* per segment and channel: 0 off, 1 falling, 2 full, 3 rising */
    static const uint8_t r[6] = { 2, 1, 0, 0, 3, 2 }, g[6] = { 3, 2, 2, 1, 0, 0 },
                         b[6] = { 0, 0, 3, 2, 2, 1 };
    const uint32_t level[4] = { 0, 15 - f, 15, f };
    return (level[r[seg]] << 8) | (level[g[seg]] << 4) | level[b[seg]];
}

/** Colours 1-14 become a rainbow that moves with t; 0 (black) and 15 (white) stay. */
static void cycle_palette(uint32_t t)
{
    for (int i = 0; i < 14; i++)
        vga_set_palette(1 + i, hue((int)(((uint32_t)(i * 96 / 14) + t) % 96)));
}

static int holding(void) { return (GPIO_IN >> 9) & 1u; }
static int speed(void) { return (int)(GPIO_IN & 3u) + 1; }

static void draw_text(int x, int y, const char *s, uint8_t fg, uint8_t bg)
{
    for (; *s; s++, x += 8)
        vga_draw_char(x, y, *s, fg, bg);
}

static void title(const char *text)
{
    vga_fill_rect(0, 0, VGA_WIDTH, TOP, VGA_BLACK);
    draw_text(0, 1, text, VGA_WHITE, VGA_BLACK);
}

static void hint(const char *text)
{
    vga_fill_rect(0, BOTTOM, VGA_WIDTH, VGA_HEIGHT - BOTTOM, VGA_BLACK);
    draw_text(0, BOTTOM + 1, text, VGA_WHITE, VGA_BLACK);
}

static const char switch_hint[] = "SW9 up: hold scene   SW0-1: speed";

static uint32_t cycles(void) { return csr_read(mcycle); }
static unsigned microseconds(uint32_t c) { return (unsigned)(c / (TIMUR_CLOCK_HZ / 1000000)); }

static void draw_line(int x0, int y0, int x1, int y1, uint8_t colour)
{
    const int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    const int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    for (;;) {
        vga_set_pixel(x0, y0, colour);
        if (x0 == x1 && y0 == y1)
            return;
        const int e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

/* ---- 1 console --------------------------------------------------------------------- */

static uint32_t prime_candidate, prime_count;

static void console_init(void)
{
    const uint32_t misa = csr_read(misa);

    vga_console_init(VGA_WHITE, VGA_BLUE);
    vga_set_colours(VGA_YELLOW, VGA_BLUE);
    printf("1/7 TIMUR RV32IMC - console\n\n");
    vga_set_colours(VGA_WHITE, VGA_BLUE);
    printf("ISA     RV32");
    for (const char *letter = "IEMAFDC"; *letter; letter++) /* the canonical order */
        if (misa & MISA_EXT(*letter))
            printf("%c", *letter);
    printf(" (from misa)\n");
    printf("Clock   %u MHz, 5-stage pipeline\n", (unsigned)(TIMUR_CLOCK_HZ / 1000000));
    printf("Memory  64 KB ROM, 64 KB RAM\n");
    printf("Video   320x240, 16 of 4096 colours\n");
    printf("I/O     UART, DMA, 10 LEDs, 10 SW\n\n");
    printf("printf writes here and to the UART.\n");
    printf("Counting primes with DIV/REM...\n\n");
    prime_candidate = 1;
    prime_count = 0;
}

static int is_prime(uint32_t n)
{
    if (n < 2)
        return 0;
    for (uint32_t d = 2; d * d <= n; d++)
        if (n % d == 0)
            return 0;
    return 1;
}

static void console_step(uint32_t t)
{
    if (t % (uint32_t)(5 - speed()))
        return;
    while (!is_prime(++prime_candidate))
        ;
    prime_count++;
    vga_set_colours((uint8_t)(10 + prime_count % 6), VGA_BLUE); /* 10-15: bright on blue */
    printf("prime %4u is %6u\n", (unsigned)prime_count, (unsigned)prime_candidate);
}

/* ---- 2 plasma ---------------------------------------------------------------------- */

static uint32_t palette_phase;

static void plasma_init(void)
{
    vga_clear(VGA_BLACK);
    for (int y = 0; y < VGA_HEIGHT; y++) {
        const int dy = y - VGA_HEIGHT / 2;
        for (int x = 0; x < VGA_WIDTH; x += 8) {
            uint32_t word = 0;
            for (int i = 0; i < 8; i++) {
                const int px = x + i, dx = px - VGA_WIDTH / 2;
                const int v = isin(px * 3) + isin(y * 4) + isin((px + y) * 2) +
                              isin((dx * dx + dy * dy) >> 7);
                const uint32_t colour = 1u + (uint32_t)((v + 512) >> 3) % 14u;
                word |= colour << (4 * i);
            }
            FB_WORDS[y * ROW_WORDS + x / 8] = word;
        }
    }
    title("2/7 PLASMA: only the palette moves");
    hint(switch_hint);
    palette_phase = 0;
}

static void plasma_step(uint32_t t)
{
    (void)t;
    palette_phase += (uint32_t)speed();
    cycle_palette(palette_phase);
}

/* ---- 3 fractal --------------------------------------------------------------------- */

#define FRAC     12 /* fixed point: 12 fraction bits */
#define MAX_ITER 48

static void fractal_init(void)
{
    char line[48];
    uint32_t iterations = 0;

    vga_clear(VGA_BLACK);
    title("3/7 MANDELBROT: fixed point, MUL");
    hint("rendering...");
    cycle_palette(0);

    const uint32_t start = cycles();
    const int step = 41;         /* 0.01 in Q12 */
    int ci = -(11 << FRAC) / 10; /* -1.1 */
    for (int y = TOP; y < BOTTOM; y++, ci += step) {
        int cr = -(22 << FRAC) / 10; /* -2.2 */
        for (int x = 0; x < VGA_WIDTH; x += 8) {
            uint32_t word = 0;
            for (int i = 0; i < 8; i++, cr += step) {
                int zr = 0, zi = 0, n = 0;
                for (; n < MAX_ITER; n++) {
                    const int rr = (zr * zr) >> FRAC, ii = (zi * zi) >> FRAC;
                    if (rr + ii > (4 << FRAC))
                        break;
                    zi = ((zr * zi) >> (FRAC - 1)) + ci;
                    zr = rr - ii + cr;
                }
                iterations += (uint32_t)n;
                word |= (uint32_t)(n == MAX_ITER ? 0 : 1 + n % 14) << (4 * i);
            }
            FB_WORDS[y * ROW_WORDS + x / 8] = word;
        }
    }
    const uint32_t elapsed = cycles() - start;

    snprintf(line, sizeof line, "%u ms, %u iterations", microseconds(elapsed) / 1000u,
             (unsigned)iterations);
    hint(line);
    uart_puts("  fractal: ");
    uart_puts(line);
    uart_puts("\n");
    palette_phase = 0;
}

static void fractal_step(uint32_t t)
{
    if (t % 2 == 0)
        palette_phase += (uint32_t)speed();
    cycle_palette(palette_phase);
}

/* ---- 4 cube ------------------------------------------------------------------------ */

#define CUBE_SIZE 45
#define CUBE_DIST 220 /* camera distance, and the focal length */

static const int8_t cube_vertex[8][3] = {
    { -1, -1, -1 }, { 1, -1, -1 }, { 1, 1, -1 }, { -1, 1, -1 },
    { -1, -1, 1 },  { 1, -1, 1 },  { 1, 1, 1 },  { -1, 1, 1 },
};
static const uint8_t cube_edge[12][2] = {
    { 0, 1 }, { 1, 2 }, { 2, 3 }, { 3, 0 }, { 4, 5 }, { 5, 6 },
    { 6, 7 }, { 7, 4 }, { 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 },
};
static int cube_x[8], cube_y[8], cube_drawn;
static int angle_a, angle_b;

static void cube_draw(uint8_t colour)
{
    for (int e = 0; e < 12; e++) {
        const int a = cube_edge[e][0], b = cube_edge[e][1];
        draw_line(cube_x[a], cube_y[a], cube_x[b], cube_y[b], colour);
    }
}

static void cube_init(void)
{
    vga_clear(VGA_BLACK);
    title("4/7 3D CUBE: MUL, DIV, lines");
    hint(switch_hint);
    cube_drawn = 0;
    angle_a = angle_b = 0;
}

static void cube_step(uint32_t t)
{
    if (cube_drawn)
        cube_draw(VGA_BLACK);
    angle_a += speed();
    angle_b += speed() * 2;
    for (int v = 0; v < 8; v++) {
        const int x = cube_vertex[v][0] * CUBE_SIZE, y = cube_vertex[v][1] * CUBE_SIZE,
                  z = cube_vertex[v][2] * CUBE_SIZE;
        const int x1 = (x * icos(angle_a) + z * isin(angle_a)) >> 7;
        const int z1 = (z * icos(angle_a) - x * isin(angle_a)) >> 7;
        const int y2 = (y * icos(angle_b) - z1 * isin(angle_b)) >> 7;
        const int z2 = (y * isin(angle_b) + z1 * icos(angle_b)) >> 7;
        cube_x[v] = VGA_WIDTH / 2 + x1 * CUBE_DIST / (z2 + CUBE_DIST);
        cube_y[v] = VGA_HEIGHT / 2 + y2 * CUBE_DIST / (z2 + CUBE_DIST);
    }
    cube_draw((uint8_t)(9 + (t / 30) % 7)); /* the bright colours 9-15 */
    cube_drawn = 1;
}

/* ---- 5 balls ----------------------------------------------------------------------- */

#define BALLS   12
#define RADIUS  7
#define GRAVITY 2 /* 1/16 pixel per frame per frame */

struct ball {
    int x, y, vx, vy; /* 1/16 pixel */
    int drawn_x, drawn_y;
    uint8_t colour;
};
static struct ball balls[BALLS];
static int8_t ball_span[2 * RADIUS + 1]; /* half width of each row of the disc */
static uint32_t random_state = 12345;

static int random_below(int n)
{
    random_state = random_state * 1103515245u + 12345u;
    return (int)((random_state >> 16) % (uint32_t)n);
}

static void ball_draw(int cx, int cy, uint8_t colour)
{
    for (int dy = -RADIUS; dy <= RADIUS; dy++) {
        const int w = ball_span[dy + RADIUS];
        vga_fill_rect(cx - w, cy + dy, 2 * w + 1, 1, colour);
    }
}

static void balls_init(void)
{
    for (int dy = -RADIUS; dy <= RADIUS; dy++) {
        int w = 0;
        while ((w + 1) * (w + 1) + dy * dy <= RADIUS * RADIUS)
            w++;
        ball_span[dy + RADIUS] = (int8_t)w;
    }
    vga_clear(VGA_BLACK);
    title("5/7 SPRITES: synced to vblank");
    hint(switch_hint);
    for (int i = 0; i < BALLS; i++) {
        struct ball *b = &balls[i];
        b->x = (RADIUS + random_below(VGA_WIDTH - 2 * RADIUS)) * 16;
        b->y = (TOP + RADIUS + random_below(100)) * 16;
        b->vx = random_below(64) - 32;
        b->vy = random_below(32) - 16;
        b->colour = (uint8_t)(9 + i % 7);
        b->drawn_x = -1;
    }
}

static void balls_step(uint32_t t)
{
    const int x_max = (VGA_WIDTH - 1 - RADIUS) * 16, x_min = RADIUS * 16;
    const int y_max = (BOTTOM - 1 - RADIUS) * 16, y_min = (TOP + RADIUS) * 16;

    (void)t;
    for (int i = 0; i < BALLS; i++)
        if (balls[i].drawn_x >= 0)
            ball_draw(balls[i].drawn_x, balls[i].drawn_y, VGA_BLACK);
    for (int i = 0; i < BALLS; i++) {
        struct ball *b = &balls[i];
        for (int s = speed(); s > 0; s--) {
            b->vy += GRAVITY;
            b->x += b->vx;
            b->y += b->vy;
            if (b->x < x_min || b->x > x_max) {
                b->x = b->x < x_min ? x_min : x_max;
                b->vx = -b->vx;
            }
            if (b->y > y_max) {
                b->y = y_max;
                b->vy = -b->vy;
            } else if (b->y < y_min) {
                b->y = y_min;
                b->vy = -b->vy;
            }
        }
        b->drawn_x = b->x / 16;
        b->drawn_y = b->y / 16;
        ball_draw(b->drawn_x, b->drawn_y, b->colour);
    }
}

/* ---- 6 dma ------------------------------------------------------------------------- */

#define DMA_TOP    40 /* rows 0-39 hold the text */
#define DMA_ROWS   (VGA_HEIGHT - DMA_TOP)
#define DMA_PERIOD 32 /* the pattern repeats every 32 rows */
#define DMA_WORDS  (DMA_ROWS * ROW_WORDS)

/** The picture in RAM, one period taller than the area it fills. */
static uint32_t dma_image[(DMA_ROWS + DMA_PERIOD) * ROW_WORDS];

static void dma_copy(const uint32_t *source)
{
    DMAC_SRC = (uint32_t)(uintptr_t)source;
    DMAC_DST = TIMUR_VGA_FB_BASE + DMA_TOP * VGA_ROW_BYTES;
    DMAC_LEN = DMA_WORDS;
    DMAC_CTRL = DMAC_START;
    while (!(DMAC_STATUS & DMAC_DONE))
        ;
    DMAC_CTRL = 0; /* clears DONE */
}

static void dma_init(void)
{
    char line[48];

    vga_clear(VGA_BLACK);
    title("6/7 DMA: the CPU only starts it");
    for (int y = 0; y < DMA_ROWS + DMA_PERIOD; y++)
        for (int x = 0; x < VGA_WIDTH; x += 8) {
            uint32_t word = 0;
            for (int i = 0; i < 8; i++) {
                const int px = x + i;
                const uint32_t colour = (uint32_t)(((px + 4 * y) >> 3) & 7) |
                                        (uint32_t)(((px >> 4) ^ (y >> 4)) & 1) << 3;
                word |= colour << (4 * i);
            }
            dma_image[y * ROW_WORDS + x / 8] = word;
        }

    uint32_t start = cycles();
    for (int i = 0; i < DMA_WORDS; i++)
        FB_WORDS[DMA_TOP * ROW_WORDS + i] = dma_image[i];
    const uint32_t cpu_time = cycles() - start;

    start = cycles();
    dma_copy(dma_image);
    const uint32_t dma_time = cycles() - start;

    snprintf(line, sizeof line, "CPU copy, %u words: %5u us", DMA_WORDS, microseconds(cpu_time));
    draw_text(0, 13, line, VGA_LIGHT_RED, VGA_BLACK);
    uart_puts("  dma: ");
    uart_puts(line);
    snprintf(line, sizeof line, "DMA copy, %u words: %5u us", DMA_WORDS, microseconds(dma_time));
    draw_text(0, 22, line, VGA_LIGHT_GREEN, VGA_BLACK);
    uart_puts(", ");
    uart_puts(line);
    uart_puts("\n");
    draw_text(0, 31, "DMA redraws the picture every frame", VGA_YELLOW, VGA_BLACK);
}

static void dma_step(uint32_t t)
{
    const uint32_t row = (t * (uint32_t)speed()) % DMA_PERIOD;
    dma_copy(&dma_image[(DMA_PERIOD - 1 - row) * ROW_WORDS]);
}

/* ---- 7 scroller -------------------------------------------------------------------- */

static const char *const roller_text[VGA_CONSOLE_ROWS] = {
    "",
    "TIMUR RV32IMC",
    "",
    "a five-stage pipelined RISC-V CPU",
    "at 50 MHz on a MAX 10 FPGA",
    "",
    "RV32I  base integer instructions ",
    "M      multiply and divide       ",
    "C      16-bit compressed code    ",
    "Zicsr  CSRs, traps, interrupts   ",
    "",
    "AHB-Lite bus with two masters",
    "64 KB ROM    64 KB RAM",
    "UART   GPIO   DMA   VGA",
    "",
    "VGA 640x480 at 60 Hz",
    "320x240 pixels, 4 bits each",
    "16 colours out of 4096",
    "",
    "Nothing here is being copied:",
    "the SCROLL register moves the",
    "picture, and the CPU just waits",
    "for the vertical blank.",
    "",
    "SW9 up: hold this scene",
    "SW0-1: speed",
    "",
    "7/7 HARDWARE SCROLLING",
    "",
    "",
};

static uint32_t roller_row;

static void roller_init(void)
{
    vga_clear(VGA_BLACK);
    for (int row = 0; row < VGA_CONSOLE_ROWS; row++) {
        const uint8_t bar = (uint8_t)(1 + row % 14);
        const char *text = roller_text[row];
        int length = 0;
        while (text[length])
            length++;
        vga_fill_rect(0, row * 8, 12, 8, bar);
        vga_fill_rect(VGA_WIDTH - 12, row * 8, 12, 8, bar);
        draw_text((VGA_CONSOLE_COLUMNS - length) / 2 * 8, row * 8, text,
                  row == 1 || row == 27 ? VGA_YELLOW : VGA_WHITE, VGA_BLACK);
    }
    roller_row = 0;
}

static void roller_step(uint32_t t)
{
    (void)t;
    roller_row = (roller_row + (uint32_t)speed()) % VGA_HEIGHT;
    VGA_SCROLL = roller_row; /* the next scene's vga_clear sets it back to 0 */
}

/* ---- main -------------------------------------------------------------------------- */

struct scene {
    const char *name;
    void (*init)(void);
    void (*step)(uint32_t t);
};

static const struct scene scenes[] = {
    { "console", console_init, console_step }, { "plasma", plasma_init, plasma_step },
    { "fractal", fractal_init, fractal_step }, { "cube", cube_init, cube_step },
    { "balls", balls_init, balls_step },       { "dma", dma_init, dma_step },
    { "scroller", roller_init, roller_step },
};
#define SCENE_COUNT ((int)(sizeof scenes / sizeof scenes[0]))

int main(void)
{
    uart_puts("Timur showcase: 7 scenes, SW9 holds, SW0-1 set the speed\n");
    for (int s = FIRST_SCENE % SCENE_COUNT;; s = (s + 1) % SCENE_COUNT) {
        const struct scene *scene = &scenes[s];
        GPIO_OUT = 1u << s;
        uart_puts("scene ");
        uart_puts(scene->name);
        uart_puts("\n");
        reset_palette();
        scene->init();
        for (uint32_t t = 0, shown = 0; shown < FRAMES_PER_SCENE || holding(); t++) {
            vga_wait_vblank();
            scene->step(t);
            if (holding())
                GPIO_OUT = (1u << s) | LED_HOLD;
            else {
                GPIO_OUT = 1u << s;
                shown++;
            }
        }
    }
}
