# Timur RV32IMC directed test program. Assembled by the mini assembler
# (sw/timur_tools/asm.py: x-register names, absolute labels, .org, .word); the
# image, the expected end state from the reference model and the RTL run are
# produced by sw/gen_soc_tests.py for tb/timur_soc_tb.v. Bare-metal from the
# reset address 0: no stack and no calling convention; `halt` is the
# jump-to-self that ends the run.
#
# Phase 6: loads of every size, stores of every size and offset, links, LUI/AUIPC,
# register-file bypass at distance three, loads from the ROM data port
        lui   x31, 0x20000         # RAM base
        lui   x1, 0x80FF8
        addi  x1, x1, 0x17F        # x1 = 80FF817F
        sw    x1, 0(x31)
        nop
        nop
        lb    x2, 0(x31)           # 0000007F
        lb    x3, 1(x31)           # FFFFFF81
        lbu   x4, 1(x31)           # 00000081
        lb    x5, 2(x31)           # FFFFFFFF
        lbu   x6, 3(x31)           # 00000080
        lb    x7, 3(x31)           # FFFFFF80: sign extension of 0x80
        lh    x8, 0(x31)           # FFFF817F
        lhu   x9, 0(x31)           # 0000817F
        lh    x10, 2(x31)          # FFFF80FF: sign extension of 0x80FF
        lhu   x11, 2(x31)          # 000080FF
        lw    x12, 0(x31)          # 80FF817F
        addi  x13, x0, -1
        sw    x13, 4(x31)          # FFFFFFFF
        sb    x0, 5(x31)           # FFFF00FF: other lanes untouched
        addi  x14, x0, 0x5A
        sb    x14, 7(x31)          # 5AFF00FF
        lui   x15, 0x12345
        addi  x15, x15, 0x678      # 12345678
        sh    x15, 10(x31)         # word 8 = 56780000
        sb    x15, 12(x31)         # word 12 = 00000078
        sb    x15, 14(x31)         # word 12 = 00780078
        sh    x13, 16(x31)         # word 16 = 0000FFFF
        sb    x14, 18(x31)         # word 16 = 005AFFFF
        lw    x16, 4(x31)
        lw    x17, 8(x31)
        lw    x18, 12(x31)
        lw    x19, 16(x31)
        jal   x20, link1           # x20 = PC + 4
        addi  x21, x0, 1           # skipped
link1:  auipc x21, 0               # x21 = PC
        jalr  x22, 12(x21)         # to link2, x22 = PC + 4
        addi  x23, x0, 1           # skipped
link2:  lui   x23, 0xFEDCB         # FEDCB000
        addi  x24, x0, 42
        nop
        nop
        add   x25, x24, x0         # distance 3: register-file write-through bypass
        addi  x26, x0, 7
        nop
        nop
        nop
        add   x27, x26, x0         # distance 4: register file
        lw    x28, 0(x0)           # ROM data port: first program word
        lhu   x29, 2(x0)
        lb    x30, 7(x0)
halt:   jal   x0, halt
