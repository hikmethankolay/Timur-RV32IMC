`timescale 1ns/1ps
//
// instr_parser_tb — regression testbench for the instr_parser module.
// Reads 32-bit instruction words and expected field values from a vector
// file and checks all six outputs (opcode, rd, funct3, rs1, rs2, funct7)
// simultaneously.
//
module instr_parser_tb;

    reg  [31:0] instruction;
    wire [6:0]  opcode;
    wire [4:0]  rd;
    wire [2:0]  funct3;
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [6:0]  funct7;

    instr_parser dut (
        .instruction(instruction),
        .opcode     (opcode),
        .rd         (rd),
        .funct3     (funct3),
        .rs1        (rs1),
        .rs2        (rs2),
        .funct7     (funct7)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    task run_vectors(input [8*64-1:0] filename);
        reg [31:0] instr_tmp;
        reg [6:0]  exp_opcode, exp_funct7;
        reg [4:0]  exp_rd, exp_rs1, exp_rs2;
        reg [2:0]  exp_funct3;
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
                        r = $sscanf(line, "%h %h %h %h %h %h %h",
                                    instr_tmp,
                                    exp_opcode, exp_rd, exp_funct3,
                                    exp_rs1, exp_rs2, exp_funct7);
                        if (r == 7) begin
                            instruction = instr_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (opcode  !== exp_opcode  ||
                                rd      !== exp_rd      ||
                                funct3  !== exp_funct3  ||
                                rs1     !== exp_rs1     ||
                                rs2     !== exp_rs2     ||
                                funct7  !== exp_funct7) begin
                                $display("FAIL test %0d: instr=%h | got op=%h rd=%h f3=%h rs1=%h rs2=%h f7=%h | exp op=%h rd=%h f3=%h rs1=%h rs2=%h f7=%h",
                                          test_num, instr_tmp,
                                          opcode, rd, funct3, rs1, rs2, funct7,
                                          exp_opcode, exp_rd, exp_funct3,
                                          exp_rs1, exp_rs2, exp_funct7);
                                failed = failed + 1;
                            end else begin
                                $display("PASS test %0d: instr=%h | op=%h rd=%h f3=%h rs1=%h rs2=%h f7=%h",
                                          test_num, instr_tmp,
                                          opcode, rd, funct3, rs1, rs2, funct7);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    initial begin
        run_vectors("tb/vectors/instr_parser_vectors.txt");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
