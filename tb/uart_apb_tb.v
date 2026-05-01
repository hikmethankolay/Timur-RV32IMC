`timescale 1ns/1ps
module uart_apb_tb;

    reg        PCLK, PRESETn;
    reg        PSEL, PENABLE, PWRITE;
    reg [7:0]  PADDR;
    reg [31:0] PWDATA;
    wire [31:0] PRDATA;
    wire        PREADY, PSLVERR;
    wire        uart_tx;

    integer failed = 0;
    integer total  = 0;

    uart_apb dut (
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
        .uart_tx (uart_tx),
        .uart_rx (uart_tx)   // loopback: TX wire feeds back into RX
    );

    initial PCLK = 0;
    always #5 PCLK = ~PCLK;   // 100 MHz

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

    task check;
        input [7:0]  got;
        input [7:0]  exp;
        input [63:0] label;
        begin
            total = total + 1;
            if (got !== exp) begin
                $display("FAIL %s: got=0x%02h exp=0x%02h", label, got, exp);
                failed = failed + 1;
            end else begin
                $display("PASS %s: 0x%02h", label, got);
            end
        end
    endtask

    integer   timeout;
    reg [31:0] rd;

    initial begin
        PSEL = 0; PENABLE = 0; PWRITE = 0; PADDR = 0; PWDATA = 0;
        PRESETn = 0;
        repeat (4) @(posedge PCLK);
        PRESETn = 1;
        repeat (2) @(posedge PCLK);

        // Configure baud divisor - small value so simulation is fast
        apb_write(8'h08, 32'd16);

        // ── Test 1: loopback 'A' (0x41) ──────────────────────────────
        apb_write(8'h00, 32'h41);
        timeout = 10000; rd = 0;
        while (!rd[1] && timeout > 0) begin
            apb_read(8'h04, rd);   // poll STATUS bit1 = rx_valid
            timeout = timeout - 1;
        end
        if (timeout == 0) begin
            $display("FAIL loopback_A: timed out waiting for rx_valid");
            failed = failed + 1; total = total + 1;
        end else begin
            apb_read(8'h00, rd);
            check(rd[7:0], 8'h41, "loopback_A");
        end

        // ── Test 2: loopback 0x00 ────────────────────────────────────
        apb_write(8'h00, 32'h00);
        timeout = 10000; rd = 0;
        while (!rd[1] && timeout > 0) begin
            apb_read(8'h04, rd);
            timeout = timeout - 1;
        end
        if (timeout == 0) begin
            $display("FAIL loopback_00: timed out waiting for rx_valid");
            failed = failed + 1; total = total + 1;
        end else begin
            apb_read(8'h00, rd);
            check(rd[7:0], 8'h00, "loopback_00");
        end

        // ── Test 3: loopback 0xFF ────────────────────────────────────
        apb_write(8'h00, 32'hFF);
        timeout = 10000; rd = 0;
        while (!rd[1] && timeout > 0) begin
            apb_read(8'h04, rd);
            timeout = timeout - 1;
        end
        if (timeout == 0) begin
            $display("FAIL loopback_FF: timed out waiting for rx_valid");
            failed = failed + 1; total = total + 1;
        end else begin
            apb_read(8'h00, rd);
            check(rd[7:0], 8'hFF, "loopback_FF");
        end

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");

        $finish;
    end

    initial begin
        #2_000_000;
        $display("TIMEOUT: simulation exceeded 2 ms");
        $finish;
    end

endmodule
