`timescale 1ns/1ps
//
// multiplier_tb: MUL, MULH, MULHSU, MULHU from one 33 x 33 multiply
// (Phase 2). Combinational: apply, wait 10 ns, compare.
// Vector: a(hex) b(hex) mul_op(dec) result(hex).
//
module multiplier_tb;

    reg  [31:0] a, b;
    reg  [1:0]  mul_op;
    wire [31:0] result;

    multiplier dut (
        .a      (a),
        .b      (b),
        .mul_op (mul_op),
        .result (result)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp_result;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        a = 32'b0;
        b = 32'b0;
        mul_op = 2'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/multiplier_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/multiplier_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %d %h", a, b, mul_op, exp_result) == 4) begin
                    #10;
                    total = total + 1;
                    if (result !== exp_result) begin
                        failed = failed + 1;
                        $display("FAIL a=%h b=%h mul_op=%0d | got=%h expected=%h",
                                 a, b, mul_op, result, exp_result);
                    end else
                        $display("PASS a=%h b=%h mul_op=%0d | result=%h",
                                 a, b, mul_op, result);
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
