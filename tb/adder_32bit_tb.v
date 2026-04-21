`timescale 1ns/1ps
//
// adder_32bit_tb — vector-driven regression for the 32-bit add/sub unit.
//
module adder_32bit_tb;

    reg  [31:0] a, b;
    reg         sub;
    wire [31:0] result;
    wire        cout;
    wire        overflow;

    adder_32bit dut (
        .a(a),
        .b(b),
        .sub(sub),
        .result(result),
        .cout(cout),
        .overflow(overflow)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    reg [31:0]       exp_res;
    reg              exp_cout;
    reg              exp_ovf;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    initial begin
        a   = 32'h0;
        b   = 32'h0;
        sub = 1'b0;

        file = $fopen("vectors/adder_32bit_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open adder_32bit_vectors.txt");
            failed = failed + 1;
        end else begin
            while (!$feof(file)) begin
                line = 0;
                slen = $fgets(line, file);
                if (slen > 0) begin
                    r = $sscanf(line, "%h %h %b %h %b %b",
                                a, b, sub, exp_res, exp_cout, exp_ovf);
                    if (r == 6) begin
                        #10;
                        test_num = test_num + 1;
                        total    = total    + 1;
                        if (result !== exp_res || cout !== exp_cout
                            || overflow !== exp_ovf) begin
                            $display("FAIL test %0d: a=%h b=%h sub=%b | got res=%h cout=%b ovf=%b | exp res=%h cout=%b ovf=%b",
                                      test_num, a, b, sub,
                                      result, cout, overflow,
                                      exp_res, exp_cout, exp_ovf);
                            failed = failed + 1;
                        end else begin
                            $display("PASS test %0d: a=%h b=%h sub=%b | res=%h cout=%b ovf=%b",
                                      test_num, a, b, sub, result, cout, overflow);
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
