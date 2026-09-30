# Timur RV32IMC directed test program. Assembled by the mini assembler
# (sw/timur_tools/asm.py: x-register names, absolute labels, .org, .word); the
# image, the expected end state from the reference model and the RTL run are
# produced by sw/gen_soc_tests.py for tb/timur_soc_tb.v. Bare-metal from the
# reset address 0: no stack and no calling convention; `halt` is the
# jump-to-self that ends the run.
#
# Phase 5 test program (no loads)
        addi  x1, x0, 5
        addi  x2, x0, 3
        add   x3, x1, x2
        sub   x4, x1, x2
        and   x5, x1, x2
        or    x6, x1, x2
        lui   x10, 0x20000
        sw    x3, 0(x10)
        beq   x1, x1, t2c
        lui   x7, 0xDEADC          # skipped
        lui   x7, 0xDEADC          # skipped
t2c:    addi  x7, x0, 1
        lui   x8, 0x12345          # LUI fix
        auipc x9, 0x1
        addi  x11, x0, -5          # decoder fix: ADD, not SUB
        addi  x12, x0, 40          # decoder fix: ADD, not MUL
        jal   x13, t48
        addi  x14, x0, 1           # skipped
t48:    jal   x0, t48              # halt
