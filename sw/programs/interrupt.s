# Timur RV32IMC directed test program. Assembled by the mini assembler
# (sw/timur_tools/asm.py: x-register names, absolute labels, .org, .word); the
# image, the expected end state from the reference model and the RTL run are
# produced by sw/gen_soc_tests.py for tb/timur_soc_tb.v. Bare-metal from the
# reset address 0: no stack and no calling convention; `halt` is the
# jump-to-self that ends the run.
#
# Phase 10: the DMAC's done interrupt. The DMA finishes while a chain of DIVs
# occupies EX; the interrupt waits until no DIV is in EX, then enters the
# handler exactly once.
        lui   x31, 0x20000         # RAM base
        lui   x30, 0x40000         # APB base
        addi  x29, x30, 0x200      # DMAC registers
        addi  x1, x0, handler
        csrrw x0, mtvec, x1
        addi  x1, x0, 1
        slli  x1, x1, 11
        csrrs x0, mie, x1          # MEIE = 1
        csrrsi x0, mstatus, 8      # MIE = 1
        lui   x2, 0x1
        sw    x2, 0(x29)           # SRC = 0x1000 (ROM)
        addi  x3, x31, 0x100
        sw    x3, 4(x29)           # DST = 0x2000_0100
        addi  x4, x0, 4
        sw    x4, 8(x29)           # LEN = 4 words
        addi  x5, x0, 3
        sw    x5, 12(x29)          # CTRL: start, irq_enable
        lui   x6, 0x12345
        addi  x7, x0, 7
        div   x8, x6, x7           # the DMA finishes during this chain
        div   x9, x8, x7
        div   x10, x9, x7
        div   x11, x10, x7
wait:   beq   x20, x0, wait        # the handler sets x20
        addi  x21, x0, 1
halt:   jal   x0, halt
        .org 0x300
handler:
        csrrs x22, mcause, x0      # 8000000B
        csrrs x23, mip, x0         # 800: MEIP
        sw    x0, 12(x29)          # a CTRL write clears done: the interrupt line drops
        lw    x24, 16(x29)         # STATUS: 0
        add   x24, x24, x0
        csrrs x25, mip, x0         # 0
        addi  x20, x0, 1
        addi  x26, x26, 1          # interrupts taken: exactly one
        mret
        .org 0x1000
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444
