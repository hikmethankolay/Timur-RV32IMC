`timescale 1ns/1ps
//
// barrel_shifter_tb — vector-driven regression for the 32-bit barrel shifter.
// shift_type: 00=SLL, 01=SRL, 10=SRA, 11=per-stage bypass (RTL mux in3 = in).
//
module barrel_shifter_tb;

    reg  [31:0] din;
    reg  [4:0]  shamt;
    reg  [1:0]  shift_type;
    wire [31:0] dout;

    barrel_shifter dut (
        .in(din),
        .shamt(shamt),
        .shift_type(shift_type),
        .out(dout)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    reg [31:0]       exp_out;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    initial begin
        din        = 32'h0;
        shamt      = 5'h0;
        shift_type = 2'h0;

        file = $fopen("tb/vectors/barrel_shifter_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open barrel_shifter_vectors.txt");
            failed = failed + 1;
        end else begin
            while (!$feof(file)) begin
                line = 0;
                slen = $fgets(line, file);
                if (slen > 0) begin
                    r = $sscanf(line, "%h %d %b %h",
                                din, shamt, shift_type, exp_out);
                    if (r == 4) begin
                        #10;
                        test_num = test_num + 1;
                        total    = total    + 1;
                        if (dout !== exp_out) begin
                            $display("FAIL test %0d: in=%h shamt=%0d ty=%b | got=%h exp=%h",
                                      test_num, din, shamt, shift_type, dout, exp_out);
                            failed = failed + 1;
                        end else begin
                            $display("PASS test %0d: in=%h shamt=%0d ty=%b | out=%h",
                                      test_num, din, shamt, shift_type, dout);
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
