`timescale 1ns/1ps
module dmac_ahb_master_tb;

    reg         HCLK, HRESETn;

    // DMA parameter inputs
    reg  [31:0] dmac_src, dmac_dst, dmac_len;
    reg         dmac_enable;

    // AHB slave response
    reg  [31:0] HRDATA;
    reg         HREADY;
    reg         HGRANT;

    // AHB master outputs
    wire [31:0] HADDR;
    wire [1:0]  HTRANS;
    wire        HWRITE;
    wire [2:0]  HSIZE;
    wire [31:0] HWDATA;
    wire        HBUSREQ;

    // Status
    wire        dmac_busy;
    wire        dmac_done;

    dmac_ahb_master dut (
        .HCLK        (HCLK),
        .HRESETn     (HRESETn),
        .dmac_src    (dmac_src),
        .dmac_dst    (dmac_dst),
        .dmac_len    (dmac_len),
        .dmac_enable (dmac_enable),
        .HRDATA      (HRDATA),
        .HREADY      (HREADY),
        .HGRANT      (HGRANT),
        .HADDR       (HADDR),
        .HTRANS      (HTRANS),
        .HWRITE      (HWRITE),
        .HSIZE       (HSIZE),
        .HWDATA      (HWDATA),
        .HBUSREQ     (HBUSREQ),
        .dmac_busy   (dmac_busy),
        .dmac_done   (dmac_done)
    );

    always #5 HCLK = ~HCLK;

    // ── Simple AHB slave model ────────────────────────────────────────────────
    // src_mem holds data DMAC reads; dst_mem captures what DMAC writes.
    reg [31:0] src_mem [0:15];
    reg [31:0] dst_mem [0:15];

    // Slave drives HRDATA for reads; captures HWDATA for writes.
    // Address is pipelined: latch it in address phase, use in data phase.
    reg [31:0] slave_addr_q;
    reg        slave_write_q;

    always @(posedge HCLK) begin
        if (HTRANS[1] && HREADY) begin
            slave_addr_q  <= HADDR;
            slave_write_q <= HWRITE;
        end
    end

    always @(*) begin
        if (slave_write_q)
            HRDATA = 32'h0;
        else
            HRDATA = src_mem[slave_addr_q[5:2]];  // word index from byte addr
    end

    always @(posedge HCLK) begin
        if (slave_write_q && HREADY)
            dst_mem[slave_addr_q[5:2]] <= HWDATA;
    end

    // ── Arbiter model: grant after 2 cycles ───────────────────────────────────
    integer grant_delay_cnt;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HGRANT        <= 1'b0;
            grant_delay_cnt <= 0;
        end else if (HBUSREQ && !HGRANT) begin
            if (grant_delay_cnt == 1) begin
                HGRANT <= 1'b1;
                grant_delay_cnt <= 0;
            end else
                grant_delay_cnt <= grant_delay_cnt + 1;
        end else if (!HBUSREQ)
            HGRANT <= 1'b0;
    end

    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;
    integer i;

    task check;
        input [255:0] label;
        input [31:0]  got, exp;
        begin
            test_num = test_num + 1;
            total    = total    + 1;
            if (got !== exp) begin
                $display("FAIL T%0d %0s: got=0x%08h  exp=0x%08h",
                          test_num, label, got, exp);
                failed = failed + 1;
            end else
                $display("PASS T%0d %0s: 0x%08h", test_num, label, got);
        end
    endtask

    task check1;
        input [255:0] label;
        input         got, exp;
        begin
            test_num = test_num + 1;
            total    = total    + 1;
            if (got !== exp) begin
                $display("FAIL T%0d %0s: got=%b  exp=%b",
                          test_num, label, got, exp);
                failed = failed + 1;
            end else
                $display("PASS T%0d %0s: %b", test_num, label, got);
        end
    endtask

    // Wait for dmac_done or timeout
    task wait_done;
        input integer timeout_cycles;
        integer c;
        begin
            c = 0;
            while (!dmac_done && c < timeout_cycles) begin
                @(posedge HCLK); #1;
                c = c + 1;
            end
            if (c >= timeout_cycles)
                $display("WARNING: dmac_done timeout after %0d cycles", timeout_cycles);
        end
    endtask

    initial begin
        HCLK       = 0;
        HRESETn    = 0;
        dmac_src   = 32'h0;
        dmac_dst   = 32'h0;
        dmac_len   = 32'h0;
        dmac_enable = 1'b0;
        HREADY     = 1'b1;
        HGRANT     = 1'b0;
        HRDATA     = 32'h0;
        slave_addr_q  = 32'h0;
        slave_write_q = 1'b0;

        // Initialize source memory with known pattern
        for (i = 0; i < 16; i = i + 1)
            src_mem[i] = 32'hA000_0000 + i;
        for (i = 0; i < 16; i = i + 1)
            dst_mem[i] = 32'hDEAD_DEAD;

        repeat (4) @(posedge HCLK);
        HRESETn = 1;
        @(posedge HCLK); #1;

        // ── T1: idle state after reset ─────────────────────────────────────────
        check1("T1 idle HBUSREQ=0",   HBUSREQ,   1'b0);
        check1("T1 idle HTRANS IDLE", HTRANS[1],  1'b0);
        check1("T1 idle dmac_busy=0", dmac_busy,  1'b0);
        check1("T1 idle dmac_done=0", dmac_done,  1'b0);

        // ── T2: single-word transfer (len=1) src=0x00 dst=0x40 ────────────────
        dmac_src    = 32'h0000_0000;
        dmac_dst    = 32'h0000_0040;
        dmac_len    = 32'h0000_0001;
        dmac_enable = 1'b1;
        @(posedge HCLK); #1;
        dmac_enable = 1'b0;

        // DMAC should assert HBUSREQ and dmac_busy
        @(posedge HCLK); #1;
        check1("T2 HBUSREQ asserted",  HBUSREQ,  1'b1);
        check1("T2 dmac_busy asserted", dmac_busy, 1'b1);

        // Wait for transfer to complete
        wait_done(50);
        @(posedge HCLK); #1;

        check1("T2 done pulse seen",   dmac_done,  1'b1);
        @(posedge HCLK); #1;
        check1("T2 HBUSREQ released",  HBUSREQ,   1'b0);
        check1("T2 dmac_busy cleared", dmac_busy,  1'b0);

        // Verify destination received source word
        check("T2 word copied",   dst_mem[32'h40>>2], src_mem[0]);

        // ── T3: 4-word burst transfer src=0x00 dst=0x80 ───────────────────────
        for (i = 0; i < 16; i = i + 1) dst_mem[i] = 32'hDEAD_DEAD;

        dmac_src    = 32'h0000_0000;
        dmac_dst    = 32'h0000_0080;
        dmac_len    = 32'h0000_0004;
        dmac_enable = 1'b1;
        @(posedge HCLK); #1;
        dmac_enable = 1'b0;

        wait_done(100);
        @(posedge HCLK); #1;
        check1("T3 done",          dmac_done,  1'b1);
        @(posedge HCLK); #1;
        check1("T3 busy cleared",  dmac_busy,  1'b0);

        for (i = 0; i < 4; i = i + 1)
            check({"T3 word[", i[3:0], "]"},
                  dst_mem[(32'h80>>2)+i], src_mem[i]);

        // ── T4: HREADY=0 wait state during read ───────────────────────────────
        for (i = 0; i < 16; i = i + 1) dst_mem[i] = 32'hDEAD_DEAD;

        dmac_src    = 32'h0000_0000;
        dmac_dst    = 32'h0000_0040;
        dmac_len    = 32'h0000_0001;
        dmac_enable = 1'b1;
        @(posedge HCLK); #1;
        dmac_enable = 1'b0;

        // After grant is given, inject a wait state
        repeat (3) @(posedge HCLK);
        HREADY = 1'b0;
        repeat (2) @(posedge HCLK);
        HREADY = 1'b1;

        wait_done(60);
        @(posedge HCLK); #1;
        check1("T4 done after wait",    dmac_done,  1'b1);
        check("T4 word copied (wait)",  dst_mem[32'h40>>2], src_mem[0]);

        // ── T5: HSIZE is always word (3'b010) ─────────────────────────────────
        // Checked opportunistically during any active transfer
        dmac_src    = 32'h0000_0004;
        dmac_dst    = 32'h0000_0044;
        dmac_len    = 32'h0000_0001;
        dmac_enable = 1'b1;
        @(posedge HCLK); #1;
        dmac_enable = 1'b0;

        // Wait for HTRANS to go active (NONSEQ)
        begin : wait_active
            integer c2;
            c2 = 0;
            while (HTRANS !== 2'b10 && c2 < 20) begin
                @(posedge HCLK); #1;
                c2 = c2 + 1;
            end
        end

        if (HTRANS == 2'b10)
            check("T5 HSIZE=word", {29'b0, HSIZE}, 32'h0000_0002);

        wait_done(40);

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
