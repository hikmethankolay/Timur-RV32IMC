/* Timur RV32IMC startup code and trap entry (Phase 12).
 *
 * _start, at the reset address 0:
 *   1. gp <- __global_pointer$ (with linker relaxation off for that one
 *      instruction, or it would become gp-relative to itself)
 *   2. sp <- _stack_top
 *   3. mtvec <- trap_entry (4-byte aligned; direct mode)
 *   4. copy .data from its load address in ROM to RAM, one word at a time
 *   5. clear .bss
 *   6. run the constructors in .init_array
 *   7. main(0, 0), then exit(result): exit flushes stdio and ends in _exit
 *
 * trap_entry saves the caller-saved registers (struct trap_frame in timur.h),
 * calls timur_trap(frame) and restores them before MRET. timur_trap is C code,
 * so it preserves s0-s11 itself; a system call's result goes into the saved
 * a0, which the restore below then loads. */

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
    .align  2
    .globl  trap_entry
    .type   trap_entry, @function
trap_entry:
    addi    sp, sp, -64
    sw      ra,  0(sp)
    sw      t0,  4(sp)
    sw      t1,  8(sp)
    sw      t2, 12(sp)
    sw      a0, 16(sp)
    sw      a1, 20(sp)
    sw      a2, 24(sp)
    sw      a3, 28(sp)
    sw      a4, 32(sp)
    sw      a5, 36(sp)
    sw      a6, 40(sp)
    sw      a7, 44(sp)
    sw      t3, 48(sp)
    sw      t4, 52(sp)
    sw      t5, 56(sp)
    sw      t6, 60(sp)
    mv      a0, sp
    call    timur_trap
    lw      ra,  0(sp)
    lw      t0,  4(sp)
    lw      t1,  8(sp)
    lw      t2, 12(sp)
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    lw      a3, 28(sp)
    lw      a4, 32(sp)
    lw      a5, 36(sp)
    lw      a6, 40(sp)
    lw      a7, 44(sp)
    lw      t3, 48(sp)
    lw      t4, 52(sp)
    lw      t5, 56(sp)
    lw      t6, 60(sp)
    addi    sp, sp, 64
    mret
    .size   trap_entry, . - trap_entry
