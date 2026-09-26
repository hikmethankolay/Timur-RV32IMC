`timescale 1ns/1ps
//
// ahb_apb_bridge_tb: IDLE -> SETUP -> ACCESS with one wait state, HREADYOUT
// low in SETUP and in ACCESS until PREADY, back-to-back APB transfers,
// PADDR[15:8] decode with no PSEL for unmapped pages, address phases taken
// only with HSEL, HTRANS[1] and HREADY (Phase 9).
// The bus HREADY is HREADYOUT AND hready_other.
// Vector: see vectors/ahb_apb_bridge_vectors.txt (x = don't care).
//
module ahb_apb_bridge_tb;

    reg         clk, rst_n;
    reg         HSEL, HWRITE, hready_other;
    reg  [31:0] HADDR, HWDATA;
    reg  [1:0]  HTRANS;
    reg         PREADY_UART, PREADY_GPIO, PREADY_DMAC;
    wire [31:0] HRDATA, PADDR, PWDATA;
    wire        HREADYOUT, HRESP, PWRITE, PENABLE, PSEL_UART, PSEL_GPIO, PSEL_DMAC;
    wire        HREADY = HREADYOUT & hready_other;

    ahb_apb_bridge dut (
        .HCLK        (clk),
        .HRESETn     (rst_n),
        .HSEL        (HSEL),
        .HADDR       (HADDR),
        .HTRANS      (HTRANS),
        .HWRITE      (HWRITE),
        .HSIZE       (3'b010),
        .HWDATA      (HWDATA),
        .HREADY      (HREADY),
        .HRDATA      (HRDATA),
        .HREADYOUT   (HREADYOUT),
        .HRESP       (HRESP),
        .PADDR       (PADDR),
        .PWRITE      (PWRITE),
        .PWDATA      (PWDATA),
        .PENABLE     (PENABLE),
        .PSEL_UART   (PSEL_UART),
        .PSEL_GPIO   (PSEL_GPIO),
        .PSEL_DMAC   (PSEL_DMAC),
        .PRDATA_UART (32'h0000AAAA),
        .PRDATA_GPIO (32'h0000BBBB),
        .PRDATA_DMAC (32'h0000CCCC),
        .PREADY_UART (PREADY_UART),
        .PREADY_GPIO (PREADY_GPIO),
        .PREADY_DMAC (PREADY_DMAC)
    );

    always #5 clk = ~clk;

    function match;
        input [31:0] got;
        input [31:0] exp;
        integer i;
        begin
            match = 1'b1;
            for (i = 0; i < 32; i = i + 1)
                if (exp[i] !== 1'bx && got[i] !== exp[i])
                    match = 1'b0;
        end
    endfunction

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      e_hrdata, e_paddr, e_pwdata;
    reg             e_hreadyout, e_pwrite, e_penable, e_psel_uart, e_psel_gpio, e_psel_dmac;
    reg             wait_type, ok;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        {HSEL, HWRITE} = 2'b0;
        hready_other = 1'b1;
        {HADDR, HWDATA} = 64'b0;
        HTRANS = 2'b00;
        {PREADY_UART, PREADY_GPIO, PREADY_DMAC} = 3'b111;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/ahb_apb_bridge_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/ahb_apb_bridge_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %h %b %b %h %b %b %b %b %h %b %h %b %h %b %b %b %b %b",
                            rst_n, HSEL, HADDR, HTRANS, HWRITE, HWDATA, hready_other,
                            PREADY_UART, PREADY_GPIO, PREADY_DMAC,
                            e_hrdata, e_hreadyout, e_paddr, e_pwrite, e_pwdata, e_penable,
                            e_psel_uart, e_psel_gpio, e_psel_dmac, wait_type) == 20) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    ok = match(HRDATA, e_hrdata) && match({31'b0, HREADYOUT}, {31'b0, e_hreadyout}) &&
                         match(PADDR, e_paddr) && match({31'b0, PWRITE}, {31'b0, e_pwrite}) &&
                         match(PWDATA, e_pwdata) && match({31'b0, PENABLE}, {31'b0, e_penable}) &&
                         match({31'b0, PSEL_UART}, {31'b0, e_psel_uart}) &&
                         match({31'b0, PSEL_GPIO}, {31'b0, e_psel_gpio}) &&
                         match({31'b0, PSEL_DMAC}, {31'b0, e_psel_dmac}) && (HRESP === 1'b0);
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL hsel=%b haddr=%h htrans=%b hwrite=%b | got hrdata=%h hreadyout=%b paddr=%h pwrite=%b pwdata=%h penable=%b psel=%b%b%b | expected %h %b %h %b %h %b %b%b%b",
                                 HSEL, HADDR, HTRANS, HWRITE, HRDATA, HREADYOUT, PADDR, PWRITE, PWDATA,
                                 PENABLE, PSEL_UART, PSEL_GPIO, PSEL_DMAC,
                                 e_hrdata, e_hreadyout, e_paddr, e_pwrite, e_pwdata, e_penable,
                                 e_psel_uart, e_psel_gpio, e_psel_dmac);
                    end else
                        $display("PASS hsel=%b haddr=%h htrans=%b hwrite=%b wait=%b | hreadyout=%b penable=%b psel=%b%b%b",
                                 HSEL, HADDR, HTRANS, HWRITE, wait_type, HREADYOUT, PENABLE,
                                 PSEL_UART, PSEL_GPIO, PSEL_DMAC);
                end
            end
            $fclose(fd);
        end

        if (total == 0)
            $display("FAIL no test vectors were applied");
        if (failed == 0 && total > 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $stop;
    end

endmodule
