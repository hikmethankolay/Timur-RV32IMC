# Timur RV32IMC directed test program. Assembled by the mini assembler
# (sw/timur_tools/asm.py: x-register names, absolute labels, .org, .word); the
# image, the expected end state from the reference model and the RTL run are
# produced by sw/gen_soc_tests.py for tb/timur_soc_tb.v. Bare-metal from the
# reset address 0: no stack and no calling convention; `halt` is the
# jump-to-self that ends the run.
#
# Final cross-phase verification program
        lui   x20, 0x20000         # RAM base
        lui   x21, 0x40000         # APB base
        addi  x1, x0, 10
        addi  x2, x0, 1
        sw    x1, 0(x20)           # AHB write to RAM
        lw    x3, 0(x20)           # store -> load of the same word: RAM bypass
        add   x4, x3, x2           # load-use bubble + WB forwarding -> 11
        mul   x5, x1, x2           # multiply, one EX stall -> 10
        div   x6, x1, x2           # divider EX stall -> 10
        bne   x5, x6, skip         # not taken (forwarding from EX/MEM)
        addi  x7, x0, 42           # must execute
skip:   sw    x7, 0x100(x21)       # GPIO_OUT: LEDs show 42
        addi  x10, x0, 0x55
        sw    x10, 0(x21)          # UART: 'U'
        addi  x11, x21, 0x200      # DMAC register base
        lui   x12, 0x1             # 0x1000: data table in ROM
        sw    x12, 0(x11)          # DMAC_SRC
        addi  x13, x20, 0x100
        sw    x13, 4(x11)          # DMAC_DST = 0x2000_0100
        addi  x14, x0, 4
        sw    x14, 8(x11)          # DMAC_LEN = 4 words
        addi  x15, x0, 1
        sw    x15, 12(x11)         # DMAC_CTRL: start
poll:   lw    x16, 16(x11)         # DMAC_STATUS (APB wait states)
        andi  x16, x16, 1          # busy bit
        bne   x16, x0, poll
        csrrs x17, cycle, x0       # read-only CSR read, no trap
        addi  x18, x0, 0x100       # handler address
        csrrw x0, mtvec, x18       # mtvec = 0x100
        ecall                      # trap to 0x100
        addi  x19, x0, 99          # executed after MRET
halt:   jal   x0, halt
        .org 0x100
        csrrs x22, mcause, x0      # handler: x22 = 11
        csrrs x23, mepc, x0        # x23 = 0x74
        addi  x23, x23, 4
        csrrw x0, mepc, x23        # mepc = 0x78
        mret                       # return to 0x78
        .org 0x1000
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444
