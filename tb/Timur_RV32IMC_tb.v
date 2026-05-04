`timescale 1ns/1ps
module Timur_RV32IMC_tb;

    reg         clk_50;
    reg         clk_10;
    reg         rst_n;
    wire [31:0] pc_out;
    wire        uart_tx;
    wire [31:0] gpio_io;

    assign gpio_io = 32'hZ;

    Timur_RV32IMC dut (
        .ADC_CLK_10     (clk_10),
        .MAX10_CLK1_50  (clk_50),
        .MAX10_CLK2_50  (clk_50),
        .rst_n_i        (rst_n),
        .pc_dbg_o       (pc_out),
        .uart_rx_i      (1'b1),
        .uart_tx_o      (uart_tx),
        .gpio_io        (gpio_io)
    );

    always #10 clk_50 = ~clk_50;
    always #50 clk_10 = ~clk_10;

    initial begin
        force dut.pll_ok_w  = 1'b1;
        force dut.clk_cpu_w = clk_50;
    end

    integer failed;
    integer total;

    task check;
        input [255:0] name;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            total = total + 1;
            if (got !== exp) begin
                $display("FAIL  %0s: got=0x%08h  exp=0x%08h", name, got, exp);
                failed = failed + 1;
            end else begin
                $display("PASS  %0s: 0x%08h", name, got);
            end
        end
    endtask

    initial begin
        clk_50 = 0;
        clk_10 = 0;
        rst_n  = 0;
        failed = 0;
        total  = 0;

        repeat (4) @(posedge clk_50);
        rst_n = 1;

        // Cover: 61 instrs, multi-cycle DIV/REM/MULH, branches with halt-traps,
        // JAL/JALR redirects, sub-word loads/stores. ADDI→SW pattern at 0xC4/0xC8
        // exercises the rs2 store-data forwarding path (the just-fixed bug).
        repeat (800) @(posedge clk_50);

        $display("");
        $display("=========================================");
        $display("  Final state checks");
        $display("=========================================");

        // ---- Register file: each test writes a unique destination ----
        check("x1  ADDI 5",         dut.u_soc.u_cpu.u_dec.u_rf.regs[1],  32'h00000005);
        check("x2  ADDI -3",        dut.u_soc.u_cpu.u_dec.u_rf.regs[2],  32'hFFFFFFFD);
        check("x3  LUI 0x20000",    dut.u_soc.u_cpu.u_dec.u_rf.regs[3],  32'h20000000);
        check("x4  ADD",            dut.u_soc.u_cpu.u_dec.u_rf.regs[4],  32'h00000002);
        check("x5  SUB",            dut.u_soc.u_cpu.u_dec.u_rf.regs[5],  32'h00000008);
        check("x6  AND",            dut.u_soc.u_cpu.u_dec.u_rf.regs[6],  32'h00000000);
        check("x7  OR",             dut.u_soc.u_cpu.u_dec.u_rf.regs[7],  32'hFFFFFFFD);
        check("x8  XOR",            dut.u_soc.u_cpu.u_dec.u_rf.regs[8],  32'hFFFFFFF8);
        check("x9  ANDI",           dut.u_soc.u_cpu.u_dec.u_rf.regs[9],  32'h000000FD);
        check("x10 ORI",            dut.u_soc.u_cpu.u_dec.u_rf.regs[10], 32'h0000000D);
        check("x11 XORI",           dut.u_soc.u_cpu.u_dec.u_rf.regs[11], 32'h0000000A);
        check("x12 SLT",            dut.u_soc.u_cpu.u_dec.u_rf.regs[12], 32'h00000001);
        check("x13 SLTU",           dut.u_soc.u_cpu.u_dec.u_rf.regs[13], 32'h00000001);
        check("x14 SLTI",           dut.u_soc.u_cpu.u_dec.u_rf.regs[14], 32'h00000001);
        check("x15 SLTIU",          dut.u_soc.u_cpu.u_dec.u_rf.regs[15], 32'h00000000);
        check("x16 SLLI",           dut.u_soc.u_cpu.u_dec.u_rf.regs[16], 32'h00000050);
        check("x17 SRLI",           dut.u_soc.u_cpu.u_dec.u_rf.regs[17], 32'h7FFFFFFE);
        check("x18 SRAI",           dut.u_soc.u_cpu.u_dec.u_rf.regs[18], 32'hFFFFFFFE);
        check("x19 SLL",            dut.u_soc.u_cpu.u_dec.u_rf.regs[19], 32'h00000500);
        check("x20 SRL",            dut.u_soc.u_cpu.u_dec.u_rf.regs[20], 32'h07FFFFFF);
        check("x21 SRA",            dut.u_soc.u_cpu.u_dec.u_rf.regs[21], 32'hFFFFFFFF);
        check("x22 AUIPC (PC=0x54)",dut.u_soc.u_cpu.u_dec.u_rf.regs[22], 32'h00000054);
        check("x23 MUL",            dut.u_soc.u_cpu.u_dec.u_rf.regs[23], 32'h00000019);
        check("x24 MULH",           dut.u_soc.u_cpu.u_dec.u_rf.regs[24], 32'h00000000);
        check("x25 MULHSU",         dut.u_soc.u_cpu.u_dec.u_rf.regs[25], 32'hFFFFFFFF);
        check("x26 MULHU",          dut.u_soc.u_cpu.u_dec.u_rf.regs[26], 32'h00000004);
        check("x27 DIV",            dut.u_soc.u_cpu.u_dec.u_rf.regs[27], 32'h00000001);
        check("x28 DIVU",           dut.u_soc.u_cpu.u_dec.u_rf.regs[28], 32'h00000002);
        check("x29 REM",            dut.u_soc.u_cpu.u_dec.u_rf.regs[29], 32'h00000003);
        check("x30 REMU",           dut.u_soc.u_cpu.u_dec.u_rf.regs[30], 32'h00000003);
        // x31 = LW from mem[12] = 0xFFFFFF80 (set via ADDI x31,-128 + SW x31)
        check("x31 LW (sign-ext)",  dut.u_soc.u_cpu.u_dec.u_rf.regs[31], 32'hFFFFFF80);

        // ---- Memory ----
        // [0x00] SW x1 (=5) — full word
        check("MEM[0x00] SW word",
              {dut.u_soc.u_ram.mem3[0], dut.u_soc.u_ram.mem2[0],
               dut.u_soc.u_ram.mem1[0], dut.u_soc.u_ram.mem0[0]},
              32'h00000005);
        // [0x04] SB x2 byte 0 = 0xFD; bytes 5..7 left uninit
        check("MEM[0x04] SB byte",
              {24'h0, dut.u_soc.u_ram.mem0[1]},
              32'h000000FD);
        // [0x08] SH x4 halfword 0 = 0x0002; bytes 10..11 left uninit
        check("MEM[0x08] SH half",
              {16'h0, dut.u_soc.u_ram.mem1[2], dut.u_soc.u_ram.mem0[2]},
              32'h00000002);
        // [0x0C] SW x31 (=0xFFFFFF80, set by ADDI immediately before)
        // → exercises the rs2 store-data forwarding fix.
        check("MEM[0x0C] SW after ADDI (FWD test)",
              {dut.u_soc.u_ram.mem3[3], dut.u_soc.u_ram.mem2[3],
               dut.u_soc.u_ram.mem1[3], dut.u_soc.u_ram.mem0[3]},
              32'hFFFFFF80);
        // [0x10] SW (LB sign-ext byte 0x80) = 0xFFFFFF80
        check("MEM[0x10] LB sign-ext",
              {dut.u_soc.u_ram.mem3[4], dut.u_soc.u_ram.mem2[4],
               dut.u_soc.u_ram.mem1[4], dut.u_soc.u_ram.mem0[4]},
              32'hFFFFFF80);
        // [0x14] SW (LBU zero-ext byte 0x80) = 0x00000080
        check("MEM[0x14] LBU zero-ext",
              {dut.u_soc.u_ram.mem3[5], dut.u_soc.u_ram.mem2[5],
               dut.u_soc.u_ram.mem1[5], dut.u_soc.u_ram.mem0[5]},
              32'h00000080);
        // [0x18] SW (LH sign-ext half 0xFF80) = 0xFFFFFF80
        check("MEM[0x18] LH sign-ext",
              {dut.u_soc.u_ram.mem3[6], dut.u_soc.u_ram.mem2[6],
               dut.u_soc.u_ram.mem1[6], dut.u_soc.u_ram.mem0[6]},
              32'hFFFFFF80);
        // [0x1C] SW (LHU zero-ext half 0xFF80) = 0x0000FF80
        check("MEM[0x1C] LHU zero-ext",
              {dut.u_soc.u_ram.mem3[7], dut.u_soc.u_ram.mem2[7],
               dut.u_soc.u_ram.mem1[7], dut.u_soc.u_ram.mem0[7]},
              32'h0000FF80);

        // ---- Halt loop: JAL x0, 0 at 0xF0 ----
        // Any branch / JAL / JALR that misfired would halt earlier (trap = JAL x0,0).
        total = total + 1;
        if (dut.u_soc.u_cpu.pc_fetch_w >= 32'h000000F0 &&
            dut.u_soc.u_cpu.pc_fetch_w <= 32'h00000100) begin
            $display("PASS  PC inside halt loop: 0x%08h", dut.u_soc.u_cpu.pc_fetch_w);
        end else begin
            $display("FAIL  PC outside halt loop: 0x%08h", dut.u_soc.u_cpu.pc_fetch_w);
            failed = failed + 1;
        end

        $display("=========================================");
        if (failed == 0)
            $display("  ALL %0d TESTS PASSED", total);
        else
            $display("  %0d / %0d TESTS FAILED", failed, total);
        $display("=========================================");

        $finish;
    end

endmodule
