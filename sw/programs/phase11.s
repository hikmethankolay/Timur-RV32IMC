# Timur RV32IMC directed test program. Assembled by GNU as for rv32imc_zicsr
# (sw/gen_soc_tests.py: gnu_program), because it needs real 16-bit encodings;
# linked at the reset address 0. Without the toolchain the committed image
# vectors/timur_soc_phase11.hex is used. Bare-metal: x2 is set up as a stack
# pointer only to exercise the sp-relative instructions.
#
# Phase 11: every kind of compressed instruction, 32-bit instructions at both
# alignments (at 2 mod 4 a 32-bit instruction straddles two ROM words),
# compressed control flow with PC + 2 links, traps from 16-bit instructions.
# Assembled by GNU as; the c.* mnemonics force the 16-bit forms.
        .option rvc
start:  lui    x31, 0x20000             # RAM base
        addi   x28, x31, 0x200          # trap log: mcause, mepc, mtval
        lui    x2, 0x20001              # sp = 2000_1000
        la     x1, handler
        csrw   mtvec, x1
# arithmetic on x8-x15, the registers the 3-bit fields reach
        c.li   x8, 5
        c.li   x9, -3
        c.addi x8, 7                    # 12
        c.lui  x10, 0x12                # 0001_2000
        c.lui  x11, 0xfffe0             # FFFE_0000
        c.andi x9, 15                   # 13
        c.srli x10, 4                   # 0000_1200
        c.srai x11, 8                   # FFFF_FE00
        c.slli x8, 3                    # 96
        c.mv   x12, x8                  # 96
        c.add  x12, x9                  # 109
        c.sub  x12, x10                 # 109 - 1200
        c.li   x13, 0x15
        c.xor  x13, x8                  # 75
        c.li   x14, 0x0A
        c.or   x14, x9                  # 0F
        c.li   x15, -1
        c.and  x15, x10                 # 1200
# stack- and register-relative loads and stores
        c.addi16sp sp, -64              # sp = 2000_0FC0
        c.addi4spn x14, sp, 16          # x14 = 2000_0FD0
        c.swsp x12, 0(sp)
        c.lwsp x15, 0(sp)
        c.addi x15, 1                   # load-use with a 16-bit consumer
        c.sw   x15, 4(x14)
        c.lw   x13, 4(x14)
        c.mv   x16, x13
# 32-bit instructions at 2 mod 4 straddle two ROM words
        .balign 4
        c.nop
        addi   x17, x0, 0x123           # at 2 mod 4
        lui    x18, 0x54321             # at 2 mod 4
        c.nop
        addi   x18, x18, 0x765          # at 0 mod 4
        lw     x19, 4(x14)
        addi   x19, x19, 1              # load-use between straddling instructions
# compressed branches, taken and not taken, at both alignments
        c.li   x8, 0
        c.beqz x8, 1f                   # taken
        c.li   x9, 1                    # skipped
1:      c.bnez x8, 2f                   # not taken
        c.li   x9, 2
2:      c.j    3f
        c.li   x9, 3                    # skipped
3:      c.li   x10, 1
        c.bnez x10, 4f                  # taken
        c.li   x9, 4                    # skipped
4:
# links: PC + 2 for C.JAL and C.JALR, PC + 4 for JAL and JALR
        c.jal  inc20
        c.mv   x21, x1
        jal    x1, inc20
        c.mv   x22, x1
        la     x5, inc20
        c.jalr x5
        c.mv   x23, x1
        jalr   x1, 0(x5)
        c.mv   x24, x1
# a JALR to a target with bit 1 set is legal with the C extension
        la     x5, odd_target
        jalr   x0, 0(x5)
        c.li   x9, 5                    # skipped
        .balign 4
        c.nop
odd_target:
        addi   x25, x0, 0x77            # at 2 mod 4
# traps from 16-bit instructions: the handler steps over 2 bytes
        c.ebreak                        # 3, mtval = PC
        .2byte 0x0000                   # 2: the defined illegal encoding
        .2byte 0x6101                   # 2: C.ADDI16SP with a zero immediate is reserved
        ecall                           # 11: 32-bit, the handler steps over 4 bytes
        csrr   x26, misa                # 40001104
halt:   c.j    halt
inc20:  c.addi x20, 1
        c.jr   x1
        .org   0x600
handler:
        csrr   x29, mcause
        sw     x29, 0(x28)
        csrr   x29, mepc
        sw     x29, 4(x28)
        csrr   x30, mtval
        sw     x30, 8(x28)
        addi   x28, x28, 12
        lhu    x30, 0(x29)              # first halfword of the trapping instruction
        andi   x30, x30, 3
        addi   x29, x29, 2
        addi   x27, x0, 3
        bne    x30, x27, 5f             # 16-bit: 2 bytes
        addi   x29, x29, 2              # 32-bit: 4 bytes
5:      csrw   mepc, x29
        mret
