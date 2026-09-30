# Timur RV32IMC hardware bring-up program (DE10-Lite). Assembled by the mini
# assembler (sw/timur_tools/asm.py); sw/gen_soc_tests.py writes the ROM images
# sw/bringup/bringup_1_gpio.hex and _lo/_hi .hex/.mif. Copy the bank files over
# rom_lo.* and rom_hi.* in the project root and recompile to run it on the board.
#
# Bring-up 1, GPIO only: the LEDs mirror the switches; with every switch off
# they show the pattern 0x2A5
        lui   x21, 0x40000         # APB base
        addi  x2, x0, 0x2A5
loop:   lw    x1, 0x104(x21)       # GPIO_IN
        bne   x1, x0, show
        addi  x1, x2, 0
show:   sw    x1, 0x100(x21)       # GPIO_OUT
        jal   x0, loop
