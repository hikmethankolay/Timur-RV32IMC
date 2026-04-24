`timescale 1ns/1ps
//
// imm_gen_tb — regression testbench for the imm_gen module.
// Drives both instruction and opcode from a vector file and checks the
// 32-bit sign-extended immediate against the expected value.
//
module imm_gen_tb;

    reg  [31:0] instruction;
    reg  [6:0]  opcode;
    wire [31:0] imm;

    imm_gen dut (
        .instruction(instruction),
        .opcode     (opcode),
        .imm        (imm)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    task run_vectors(input [8*64-1:0] filename);
        reg [31:0] instr_tmp, exp_imm;
        reg [6:0]  opcode_tmp;
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
                        r = $sscanf(line, "%h %h %h",
                                    instr_tmp, opcode_tmp, exp_imm);
                        if (r == 3) begin
                            instruction = instr_tmp;
                            opcode      = opcode_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (imm !== exp_imm) begin
                                $display("FAIL test %0d: instr=%h op=%h | got=%h exp=%h",
                                          test_num, instr_tmp, opcode_tmp, imm, exp_imm);
                                failed = failed + 1;
                            end else begin
                                $display("PASS test %0d: instr=%h op=%h | imm=%h",
                                          test_num, instr_tmp, opcode_tmp, imm);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    initial begin
        run_vectors("tb/vectors/imm_gen_vectors.txt");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
