`timescale 1ns/1ps
//
// ahb_arbiter_tb: CPU wins simultaneous requests, ownership only changes when
// HREADY = 1, the arbiter parks on the CPU, HMASTER_DATA follows HMASTER one
// transfer later (Phase 9).
// Vector: HRESETn HBUSREQ HREADY exp_HMASTER exp_HMASTER_DATA exp_HGRANT (bin) wait_type
//
module ahb_arbiter_tb;

    reg        clk, rst_n;
    reg  [1:0] HBUSREQ;
    reg        HREADY;
    wire       HMASTER, HMASTER_DATA;
    wire [1:0] HGRANT;

    ahb_arbiter dut (
        .HCLK         (clk),
        .HRESETn      (rst_n),
        .HBUSREQ      (HBUSREQ),
        .HREADY       (HREADY),
        .HMASTER      (HMASTER),
        .HMASTER_DATA (HMASTER_DATA),
        .HGRANT       (HGRANT)
    );

    always #5 clk = ~clk;

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg             exp_master, exp_master_data, wait_type;
    reg [1:0]       exp_grant;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        HBUSREQ = 2'b00;
        HREADY = 1'b1;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/ahb_arbiter_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/ahb_arbiter_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b %b %b %b %b", rst_n, HBUSREQ, HREADY,
                            exp_master, exp_master_data, exp_grant, wait_type) == 7) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (HMASTER !== exp_master || HMASTER_DATA !== exp_master_data || HGRANT !== exp_grant) begin
                        failed = failed + 1;
                        $display("FAIL rst_n=%b req=%b hready=%b | got master=%b data=%b grant=%b | expected %b %b %b",
                                 rst_n, HBUSREQ, HREADY, HMASTER, HMASTER_DATA, HGRANT,
                                 exp_master, exp_master_data, exp_grant);
                    end else
                        $display("PASS rst_n=%b req=%b hready=%b | master=%b data=%b grant=%b",
                                 rst_n, HBUSREQ, HREADY, HMASTER, HMASTER_DATA, HGRANT);
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
