/* The Phase 12 checklist in one program: the memory layout and globals, the
 * stack, integer arithmetic, the C library, the heap up to exhaustion,
 * system calls through ECALL and the machine-mode CSRs.
 *
 * Every result is computed at run time from values the compiler cannot see
 * (volatile copies, laundered pointers) and compared with a value the
 * compiler computed from the C source, or, where C leaves the result
 * undefined (division by zero, INT32_MIN / -1), with the value the M
 * extension defines. The output is the same for the rv32im_zicsr and
 * rv32imc_zicsr builds; the exit code (LEDs 0x200 | code) is the number of
 * checks that did not match, clipped to 1. */
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "timur.h"

extern char _data_start[], _data_end[], _bss_start[], _bss_end[];
extern char _end[], _heap_end[], _stack_top[];
extern char trap_entry[];

static int checks, mismatches;

static void check(const char *what, int index, uint32_t got, uint32_t expected)
{
    checks++;
    if (got != expected) {
        mismatches++;
        printf("  MISMATCH %s[%d]: got %08lx, expected %08lx\n", what, index,
               (unsigned long)got, (unsigned long)expected);
    }
}

static void check64(const char *what, int index, uint64_t got, uint64_t expected)
{
    check(what, index, (uint32_t)(got >> 32), (uint32_t)(expected >> 32));
    check(what, index, (uint32_t)got, (uint32_t)expected);
}

/* hides where a pointer points, so the compiler must load through it */
static const void *launder(const void *p)
{
    __asm__ ("" : "+r"(p));
    return p;
}

static void report(const char *section, int first_check, int first_mismatch)
{
    int n = checks - first_check, bad = mismatches - first_mismatch;
    if (bad)
        printf("%-11s %d of %d checks differ\n", section, bad, n);
    else
        printf("%-11s %3d checks ok\n", section, n);
}

#define N(a) ((int)(sizeof(a) / sizeof((a)[0])))

/* ---- globals and sections ----------------------------------------------------- */
int bss_small;                                              /* .sbss            */
uint32_t bss_big[40];                                       /* .bss             */
int data_small = 0x12345678;                                /* .sdata           */
int32_t data_big[12] = { -1, 2, -3, 4, -5, 6, -7, 8, -9, 10, -11, 0x7FFFFFFF };
uint8_t data_bytes[7] = { 0x81, 0x02, 0x83, 0x04, 0x85, 0x06, 0x87 };
int16_t data_halves[5] = { -1, 0x7FFF, -32768, 0x1234, -2 };
static const uint32_t rodata_table[16] = {                 /* .rodata, in ROM  */
    0x00000001, 0x00000010, 0x00000100, 0x00001000, 0x00010000, 0x00100000, 0x01000000, 0x10000000,
    0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 0xDEADBEEF, 0xCAFEF00D, 0x0BADC0DE, 0x13579BDF, 0x2468ACE0,
};
static const char rodata_text[] = "read through the ROM's AHB port";
static int ctor_value;

__attribute__((constructor)) static void set_ctor_value(void)
{
    ctor_value = 0xC0DE;
}

static int in_range(const void *p, const char *lo, const char *hi)
{
    return (uintptr_t)p >= (uintptr_t)lo && (uintptr_t)p < (uintptr_t)hi;
}

static void test_globals(void)
{
    int c = checks, m = mismatches;
    const volatile int *bs = launder(&bss_small);
    const uint32_t *bb = launder(bss_big);
    const int32_t *db = launder(data_big);
    const uint8_t *by = launder(data_bytes);
    const int16_t *hw = launder(data_halves);
    const uint32_t *rt = launder(rodata_table);
    uint32_t sum = 0, expected = 0;

    check("bss_small", 0, (uint32_t)*bs, 0);
    for (int i = 0; i < N(bss_big); i++)
        sum |= bb[i];
    check("bss_big", 0, sum, 0);
    check("data_small", 0, (uint32_t)*(const volatile int *)launder(&data_small), 0x12345678);
    sum = 0;
    for (int i = 0; i < N(data_big); i++)
        sum += (uint32_t)db[i] * (uint32_t)(i + 1);
    for (int i = 0; i < N(data_big); i++)
        expected += (uint32_t)data_big[i] * (uint32_t)(i + 1);   /* folded by the compiler */
    check("data_big", 0, sum, expected);
    check("data_bytes", 3, by[3], 0x04);
    check("data_bytes", 6, (uint32_t)(int8_t)by[6], (uint32_t)(int8_t)0x87);
    check("data_halves", 2, (uint32_t)(int32_t)hw[2], (uint32_t)-32768);
    check("data_halves", 3, (uint16_t)hw[3], 0x1234);
    sum = 0;
    for (int i = 0; i < N(rodata_table); i++)
        sum ^= rt[i] + (uint32_t)i;
    expected = 0;
    for (int i = 0; i < N(rodata_table); i++)
        expected ^= rodata_table[i] + (uint32_t)i;
    check("rodata_table", 0, sum, expected);
    check("rodata_text", 0, (uint32_t)strlen(launder(rodata_text)), sizeof rodata_text - 1);
    check("ctor_value", 0, (uint32_t)ctor_value, 0xC0DE);
    check("layout .data", 0, (uint32_t)in_range(&data_small, _data_start, _data_end), 1);
    check("layout .bss", 0, (uint32_t)in_range(bss_big, _bss_start, _bss_end), 1);
    check("layout .rodata", 0, (uintptr_t)rodata_table < TIMUR_ROM_BASE + TIMUR_ROM_SIZE, 1);
    check("layout heap", 0, (uintptr_t)_end == (uintptr_t)_bss_end && (uintptr_t)_end < (uintptr_t)_heap_end, 1);
    report("globals", c, m);
}

/* ---- stack ---------------------------------------------------------------------- */
__attribute__((noinline)) static unsigned fib(unsigned n)
{
    return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

__attribute__((noinline)) static unsigned ackermann(unsigned m, unsigned n)
{
    if (m == 0)
        return n + 1;
    if (n == 0)
        return ackermann(m - 1, 1);
    return ackermann(m - 1, ackermann(m, n - 1));
}

static uintptr_t deepest;

/* each frame keeps 16 words and checks them after the deeper calls return */
__attribute__((noinline)) static int frames(int depth)
{
    volatile uint32_t local[16];
    int intact = 1, deeper = 0;

    for (int i = 0; i < 16; i++)
        local[i] = (uint32_t)depth * 16u + (uint32_t)i;
    if (depth > 1)
        deeper = frames(depth - 1);
    else
        deepest = (uintptr_t)local;
    for (int i = 0; i < 16; i++)
        if (local[i] != (uint32_t)depth * 16u + (uint32_t)i)
            intact = 0;
    return deeper + intact;
}

static int compare_ints(const void *x, const void *y)
{
    int a = *(const int *)x, b = *(const int *)y;
    return (a > b) - (a < b);
}

static void test_stack(void)
{
    int c = checks, m = mismatches;
    volatile unsigned n15 = 15, m2 = 2, n3 = 3;
    int values[32], sorted = 1;
    uint32_t seed = 12345, before = 0, after = 0;

    check("fib(15)", 0, fib(n15), 610);
    check("ackermann(2, 3)", 0, ackermann(m2, n3), 9);
    check("frames(40)", 0, (uint32_t)frames(40), 40);
    check("stack region", 0, deepest > (uintptr_t)_heap_end && deepest < (uintptr_t)_stack_top, 1);
    check("sp alignment", 0, (uintptr_t)__builtin_frame_address(0) & 15u, 0);
    for (int i = 0; i < N(values); i++) {
        seed = seed * 1103515245u + 12345u;
        values[i] = (int)(seed >> 8) - 0x400000;
        before += (uint32_t)values[i];
    }
    qsort(values, N(values), sizeof values[0], compare_ints);
    for (int i = 0; i < N(values); i++) {
        after += (uint32_t)values[i];
        if (i && values[i - 1] > values[i])
            sorted = 0;
    }
    check("qsort order", 0, (uint32_t)sorted, 1);
    check("qsort sum", 0, after, before);
    report("stack", c, m);
}

/* ---- arithmetic ------------------------------------------------------------------ */
#define DIV(a, b) { (a), (b), (a) / (b), (a) % (b) }
static const struct { int32_t a, b, q, r; } sdiv_cases[] = {
    DIV(7, 2), DIV(-7, 2), DIV(7, -2), DIV(-7, -2), DIV(0, 3), DIV(1, 7), DIV(INT32_MAX, 10),
    DIV(INT32_MIN, 10), DIV(INT32_MIN, INT32_MAX), DIV(-1, INT32_MIN), DIV(123456789, -1000),
    /* undefined in C; the M extension defines them */
    { 7, 0, -1, 7 }, { -7, 0, -1, -7 }, { 0, 0, -1, 0 }, { INT32_MIN, -1, INT32_MIN, 0 },
};
static const struct { uint32_t a, b, q, r; } udiv_cases[] = {
    DIV(7u, 2u), DIV(0xFFFFFFFFu, 2u), DIV(0x80000000u, 0xFFFFFFFFu), DIV(0xFFFFFFFFu, 0xFFFFFFFFu),
    DIV(3000000000u, 7u), DIV(5u, 0x80000000u),
    { 7u, 0u, 0xFFFFFFFFu, 7u }, { 0xFFFFFFFFu, 0u, 0xFFFFFFFFu, 0xFFFFFFFFu },
};

#define MUL(a, b) { (a), (b), (uint32_t)((a) * (b)),                                    \
                    (uint32_t)(((int64_t)(int32_t)(a) * (int32_t)(b)) >> 32),           \
                    (uint32_t)(((uint64_t)(a) * (b)) >> 32),                            \
                    (uint32_t)(((int64_t)(int32_t)(a) * (int64_t)(b)) >> 32) }
static const struct { uint32_t a, b, lo, h, hu, hsu; } mul_cases[] = {
    MUL(0u, 0u), MUL(7u, 6u), MUL(0xFFFFFFFFu, 0xFFFFFFFFu), MUL(0x80000000u, 0x80000000u),
    MUL(0x80000000u, 0xFFFFFFFFu), MUL(0x7FFFFFFFu, 0x7FFFFFFFu), MUL(0x12345678u, 0x9ABCDEF0u),
    MUL(0xFFFFFFFEu, 3u), MUL(0x00010000u, 0x00010000u),
};

static const struct { int64_t a, b, q, r; } sdiv64_cases[] = {
    DIV(-1000000000000LL, 7LL), DIV(INT64_MAX, -3LL), DIV(123456789012345LL, 1000003LL),
    DIV(-5LL, 1000000000000LL),
};
static const struct { uint64_t a, b, q, r; } udiv64_cases[] = {
    DIV(0xFFFFFFFFFFFFFFFFull, 10ull), DIV(0x8000000000000000ull, 3ull), DIV(1000000007ull, 0x100000000ull),
};

#define SHIFT(n) { (n), (uint32_t)(-0x12345678 >> (n)), 0x87654321u >> (n), 0x87654321u << (n) }
static const struct { uint32_t n, sra, srl, sll; } shift_cases[] = {
    SHIFT(0), SHIFT(1), SHIFT(4), SHIFT(16), SHIFT(31),
};
#define SHIFT64(n) { (n), (uint64_t)(-0x123456789ABCDEFLL >> (n)), 0x8123456789ABCDEFull >> (n), \
                     0x8123456789ABCDEFull << (n) }
static const struct { uint32_t n; uint64_t sra, srl, sll; } shift64_cases[] = {
    SHIFT64(0), SHIFT64(1), SHIFT64(31), SHIFT64(32), SHIFT64(33), SHIFT64(63),
};

#define CMP(a, b) { (a), (b), (int32_t)(a) < (int32_t)(b), (a) < (b) }
static const struct { uint32_t a, b, lt, ltu; } cmp_cases[] = {
    CMP(0u, 1u), CMP(0xFFFFFFFFu, 0u), CMP(0x80000000u, 0x7FFFFFFFu), CMP(5u, 5u), CMP(0x7FFFFFFFu, 0x80000000u),
};

static void test_arithmetic(void)
{
    int c = checks, m = mismatches;

    for (int i = 0; i < N(sdiv_cases); i++) {
        volatile int32_t a = sdiv_cases[i].a, b = sdiv_cases[i].b;
        check("div", i, (uint32_t)(a / b), (uint32_t)sdiv_cases[i].q);
        check("rem", i, (uint32_t)(a % b), (uint32_t)sdiv_cases[i].r);
    }
    for (int i = 0; i < N(udiv_cases); i++) {
        volatile uint32_t a = udiv_cases[i].a, b = udiv_cases[i].b;
        check("divu", i, a / b, udiv_cases[i].q);
        check("remu", i, a % b, udiv_cases[i].r);
    }
    for (int i = 0; i < N(mul_cases); i++) {
        volatile uint32_t a = mul_cases[i].a, b = mul_cases[i].b;
        uint32_t x = a, y = b;
        check("mul", i, x * y, mul_cases[i].lo);
        check("mulh", i, (uint32_t)(((int64_t)(int32_t)x * (int32_t)y) >> 32), mul_cases[i].h);
        check("mulhu", i, (uint32_t)(((uint64_t)x * y) >> 32), mul_cases[i].hu);
        check("mulhsu", i, (uint32_t)(((int64_t)(int32_t)x * (int64_t)(uint64_t)y) >> 32), mul_cases[i].hsu);
    }
    for (int i = 0; i < N(sdiv64_cases); i++) {
        volatile int64_t a = sdiv64_cases[i].a, b = sdiv64_cases[i].b;
        check64("div64", i, (uint64_t)(a / b), (uint64_t)sdiv64_cases[i].q);
        check64("rem64", i, (uint64_t)(a % b), (uint64_t)sdiv64_cases[i].r);
        check64("mul64", i, (uint64_t)a * (uint64_t)b,
                (uint64_t)sdiv64_cases[i].a * (uint64_t)sdiv64_cases[i].b);
    }
    for (int i = 0; i < N(udiv64_cases); i++) {
        volatile uint64_t a = udiv64_cases[i].a, b = udiv64_cases[i].b;
        check64("divu64", i, a / b, udiv64_cases[i].q);
        check64("remu64", i, a % b, udiv64_cases[i].r);
    }
    for (int i = 0; i < N(shift_cases); i++) {
        volatile uint32_t n = shift_cases[i].n;
        volatile int32_t neg = -0x12345678;
        volatile uint32_t pattern = 0x87654321u;
        check("sra", i, (uint32_t)(neg >> n), shift_cases[i].sra);
        check("srl", i, pattern >> n, shift_cases[i].srl);
        check("sll", i, pattern << n, shift_cases[i].sll);
    }
    for (int i = 0; i < N(shift64_cases); i++) {
        volatile uint32_t n = shift64_cases[i].n;
        volatile int64_t neg = -0x123456789ABCDEFLL;
        volatile uint64_t pattern = 0x8123456789ABCDEFull;
        check64("sra64", i, (uint64_t)(neg >> n), shift64_cases[i].sra);
        check64("srl64", i, pattern >> n, shift64_cases[i].srl);
        check64("sll64", i, pattern << n, shift64_cases[i].sll);
    }
    for (int i = 0; i < N(cmp_cases); i++) {
        volatile uint32_t a = cmp_cases[i].a, b = cmp_cases[i].b;
        check("slt", i, (int32_t)a < (int32_t)b, cmp_cases[i].lt);
        check("sltu", i, a < b, cmp_cases[i].ltu);
    }
    report("arithmetic", c, m);

    volatile int seven = 7, minus_two = -2, zero = 0, minus_one = -1;
    volatile int int_min = INT_MIN;
    volatile uint32_t all_ones = 0xFFFFFFFFu;
    uint32_t w = all_ones;
    printf("  7 / -2 = %d, 7 %% -2 = %d, -7 / 2 = %d, -7 %% 2 = %d\n",
           seven / minus_two, seven % minus_two, -seven / -minus_two, -seven % -minus_two);
    printf("  7 / 0 = %d, 7 %% 0 = %d, INT_MIN / -1 = %d, INT_MIN %% -1 = %d\n",
           seven / zero, seven % zero, int_min / minus_one, int_min % minus_one);
    printf("  FFFFFFFF x FFFFFFFF: mul %08lx, mulhu %08lx, mulh %08lx, mulhsu %08lx\n",
           (unsigned long)(w * w), (unsigned long)(((uint64_t)w * w) >> 32),
           (unsigned long)(uint32_t)(((int64_t)(int32_t)w * (int32_t)w) >> 32),
           (unsigned long)(uint32_t)(((int64_t)(int32_t)w * (int64_t)(uint64_t)w) >> 32));
}

/* ---- C library ------------------------------------------------------------------- */
static void test_library(void)
{
    int c = checks, m = mismatches;
    char buf[96], word[16];
    const char *expected = "-42|   42|42   |-0042|3000000000|beef|BEEF|00001234|T|str|%|-2147483648";
    volatile int v42 = 42;
    int d = 0, i = 0, o = 0, n;
    uint8_t bytes[24];

    n = snprintf(buf, sizeof buf, "%d|%5d|%-5d|%05d|%u|%x|%X|%08lx|%c|%s|%%|%ld", -v42, v42, v42, -v42,
                 3000000000u, 0xbeefu, 0xbeefu, 0x1234ul, 'T', "str", (long)LONG_MIN);
    check("snprintf", 0, (uint32_t)strcmp(buf, expected), 0);
    check("snprintf length", 0, (uint32_t)n, (uint32_t)strlen(expected));
    printf("  snprintf: \"%s\"\n", buf);
    check("snprintf truncation", 0, (uint32_t)snprintf(buf, 5, "%s", (const char *)launder("truncated")), 9);
    check("snprintf truncation", 1, (uint32_t)strcmp(buf, "trun"), 0);
    check("sscanf", 0, (uint32_t)sscanf("  -123 0x7f 077 word", "%d %i %o %15s", &d, &i, &o, word), 4);
    check("sscanf", 1, (uint32_t)d, (uint32_t)-123);
    check("sscanf", 2, (uint32_t)i, 127);
    check("sscanf", 3, (uint32_t)o, 63);
    check("sscanf", 4, (uint32_t)strcmp(word, "word"), 0);
    check("strtol", 0, (uint32_t)strtol("-0x1F", NULL, 16), (uint32_t)-31);
    check("strtoul", 0, (uint32_t)strtoul("4294967295", NULL, 10), 0xFFFFFFFFu);
    check("atoi", 0, (uint32_t)atoi("  42xyz"), 42);

    for (int k = 0; k < N(bytes); k++)
        bytes[k] = (uint8_t)(k * 7 + 1);
    memcpy(bytes + 1, launder("ABCDEFGHIJ"), 10);            /* unaligned destination */
    check("memcpy", 0, (uint32_t)memcmp(bytes, "\x01" "ABCDEFGHIJ", 11), 0);
    memmove(bytes + 3, bytes + 1, 10);                          /* overlapping */
    check("memmove", 0, (uint32_t)memcmp(bytes, "\x01" "ABABCDEFGHIJ", 13), 0);
    memset(bytes + 5, 0xEE, 7);
    check("memset", 0, (uint32_t)(bytes[4] == 'B' && bytes[5] == 0xEE && bytes[11] == 0xEE && bytes[12] == 'J'), 1);
    check("strchr", 0, (uint32_t)(strchr(rodata_text, 'R') - rodata_text), 17);
    check("strrchr", 0, (uint32_t)(strrchr(rodata_text, 't') - rodata_text), 30);
    check("strstr", 0, (uint32_t)(strstr(rodata_text, "AHB") - rodata_text), 23);
    check("strcmp", 0, (uint32_t)(strcmp("abc", "abd") < 0 && strcmp("b", "a") > 0), 1);
    report("C library", c, m);
}

/* ---- heap -------------------------------------------------------------------------- */
enum { BLOCK = 1024, MAX_BLOCKS = 80 };

static void test_heap(void)
{
    int c = checks, m = mismatches;
    volatile uint32_t canary[16];
    static void *blocks[MAX_BLOCKS];
    int n = 0, intact = 1, zero = 1, kept = 1;
    char *p;
    int *q;

    for (int i = 0; i < 16; i++)
        canary[i] = 0xC0FFEE00u + (uint32_t)i;

    p = malloc(100);
    q = calloc(64, sizeof *q);
    check("malloc", 0, p != NULL && q != NULL, 1);
    for (int i = 0; i < 100; i++)
        p[i] = (char)i;
    for (int i = 0; i < 64; i++)
        zero &= q[i] == 0;
    check("calloc zeroed", 0, (uint32_t)zero, 1);
    p = realloc(p, 1000);
    for (int i = 0; i < 100; i++)
        kept &= p[i] == (char)i;
    check("realloc kept", 0, (uint32_t)kept, 1);
    free(p);
    free(q);
    check("malloc(128 KB)", 0, malloc(128 * 1024) == NULL, 1);

    /* one word every 64 bytes and the last word mark each block: enough to see
       two blocks overlap, and quick to simulate */
    while (n < MAX_BLOCKS && (blocks[n] = malloc(BLOCK)) != NULL) {
        uint32_t *w = blocks[n];
        for (int i = 0; i < BLOCK / 4; i += 16)
            w[i] = 0xB10C0000u + (uint32_t)n;
        w[BLOCK / 4 - 1] = 0xB10C0000u + (uint32_t)n;
        n++;
    }
    for (int b = 0; b < n; b++) {
        const uint32_t *w = blocks[b];
        for (int i = 0; i < BLOCK / 4; i += 16)
            intact &= w[i] == 0xB10C0000u + (uint32_t)b;
        intact &= w[BLOCK / 4 - 1] == 0xB10C0000u + (uint32_t)b;
    }
    check("heap exhausted", 0, n > 30 && n < MAX_BLOCKS, 1);
    check("blocks intact", 0, (uint32_t)intact, 1);
    check("below the stack", 0, (uintptr_t)blocks[n - 1] + BLOCK <= (uintptr_t)_heap_end, 1);
    for (int i = 0; i < 16; i++)
        intact &= canary[i] == 0xC0FFEE00u + (uint32_t)i;
    check("stack canary", 0, (uint32_t)intact, 1);
    check("errno", 0, (uint32_t)errno, ENOMEM);
    for (int b = 0; b < n; b++)
        free(blocks[b]);
    p = malloc(32 * 1024);
    check("malloc after free", 0, p != NULL, 1);
    free(p);
    report("heap", c, m);
    printf("  %d blocks of 1 KB before malloc returned NULL; the stack was untouched\n", n);
}

/* ---- system calls through ECALL ------------------------------------------------------ */
/* every caller-saved register except a0 survives an ECALL: returns 0 */
static uint32_t ecall_clobbers(uint32_t *result)
{
    uint32_t bad, a0;
    __asm__ volatile (
        "li t0, 0x100\n li t1, 0x101\n li t2, 0x102\n li t3, 0x103\n li t4, 0x104\n"
        "li t5, 0x105\n li t6, 0x106\n li a1, 0x201\n li a2, 0x202\n li a3, 0x203\n"
        "li a4, 0x204\n li a5, 0x205\n li a6, 0x206\n li a7, 1234\n li ra, 0x301\n"
        "ecall\n"
        "mv %1, a0\n"
        "xori t0, t0, 0x100\n mv %0, t0\n"
        "xori t1, t1, 0x101\n or %0, %0, t1\n xori t2, t2, 0x102\n or %0, %0, t2\n"
        "xori t3, t3, 0x103\n or %0, %0, t3\n xori t4, t4, 0x104\n or %0, %0, t4\n"
        "xori t5, t5, 0x105\n or %0, %0, t5\n xori t6, t6, 0x106\n or %0, %0, t6\n"
        "xori a1, a1, 0x201\n or %0, %0, a1\n xori a2, a2, 0x202\n or %0, %0, a2\n"
        "xori a3, a3, 0x203\n or %0, %0, a3\n xori a4, a4, 0x204\n or %0, %0, a4\n"
        "xori a5, a5, 0x205\n or %0, %0, a5\n xori a6, a6, 0x206\n or %0, %0, a6\n"
        "addi a7, a7, -1234\n or %0, %0, a7\n xori ra, ra, 0x301\n or %0, %0, ra\n"
        : "=&r"(bad), "=&r"(a0)
        :
        : "ra", "t0", "t1", "t2", "t3", "t4", "t5", "t6",
          "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "memory");
    *result = a0;
    return bad;
}

static void test_ecall(void)
{
    int c = checks, m = mismatches;
    static const char msg[] = "  written by the ECALL write system call\n";
    uint32_t result = 0;

    check("ecall write", 0, (uint32_t)timur_ecall(SYS_write, 1, (long)msg, sizeof msg - 1), sizeof msg - 1);
    check("ecall write fd 5", 0, (uint32_t)timur_ecall(SYS_write, 5, (long)msg, 3), (uint32_t)-EBADF);
    check("ecall 1234", 0, (uint32_t)timur_ecall(1234, 0, 0, 0), (uint32_t)-ENOSYS);
    check("ecall registers", 0, ecall_clobbers(&result), 0);
    check("ecall registers", 1, result, (uint32_t)-ENOSYS);
    report("ecall", c, m);
}

/* ---- CSRs ------------------------------------------------------------------------------ */
static void test_csr(void)
{
    int c = checks, m = mismatches;

    check("misa", 0, csr_read(misa), MISA_VALUE);
    check("mhartid", 0, csr_read(mhartid), 0);
    check("mstatus.MPP", 0, csr_read(mstatus) & (3u << 11), 3u << 11);
    check("mtvec", 0, csr_read(mtvec), (uint32_t)(uintptr_t)trap_entry);
    csr_write(mscratch, 0xA5A55A5Au);
    check("mscratch", 0, csr_read(mscratch), 0xA5A55A5Au);
    csr_set(mstatus, MSTATUS_MIE);                 /* mie.MEIE = 0: nothing can interrupt */
    check("mstatus.MIE", 0, csr_read(mstatus) & MSTATUS_MIE, MSTATUS_MIE);
    csr_clear(mstatus, MSTATUS_MIE);
    check("mstatus.MIE", 1, csr_read(mstatus) & MSTATUS_MIE, 0);
    report("CSRs", c, m);
}

int main(void)
{
    printf("Timur C runtime self-test\n");
    test_globals();
    test_stack();
    test_arithmetic();
    test_library();
    test_heap();
    test_ecall();
    test_csr();
    if (mismatches)
        printf("%d of %d checks differ\n", mismatches, checks);
    else
        printf("all %d checks passed\n", checks);
    return mismatches ? 1 : 0;
}
