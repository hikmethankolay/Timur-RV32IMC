`timescale 1ns/1ps
module dmac_apb_tb;

    reg        PCLK, PRESETn;
    reg        PSEL, PENABLE, PWRITE;
    reg [7:0]  PADDR;
    reg [31:0] PWDATA;
    wire [31:0] PRDATA;
    wire        PREADY, PSLVERR;
    wire [31:0] dma_src, dma_dst, dma_len;
    wire        dma_start;
    reg         dma_busy, dma_done;

    integer failed = 0;
    integer total  = 0;

    dmac_apb dut (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PADDR   (PADDR),
        .PWDATA  (PWDATA),
        .PRDATA  (PRDATA),
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR),
        .dma_src (dma_src),
        .dma_dst (dma_dst),
        .dma_len (dma_len),
        .dma_start(dma_start),
        .dma_busy(dma_busy),
        .dma_done(dma_done)
    );

    initial PCLK = 0;
    always #5 PCLK = ~PCLK;

    task apb_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge PCLK); #1;
            PSEL = 1; PENABLE = 0; PWRITE = 1; PADDR = addr; PWDATA = data;
            @(posedge PCLK); #1;
            PENABLE = 1;
            @(posedge PCLK); #1;
            PSEL = 0; PENABLE = 0; PWRITE = 0;
        end
    endtask

    task apb_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge PCLK); #1;
            PSEL = 1; PENABLE = 0; PWRITE = 0; PADDR = addr;
            @(posedge PCLK); #1;
            PENABLE = 1;
            @(posedge PCLK); #1;
            data = PRDATA;
            PSEL = 0; PENABLE = 0;
        end
    endtask

    task check32;
        input [31:0] got;
        input [31:0] exp;
        input [127:0] label;
        begin
            total = total + 1;
            if (got !== exp) begin
                $display("FAIL %s: got=0x%08h exp=0x%08h", label, got, exp);
                failed = failed + 1;
            end else
                $display("PASS %s: 0x%08h", label, got);
        end
    endtask

    reg [31:0] rd;

    initial begin
        PSEL = 0; PENABLE = 0; PWRITE = 0; PADDR = 0; PWDATA = 0;
        dma_busy = 0; dma_done = 0;
        PRESETn = 0;
        repeat (4) @(posedge PCLK);
        PRESETn = 1;
        repeat (2) @(posedge PCLK);

        // ── Test 1: registers latch written values ────────────────────
        apb_write(8'h00, 32'hDEAD_0000);   // SRC
        apb_write(8'h04, 32'hBEEF_0004);   // DST
        apb_write(8'h08, 32'h0000_0100);   // LEN = 256

        apb_read(8'h00, rd); check32(rd, 32'hDEAD_0000, "SRC_readback");
        apb_read(8'h04, rd); check32(rd, 32'hBEEF_0004, "DST_readback");
        apb_read(8'h08, rd); check32(rd, 32'h0000_0100, "LEN_readback");

        // ── Test 2: dma_start pulses for exactly one cycle when not busy
        dma_busy = 0;
        @(posedge PCLK); #1;
        // setup phase
        PSEL = 1; PENABLE = 0; PWRITE = 1; PADDR = 8'h0C; PWDATA = 32'h1;
        @(posedge PCLK); #1;
        // access phase — dma_start should rise here
        PENABLE = 1;
        @(posedge PCLK); #1;
        total = total + 1;
        if (dma_start !== 1'b1) begin
            $display("FAIL start_pulse: dma_start did not assert during access phase");
            failed = failed + 1;
        end else
            $display("PASS start_pulse: dma_start=1 during access phase");
        PSEL = 0; PENABLE = 0; PWRITE = 0;
        // one cycle later it must be gone
        @(posedge PCLK); #1;
        total = total + 1;
        if (dma_start !== 1'b0) begin
            $display("FAIL start_autoclear: dma_start still high after one cycle");
            failed = failed + 1;
        end else
            $display("PASS start_autoclear: dma_start cleared after one cycle");

        // ── Test 3: dma_start blocked when busy ───────────────────────
        dma_busy = 1;
        apb_write(8'h0C, 32'h1);
        total = total + 1;
        if (dma_start !== 1'b0) begin
            $display("FAIL busy_guard: dma_start asserted while dma_busy=1");
            failed = failed + 1;
        end else
            $display("PASS busy_guard: dma_start suppressed while busy");
        dma_busy = 0;

        // ── Test 4: STATUS reflects dma_busy and dma_done ────────────
        dma_busy = 1; dma_done = 0;
        apb_read(8'h10, rd);
        check32(rd, 32'h0000_0001, "STATUS_busy");

        dma_busy = 0; dma_done = 1;
        apb_read(8'h10, rd);
        check32(rd, 32'h0000_0002, "STATUS_done");

        dma_busy = 1; dma_done = 1;
        apb_read(8'h10, rd);
        check32(rd, 32'h0000_0003, "STATUS_both");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");

        $finish;
    end

    initial begin
        #100_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
