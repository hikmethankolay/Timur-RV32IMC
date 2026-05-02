`timescale 1ns/1ps
module ahb_arbiter_tb;

    reg        HCLK, HRESETn;
    reg  [1:0] HBUSREQ;
    reg  [1:0] HLOCK;
    reg        HREADY;
    wire [1:0] HGRANT;
    wire       HMASTER;
    wire       HMASTLOCK;

    ahb_arbiter dut (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .HBUSREQ   (HBUSREQ),
        .HLOCK     (HLOCK),
        .HREADY    (HREADY),
        .HGRANT    (HGRANT),
        .HMASTER   (HMASTER),
        .HMASTLOCK (HMASTLOCK)
    );

    always #5 HCLK = ~HCLK;

    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    task check_grant;
        input [255:0] label;
        input [1:0]   exp_grant;
        input         exp_master;
        begin
            test_num = test_num + 1;
            total    = total    + 1;
            if (HGRANT !== exp_grant || HMASTER !== exp_master) begin
                $display("FAIL T%0d %0s: HGRANT=%b HMASTER=%b | exp HGRANT=%b HMASTER=%b",
                          test_num, label, HGRANT, HMASTER, exp_grant, exp_master);
                failed = failed + 1;
            end else
                $display("PASS T%0d %0s: HGRANT=%b HMASTER=%b",
                          test_num, label, HGRANT, HMASTER);
        end
    endtask

    task check_lock;
        input [255:0] label;
        input         exp_lock;
        begin
            test_num = test_num + 1;
            total    = total    + 1;
            if (HMASTLOCK !== exp_lock) begin
                $display("FAIL T%0d %0s: HMASTLOCK=%b | exp %b",
                          test_num, label, HMASTLOCK, exp_lock);
                failed = failed + 1;
            end else
                $display("PASS T%0d %0s: HMASTLOCK=%b", test_num, label, HMASTLOCK);
        end
    endtask

    initial begin
        HCLK    = 0;
        HRESETn = 0;
        HBUSREQ = 2'b00;
        HLOCK   = 2'b00;
        HREADY  = 1'b1;

        // ── T1: active-low reset → CPU owns bus immediately ────────────────────
        @(posedge HCLK); #1;
        check_grant("reset: CPU grant", 2'b01, 1'b0);

        // ── T2: release reset, no requests → CPU keeps bus ─────────────────────
        HRESETn = 1;
        @(posedge HCLK); #1;
        check_grant("post-reset no req: CPU", 2'b01, 1'b0);

        // ── T3: CPU requests, bus already with CPU → no change ──────────────────
        HBUSREQ = 2'b01;
        @(posedge HCLK); #1;
        check_grant("CPU req only: stays CPU", 2'b01, 1'b0);

        // ── T4: both request simultaneously → tie goes to CPU ──────────────────
        HBUSREQ = 2'b11; HREADY = 1;
        @(posedge HCLK); #1;
        check_grant("both req tie: CPU wins", 2'b01, 1'b0);

        // ── T5: CPU drops, DMAC requests + HREADY=1 → DMAC gets grant ──────────
        HBUSREQ = 2'b10; HREADY = 1;
        @(posedge HCLK); #1;
        check_grant("DMAC req CPU idle: DMAC grant", 2'b10, 1'b1);

        // ── T6: DMAC has grant, CPU requests → CPU reclaims next HREADY ────────
        HBUSREQ = 2'b11; HREADY = 1;
        @(posedge HCLK); #1;
        check_grant("CPU req while DMAC: CPU reclaims", 2'b01, 1'b0);

        // ── T7: DMAC requests again → DMAC gets grant ──────────────────────────
        HBUSREQ = 2'b10; HREADY = 1;
        @(posedge HCLK); #1;
        check_grant("DMAC req again: DMAC grant", 2'b10, 1'b1);

        // ── T8: HREADY=0 → grant cannot switch even if CPU requests ─────────────
        HBUSREQ = 2'b11; HREADY = 0;
        @(posedge HCLK); #1;
        check_grant("HREADY=0: no switch", 2'b10, 1'b1);

        // ── T9: HREADY=1 → CPU reclaims now ────────────────────────────────────
        HREADY = 1;
        @(posedge HCLK); #1;
        check_grant("HREADY=1 again: CPU reclaims", 2'b01, 1'b0);

        // ── T10: HLOCK[1]=1 prevents switch from DMAC to CPU ───────────────────
        HBUSREQ = 2'b10; HREADY = 1;
        @(posedge HCLK); #1;   // DMAC gets grant
        check_grant("lock setup: DMAC grant", 2'b10, 1'b1);

        HBUSREQ = 2'b11; HLOCK = 2'b10; HREADY = 1;
        @(posedge HCLK); #1;
        check_grant("HLOCK[1]: CPU blocked", 2'b10, 1'b1);
        check_lock("HMASTLOCK while DMAC locked", 1'b1);

        // ── T12: Release lock → CPU reclaims ───────────────────────────────────
        HLOCK = 2'b00;
        @(posedge HCLK); #1;
        check_grant("unlock: CPU reclaims", 2'b01, 1'b0);

        // ── T13: HMASTLOCK when CPU holds bus with HLOCK[0]=1 ──────────────────
        HBUSREQ = 2'b01; HLOCK = 2'b01;
        #1;
        check_lock("HMASTLOCK CPU HLOCK[0]", 1'b1);

        HLOCK = 2'b00;
        #1;
        check_lock("HMASTLOCK CPU no lock", 1'b0);

        // ── T14: DMAC drops request while holding grant → CPU reclaims ──────────
        HBUSREQ = 2'b10; HREADY = 1;
        @(posedge HCLK); #1;   // DMAC gets grant
        HBUSREQ = 2'b00; HREADY = 1;
        @(posedge HCLK); #1;
        check_grant("DMAC drops req: CPU reclaims", 2'b01, 1'b0);

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
