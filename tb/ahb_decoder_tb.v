`timescale 1ns/1ps
// ahb_decoder_tb — combinatorial select decode + registered data-phase mux.
// HSEL_* are combinatorial from HADDR.
// HRDATA/HREADY are from the PREVIOUS active transfer's slave; they hold
// when HTRANS=IDLE so the pipeline's WB stage can read load data safely.
module ahb_decoder_tb;

    reg         HCLK, HRESETn;
    reg  [31:0] HADDR;
    reg  [1:0]  HTRANS;
    reg  [31:0] HRDATA_rom, HRDATA_ram, HRDATA_apb;
    reg         HREADY_rom, HREADY_ram, HREADY_apb;

    wire        HSEL_rom, HSEL_ram, HSEL_apb;
    wire [31:0] HRDATA;
    wire        HREADY;

    ahb_decoder dut (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .HADDR      (HADDR),
        .HTRANS     (HTRANS),
        .HRDATA_rom (HRDATA_rom),
        .HREADY_rom (HREADY_rom),
        .HRDATA_ram (HRDATA_ram),
        .HREADY_ram (HREADY_ram),
        .HRDATA_apb (HRDATA_apb),
        .HREADY_apb (HREADY_apb),
        .HSEL_rom   (HSEL_rom),
        .HSEL_ram   (HSEL_ram),
        .HSEL_apb   (HSEL_apb),
        .HRDATA     (HRDATA),
        .HREADY     (HREADY)
    );

    always #5 HCLK = ~HCLK;

    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    // Check combinatorial address decode (no clock needed)
    task check_sel;
        input [255:0] label;
        input         exp_rom, exp_ram, exp_apb;
        begin
            #1;
            test_num = test_num + 1; total = total + 1;
            if (HSEL_rom !== exp_rom || HSEL_ram !== exp_ram || HSEL_apb !== exp_apb) begin
                $display("FAIL T%0d %0s: SEL(r/m/a)=%b%b%b | exp %b%b%b",
                          test_num, label,
                          HSEL_rom, HSEL_ram, HSEL_apb,
                          exp_rom,  exp_ram,  exp_apb);
                failed = failed + 1;
            end else
                $display("PASS T%0d %0s: SEL=%b%b%b",
                          test_num, label, HSEL_rom, HSEL_ram, HSEL_apb);
        end
    endtask

    // Present an active transfer (HTRANS=NONSEQ), clock once, then check HRDATA/HREADY
    task check_data;
        input [255:0] label;
        input [31:0]  exp_hrdata;
        input         exp_hready;
        begin
            // Address was already set; tick with active HTRANS
            HTRANS = 2'b10;
            @(posedge HCLK); #1;
            test_num = test_num + 1; total = total + 1;
            if (HRDATA !== exp_hrdata || HREADY !== exp_hready) begin
                $display("FAIL T%0d %0s: HRDATA=%h HREADY=%b | exp %h %b",
                          test_num, label, HRDATA, HREADY, exp_hrdata, exp_hready);
                failed = failed + 1;
            end else
                $display("PASS T%0d %0s: HRDATA=%h HREADY=%b",
                          test_num, label, HRDATA, HREADY);
        end
    endtask

    // Clock with HTRANS=IDLE then verify HRDATA/HREADY still holds last slave
    task check_hold;
        input [255:0] label;
        input [31:0]  exp_hrdata;
        input         exp_hready;
        begin
            HTRANS = 2'b00;
            @(posedge HCLK); #1;
            test_num = test_num + 1; total = total + 1;
            if (HRDATA !== exp_hrdata || HREADY !== exp_hready) begin
                $display("FAIL T%0d %0s: HRDATA=%h HREADY=%b | exp %h %b",
                          test_num, label, HRDATA, HREADY, exp_hrdata, exp_hready);
                failed = failed + 1;
            end else
                $display("PASS T%0d %0s: HRDATA=%h HREADY=%b (held)",
                          test_num, label, HRDATA, HREADY);
        end
    endtask

    initial begin
        HCLK       = 0;
        HRESETn    = 0;
        HADDR      = 32'h0;
        HTRANS     = 2'b00;
        HRDATA_rom = 32'hAABBCCDD;
        HRDATA_ram = 32'h11223344;
        HRDATA_apb = 32'h55667788;
        HREADY_rom = 1'b1;
        HREADY_ram = 1'b1;
        HREADY_apb = 1'b1;

        // Release reset
        @(posedge HCLK); @(posedge HCLK); #1;
        HRESETn = 1'b1; #1;

        // ── Combinatorial HSEL decode (no clock needed) ─────────────────────────
        HADDR = 32'h0000_0000; check_sel("ROM base",      1,0,0);
        HADDR = 32'h0000_FFFF; check_sel("ROM top",       1,0,0);
        HADDR = 32'h0001_0000; check_sel("above ROM",     0,0,0);
        HADDR = 32'h2000_0000; check_sel("RAM base",      0,1,0);
        HADDR = 32'h2000_8000; check_sel("RAM mid",       0,1,0);
        HADDR = 32'h2000_FFFF; check_sel("RAM top",       0,1,0);
        HADDR = 32'h1FFF_FFFF; check_sel("below RAM",     0,0,0);
        HADDR = 32'h2001_0000; check_sel("above RAM",     0,0,0);
        HADDR = 32'h4000_0000; check_sel("APB base",      0,0,1);
        HADDR = 32'h4000_0100; check_sel("APB GPIO off",  0,0,1);
        HADDR = 32'h4000_0200; check_sel("APB DMAC off",  0,0,1);
        HADDR = 32'h8000_0000; check_sel("unmapped hi",   0,0,0);
        HADDR = 32'hFFFF_FFFF; check_sel("unmapped top",  0,0,0);

        // ── Registered HRDATA/HREADY: data appears one cycle after address ────────
        // ROM access
        HADDR = 32'h0000_0000;
        check_data("ROM data",           32'hAABBCCDD, 1'b1);

        // ROM top
        HADDR = 32'h0000_FFFF;
        check_data("ROM top data",       32'hAABBCCDD, 1'b1);

        // RAM access
        HADDR = 32'h2000_0000;
        check_data("RAM data",           32'h11223344, 1'b1);

        HADDR = 32'h2000_8000;
        check_data("RAM mid data",       32'h11223344, 1'b1);

        // APB access
        HADDR = 32'h4000_0000;
        check_data("APB data",           32'h55667788, 1'b1);

        HADDR = 32'h4000_0200;
        check_data("APB DMAC data",      32'h55667788, 1'b1);

        // Unmapped → HRDATA=0, HREADY=1
        HADDR = 32'h8000_0000;
        check_data("unmapped data",      32'h0000_0000, 1'b1);

        // ── HTRANS=IDLE hold: HRDATA must hold previous slave until next active ──
        // First do a RAM access to seed HSEL_ram_d
        HADDR = 32'h2000_0004;
        check_data("RAM seed for hold",  32'h11223344, 1'b1);

        // Now switch address to ROM but keep HTRANS=IDLE — HRDATA must hold RAM
        HADDR = 32'h0000_0000;
        check_hold("hold after IDLE (addr→ROM)", 32'h11223344, 1'b1);
        check_hold("hold 2nd IDLE",              32'h11223344, 1'b1);

        // Resume with active ROM transfer — NOW HRDATA switches to ROM
        HADDR = 32'h0000_0000;
        check_data("ROM after hold",     32'hAABBCCDD, 1'b1);

        // ── HREADY wait states propagate from selected slave ─────────────────────
        HREADY_ram = 1'b0;
        HADDR = 32'h2000_0004;
        check_data("RAM wait HREADY",    32'h11223344, 1'b0);
        HREADY_ram = 1'b1;

        HREADY_apb = 1'b0;
        HADDR = 32'h4000_0000;
        check_data("APB wait HREADY",    32'h55667788, 1'b0);
        HREADY_apb = 1'b1;

        HREADY_rom = 1'b0;
        HADDR = 32'h0000_0010;
        check_data("ROM wait HREADY",    32'hAABBCCDD, 1'b0);
        HREADY_rom = 1'b1;

        // Unmapped HREADY=1 even when slaves stall
        HREADY_ram = 1'b0; HREADY_apb = 1'b0;
        HADDR = 32'hC000_0000;
        check_data("unmapped dflt HREADY", 32'h0000_0000, 1'b1);
        HREADY_ram = 1'b1; HREADY_apb = 1'b1;

        // ── Live HRDATA changes reflected ────────────────────────────────────────
        HRDATA_rom = 32'hDEAD_BEEF;
        HADDR = 32'h0000_0000;
        check_data("ROM data update",    32'hDEADBEEF, 1'b1);

        HRDATA_ram = 32'hCAFE_BABE;
        HADDR = 32'h2000_0000;
        check_data("RAM data update",    32'hCAFEBABE, 1'b1);

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
