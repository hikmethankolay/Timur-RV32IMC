`timescale 1ns/1ps
// rom_ahb_tb — dual-port AHB ROM testbench.
// Port A = dedicated I-fetch bus; Port B = shared D-bus.
// Both ports are independent: concurrent accesses to different addresses work.
module rom_ahb_tb;

    reg         HCLK, HRESETn;

    // Port A (I-fetch)
    reg         HSEL_a, HWRITE_a;
    reg  [31:0] HADDR_a, HWDATA_a;
    reg  [1:0]  HTRANS_a;
    reg  [2:0]  HSIZE_a;
    wire [31:0] HRDATA_a;
    wire        HREADY_a, HRESP_a;

    // Port B (D-bus)
    reg         HSEL_b, HWRITE_b;
    reg  [31:0] HADDR_b, HWDATA_b;
    reg  [1:0]  HTRANS_b;
    reg  [2:0]  HSIZE_b;
    wire [31:0] HRDATA_b;
    wire        HREADY_b, HRESP_b;

    rom_ahb dut (
        .HCLK    (HCLK),
        .HRESETn (HRESETn),
        .HSEL_a  (HSEL_a),  .HADDR_a  (HADDR_a),  .HTRANS_a (HTRANS_a),
        .HWRITE_a(HWRITE_a),.HSIZE_a  (HSIZE_a),  .HWDATA_a (HWDATA_a),
        .HRDATA_a(HRDATA_a),.HREADY_a (HREADY_a), .HRESP_a  (HRESP_a),
        .HSEL_b  (HSEL_b),  .HADDR_b  (HADDR_b),  .HTRANS_b (HTRANS_b),
        .HWRITE_b(HWRITE_b),.HSIZE_b  (HSIZE_b),  .HWDATA_b (HWDATA_b),
        .HRDATA_b(HRDATA_b),.HREADY_b (HREADY_b), .HRESP_b  (HRESP_b)
    );

    always #5 HCLK = ~HCLK;

    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    task check;
        input [255:0] label;
        input [31:0]  got, exp;
        begin
            test_num = test_num + 1; total = total + 1;
            if (got !== exp) begin
                $display("FAIL T%0d %0s: got=%h  exp=%h", test_num, label, got, exp);
                failed = failed + 1;
            end else
                $display("PASS T%0d %0s: %h", test_num, label, got);
        end
    endtask

    // Issue one NONSEQ read on Port A; return data captured after clock edge.
    task ahb_read_a;
        input [31:0] addr;
        output [31:0] data;
        begin
            HSEL_a = 1'b1; HADDR_a = addr;
            HTRANS_a = 2'b10; HWRITE_a = 1'b0; HSIZE_a = 3'b010;
            @(posedge HCLK); #1;
            data = HRDATA_a;
            HSEL_a = 1'b0; HTRANS_a = 2'b00;
        end
    endtask

    // Issue one NONSEQ read on Port B; return data captured after clock edge.
    task ahb_read_b;
        input [31:0] addr;
        output [31:0] data;
        begin
            HSEL_b = 1'b1; HADDR_b = addr;
            HTRANS_b = 2'b10; HWRITE_b = 1'b0; HSIZE_b = 3'b010;
            @(posedge HCLK); #1;
            data = HRDATA_b;
            HSEL_b = 1'b0; HTRANS_b = 2'b00;
        end
    endtask

    reg [31:0] got_a, got_b;

    initial begin
        HCLK    = 0;
        HRESETn = 0;
        HSEL_a  = 0; HADDR_a  = 0; HTRANS_a = 2'b00; HWRITE_a = 0;
        HSIZE_a = 3'b010; HWDATA_a = 0;
        HSEL_b  = 0; HADDR_b  = 0; HTRANS_b = 2'b00; HWRITE_b = 0;
        HSIZE_b = 3'b010; HWDATA_b = 0;

        // Seed known words before reset releases so readmemh can't clobber them.
        #1;
        dut.mem[0] = 32'h00000013;   // NOP   @ 0x000
        dut.mem[1] = 32'hAABBCCDD;   //        @ 0x004
        dut.mem[2] = 32'hDEADBEEF;   //        @ 0x008
        dut.mem[3] = 32'hCAFEBABE;   //        @ 0x00C
        dut.mem[4] = 32'h12345678;   //        @ 0x010
        dut.mem[5] = 32'hABCDABCD;   //        @ 0x014

        // ── T1: reset holds → both HRDATA outputs stay 0 ────────────────────
        @(posedge HCLK); #1;
        check("T1 reset HRDATA_a=0", HRDATA_a, 32'h0);
        check("T1 reset HRDATA_b=0", HRDATA_b, 32'h0);

        // ── T2: HREADY always 1, HRESP always 0 ─────────────────────────────
        test_num = test_num + 1; total = total + 1;
        if (HREADY_a !== 1'b1 || HREADY_b !== 1'b1 ||
            HRESP_a  !== 1'b0 || HRESP_b  !== 1'b0) begin
            $display("FAIL T%0d HREADY/HRESP static", test_num);
            failed = failed + 1;
        end else
            $display("PASS T%0d HREADY/HRESP: a=%b/%b b=%b/%b",
                      test_num, HREADY_a, HRESP_a, HREADY_b, HRESP_b);

        // ── T3-T4: Port A basic reads after reset release ────────────────────
        HRESETn = 1;
        ahb_read_a(32'h0000_0000, got_a);
        check("T3 Port-A read mem[0]", got_a, 32'h00000013);

        ahb_read_a(32'h0000_0008, got_a);
        check("T4 Port-A read mem[2]", got_a, 32'hDEADBEEF);

        // ── T5-T6: Port B basic reads ────────────────────────────────────────
        ahb_read_b(32'h0000_0004, got_b);
        check("T5 Port-B read mem[1]", got_b, 32'hAABBCCDD);

        ahb_read_b(32'h0000_000C, got_b);
        check("T6 Port-B read mem[3]", got_b, 32'hCAFEBABE);

        // ── T7: simultaneous Port A + Port B to different addresses ──────────
        HSEL_a = 1; HADDR_a = 32'h0000_0010; HTRANS_a = 2'b10; HWRITE_a = 0; HSIZE_a = 3'b010;
        HSEL_b = 1; HADDR_b = 32'h0000_0014; HTRANS_b = 2'b10; HWRITE_b = 0; HSIZE_b = 3'b010;
        @(posedge HCLK); #1;
        got_a = HRDATA_a; got_b = HRDATA_b;
        HSEL_a = 0; HTRANS_a = 2'b00;
        HSEL_b = 0; HTRANS_b = 2'b00;
        check("T7 simultaneous A(0x10)", got_a, 32'h12345678);
        check("T7 simultaneous B(0x14)", got_b, 32'hABCDABCD);

        // ── T8: HTRANS=IDLE on Port A — addr not latched, HRDATA holds last ──
        HSEL_a = 1; HADDR_a = 32'h0000_0008; HTRANS_a = 2'b00;
        @(posedge HCLK); #1;
        check("T8 A HTRANS=IDLE holds last", HRDATA_a, 32'h12345678);
        HSEL_a = 0;

        // ── T9: HSEL=0 on Port B — not latched ──────────────────────────────
        HSEL_b = 0; HADDR_b = 32'h0000_0008; HTRANS_b = 2'b10;
        @(posedge HCLK); #1;
        check("T9 B HSEL=0 holds last", HRDATA_b, 32'hABCDABCD);
        HTRANS_b = 2'b00;

        // ── T10: Port B vector-style sequence (mirrors old single-port tests) ─
        // NONSEQ to 0x008
        ahb_read_b(32'h0000_0008, got_b);
        check("T10 Port-B 0x008=DEADBEEF", got_b, 32'hDEADBEEF);

        // SEQ to 0x00C
        HSEL_b = 1; HADDR_b = 32'h0000_000C; HTRANS_b = 2'b11; HWRITE_b = 0; HSIZE_b = 3'b010;
        @(posedge HCLK); #1;
        check("T11 Port-B SEQ 0x00C=CAFEBABE", HRDATA_b, 32'hCAFEBABE);
        HSEL_b = 0; HTRANS_b = 2'b00;

        // ── T12-T13: reset mid-operation clears both ports ───────────────────
        // Start a read so registers have data, then assert reset
        HSEL_a = 1; HADDR_a = 32'h0000_0004; HTRANS_a = 2'b10; HWRITE_a = 0; HSIZE_a = 3'b010;
        HSEL_b = 1; HADDR_b = 32'h0000_0004; HTRANS_b = 2'b10; HWRITE_b = 0; HSIZE_b = 3'b010;
        @(posedge HCLK);
        HRESETn = 0; #1;
        check("T12 async reset clears A", HRDATA_a, 32'h0);
        check("T13 async reset clears B", HRDATA_b, 32'h0);
        HSEL_a = 0; HTRANS_a = 2'b00;
        HSEL_b = 0; HTRANS_b = 2'b00;

        // ── T14: release reset, read again on Port A ─────────────────────────
        HRESETn = 1;
        ahb_read_a(32'h0000_0000, got_a);
        check("T14 post-reset A read mem[0]", got_a, 32'h00000013);

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
