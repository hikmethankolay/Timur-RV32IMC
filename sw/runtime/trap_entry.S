/* Timur RV32IMC trap entry: every trap (mtvec, direct mode) comes here.
 *
 * trap_entry saves the caller-saved registers in a struct trap_frame (timur.h;
 * offsets in timur_defs.h) on the interrupted stack, calls timur_trap(frame)
 * (trap.c) and restores them before MRET. timur_trap is C code, so it
 * preserves s0-s11 and sp itself; a system call's result goes into the saved
 * a0, which the restore then loads, and a handler that sets mepc chooses where
 * MRET resumes.
 *
 * Constraints:
 *   - traps do not nest: the hardware clears mstatus.MIE on entry and nothing
 *     sets it again before MRET, so mepc, mcause and mtval need no saving;
 *   - the frame lives on the interrupted stack: a trap needs TRAP_FRAME_SIZE
 *     bytes of it plus what the C handlers use, and sp must be valid, which
 *     it is from the second instruction of _start on;
 *   - TRAP_FRAME_SIZE is a multiple of 16, so the C code gets an aligned sp. */

#include "timur_defs.h"

    .text
    .align  2                           # mtvec ignores bits [1:0]
    .globl  trap_entry
    .type   trap_entry, @function
trap_entry:
    addi    sp, sp, -TRAP_FRAME_SIZE
    sw      ra, TRAP_FRAME_RA(sp)
    sw      t0, TRAP_FRAME_T0(sp)
    sw      t1, TRAP_FRAME_T1(sp)
    sw      t2, TRAP_FRAME_T2(sp)
    sw      a0, TRAP_FRAME_A0(sp)
    sw      a1, TRAP_FRAME_A1(sp)
    sw      a2, TRAP_FRAME_A2(sp)
    sw      a3, TRAP_FRAME_A3(sp)
    sw      a4, TRAP_FRAME_A4(sp)
    sw      a5, TRAP_FRAME_A5(sp)
    sw      a6, TRAP_FRAME_A6(sp)
    sw      a7, TRAP_FRAME_A7(sp)
    sw      t3, TRAP_FRAME_T3(sp)
    sw      t4, TRAP_FRAME_T4(sp)
    sw      t5, TRAP_FRAME_T5(sp)
    sw      t6, TRAP_FRAME_T6(sp)
    mv      a0, sp                      # timur_trap(struct trap_frame *frame)
    call    timur_trap
    lw      ra, TRAP_FRAME_RA(sp)
    lw      t0, TRAP_FRAME_T0(sp)
    lw      t1, TRAP_FRAME_T1(sp)
    lw      t2, TRAP_FRAME_T2(sp)
    lw      a0, TRAP_FRAME_A0(sp)
    lw      a1, TRAP_FRAME_A1(sp)
    lw      a2, TRAP_FRAME_A2(sp)
    lw      a3, TRAP_FRAME_A3(sp)
    lw      a4, TRAP_FRAME_A4(sp)
    lw      a5, TRAP_FRAME_A5(sp)
    lw      a6, TRAP_FRAME_A6(sp)
    lw      a7, TRAP_FRAME_A7(sp)
    lw      t3, TRAP_FRAME_T3(sp)
    lw      t4, TRAP_FRAME_T4(sp)
    lw      t5, TRAP_FRAME_T5(sp)
    lw      t6, TRAP_FRAME_T6(sp)
    addi    sp, sp, TRAP_FRAME_SIZE
    mret
    .size   trap_entry, . - trap_entry
