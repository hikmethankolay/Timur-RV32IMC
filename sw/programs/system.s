# Timur RV32IMC directed test program. Assembled by the mini assembler
# (sw/timur_tools/asm.py: x-register names, absolute labels, .org, .word); the
# image, the expected end state from the reference model and the RTL run are
# produced by sw/gen_soc_tests.py for tb/timur_soc_tb.v. Bare-metal from the
# reset address 0: no stack and no calling convention; `halt` is the
# jump-to-self that ends the run.
#
# Phase 9 system test: GPIO, UART, DMA copy while the CPU uses the bus,
# DMAC STATUS busy/done, LEN = 0, default slave
        lui   x20, 0x20000         # RAM base
        lui   x21, 0x40000         # APB base
        addi  x1, x0, 0x2A5
        sw    x1, 0x100(x21)       # GPIO_OUT
        lw    x2, 0x100(x21)       # 2A5
        lw    x3, 0x104(x21)       # GPIO_IN = switches
        addi  x4, x0, 0x3FF
        sw    x4, 0x108(x21)       # GPIO_DIR
        lw    x5, 0x108(x21)       # 3FF
        addi  x6, x0, 0xC3
        sb    x6, 0x101(x21)       # SB to an APB register: whole-register write of C3C3C3C3
        lw    x7, 0x100(x21)       # 3C3
        lbu   x8, 0x101(x21)       # byte 1 of GPIO_OUT = 03
        addi  x9, x0, 0x55
        sw    x9, 0(x21)           # UART_DATA = 'U'
        lw    x10, 4(x21)          # STATUS: tx_busy -> 1
        addi  x11, x0, 0x56
        sw    x11, 0(x21)          # ignored while tx_busy
        lw    x12, 8(x21)          # CTRL resets to 0
        addi  x13, x0, 1
        sw    x13, 8(x21)          # rx_enable
        lw    x14, 8(x21)          # 1
        addi  x15, x21, 0x200      # DMAC registers
        lui   x16, 0x1             # SRC = 0x1000 (table in ROM)
        sw    x16, 0(x15)
        addi  x17, x20, 0x100      # DST = 0x2000_0100
        sw    x17, 4(x15)
        addi  x18, x0, 8
        sw    x18, 8(x15)          # LEN = 8 words
        addi  x19, x0, 1
        sw    x19, 12(x15)         # start
        sw    x1, 0(x20)           # CPU loads and stores while the DMA runs
        lw    x22, 0(x20)          # 2A5
        sw    x22, 4(x20)
        lw    x23, 4(x16)          # ROM data port: 22222222
        sw    x23, 8(x20)
        lw    x24, 8(x20)          # 22222222
dma:    lw    x25, 16(x15)         # poll STATUS until busy clears
        andi  x26, x25, 1
        bne   x26, x0, dma
        lw    x27, 12(x15)         # CTRL: start reads 0, irq_enable 0
        sw    x0, 12(x15)          # any CTRL write clears done
        lw    x28, 16(x15)         # 0
        sw    x0, 8(x15)           # LEN = 0: done at once, no transfer
        sw    x19, 12(x15)
        nop
        nop
        lw    x29, 16(x15)         # done -> 2
uart:   lw    x30, 4(x21)          # wait for the 'U' frame to finish
        andi  x30, x30, 1
        bne   x30, x0, uart
        addi  x9, x0, 0x4B
        sb    x9, 0(x21)           # SB to UART_DATA: 'K'
        lui   x31, 0x10000         # unmapped: default slave
        sw    x1, 0(x31)           # ignored
        lw    x31, 0(x31)          # 0
halt:   jal   x0, halt
        .org 0x1000
        .word 0x11111111
        .word 0x22222222
        .word 0x33333333
        .word 0x44444444
        .word 0x55555555
        .word 0x66666666
        .word 0x77777777
        .word 0x88888888
