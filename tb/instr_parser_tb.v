`timescale 1ns/1ps
//
// instr_parser_tb: field slicing for R, I, S, B, U, J and SYSTEM encodings
// (Phase 4).
// Vector: instruction opcode rd funct3 rs1 rs2 funct7 (all hex).
//
module instr_parser_tb;

    reg  [31:0] instruction;
    wire [6:0]  opcode, funct7;
    wire [4:0]  rd, rs1, rs2;
    wire [2:0]  funct3;

    instr_parser dut (
        .instruction (instruction),
        .opcode      (opcode),
        .rd          (rd),
        .funct3      (funct3),
        .rs1         (rs1),
        .rs2         (rs2),
        .funct7      (funct7)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [6:0]       exp_opcode, exp_funct7;
    reg [4:0]       exp_rd, exp_rs1, exp_rs2;
    reg [2:0]       exp_funct3;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        instruction = 32'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/instr_parser_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/instr_parser_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %h %h %h %h %h", instruction, exp_opcode, exp_rd,
                            exp_funct3, exp_rs1, exp_rs2, exp_funct7) == 7) begin
                    #10;
                    total = total + 1;
                    if (opcode !== exp_opcode || rd !== exp_rd || funct3 !== exp_funct3 ||
                        rs1 !== exp_rs1 || rs2 !== exp_rs2 || funct7 !== exp_funct7) begin
                        failed = failed + 1;
                        $display("FAIL instr=%h | got op=%h rd=%h f3=%h rs1=%h rs2=%h f7=%h | expected op=%h rd=%h f3=%h rs1=%h rs2=%h f7=%h",
                                 instruction, opcode, rd, funct3, rs1, rs2, funct7,
                                 exp_opcode, exp_rd, exp_funct3, exp_rs1, exp_rs2, exp_funct7);
                    end else
                        $display("PASS instr=%h | op=%h rd=%h f3=%h rs1=%h rs2=%h f7=%h",
                                 instruction, opcode, rd, funct3, rs1, rs2, funct7);
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
