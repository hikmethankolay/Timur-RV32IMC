# Timur RV32IMC hardware bring-up program (DE10-Lite). Assembled by the mini
# assembler (sw/timur_tools/asm.py); sw/gen_soc_tests.py writes the ROM images
# sw/bringup/bringup_3_dma.hex and _lo/_hi .hex/.mif. Copy the bank files over
# rom_lo.* and rom_hi.* in the project root and recompile to run it on the board.
#
# Bring-up 3, DMA: copy four ROM words into RAM, read them back and show the
# checksum AAAAAAAA on the LEDs (0x2AA)
        lui   x20, 0x20000         # RAM base
        lui   x21, 0x40000         # APB base
        addi  x11, x21, 0x200      # DMAC registers
        lui   x12, 0x1
        sw    x12, 0(x11)          # SRC = 0x1000
        addi  x13, x20, 0x100
        sw    x13, 4(x11)          # DST = 0x2000_0100
        addi  x14, x0, 4
        sw    x14, 8(x11)          # LEN = 4 words
        addi  x15, x0, 1
        sw    x15, 12(x11)         # start
poll:   lw    x16, 16(x11)         # STATUS
        andi  x16, x16, 1
        bne   x16, x0, poll
        lw    x1, 0(x13)
        lw    x2, 4(x13)
        lw    x3, 8(x13)
        lw    x4, 12(x13)
        add   x5, x1, x2
        add   x5, x5, x3
        add   x5, x5, x4           # checksum
        sw    x5, 0x100(x21)       # GPIO_OUT
halt:   jal   x0, halt
        .org 0x1000
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444
