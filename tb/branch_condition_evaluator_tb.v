`timescale 1ns/1ps
//
// branch_condition_evaluator_tb — vector-driven regression for all six RISC-V
// branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU) plus the default case.
//
module branch_condition_evaluator_tb;

    reg        zero, alu_result_msb, overflow, cout;
    reg  [2:0] BranchType;
    wire       BranchTaken;

    branch_condition_evaluator dut (
        .zero           (zero),
        .alu_result_msb (alu_result_msb),
        .overflow       (overflow),
        .cout           (cout),
        .BranchType     (BranchType),
        .BranchTaken    (BranchTaken)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    reg              exp_taken;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    initial begin
        zero           = 0;
        alu_result_msb = 0;
        overflow       = 0;
        cout           = 0;
        BranchType     = 3'h0;

        file = $fopen("vectors/branch_condition_evaluator_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open branch_condition_evaluator_vectors.txt");
            failed = failed + 1;
        end else begin
            while (!$feof(file)) begin
                line = 0;
                slen = $fgets(line, file);
                if (slen > 0) begin
                    r = $sscanf(line, "%b %b %b %b %d %b",
                                zero, alu_result_msb, overflow, cout,
                                BranchType, exp_taken);
                    if (r == 6) begin
                        #10;
                        test_num = test_num + 1;
                        total    = total    + 1;
                        if (BranchTaken !== exp_taken) begin
                            $display("FAIL test %0d: zero=%b msb=%b ovf=%b cout=%b BranchType=%0d | got=%b exp=%b",
                                      test_num, zero, alu_result_msb, overflow, cout,
                                      BranchType, BranchTaken, exp_taken);
                            failed = failed + 1;
                        end else begin
                            $display("PASS test %0d: zero=%b msb=%b ovf=%b cout=%b BranchType=%0d | taken=%b",
                                      test_num, zero, alu_result_msb, overflow, cout,
                                      BranchType, BranchTaken);
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
