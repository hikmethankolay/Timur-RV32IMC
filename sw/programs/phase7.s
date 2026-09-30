# Timur RV32IMC directed test program. Assembled by the mini assembler
# (sw/timur_tools/asm.py: x-register names, absolute labels, .org, .word); the
# image, the expected end state from the reference model and the RTL run are
# produced by sw/gen_soc_tests.py for tb/timur_soc_tb.v. Bare-metal from the
# reset address 0: no stack and no calling convention; `halt` is the
# jump-to-self that ends the run.
#
# Phase 7: forwarding, load-use, divider, multiplier, redirects, bus waits
        lui   x31, 0x20000         # RAM base
        lui   x30, 0x40000         # APB base
# forwarding: EX/MEM (10), MEM/WB (01), EX/MEM priority, x0 never forwarded
        addi  x1, x0, 7
        addi  x2, x1, 3            # x1 from EX/MEM -> 10
        addi  x3, x1, 1            # x1 from MEM/WB -> 8
        add   x4, x2, x3           # x2 from MEM/WB, x3 from EX/MEM -> 18
        addi  x5, x0, 1
        addi  x5, x0, 2
        add   x6, x5, x5           # EX/MEM wins over MEM/WB -> 4
        addi  x0, x0, 5            # the write to x0 is dropped
        add   x7, x0, x0           # x0 reads 0 -> 0
        sw    x2, 0x40(x31)
        sw    x3, 0x44(x31)
        sw    x4, 0x48(x31)
        sw    x6, 0x4C(x31)
        sw    x7, 0x50(x31)
# store immediately followed by a load of the same address (RAM bypass)
        sw    x4, 0(x31)
        lw    x8, 0(x31)           # 18
# load-use: dependent ALU op, dependent store data, dependent store address
        addi  x9, x8, 1            # one bubble -> 19
        lw    x10, 0(x31)
        sw    x10, 4(x31)          # store data from the load
        lw    x11, 4(x31)          # 18
        addi  x12, x31, 8
        sw    x12, 12(x31)
        lw    x13, 12(x31)         # pointer 20000008
        sw    x9, 0(x13)           # store address from the load: word 8 = 19
        lw    x14, 8(x31)          # 19
# Phase 7 walkthrough: LW, dependent ADD, DIV, taken BEQ on the DIV result
        addi  x15, x0, 5
        sw    x15, 16(x31)
        addi  x16, x31, 16
        addi  x17, x0, 1
        addi  x18, x0, 100
        lw    x19, 0(x16)          # LW  x1, 0(x2)   -> 5
        add   x20, x19, x17        # ADD x3, x1, x4  -> 6 (load-use)
        div   x21, x20, x18        # DIV x5, x3, x6  -> 0 (EX stall)
        beq   x21, x0, walk        # BEQ x5, x0, +16: taken
        addi  x22, x0, 1           # wrong path, killed
        addi  x22, x0, 2           # wrong path, killed
        addi  x22, x0, 3           # never fetched
walk:
# MUL: one EX stall cycle (operand capture), result forwarded
        mul   x22, x20, x18        # 600
        add   x23, x22, x1         # 607
# DIV and REM results forwarded to the next instruction
        div   x24, x23, x1         # 86
        addi  x25, x24, 1          # 87
        rem   x26, x23, x1         # 5
        sw    x22, 0x54(x31)
        sw    x23, 0x58(x31)
        sw    x24, 0x5C(x31)
        sw    x25, 0x60(x31)
        sw    x26, 0x64(x31)
# DIV whose operand comes from an APB load: the start waits for the bus
        addi  x27, x0, 0x155
        sw    x27, 0x100(x30)      # GPIO_OUT
        lw    x28, 0x100(x30)      # 155
        div   x29, x28, x1         # 48
        sw    x29, 0x68(x31)
# DIV whose operand comes straight from a RAM load: with HREADY wait states
# the start must wait until the data phase completes
        lw    x5, 0x58(x31)        # 607
        div   x6, x5, x1           # 86
        sw    x6, 0x7C(x31)
# MUL whose operand comes straight from a RAM load: the operand capture must
# also wait for the data phase
        lw    x5, 0x58(x31)        # 607
        mul   x6, x5, x1           # 4249
        sw    x6, 0x80(x31)
# REM by zero right after an independent APB load: done is not lost
        addi  x5, x0, 123
        lw    x6, 0x108(x30)       # GPIO_DIR = 0
        rem   x7, x5, x0           # 123
        divu  x8, x5, x0           # FFFFFFFF
        sw    x7, 0x6C(x31)
        sw    x8, 0x70(x31)
# signed overflow: 80000000 / FFFFFFFF
        lui   x9, 0x80000
        addi  x10, x0, -1
        div   x11, x9, x10         # 80000000
        rem   x12, x9, x10         # 0
        sw    x11, 0x74(x31)
        sw    x12, 0x78(x31)
# taken branch, JAL and JALR each kill exactly two instructions
        addi  x13, x0, 0
        addi  x14, x0, 0
        addi  x15, x0, 0
        beq   x0, x0, b1
        addi  x13, x13, 1          # killed
        addi  x13, x13, 2          # killed
b1:     jal   x16, b2
        addi  x14, x14, 1          # killed
        addi  x14, x14, 2          # killed
b2:     auipc x17, 0
        jalr  x18, 12(x17)         # to b3
        addi  x15, x15, 1          # killed
        addi  x15, x15, 2          # killed
b3:     bne   x0, x0, bad          # not taken: nothing is killed
        addi  x19, x0, 77
# branch and JALR operands straight from a load
        lw    x20, 0(x31)          # 18
        bne   x20, x4, bad
        sw    x17, 20(x31)
        lw    x21, 20(x31)
        jalr  x22, b4-b2(x21)      # load-use into JALR
        jal   x0, bad
b4:     addi  x23, x0, 99
halt:   jal   x0, halt
bad:    lui   x24, 0xBAD00
        jal   x0, bad
