`timescale 1ns/1ps
//
// multiplier_tb: MUL, MULH, MULHSU, MULHU from one 33 x 33 multiply
// (Phase 2), two cycles. Per vector: apply the operands and pulse start for
// one cycle, then scramble a and b (the product must come from the
// registered copies), check done and the result, pulse ack and check that
// done clears.
// Vector: a(hex) b(hex) mul_op(dec) result(hex).
//
module multiplier_tb;

    reg         clk, rst_n, start, ack;
    reg  [31:0] a, b;
    reg  [1:0]  mul_op;
    wire [31:0] result;
    wire        done;

    multiplier dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (start),
        .ack    (ack),
        .a      (a),
        .b      (b),
        .mul_op (mul_op),
        .result (result),
        .done   (done)
    );

    always #5 clk = ~clk;

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      a_vec, b_vec, exp_result;
    reg [31:0]      got;
    reg             ok;

    initial begin : watchdog
        #1000000;
        $display("FAIL watchdog: no summary after 1 ms");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        ack = 1'b0;
        a = 32'b0;
        b = 32'b0;
        mul_op = 2'b0;
        total = 0;
        failed = 0;
        @(posedge clk);
        #1 rst_n = 1'b1;

        fd = $fopen("vectors/multiplier_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/multiplier_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %d %h", a_vec, b_vec, mul_op, exp_result) == 4) begin
                    a = a_vec;
                    b = b_vec;
                    ok = (done === 1'b0);
                    start = 1'b1;
                    @(posedge clk);
                    #1 start = 1'b0;
                    a = ~a_vec;
                    b = ~b_vec;
                    #1;
                    got = result;
                    ok = ok && (done === 1'b1) && (got === exp_result);

                    ack = 1'b1;
                    @(posedge clk);
                    #1 ack = 1'b0;
                    ok = ok && (done === 1'b0);

                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL a=%h b=%h mul_op=%0d | got=%h expected=%h (done must rise after start and clear on ack)",
                                 a_vec, b_vec, mul_op, got, exp_result);
                    end else
                        $display("PASS a=%h b=%h mul_op=%0d | result=%h",
                                 a_vec, b_vec, mul_op, got);
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
