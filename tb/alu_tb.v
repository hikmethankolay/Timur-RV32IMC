`timescale 1ns/1ps
//
// alu_tb: every ALUControl operation, zero flag and adder flags (Phase 2).
// Combinational operations: apply, wait 10 ns, compare. Divider operations:
// pulse div_start, wait for div_done, compare, then pulse div_ack (the DIV
// leaving EX) and check that div_done clears.
// Vector: a(hex) b(hex) ALUControl(dec) result(hex) zero(bin) cout(bin) overflow(bin).
//
module alu_tb;

    reg         clk, rst_n, div_start, div_ack;
    reg  [31:0] a, b;
    reg  [4:0]  ALUControl;
    wire [31:0] result;
    wire        zero, cout, overflow;
    wire        div_busy, div_done;

    alu dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .a          (a),
        .b          (b),
        .ALUControl (ALUControl),
        .div_start  (div_start),
        .div_ack    (div_ack),
        .result     (result),
        .zero       (zero),
        .cout       (cout),
        .overflow   (overflow),
        .div_busy   (div_busy),
        .div_done   (div_done)
    );

    always #5 clk = ~clk;

    integer         fd, n, guard;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp_result;
    reg             exp_zero, exp_cout, exp_ovf;
    reg             is_div, ok;

    initial begin : watchdog
        repeat (50000) @(posedge clk);
        $display("FAIL watchdog: no summary after 50000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        div_start = 1'b0;
        div_ack = 1'b0;
        a = 32'b0;
        b = 32'b0;
        ALUControl = 5'b0;
        total = 0;
        failed = 0;
        @(posedge clk);
        #1 rst_n = 1'b1;

        fd = $fopen("vectors/alu_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/alu_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %d %h %b %b %b", a, b, ALUControl, exp_result,
                            exp_zero, exp_cout, exp_ovf) == 7) begin
                    is_div = (ALUControl[4:2] == 3'b101);
                    if (is_div) begin
                        div_start = 1'b1;
                        @(posedge clk);
                        #1 div_start = 1'b0;
                        guard = 0;
                        while (!div_done && guard < 100) begin
                            @(posedge clk);
                            #1 guard = guard + 1;
                        end
                    end else
                        #10;

                    ok = (result === exp_result) && (zero === exp_zero) &&
                         (cout === exp_cout) && (overflow === exp_ovf);

                    if (is_div) begin
                        div_ack = 1'b1;
                        @(posedge clk);
                        #1 div_ack = 1'b0;
                        if (div_done !== 1'b0)
                            ok = 1'b0;
                    end

                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL a=%h b=%h ctrl=%0d | got %h z=%b c=%b v=%b | expected %h z=%b c=%b v=%b",
                                 a, b, ALUControl, result, zero, cout, overflow,
                                 exp_result, exp_zero, exp_cout, exp_ovf);
                    end else
                        $display("PASS a=%h b=%h ctrl=%0d | %h z=%b c=%b v=%b",
                                 a, b, ALUControl, result, zero, cout, overflow);
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
