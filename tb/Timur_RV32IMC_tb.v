`timescale 1ns/1ps
module Timur_RV32IMC_tb;

    reg         clk_50;
    reg         clk_10;
    reg         rst_n;
    wire [31:0] pc_out;
    wire        uart_tx;
    wire [31:0] gpio_io;   // tri-state: driven low externally (no GPIO stimuli)

    // GPIO inputs float low when OE=0; safe to leave undriven for CPU test.
    assign gpio_io = 32'hZ;

    Timur_RV32IMC dut (
        .ADC_CLK_10     (clk_10),
        .MAX10_CLK1_50  (clk_50),
        .MAX10_CLK2_50  (clk_50),
        .rst_n_i        (rst_n),
        .pc_dbg_o       (pc_out),
        .uart_rx_i      (1'b1),    // idle UART line (no incoming bytes)
        .uart_tx_o      (uart_tx),
        .gpio_io        (gpio_io)
    );

    // Match board / SDC: 50 MHz (20 ns) and 10 MHz (100 ns)
    always #10  clk_50 = ~clk_50;
    always #50  clk_10 = ~clk_10;

    // Bypass Altera PLL black-box: drive cpu clock = 50 MHz board clock, locked = 1.
    initial begin
        force dut.pll_ok_w  = 1'b1;
        force dut.clk_cpu_w = clk_50;
    end

    integer failed;
    integer total;
    integer t;
    integer cycle;

    task check;
        input [255:0] name;
        input [31:0] got;
        input [31:0] exp;
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
        t      = 0;
        cycle  = 0;

        // Hold reset for a few cycles
        repeat (4) @(posedge clk_50);
        rst_n = 1;

        // Run long enough to cover:
        //   - 37 instructions
        //   - 3x DIV @ 32 cycles each   (~96 cycles)
        //   - 1x load-use stall          (~1 cycle)
        //   - 4x branch/jump flush      (~8 cycles)
        //   - AHB pipeline latencies
        // 320 cycles is comfortable (MUL is now 2-cycle pipelined).
        repeat (320) begin
            @(posedge clk_50);
            cycle = cycle + 1;
        end

        $display("");
        $display("=========================================");
        $display("  Final state checks");
        $display("=========================================");

        // ---- Register file ----
        check("x1  ADDI 5",            dut.u_soc.u_cpu.u_dec.u_rf.regs[1],  32'h00000005);
        check("x2  ADDI -3",           dut.u_soc.u_cpu.u_dec.u_rf.regs[2],  32'hFFFFFFFD);
        check("x3  ADD  (fwd)",        dut.u_soc.u_cpu.u_dec.u_rf.regs[3],  32'h00000002);
        check("x4  SUB",               dut.u_soc.u_cpu.u_dec.u_rf.regs[4],  32'h00000008);
        check("x5  AND  (fwd)",        dut.u_soc.u_cpu.u_dec.u_rf.regs[5],  32'h00000000);
        check("x6  OR",                dut.u_soc.u_cpu.u_dec.u_rf.regs[6],  32'hFFFFFFFD);
        check("x7  XOR",               dut.u_soc.u_cpu.u_dec.u_rf.regs[7],  32'hFFFFFFF8);
        check("x8  SLLI",              dut.u_soc.u_cpu.u_dec.u_rf.regs[8],  32'h00000050);
        check("x9  SRAI",              dut.u_soc.u_cpu.u_dec.u_rf.regs[9],  32'hFFFFFFFE);
        check("x10 SLT",               dut.u_soc.u_cpu.u_dec.u_rf.regs[10], 32'h00000001);
        check("x11 SLTU",              dut.u_soc.u_cpu.u_dec.u_rf.regs[11], 32'h00000000);
        check("x12 LW",                dut.u_soc.u_cpu.u_dec.u_rf.regs[12], 32'h00000005);
        check("x13 ADDI (load-use)",   dut.u_soc.u_cpu.u_dec.u_rf.regs[13], 32'h0000000C);
        check("x14 MUL",               dut.u_soc.u_cpu.u_dec.u_rf.regs[14], 32'h00000019);
        check("x15 DIV  (8/5)",        dut.u_soc.u_cpu.u_dec.u_rf.regs[15], 32'h00000001);
        check("x16 REM  (8%5)",        dut.u_soc.u_cpu.u_dec.u_rf.regs[16], 32'h00000003);
        check("x17 DIVU (5/0)",        dut.u_soc.u_cpu.u_dec.u_rf.regs[17], 32'hFFFFFFFF);
        check("x18 BEQ not-taken",     dut.u_soc.u_cpu.u_dec.u_rf.regs[18], 32'h00000063);
        check("x19 BEQ taken target",  dut.u_soc.u_cpu.u_dec.u_rf.regs[19], 32'h00000007);
        check("x20 JAL link",          dut.u_soc.u_cpu.u_dec.u_rf.regs[20], 32'h00000068);
        check("x21 JAL target",        dut.u_soc.u_cpu.u_dec.u_rf.regs[21], 32'h0000000B);
        check("x22 AUIPC + ADDI",      dut.u_soc.u_cpu.u_dec.u_rf.regs[22], 32'h0000008C);
        check("x23 JALR link",         dut.u_soc.u_cpu.u_dec.u_rf.regs[23], 32'h00000080);
        check("x26 return point",      dut.u_soc.u_cpu.u_dec.u_rf.regs[26], 32'h00000016);
        check("x27 function body",     dut.u_soc.u_cpu.u_dec.u_rf.regs[27], 32'h0000000D);

        // ---- Sentinel: x31 must remain 0 ----
        check("x31 sentinel",          dut.u_soc.u_cpu.u_dec.u_rf.regs[31], 32'h00000000);

        // ---- Data RAM: SW x1 stored 5 at byte address 0x20000000 ----
        // RAM lifted to soc level (u_ram); word at index 0 = {mem3,mem2,mem1,mem0}[0]
        check("MEM[0x20000000]",
              {dut.u_soc.u_ram.mem3[0],
               dut.u_soc.u_ram.mem2[0],
               dut.u_soc.u_ram.mem1[0],
               dut.u_soc.u_ram.mem0[0]},
              32'h00000005);

        // ---- PC must be inside the halt loop's 4-cycle phase ----
        // JAL x0, 0 at 0x84 cycles PC through 0x84 -> 0x88 -> 0x8C -> 0x90
        // (the latter three are speculatively fetched then flushed).
        // We assert the PC is in this range; outside it means the CPU
        // escaped into invalid memory.
        total = total + 1;
        if (dut.u_soc.u_cpu.pc_fetch_w >= 32'h00000080 &&
            dut.u_soc.u_cpu.pc_fetch_w <= 32'h00000094) begin
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
