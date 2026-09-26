`timescale 1ns/1ps
//
// branch_condition_evaluator_tb: all six branch conditions for every
// combination of the compare results, and the reserved funct3 values (Phase 2).
// Vector: equal less (bin) BranchType(bin) BranchTaken(bin).
//
module branch_condition_evaluator_tb;

    reg        equal, less;
    reg  [2:0] BranchType;
    wire       BranchTaken;

    branch_condition_evaluator dut (
        .equal       (equal),
        .less        (less),
        .BranchType  (BranchType),
        .BranchTaken (BranchTaken)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg             exp_taken;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        {equal, less} = 2'b0;
        BranchType = 3'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/branch_condition_evaluator_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/branch_condition_evaluator_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b %b", equal, less, BranchType, exp_taken) == 4) begin
                    #10;
                    total = total + 1;
                    if (BranchTaken !== exp_taken) begin
                        failed = failed + 1;
                        $display("FAIL equal=%b less=%b funct3=%b | got=%b expected=%b",
                                 equal, less, BranchType, BranchTaken, exp_taken);
                    end else
                        $display("PASS equal=%b less=%b funct3=%b | taken=%b",
                                 equal, less, BranchType, BranchTaken);
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
