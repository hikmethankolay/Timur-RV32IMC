/* Exceptions handled by the program. The runtime passes every exception
 * other than ECALL to exception_handler; this one records mcause, mepc and
 * mtval and resumes after the faulting instruction, whose length it reads
 * from the instruction itself (a 16-bit instruction has bits [1:0] != 11).
 * Each faulting instruction is its own small function, so its address is the
 * expected mepc. Finally the handler declines an exception and the runtime
 * reports it (timur_fatal) and stops with the LEDs showing 0x302.
 * The output up to that report is the same for both builds; the report
 * shows mepc, a code address. */
#include <stdio.h>
#include "timur.h"

void fault_csr(void *base);         /* csrrw to the read-only cycle CSR (unimp) */
void fault_custom(void *base);      /* a custom-0 opcode                        */
void fault_c_unimp(void *base);     /* 16-bit 0x0000                            */
void fault_ebreak(void *base);
void fault_c_ebreak(void *base);
void fault_lw(void *base);          /* lw  from base + 1                        */
void fault_lh(void *base);          /* lh  from base + 3                        */
void fault_lhu(void *base);         /* lhu from base + 1                        */
void fault_sw(void *base);          /* sw  to   base + 2                        */
void fault_sh(void *base);          /* sh  to   base + 1                        */

__asm__(
    "    .text\n"
    "    .globl fault_csr\n"
    "fault_csr:      .4byte 0xC0001073\n    ret\n"
    "    .globl fault_custom\n"
    "fault_custom:   .4byte 0x0000000B\n    ret\n"
    "    .globl fault_c_unimp\n"
    "fault_c_unimp:  .2byte 0x0000\n    ret\n"
    "    .globl fault_ebreak\n"
    "fault_ebreak:   .4byte 0x00100073\n    ret\n"
    "    .globl fault_c_ebreak\n"
    "fault_c_ebreak: .2byte 0x9002\n    ret\n"
    "    .globl fault_lw\n"
    "fault_lw:       lw  t0, 1(a0)\n    ret\n"
    "    .globl fault_lh\n"
    "fault_lh:       lh  t0, 3(a0)\n    ret\n"
    "    .globl fault_lhu\n"
    "fault_lhu:      lhu t0, 1(a0)\n    ret\n"
    "    .globl fault_sw\n"
    "fault_sw:       sw  a0, 2(a0)\n    ret\n"
    "    .globl fault_sh\n"
    "fault_sh:       sh  a0, 1(a0)\n    ret\n");

static volatile int handle = 1;
static volatile uint32_t seen_cause, seen_epc, seen_tval, seen_count;
static uint32_t buffer[4];

int exception_handler(struct trap_frame *frame, uint32_t mcause, uint32_t *mepc, uint32_t mtval)
{
    uint16_t first = *(const volatile uint16_t *)(uintptr_t)*mepc;   /* through the ROM's data port */

    (void)frame;
    if (!handle)
        return 0;
    seen_cause = mcause;
    seen_epc = *mepc;
    seen_tval = mtval;
    seen_count++;
    *mepc += (first & 3u) == 3u ? 4u : 2u;
    return 1;
}

static const struct {
    const char *what;
    void (*fault)(void *);
    uint32_t cause;
    int tval;                       /* -1: mtval = mepc, otherwise buffer + tval, or 0 */
    int length;
} faults[] = {
    { "csrrw to the read-only cycle CSR", fault_csr,      CAUSE_ILLEGAL_INSTRUCTION,  0, 4 },
    { "custom-0 opcode                 ", fault_custom,   CAUSE_ILLEGAL_INSTRUCTION,  0, 4 },
    { "16-bit 0x0000                   ", fault_c_unimp,  CAUSE_ILLEGAL_INSTRUCTION,  0, 2 },
    { "ebreak                          ", fault_ebreak,   CAUSE_BREAKPOINT,          -1, 4 },
    { "c.ebreak                        ", fault_c_ebreak, CAUSE_BREAKPOINT,          -1, 2 },
    { "lw  from buffer + 1             ", fault_lw,       CAUSE_LOAD_MISALIGNED,      1, 4 },
    { "lh  from buffer + 3             ", fault_lh,       CAUSE_LOAD_MISALIGNED,      3, 4 },
    { "lhu from buffer + 1             ", fault_lhu,      CAUSE_LOAD_MISALIGNED,      1, 4 },
    { "sw  to   buffer + 2             ", fault_sw,       CAUSE_STORE_MISALIGNED,     2, 4 },
    { "sh  to   buffer + 1             ", fault_sh,       CAUSE_STORE_MISALIGNED,     1, 4 },
};

int main(void)
{
    int differ = 0;

    printf("Exceptions handled by the program\n");
    for (unsigned i = 0; i < sizeof faults / sizeof faults[0]; i++) {
        uint32_t epc = (uint32_t)(uintptr_t)faults[i].fault;
        uint32_t tval = faults[i].tval < 0 ? epc
                      : faults[i].tval ? (uint32_t)(uintptr_t)buffer + (uint32_t)faults[i].tval : 0;
        uint32_t count = seen_count;
        int ok;

        buffer[0] = buffer[1] = 0x5A5A5A5Au;
        faults[i].fault(buffer);
        ok = seen_count == count + 1 && seen_cause == faults[i].cause && seen_epc == epc && seen_tval == tval
             && buffer[0] == 0x5A5A5A5Au && buffer[1] == 0x5A5A5A5Au;   /* a trapped store writes nothing */
        differ |= !ok;
        printf("  %s mcause %lu, %s, %d-byte instruction: %s\n", faults[i].what, (unsigned long)seen_cause,
               faults[i].tval < 0 ? "mtval = mepc" : faults[i].tval ? "mtval = address" : "mtval = 0",
               faults[i].length, ok ? "ok" : "DIFFERS");
    }
    printf("%lu exceptions handled%s; an ECALL still reaches the system calls: ", (unsigned long)seen_count,
           differ ? " (some differ)" : "");
    fflush(stdout);
    timur_ecall(SYS_write, 1, (long)"yes\n", 4);

    printf("now an exception the program does not handle:\n");
    fflush(stdout);
    handle = 0;
    fault_csr(buffer);
    printf("not reached\n");
    return 0;
}
