/* Timur RV32IMC startup code and trap entry.
 *
 * _start, at the reset address 0 (linker.ld places .text.start first):
 *   1. gp <- __global_pointer$ (with linker relaxation off for that one
 *      instruction, or it would become gp-relative to itself)
 *   2. sp <- _stack_top
 *   3. mtvec <- trap_entry (4-byte aligned; direct mode)
 *   4. copy .data from its load address in ROM to RAM, one word at a time
 *   5. clear .bss
 *   6. run the constructors in .init_array
 *   7. main(0, 0), then exit(result): exit flushes stdio and ends in _exit
 * Only t0-t3 and s0-s1 are used before main; s0-s1 keep the constructor loop
 * state across the calls, as the calling convention guarantees.
 *
 * trap_entry saves the caller-saved registers (struct trap_frame in timur.h,
 * offsets in timur_defs.h), calls timur_trap(frame) and restores them before
 * MRET. timur_trap is C code, so it preserves s0-s11 itself; a system call's
 * result goes into the saved a0, which the restore below then loads. The frame
 * lives on the interrupted stack, so a trap needs TRAP_FRAME_SIZE bytes of
 * stack plus what the C handlers use. */

#include "timur_defs.h"

    .section .text.start, "ax", @progbits
    .globl  _start
    .type   _start, @function
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    la      sp, _stack_top
    la      t0, trap_entry
    csrw    mtvec, t0

    la      t0, _data_load              # 4. .data: ROM -> RAM
    la      t1, _data_start
    la      t2, _data_end
    j       2f
1:  lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
2:  bltu    t1, t2, 1b

    la      t0, _bss_start              # 5. clear .bss
    la      t1, _bss_end
    j       4f
3:  sw      zero, 0(t0)
    addi    t0, t0, 4
4:  bltu    t0, t1, 3b

    la      s0, __init_array_start      # 6. constructors
    la      s1, __init_array_end
    j       6f
5:  lw      t0, 0(s0)
    jalr    t0
    addi    s0, s0, 4
6:  bltu    s0, s1, 5b

    li      a0, 0                       # 7. argc = 0, argv = NULL
    li      a1, 0
    call    main
    call    exit                        # does not return
    .size   _start, . - _start

/* _exit (syscalls.c) ends here: the jump-to-self that testbenches and the
 * reference model treat as the end of a program. */
    .text
    .globl  _halt
    .type   _halt, @function
_halt:
    j       _halt
    .size   _halt, . - _halt

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
