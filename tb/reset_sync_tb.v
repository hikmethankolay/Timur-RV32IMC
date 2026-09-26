`timescale 1ns/1ps
//
// reset_sync_tb: asynchronous assertion, release on the second rising edge
// (Phase 1).
// Vector: async_rst_n(bin) expected_sync_rst_n(bin) wait_type.
//
module reset_sync_tb;

    reg  clk, async_rst_n;
    wire sync_rst_n;

    reset_sync dut (
        .clk         (clk),
        .async_rst_n (async_rst_n),
        .sync_rst_n  (sync_rst_n)
    );

    always #5 clk = ~clk;

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg             exp;
    reg             wait_type;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        async_rst_n = 1'b1;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/reset_sync_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/reset_sync_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b", async_rst_n, exp, wait_type) == 3) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (sync_rst_n !== exp) begin
                        failed = failed + 1;
                        $display("FAIL async_rst_n=%b wait=%b | got=%b expected=%b",
                                 async_rst_n, wait_type, sync_rst_n, exp);
                    end else
                        $display("PASS async_rst_n=%b wait=%b | sync_rst_n=%b",
                                 async_rst_n, wait_type, sync_rst_n);
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
