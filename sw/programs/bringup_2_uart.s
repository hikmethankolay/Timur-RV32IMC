# Timur RV32IMC hardware bring-up program (DE10-Lite). Assembled by the mini
# assembler (sw/timur_tools/asm.py); sw/gen_soc_tests.py writes the ROM images
# sw/bringup/bringup_2_uart.hex and _lo/_hi .hex/.mif. Copy the bank files over
# rom_lo.* and rom_hi.* in the project root and recompile to run it on the board.
#
# Bring-up 2, UART transmit: 'U' (0x55) in a loop, a square wave on a scope and
# UUUU in a terminal at 115200 8N1
        lui   x21, 0x40000         # APB base
        addi  x1, x0, 0x55
wait:   lw    x2, 4(x21)           # UART_STATUS
        andi  x2, x2, 1            # tx_busy
        bne   x2, x0, wait
        sw    x1, 0(x21)           # UART_DATA
        jal   x0, wait
