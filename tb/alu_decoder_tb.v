`timescale 1ns/1ps
//
// alu_decoder_tb: ALUOp / funct3 / funct7 / op5 to ALUControl (Phase 4),
// including ADDI -5 and ADDI 40 (I-type funct7 must not select SUB or MUL).
// Vector: ALUOp(bin) funct3(bin) funct7(bin) op5(bin) ALUControl(bin).
//
module alu_decoder_tb;

    reg  [1:0] ALUOp;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    reg        op5;
    wire [4:0] ALUControl;

    alu_decoder dut (
        .ALUOp      (ALUOp),
        .funct3     (funct3),
        .funct7     (funct7),
        .op5        (op5),
        .ALUControl (ALUControl)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [4:0]       exp_control;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        ALUOp = 2'b0;
        funct3 = 3'b0;
        funct7 = 7'b0;
        op5 = 1'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/alu_decoder_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/alu_decoder_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b %b %b", ALUOp, funct3, funct7, op5, exp_control) == 5) begin
                    #10;
                    total = total + 1;
                    if (ALUControl !== exp_control) begin
                        failed = failed + 1;
                        $display("FAIL ALUOp=%b funct3=%b funct7=%b op5=%b | got=%b expected=%b",
                                 ALUOp, funct3, funct7, op5, ALUControl, exp_control);
                    end else
                        $display("PASS ALUOp=%b funct3=%b funct7=%b op5=%b | ALUControl=%b",
                                 ALUOp, funct3, funct7, op5, ALUControl);
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
