`timescale 1ns/1ps
//
// dmac_ahb_master_tb: RD_ADDR -> RD_DATA -> WR_ADDR -> WR_DATA per word,
// waiting with its data preserved when the bus is taken, slave wait states,
// LEN = 0 finishing at once, count compared after the increment, parameters
// latched at start (Phase 9).
// Vector: see vectors/dmac_ahb_master_vectors.txt (x = don't care).
//
module dmac_ahb_master_tb;

    reg         clk, rst_n;
    reg  [31:0] dmac_src, dmac_dst, dmac_len, HRDATA;
    reg         dmac_start, HGRANT, HREADY;
    wire        dmac_busy, dmac_done, HBUSREQ, HWRITE;
    wire [31:0] HADDR, HWDATA;
    wire [1:0]  HTRANS;
    wire [2:0]  HSIZE;

    dmac_ahb_master dut (
        .HCLK       (clk),
        .HRESETn    (rst_n),
        .dmac_src   (dmac_src),
        .dmac_dst   (dmac_dst),
        .dmac_len   (dmac_len),
        .dmac_start (dmac_start),
        .dmac_busy  (dmac_busy),
        .dmac_done  (dmac_done),
        .HGRANT     (HGRANT),
        .HREADY     (HREADY),
        .HRDATA     (HRDATA),
        .HBUSREQ    (HBUSREQ),
        .HADDR      (HADDR),
        .HTRANS     (HTRANS),
        .HWRITE     (HWRITE),
        .HSIZE      (HSIZE),
        .HWDATA     (HWDATA)
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
    reg [31:0]      e_haddr, e_hwdata;
    reg [1:0]       e_htrans;
    reg             e_hbusreq, e_hwrite, e_busy, e_done, wait_type, ok;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        {dmac_src, dmac_dst, dmac_len, HRDATA} = 128'b0;
        {dmac_start, HGRANT, HREADY} = 3'b011;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/dmac_ahb_master_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/dmac_ahb_master_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %h %h %h %b %b %b %h %b %h %b %b %h %b %b %b",
                            rst_n, dmac_src, dmac_dst, dmac_len, dmac_start, HGRANT, HREADY, HRDATA,
                            e_hbusreq, e_haddr, e_htrans, e_hwrite, e_hwdata, e_busy, e_done,
                            wait_type) == 16) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    ok = match({31'b0, HBUSREQ}, {31'b0, e_hbusreq}) && match(HADDR, e_haddr) &&
                         match({30'b0, HTRANS}, {30'b0, e_htrans}) && match({31'b0, HWRITE}, {31'b0, e_hwrite}) &&
                         match(HWDATA, e_hwdata) && match({31'b0, dmac_busy}, {31'b0, e_busy}) &&
                         match({31'b0, dmac_done}, {31'b0, e_done}) && (HSIZE === 3'b010);
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL start=%b grant=%b ready=%b hrdata=%h | got req=%b haddr=%h htrans=%b hwrite=%b hwdata=%h busy=%b done=%b | expected %b %h %b %b %h %b %b",
                                 dmac_start, HGRANT, HREADY, HRDATA, HBUSREQ, HADDR, HTRANS, HWRITE, HWDATA,
                                 dmac_busy, dmac_done, e_hbusreq, e_haddr, e_htrans, e_hwrite, e_hwdata, e_busy, e_done);
                    end else
                        $display("PASS start=%b grant=%b ready=%b wait=%b | req=%b haddr=%h htrans=%b hwrite=%b busy=%b done=%b",
                                 dmac_start, HGRANT, HREADY, wait_type, HBUSREQ, HADDR, HTRANS, HWRITE,
                                 dmac_busy, dmac_done);
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
