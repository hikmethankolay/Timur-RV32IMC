/* Timur RV32IMC startup code: the reset entry _start and the end of a program, _halt.
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
 * The trap entry is in trap_entry.S. */

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
    call    exit                        # does not return; if it did:
    j       _halt
    .size   _start, . - _start

/* _exit (syscalls.c) ends here: the jump-to-self that testbenches and the
 * reference model treat as the end of a program. */
    .text
    .globl  _halt
    .type   _halt, @function
_halt:
    j       _halt
    .size   _halt, . - _halt
