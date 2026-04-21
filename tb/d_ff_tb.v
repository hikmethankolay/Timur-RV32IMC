`timescale 1ns/1ps
module d_ff_tb;

    reg        clk, rst_n, en;
    reg  [7:0] d;
    wire [7:0] q;

    d_ff #(.WIDTH(8)) dut (
        .d(d), .clk(clk), .en(en), .rst_n(rst_n), .q(q)
    );

    always #5 clk = ~clk;

    integer file, r, slen;
    reg [7:0] exp;
    reg       wait_type;   // 0 = async check (no clock), 1 = clock then check
    reg [8*256-1:0] line;
    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    initial begin
        clk   = 0;
        rst_n = 1;
        en    = 0;
        d     = 8'h00;

        file = $fopen("tb/vectors/d_ff_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open d_ff_vectors.txt");
            $finish;
        end

        while (!$feof(file)) begin
            line = 0;
            slen = $fgets(line, file);
            if (slen > 0) begin
                r = $sscanf(line, "%b %b %h %h %b", rst_n, en, d, exp, wait_type);
                if (r == 5) begin
                    test_num = test_num + 1;
                    total    = total    + 1;

                    if (wait_type == 1'b0) begin
                        // async check - no clock edge, just wait 3ns
                        #3;
                    end else begin
                        // sequential check - wait for rising edge, then 1ns settle
                        @(posedge clk); #1;
                    end

                    if (q !== exp) begin
                        $display("FAIL test %0d: rst_n=%b en=%b d=%h | got=%h expected=%h",
                                  test_num, rst_n, en, d, q, exp);
                        failed = failed + 1;
                    end else begin
                        $display("PASS test %0d: rst_n=%b en=%b d=%h | q=%h",
                                  test_num, rst_n, en, d, q);
                    end
                end
            end
        end

        $fclose(file);

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");

        $finish;
    end

endmodule
