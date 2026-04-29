`timescale 1ns/1ps
//
// alu_tb — vector-driven regression for the ALU (logic, add/sub, shifts, M-extension mul*, div/rem).
// Combinational ops: apply inputs, wait #10, check result/zero/cout/overflow.
// Mul ops (ALUControl 16-19): single-cycle combinational — same delay as other ops.
// Div/rem ops (ALUControl 20-23): pulse div_start, wait for div_done, check result/zero only
// (cout/overflow reflect the internal adder and are not meaningful for mul/div results).
//
module alu_tb;

    reg         clk, rst_n, div_start;
    reg  [31:0] a, b;
    reg  [4:0]  ALUControl;
    wire [31:0] result;
    wire        zero;
    wire        cout;
    wire        overflow;
    wire        div_busy;
    wire        div_done;

    alu dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (a),
        .b         (b),
        .ALUControl(ALUControl),
        .div_start (div_start),
        .result    (result),
        .zero      (zero),
        .cout      (cout),
        .overflow  (overflow),
        .div_busy  (div_busy),
        .div_done  (div_done)
    );

    always #5 clk = ~clk;

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    reg [31:0]       exp_res;
    reg              exp_zero;
    reg              exp_cout;
    reg              exp_ovf;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;
    reg              is_div_op;
    reg              is_mul_op;

    initial begin
        clk        = 0;
        rst_n      = 0;
        div_start  = 0;
        a          = 32'h0;
        b          = 32'h0;
        ALUControl = 5'h0;

        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        file = $fopen("tb/vectors/alu_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open alu_vectors.txt");
            failed = failed + 1;
        end else begin
            while (!$feof(file)) begin
                line = 0;
                slen = $fgets(line, file);
                if (slen > 0) begin
                    r = $sscanf(line, "%h %h %d %h %b %b %b",
                                a, b, ALUControl, exp_res,
                                exp_zero, exp_cout, exp_ovf);
                    if (r == 7) begin
                        is_div_op = (ALUControl >= 5'd20 && ALUControl <= 5'd23);
                        is_mul_op = (ALUControl >= 5'd16 && ALUControl <= 5'd19);
                        test_num = test_num + 1;
                        total    = total    + 1;

                        if (is_div_op) begin
                            @(posedge clk); #1;
                            div_start = 1;
                            @(posedge clk); #1;
                            div_start = 0;
                            if (!div_done) @(posedge div_done);
                            #1;
                        end else if (is_mul_op) begin
                            #1;
                        end else begin
                            #10;
                        end

                        if (is_div_op || is_mul_op) begin
                            if (result !== exp_res || zero !== exp_zero) begin
                                $display("FAIL test %0d: a=%h b=%h ctrl=%0d | got res=%h z=%b | exp res=%h z=%b",
                                          test_num, a, b, ALUControl,
                                          result, zero, exp_res, exp_zero);
                                failed = failed + 1;
                            end else begin
                                $display("PASS test %0d: a=%h b=%h ctrl=%0d | res=%h z=%b",
                                          test_num, a, b, ALUControl,
                                          result, zero);
                            end
                        end else begin
                            if (result !== exp_res || zero !== exp_zero
                                || cout !== exp_cout
                                || overflow !== exp_ovf) begin
                                $display("FAIL test %0d: a=%h b=%h ctrl=%0d | got res=%h z=%b c=%b v=%b | exp res=%h z=%b c=%b v=%b",
                                          test_num, a, b, ALUControl,
                                          result, zero, cout, overflow,
                                          exp_res, exp_zero, exp_cout, exp_ovf);
                                failed = failed + 1;
                            end else begin
                                $display("PASS test %0d: a=%h b=%h ctrl=%0d | res=%h z=%b c=%b v=%b",
                                          test_num, a, b, ALUControl,
                                          result, zero, cout, overflow);
                            end
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
