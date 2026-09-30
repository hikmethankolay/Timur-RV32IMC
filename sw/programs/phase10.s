# Timur RV32IMC directed test program. Assembled by the mini assembler
# (sw/timur_tools/asm.py: x-register names, absolute labels, .org, .word); the
# image, the expected end state from the reference model and the RTL run are
# produced by sw/gen_soc_tests.py for tb/timur_soc_tb.v. Bare-metal from the
# reset address 0: no stack and no calling convention; `halt` is the
# jump-to-self that ends the run.
#
# Phase 10: CSR instructions, precise traps, MRET, counters
        lui   x31, 0x20000         # RAM base
        addi  x28, x31, 0x200      # trap log: mcause, mepc, mtval for each trap
        addi  x1, x0, handler
        csrrw x0, mtvec, x1        # mtvec = handler
        csrrs x2, mtvec, x0        # read back
# WRITE, SET, CLEAR and the immediate forms on mscratch
        addi  x3, x0, 0x5A
        csrrw x4, mscratch, x3     # old value 0, mscratch = 5A
        csrrs x5, mscratch, x0     # 5A, no write
        addi  x6, x0, 0x0F
        csrrs x7, mscratch, x6     # 5A, mscratch = 5F
        csrrc x8, mscratch, x6     # 5F, mscratch = 50
        csrrwi x9, mscratch, 7     # 50, mscratch = 7
        csrrsi x10, mscratch, 8    # 7, mscratch = F
        csrrci x11, mscratch, 3    # F, mscratch = C
        csrrs x12, mscratch, x0    # C
# the operand arrives by forwarding; the old value is forwarded onwards
        addi  x15, x0, 0x123
        csrrw x0, mscratch, x15
        csrrs x16, mscratch, x0    # 123
        add   x17, x16, x16        # 246
# back-to-back CSR instructions on the same CSR behave sequentially
        csrrwi x0, mscratch, 1
        csrrsi x13, mscratch, 2    # 1, mscratch = 3
        csrrs x14, mscratch, x0    # 3
# WARL fields and identification
        addi  x18, x0, 0x7FF
        csrrw x0, mepc, x18        # mepc[1:0] read 0
        csrrs x18, mepc, x0        # 7FC
        csrrs x19, misa, x0        # 40001104
        csrrs x20, mhartid, x0     # 0
        csrrsi x0, mstatus, 8      # MIE = 1
        csrrs x21, mstatus, x0     # 1808
        csrrci x0, mstatus, 8      # MIE = 0
# counters: csrr of a read-only CSR does not trap; cycle advances by one per
# cycle, instret by one per retired instruction
        csrrs x22, cycle, x0
        csrrs x23, cycle, x0
        sub   x24, x23, x22        # 1
        csrrs x25, instret, x0
        addi  x0, x0, 0
        addi  x0, x0, 0
        addi  x0, x0, 0
        csrrs x26, instret, x0
        sub   x26, x26, x25        # 4
# a CSR instruction held in EX by a bus freeze writes once: with HREADY waits
# the CSRRSI sits in EX while the load's data phase waits
        lw    x27, 0(x31)
        addi  x0, x0, 0
        csrrsi x13, mscratch, 4    # old value 3 (written twice it would read 7)
        csrrs x14, mscratch, x0    # 7
# traps: the handler logs mcause, mepc and mtval and returns behind the
# trapping instruction, which leaves no trace
        ecall                      # 11
        ebreak                     # 3, mtval = PC
        .word 0x00000000           # 2: illegal instruction
        csrrs x0, 0x7C0, x0        # 2: CSR not implemented
        csrrw x0, cycle, x1        # 2: write to the read-only space
        lw    x1, 1(x31)           # 4, mtval = address; x1 keeps its value
        lh    x1, 3(x31)           # 4
        lhu   x1, 1(x31)           # 4
        addi  x27, x31, 2
        lw    x1, 0(x27)           # 4: misaligned through the base register
        sw    x3, 0(x27)           # 6
        lw    x27, 2(x27)          # base + offset aligned: no trap
        lb    x27, 3(x31)          # bytes never trap
        sw    x3, 2(x31)           # 6: misaligned store, the RAM is not written
        sh    x3, 1(x31)           # 6
        sb    x3, 3(x31)           # RAM word 0 = 5A000000
        csrrs x29, mstatus, x0     # 1880: MPIE = 1 after MRET
        csrrs x30, mepc, x0        # behind the last trapping instruction
halt:   jal   x0, halt
        .org 0x300
handler:
        csrrs x29, mcause, x0
        sw    x29, 0(x28)
        csrrs x29, mepc, x0
        sw    x29, 4(x28)
        csrrs x30, mtval, x0
        sw    x30, 8(x28)
        addi  x28, x28, 12
        addi  x29, x29, 4          # return behind the trapping instruction
        csrrw x0, mepc, x29
        mret
