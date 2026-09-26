`timescale 1ns/1ps
//
// d_ff_tb: d_ff at WIDTH = 8 (Phase 1).
// Vector: rst_n(bin) en(bin) d(hex) expected_q(hex) wait_type.
//
module d_ff_tb;

    reg        clk, rst_n, en;
    reg  [7:0] d;
    wire [7:0] q;

    d_ff #(.WIDTH(8)) dut (
        .d     (d),
        .clk   (clk),
        .en    (en),
        .rst_n (rst_n),
        .q     (q)
    );

    always #5 clk = ~clk;

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [7:0]       exp;
    reg             wait_type;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        en = 1'b0;
        d = 8'h00;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/d_ff_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/d_ff_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %h %h %b", rst_n, en, d, exp, wait_type) == 5) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (q !== exp) begin
                        failed = failed + 1;
                        $display("FAIL rst_n=%b en=%b d=%h wait=%b | got=%h expected=%h",
                                 rst_n, en, d, wait_type, q, exp);
                    end else
                        $display("PASS rst_n=%b en=%b d=%h wait=%b | q=%h",
                                 rst_n, en, d, wait_type, q);
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
