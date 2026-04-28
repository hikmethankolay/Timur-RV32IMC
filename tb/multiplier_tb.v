`timescale 1ns/1ps
//
// multiplier_tb — vector-driven regression for MUL / MULH / MULHSU / MULHU.
// Updated for the 2-cycle pipelined multiplier interface.
//
module multiplier_tb;

    reg         clk, rst_n;
    reg         start;
    reg  [31:0] a, b;
    reg  [1:0]  mul_op;
    wire [31:0] result;
    wire        busy, done;

    multiplier dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (start),
        .a      (a),
        .b      (b),
        .mul_op (mul_op),
        .result (result),
        .busy   (busy),
        .done   (done)
    );

    // 10 ns clock period
    always #5 clk = ~clk;

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    reg [31:0]       exp_res;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    initial begin
        clk    = 0;
        rst_n  = 0;
        start  = 0;
        a      = 32'h0;
        b      = 32'h0;
        mul_op = 2'h0;

        // Reset
        #20;
        rst_n = 1;
        #10;

        file = $fopen("tb/vectors/multiplier_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open multiplier_vectors.txt");
            failed = failed + 1;
        end else begin
            while (!$feof(file)) begin
                line = 0;
                slen = $fgets(line, file);
                if (slen > 0) begin
                    r = $sscanf(line, "%h %h %d %h", a, b, mul_op, exp_res);
                    if (r == 4) begin
                        // Drive inputs and pulse start
                        @(posedge clk);
                        start = 1;
                        @(posedge clk);
                        start = 0;

                        // Wait for done
                        @(posedge done);
                        @(posedge clk); // let result settle

                        test_num = test_num + 1;
                        total    = total    + 1;
                        if (result !== exp_res) begin
                            $display("FAIL test %0d: a=%h b=%h mul_op=%0d | got=%h exp=%h",
                                      test_num, a, b, mul_op, result, exp_res);
                            failed = failed + 1;
                        end else begin
                            $display("PASS test %0d: a=%h b=%h mul_op=%0d | res=%h",
                                      test_num, a, b, mul_op, result);
                        end
                    end
                end
            end
            $fclose(file);
        end

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
