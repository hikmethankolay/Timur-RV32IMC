`timescale 1ns/1ps
module Timur_RV32IMC_tb;

    reg         clk;
    reg         rst_n;
    wire [31:0] pc_out;

    Timur_RV32IMC dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .pc_out (pc_out)
    );

    // 50 MHz board clock — 20 ns period
    always #10 clk = ~clk;

    // Bypass Altera PLL black-box: drive cpu clock = board clock, locked = 1.
    // The cpu_pll black-box (cpu_pll_bb.v) leaves c0/locked undriven in
    // simulation; force overrides those drivers so the CPU actually runs.
    initial begin
        force dut.pll_locked = 1'b1;
        force dut.clk_cpu    = clk;
    end

    integer failed;
    integer total;
    integer t;
    integer cycle;

    task check;
        input [31:0] got;
        input [31:0] exp;
        input integer tn;
        begin
            total = total + 1;
            if (got !== exp) begin
                $display("FAIL test %0d: got=0x%08h  exp=0x%08h", tn, got, exp);
                failed = failed + 1;
            end else
                $display("PASS test %0d: value=0x%08h", tn, got);
        end
    endtask

    initial begin
        clk    = 0;
        rst_n  = 0;
        failed = 0;
        total  = 0;
        t      = 0;
        cycle  = 0;

        // hold reset for 4 cycles, then release
        repeat (4) @(posedge clk);
        rst_n = 1;

        // run 50 cycles — comfortably covers the 16-instruction test program
        repeat (50) begin
            @(posedge clk);
            cycle = cycle + 1;
            $display("Cycle %0d | PC=%08h | instr=%08h | x1=%0d x2=%0d x3=%0d x4=%0d x5=%0d x6=%0d x7=%0d x8=%0d",
                cycle,
                dut.cpu.if_pc_current,
                dut.cpu.if_instruction,
                dut.cpu.decode.register_file.regs[1],
                dut.cpu.decode.register_file.regs[2],
                dut.cpu.decode.register_file.regs[3],
                dut.cpu.decode.register_file.regs[4],
                dut.cpu.decode.register_file.regs[5],
                dut.cpu.decode.register_file.regs[6],
                dut.cpu.decode.register_file.regs[7],
                dut.cpu.decode.register_file.regs[8]
            );
        end

        // -------------------------------------------------------
        // test_rom.hex program (RISC-V expected results):
        //   00500093  ADDI x1, x0, 5        x1 = 5
        //   00300113  ADDI x2, x0, 3        x2 = 3
        //   002081B3  ADD  x3, x1, x2       x3 = 8
        //   402081B3  SUB  x3, x1, x2       x3 = 2  (overwrites ADD result)
        //   0020F2B3  AND  x5, x1, x2       x5 = 1
        //   0020E333  OR   x6, x1, x2       x6 = 7
        //   20000137  LUI  x2, 0x20000      x2 = 0x20000000
        //   00312023  SW   x3, 0(x2)        mem[0x20000000] = 2 (address phase)
        //   00000013  NOP                   SW data phase completes; bubble before LW
        //   00012203  LW   x4, 0(x2)        x4 = 2
        //   00100293  ADDI x5, x0, 1        x5 = 1
        //   00100313  ADDI x6, x0, 1        x6 = 1
        //   00628663  BEQ  x5, x6, +12     branch taken  → skip next 2
        //   DEADC2B7  LUI  x5, 0xDEADC     SKIPPED
        //   DEADC337  LUI  x6, 0xDEADC     SKIPPED
        //   00100393  ADDI x7, x0, 1        x7 = 1  (branch target)
        //   00C0006F  JAL  x0, +12          jump to 0x4c → x6 stays 1
        //   00200313  ADDI x6, x0, 2        SKIPPED (would overwrite x6)
        //   00628663  BEQ  x5, x6, +12     SKIPPED
        //   00200413  ADDI x8, x0, 2        x8 = 2  (JAL lands here)
        //   00840463  BEQ  x8, x8, +8      always taken → skip sentinel
        //   DEADB437  LUI  x8, 0xDEADB     SKIPPED (sentinel for wrong branch)
        //   0000006F  JAL  x0, 0            infinite loop
        // -------------------------------------------------------
        $display("-----------------------------");
        $display("Final register checks:");

        t = t + 1; check(dut.cpu.decode.register_file.regs[1], 32'd5,        t); // x1 = ADDI 5
        t = t + 1; check(dut.cpu.decode.register_file.regs[2], 32'h20000000, t); // x2 = LUI 0x20000
        t = t + 1; check(dut.cpu.decode.register_file.regs[3], 32'd2,        t); // x3 = SUB 5-3
        t = t + 1; check(dut.cpu.decode.register_file.regs[4], 32'd2,        t); // x4 = LW (loaded x3)
        t = t + 1; check(dut.cpu.decode.register_file.regs[5], 32'd1,        t); // x5 = 1, NOT 0xDEADC000
        t = t + 1; check(dut.cpu.decode.register_file.regs[6], 32'd1,        t); // x6 = 1, NOT 0xDEADC000
        t = t + 1; check(dut.cpu.decode.register_file.regs[7], 32'd1,        t); // x7 = 1 (BEQ taken: branch target ran)
        t = t + 1; check(dut.cpu.decode.register_file.regs[8], 32'd2,        t); // x8 = 2 (BEQ not-taken: fell through)

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");

        $finish;
    end

endmodule
