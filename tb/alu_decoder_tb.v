`timescale 1ns/1ps
//
// alu_decoder_tb — vector-driven regression for the alu_decoder module.
// Purely combinational: apply {ALUOp, funct3, funct7}, wait #10, check ALUControl.
// Vector format (hex): ALUOp funct3 funct7 exp_ALUControl
//
module alu_decoder_tb;

    reg  [1:0] ALUOp;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    wire [4:0] ALUControl;

    alu_decoder dut (
        .ALUOp     (ALUOp),
        .funct3    (funct3),
        .funct7    (funct7),
        .ALUControl(ALUControl)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    task run_vectors(input [8*64-1:0] filename);
        reg [1:0] op_tmp;
        reg [2:0] f3_tmp;
        reg [6:0] f7_tmp;
        reg [4:0] exp_ctrl;
        begin
            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("ERROR: could not open %0s", filename);
                failed = failed + 1;
            end else begin
                while (!$feof(file)) begin
                    line = 0;
                    slen = $fgets(line, file);
                    if (slen > 0) begin
                        r = $sscanf(line, "%h %h %h %h",
                                    op_tmp, f3_tmp, f7_tmp, exp_ctrl);
                        if (r == 4) begin
                            ALUOp  = op_tmp;
                            funct3 = f3_tmp;
                            funct7 = f7_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (ALUControl !== exp_ctrl) begin
                                $display("FAIL test %0d: ALUOp=%02b funct3=%03b funct7=%07b | got ALUControl=%05b | exp %05b",
                                          test_num, ALUOp, funct3, funct7,
                                          ALUControl, exp_ctrl);
                                failed = failed + 1;
                            end else begin
                                $display("PASS test %0d: ALUOp=%02b funct3=%03b funct7=%07b | ALUControl=%05b",
                                          test_num, ALUOp, funct3, funct7,
                                          ALUControl);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    initial begin
        ALUOp  = 2'b00;
        funct3 = 3'b000;
        funct7 = 7'b0000000;

        run_vectors("tb/vectors/alu_decoder_vectors.txt");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
