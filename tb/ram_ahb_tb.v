`timescale 1ns/1ps
//
// ram_ahb_tb: data RAM (Phase 3). One vector per clock cycle, generated
// from an AHB model: every size and offset, untouched lanes preserved,
// store immediately followed by a load of the same word (bypass), address
// phases ignored without HSEL, HTRANS[1] or HREADY.
// Vector: HSEL HTRANS HWRITE HSIZE HREADY HADDR HWDATA check exp_HRDATA wait_type
//
module ram_ahb_tb;

    reg         clk, rst_n;
    reg         HSEL, HWRITE, HREADY;
    reg  [1:0]  HTRANS;
    reg  [2:0]  HSIZE;
    reg  [31:0] HADDR, HWDATA;
    wire [31:0] HRDATA;
    wire        HREADYOUT, HRESP;

    ram_ahb dut (
        .HCLK      (clk),
        .HRESETn   (rst_n),
        .HSEL      (HSEL),
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HWDATA    (HWDATA),
        .HREADY    (HREADY),
        .HRDATA    (HRDATA),
        .HREADYOUT (HREADYOUT),
        .HRESP     (HRESP)
    );

    always #5 clk = ~clk;

    integer         fd, n, i;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg             check;
    reg [31:0]      exp_hrdata;
    reg             wait_type;
    reg             ok;

    initial begin : watchdog
        repeat (2000) @(posedge clk);
        $display("FAIL watchdog: no summary after 2000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        HSEL = 1'b0;
        HTRANS = 2'b00;
        HWRITE = 1'b0;
        HSIZE = 3'b010;
        HREADY = 1'b1;
        HADDR = 32'b0;
        HWDATA = 32'b0;
        total = 0;
        failed = 0;
        // the vectors assume a zeroed RAM
        for (i = 0; i < 16384; i = i + 1) begin
            dut.lane0[i] = 8'h00;
            dut.lane1[i] = 8'h00;
            dut.lane2[i] = 8'h00;
            dut.lane3[i] = 8'h00;
        end
        @(posedge clk);
        #1 rst_n = 1'b1;

        fd = $fopen("vectors/ram_ahb_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/ram_ahb_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b %b %b %h %h %b %h %b", HSEL, HTRANS, HWRITE, HSIZE, HREADY,
                            HADDR, HWDATA, check, exp_hrdata, wait_type) == 10) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    ok = (HREADYOUT === 1'b1) && (HRESP === 1'b0);
                    if (check && HRDATA !== exp_hrdata)
                        ok = 1'b0;
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL hsel=%b htrans=%b hwrite=%b hsize=%b hready=%b haddr=%h hwdata=%h | got hrdata=%h ready=%b resp=%b | expected %h (check=%b)",
                                 HSEL, HTRANS, HWRITE, HSIZE, HREADY, HADDR, HWDATA, HRDATA,
                                 HREADYOUT, HRESP, exp_hrdata, check);
                    end else
                        $display("PASS hsel=%b htrans=%b hwrite=%b hsize=%b hready=%b haddr=%h hwdata=%h | hrdata=%h (check=%b)",
                                 HSEL, HTRANS, HWRITE, HSIZE, HREADY, HADDR, HWDATA, HRDATA, check);
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
