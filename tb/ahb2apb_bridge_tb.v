`timescale 1ns/1ps
module ahb2apb_bridge_tb;

    reg         HCLK, HRESETn;
    reg         HSEL;
    reg  [31:0] HADDR;
    reg  [1:0]  HTRANS;
    reg         HWRITE;
    reg  [2:0]  HSIZE;
    reg  [31:0] HWDATA;
    wire [31:0] HRDATA;
    wire        HREADY;
    wire        HRESP;

    wire        PSEL_uart, PSEL_gpio, PSEL_dmac;
    wire        PENABLE, PWRITE;
    wire [7:0]  PADDR;
    wire [31:0] PWDATA;

    reg  [31:0] PRDATA_uart, PRDATA_gpio, PRDATA_dmac;
    reg         PREADY_uart, PREADY_gpio, PREADY_dmac;

    integer failed = 0;
    integer total  = 0;

    ahb2apb_bridge dut (
        .HCLK        (HCLK),
        .HRESETn     (HRESETn),
        .HSEL        (HSEL),
        .HADDR       (HADDR),
        .HTRANS      (HTRANS),
        .HWRITE      (HWRITE),
        .HSIZE       (HSIZE),
        .HWDATA      (HWDATA),
        .HRDATA      (HRDATA),
        .HREADY      (HREADY),
        .HRESP       (HRESP),
        .PSEL_uart   (PSEL_uart),
        .PSEL_gpio   (PSEL_gpio),
        .PSEL_dmac   (PSEL_dmac),
        .PENABLE     (PENABLE),
        .PWRITE      (PWRITE),
        .PADDR       (PADDR),
        .PWDATA      (PWDATA),
        .PRDATA_uart (PRDATA_uart),
        .PREADY_uart (PREADY_uart),
        .PRDATA_gpio (PRDATA_gpio),
        .PREADY_gpio (PREADY_gpio),
        .PRDATA_dmac (PRDATA_dmac),
        .PREADY_dmac (PREADY_dmac)
    );

    initial HCLK = 0;
    always #5 HCLK = ~HCLK;

    task check1;
        input        got;
        input        exp;
        input [127:0] label;
        begin
            total = total + 1;
            if (got !== exp) begin
                $display("FAIL %s: got=%b exp=%b", label, got, exp);
                failed = failed + 1;
            end else
                $display("PASS %s", label);
        end
    endtask

    task check8;
        input [7:0]   got;
        input [7:0]   exp;
        input [127:0] label;
        begin
            total = total + 1;
            if (got !== exp) begin
                $display("FAIL %s: got=0x%02h exp=0x%02h", label, got, exp);
                failed = failed + 1;
            end else
                $display("PASS %s: 0x%02h", label, got);
        end
    endtask

    task check32;
        input [31:0]  got;
        input [31:0]  exp;
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

    initial begin
        HSEL    = 0; HADDR = 0; HTRANS = 2'b00;
        HWRITE  = 0; HSIZE = 3'b010; HWDATA = 0;
        PRDATA_uart = 32'hAAAA_0001;
        PRDATA_gpio = 32'hBBBB_0002;
        PRDATA_dmac = 32'hCCCC_0003;
        PREADY_uart = 1'b1;
        PREADY_gpio = 1'b1;
        PREADY_dmac = 1'b1;
        HRESETn = 0;
        repeat (4) @(posedge HCLK);
        HRESETn = 1;
        repeat (2) @(posedge HCLK);

        // ── Test 1: after reset bridge is idle ────────────────────────
        check1(HREADY,   1'b1, "idle_hready");
        check1(PSEL_uart,1'b0, "idle_psel_uart");
        check1(PSEL_gpio,1'b0, "idle_psel_gpio");
        check1(PSEL_dmac,1'b0, "idle_psel_dmac");
        check1(HRESP,    1'b0, "idle_hresp");

        // ── Test 2: AHB write → UART (HADDR[9:8]=00) ─────────────────
        // Address phase: present address + control
        @(posedge HCLK); #1;
        HSEL = 1; HTRANS = 2'b10; HADDR = 32'h0000_0008; HWRITE = 1;
        // posedge → FSM: IDLE→SETUP, haddr_lat=0x08, hwrite_lat=1

        @(posedge HCLK); #1;
        // state = SETUP: PSEL asserted, PENABLE low, HREADY low
        HWDATA = 32'hDEAD_BEEF;   // data phase: HWDATA valid one cycle after HADDR
        HSEL = 0; HTRANS = 2'b00;
        check1 (PSEL_uart,  1'b1,       "uart_wr_psel");
        check1 (PSEL_gpio,  1'b0,       "uart_wr_no_gpio");
        check1 (PSEL_dmac,  1'b0,       "uart_wr_no_dmac");
        check1 (PENABLE,    1'b0,       "uart_wr_pen_s");
        check1 (PWRITE,     1'b1,       "uart_wr_pwrite");
        check8 (PADDR,      8'h08,      "uart_wr_paddr");
        check1 (HREADY,     1'b0,       "uart_wr_hready_lo");
        // posedge → FSM: SETUP→ACCESS, hwdata_lat=DEAD_BEEF

        @(posedge HCLK); #1;
        // state = ACCESS: PENABLE high, PWDATA valid
        check1 (PENABLE,    1'b1,       "uart_wr_pen_a");
        check32(PWDATA,     32'hDEAD_BEEF, "uart_wr_pwdata");
        // PREADY_uart=1 → posedge → FSM: ACCESS→COMPLETE

        @(posedge HCLK); #1;
        // state = COMPLETE: HREADY=1, APB deasserted
        check1 (HREADY,     1'b1,       "uart_wr_hready_hi");
        check1 (PSEL_uart,  1'b0,       "uart_wr_psel_clr");
        check1 (PENABLE,    1'b0,       "uart_wr_pen_clr");
        @(posedge HCLK); #1;
        // state = IDLE

        // ── Test 3: AHB read → GPIO (HADDR[9:8]=01) ──────────────────
        @(posedge HCLK); #1;
        HSEL = 1; HTRANS = 2'b10; HADDR = 32'h0000_0104; HWRITE = 0;
        // posedge → IDLE→SETUP, haddr_lat=0x104

        @(posedge HCLK); #1;
        // SETUP
        HSEL = 0; HTRANS = 2'b00;
        check1 (PSEL_gpio,  1'b1,       "gpio_rd_psel");
        check1 (PSEL_uart,  1'b0,       "gpio_rd_no_uart");
        check1 (PSEL_dmac,  1'b0,       "gpio_rd_no_dmac");
        check1 (PWRITE,     1'b0,       "gpio_rd_pwrite");
        check8 (PADDR,      8'h04,      "gpio_rd_paddr");
        // posedge → SETUP→ACCESS

        @(posedge HCLK); #1;
        // ACCESS
        check1 (PENABLE,    1'b1,       "gpio_rd_penable");
        check32(HRDATA,     32'hBBBB_0002, "gpio_rd_hrdata");
        // posedge → COMPLETE

        @(posedge HCLK); #1;
        check1 (HREADY,     1'b1,       "gpio_rd_hready");
        @(posedge HCLK); #1;
        // IDLE

        // ── Test 4: AHB write → DMAC (HADDR[9:8]=10) ─────────────────
        @(posedge HCLK); #1;
        HSEL = 1; HTRANS = 2'b10; HADDR = 32'h0000_0200; HWRITE = 1;
        // posedge → IDLE→SETUP

        @(posedge HCLK); #1;
        // SETUP
        HWDATA = 32'hCAFE_BABE;
        HSEL = 0; HTRANS = 2'b00;
        check1 (PSEL_dmac,  1'b1,       "dmac_wr_psel");
        check1 (PSEL_uart,  1'b0,       "dmac_wr_no_uart");
        check1 (PSEL_gpio,  1'b0,       "dmac_wr_no_gpio");
        // posedge → ACCESS

        @(posedge HCLK); #1;
        // ACCESS
        check32(PWDATA,     32'hCAFE_BABE, "dmac_wr_pwdata");
        @(posedge HCLK); #1; // COMPLETE
        @(posedge HCLK); #1; // IDLE

        // ── Test 5: HTRANS=IDLE does not start a transfer ─────────────
        @(posedge HCLK); #1;
        HSEL = 1; HTRANS = 2'b00; HADDR = 32'h0000_0000; HWRITE = 1;
        // posedge → IDLE, HTRANS[1]=0 → state stays IDLE

        @(posedge HCLK); #1;
        check1 (HREADY,     1'b1,       "idle_trans_ready");
        check1 (PSEL_uart,  1'b0,       "idle_trans_nopsel");
        HSEL = 0;
        @(posedge HCLK); #1;

        // ── Test 6: PREADY wait state ─────────────────────────────────
        // Slave holds PREADY low for one extra ACCESS cycle
        PREADY_uart = 1'b0;
        @(posedge HCLK); #1;
        HSEL = 1; HTRANS = 2'b10; HADDR = 32'h0000_0000; HWRITE = 1;
        // posedge → IDLE→SETUP

        @(posedge HCLK); #1;
        // SETUP
        HWDATA = 32'h1234_5678;
        HSEL = 0; HTRANS = 2'b00;
        // posedge → ACCESS (PREADY_uart=0 → stays ACCESS)

        @(posedge HCLK); #1;
        // ACCESS, slave not ready
        check1 (PENABLE,    1'b1,       "wait_penable");
        check1 (HREADY,     1'b0,       "wait_hready_lo");

        PREADY_uart = 1'b1;
        // posedge → pready_sel=1 → ACCESS→COMPLETE

        @(posedge HCLK); #1;
        // COMPLETE
        check1 (HREADY,     1'b1,       "wait_hready_hi");
        @(posedge HCLK); #1;
        // IDLE

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
