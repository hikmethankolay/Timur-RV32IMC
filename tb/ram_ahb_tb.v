`timescale 1ns/1ps
module ram_ahb_tb;

    reg         HCLK, HRESETn, HSEL, HWRITE;
    reg  [31:0] HADDR, HWDATA;
    reg  [1:0]  HTRANS;
    reg  [2:0]  HSIZE;
    wire [31:0] HRDATA;
    wire        HREADY, HRESP;

    ram_ahb dut (
        .HCLK   (HCLK),
        .HRESETn(HRESETn),
        .HSEL   (HSEL),
        .HADDR  (HADDR),
        .HTRANS (HTRANS),
        .HWRITE (HWRITE),
        .HSIZE  (HSIZE),
        .HWDATA (HWDATA),
        .HRDATA (HRDATA),
        .HREADY (HREADY),
        .HRESP  (HRESP)
    );

    always #5 HCLK = ~HCLK;

    integer failed;
    integer total;
    integer t;

    // AHB write: address phase → clock (ctrl registered) → data phase → clock (write occurs)
    task ahb_write;
        input [31:0] addr;
        input [2:0]  size;
        input [31:0] data;
        begin
            HSEL   = 1; HWRITE = 1;
            HADDR  = addr; HTRANS = 2'b10; HSIZE = size;
            @(posedge HCLK); #1;
            HWDATA = data;
            HSEL   = 0; HWRITE = 0; HTRANS = 2'b00;
            @(posedge HCLK); #1;
        end
    endtask

    // AHB read: address phase -> next clock -> sample full 32-bit aligned HRDATA
    task ahb_read;
        input  [31:0] addr;
        input  [2:0]  size;
        output [31:0] rdata;
        begin
            HSEL   = 1; HWRITE = 0;
            HADDR  = addr; HTRANS = 2'b10; HSIZE = size;
            @(posedge HCLK); #1;
            rdata = HRDATA;
            HSEL   = 0; HTRANS = 2'b00;
        end
    endtask

    // CPU LSU-side load extraction/extension from full 32-bit bus HRDATA.
    function [31:0] lsu_load_format;
        input [31:0] word;
        input [1:0]  addr_lsb;
        input [2:0]  f3;
        reg   [7:0]  b;
        reg   [15:0] h;
        begin
            case (addr_lsb)
                2'b00: b = word[7:0];
                2'b01: b = word[15:8];
                2'b10: b = word[23:16];
                default: b = word[31:24];
            endcase

            if (addr_lsb[1] == 1'b0)
                h = word[15:0];
            else
                h = word[31:16];

            case (f3)
                3'b000:  lsu_load_format = {{24{b[7]}}, b};
                3'b100:  lsu_load_format = {24'b0, b};
                3'b001:  lsu_load_format = {{16{h[15]}}, h};
                3'b101:  lsu_load_format = {16'b0, h};
                default: lsu_load_format = word;
            endcase
        end
    endfunction

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
                $display("PASS test %0d: data=0x%08h", tn, got);
        end
    endtask

    reg [31:0] rdata;

    initial begin
        HCLK    = 0; HRESETn = 0;
        HSEL    = 0; HWRITE  = 0;
        HADDR   = 32'h0; HTRANS = 2'b00;
        HSIZE   = 3'b010; HWDATA = 32'h0;
        failed  = 0; total = 0; t = 0;

        #12; HRESETn = 1; #3;

        // -------------------------------------------------------
        // Test 1: HREADY=1 HRESP=0 (constant outputs)
        // -------------------------------------------------------
        t = t + 1; total = total + 1;
        if (HREADY !== 1'b1 || HRESP !== 1'b0) begin
            $display("FAIL test %0d: HREADY=%b HRESP=%b (exp 1/0)", t, HREADY, HRESP);
            failed = failed + 1;
        end else
            $display("PASS test %0d: HREADY=1 HRESP=0", t);

        // -------------------------------------------------------
        // Test 2: word write / word read
        // -------------------------------------------------------
        ahb_write(32'h0000_0000, 3'b010, 32'hDEAD_BEEF);
        ahb_read (32'h0000_0000, 3'b010, rdata);
        t = t + 1; check(rdata, 32'hDEAD_BEEF, t);

        // -------------------------------------------------------
        // Test 3: second word address
        // -------------------------------------------------------
        ahb_write(32'h0000_0004, 3'b010, 32'hCAFE_BABE);
        ahb_read (32'h0000_0004, 3'b010, rdata);
        t = t + 1; check(rdata, 32'hCAFE_BABE, t);

        // -------------------------------------------------------
        // Tests 4-7: byte writes then full-word reads + LSU LB checks
        // Clear target word first so untouched lanes are deterministic.
        // Data must sit at the correct byte lane in HWDATA so the
        // byte-enable mux places it in the right mem byte.
        //   byte 0 → HWDATA[7:0],  byte 1 → HWDATA[15:8],
        //   byte 2 → HWDATA[23:16], byte 3 → HWDATA[31:24]
        // -------------------------------------------------------
        ahb_write(32'h0000_0008, 3'b010, 32'h0000_0000); // clear word
        ahb_write(32'h0000_0008, 3'b000, 32'h0000_0012); // byte 0 ← 0x12
        ahb_read (32'h0000_0008, 3'b000, rdata);
        t = t + 1; check(rdata, 32'h0000_0012, t); // raw word
        t = t + 1; check(lsu_load_format(rdata, 2'b00, 3'b000), 32'h0000_0012, t); // LB

        ahb_write(32'h0000_0009, 3'b000, 32'h0000_AB00); // byte 1 ← 0xAB
        ahb_read (32'h0000_0009, 3'b000, rdata);
        t = t + 1; check(rdata, 32'h0000_AB12, t); // raw word
        t = t + 1; check(lsu_load_format(rdata, 2'b01, 3'b000), 32'hFFFF_FFAB, t); // LB

        ahb_write(32'h0000_000A, 3'b000, 32'h007F_0000); // byte 2 ← 0x7F
        ahb_read (32'h0000_000A, 3'b000, rdata);
        t = t + 1; check(rdata, 32'h007F_AB12, t); // raw word
        t = t + 1; check(lsu_load_format(rdata, 2'b10, 3'b000), 32'h0000_007F, t); // LB

        ahb_write(32'h0000_000B, 3'b000, 32'h8000_0000); // byte 3 ← 0x80
        ahb_read (32'h0000_000B, 3'b000, rdata);
        t = t + 1; check(rdata, 32'h807F_AB12, t); // raw word
        t = t + 1; check(lsu_load_format(rdata, 2'b11, 3'b000), 32'hFFFF_FF80, t); // LB

        // Tests 8-9: LBU (zero-extend) checks using raw full-word HRDATA
        ahb_read(32'h0000_0009, 3'b100, rdata);
        t = t + 1; check(rdata, 32'h807F_AB12, t); // raw word unchanged by HSIZE
        t = t + 1; check(lsu_load_format(rdata, 2'b01, 3'b100), 32'h0000_00AB, t);

        ahb_read(32'h0000_000B, 3'b100, rdata);
        t = t + 1; check(rdata, 32'h807F_AB12, t); // raw word unchanged by HSIZE
        t = t + 1; check(lsu_load_format(rdata, 2'b11, 3'b100), 32'h0000_0080, t);

        // Tests 10-11: halfword writes then full-word reads + LSU LH checks
        // Clear target word first so untouched halfword is deterministic.
        //   low  half (addr[1]=0) → HWDATA[15:0]
        //   high half (addr[1]=1) → HWDATA[31:16]
        // -------------------------------------------------------
        ahb_write(32'h0000_0010, 3'b010, 32'h0000_0000); // clear word
        ahb_write(32'h0000_0010, 3'b001, 32'h0000_ABCD); // half[15:0] ← 0xABCD
        ahb_read (32'h0000_0010, 3'b001, rdata);
        t = t + 1; check(rdata, 32'h0000_ABCD, t); // raw word
        t = t + 1; check(lsu_load_format(rdata, 2'b00, 3'b001), 32'hFFFF_ABCD, t); // LH

        ahb_write(32'h0000_0012, 3'b001, 32'h1234_0000); // half[31:16] ← 0x1234
        ahb_read (32'h0000_0012, 3'b001, rdata);
        t = t + 1; check(rdata, 32'h1234_ABCD, t); // raw word
        t = t + 1; check(lsu_load_format(rdata, 2'b10, 3'b001), 32'h0000_1234, t); // LH

        // Tests 12-13: LHU (zero-extend) checks using raw full-word HRDATA
        ahb_read(32'h0000_0010, 3'b101, rdata);
        t = t + 1; check(rdata, 32'h1234_ABCD, t); // raw word unchanged by HSIZE
        t = t + 1; check(lsu_load_format(rdata, 2'b00, 3'b101), 32'h0000_ABCD, t);

        ahb_read(32'h0000_0012, 3'b101, rdata);
        t = t + 1; check(rdata, 32'h1234_ABCD, t); // raw word unchanged by HSIZE
        t = t + 1; check(lsu_load_format(rdata, 2'b10, 3'b101), 32'h0000_1234, t);

        // -------------------------------------------------------
        // Test 14: HTRANS=IDLE suppresses write (active=0, hsel_reg stays 0)
        // -------------------------------------------------------
        ahb_write(32'h0000_0020, 3'b010, 32'hAAAA_AAAA); // known initial value
        HSEL   = 1; HWRITE = 1; HADDR  = 32'h0000_0020;
        HTRANS = 2'b00; HSIZE  = 3'b010;                  // IDLE — no active transfer
        @(posedge HCLK); #1;                               // hsel_reg ← 0
        HWDATA = 32'hDEAD_DEAD;
        HSEL   = 0; HWRITE = 0; HTRANS = 2'b00;
        @(posedge HCLK); #1;                               // no write (hsel_reg=0)
        ahb_read(32'h0000_0020, 3'b010, rdata);
        t = t + 1; check(rdata, 32'hAAAA_AAAA, t);

        // -------------------------------------------------------
        // Test 15: HSEL=0 suppresses write
        // -------------------------------------------------------
        ahb_write(32'h0000_0024, 3'b010, 32'h5555_5555); // known initial value
        HSEL   = 0; HWRITE = 1; HADDR  = 32'h0000_0024;  // slave not selected
        HTRANS = 2'b10; HSIZE = 3'b010;
        @(posedge HCLK); #1;                               // hsel_reg ← 0
        HWDATA = 32'hBEEF_DEAD;
        HSEL   = 0; HWRITE = 0; HTRANS = 2'b00;
        @(posedge HCLK); #1;                               // no write (hsel_reg=0)
        ahb_read(32'h0000_0024, 3'b010, rdata);
        t = t + 1; check(rdata, 32'h5555_5555, t);

        // -------------------------------------------------------
        // Test 16: async reset during data phase clears hsel_reg/hwrite_reg,
        //          suppressing the pending write
        // -------------------------------------------------------
        ahb_write(32'h0000_0028, 3'b010, 32'hBEEF_CAFE); // known initial value
        HSEL   = 1; HWRITE = 1; HADDR  = 32'h0000_0028;
        HTRANS = 2'b10; HSIZE = 3'b010;
        @(posedge HCLK); #1;     // ctrl registered: hsel_reg=1, hwrite_reg=1
        HWDATA  = 32'hDEAD_DEAD;
        HSEL    = 0; HWRITE = 0; HTRANS = 2'b00;
        HRESETn = 0;              // async: hsel_reg→0, hwrite_reg→0 immediately
        #2; HRESETn = 1;
        @(posedge HCLK); #1;     // write block sees hsel_reg=0 → no write
        ahb_read(32'h0000_0028, 3'b010, rdata);
        t = t + 1; check(rdata, 32'hBEEF_CAFE, t);

        // -------------------------------------------------------
        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");

        $finish;
    end

endmodule
