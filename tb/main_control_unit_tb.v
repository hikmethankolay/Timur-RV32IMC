`timescale 1ns/1ps
//
// main_control_unit_tb — vector-driven regression for the main_control_unit.
// Purely combinational: apply {opcode, funct3, funct7, rs2_addr}, wait #10, check all 12 control outputs.
// Vector format (all hex except single-bit fields which are binary):
//   opcode funct3 funct7 rs2_addr Branch MemRead MemToReg ALUOp MemWrite ALUSrc RegWrite CSRWrite CSROp IsECALL IsEBREAK IsMRET
//
module main_control_unit_tb;

    reg  [6:0] opcode;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    reg  [4:0] rs2_addr;
    wire        Branch;
    wire        MemRead;
    wire        MemToReg;
    wire [1:0]  ALUOp;
    wire        MemWrite;
    wire        ALUSrc;
    wire        RegWrite;
    wire        CSRWrite;
    wire [1:0]  CSROp;
    wire        IsECALL;
    wire        IsEBREAK;
    wire        IsMRET;

    main_control_unit dut (
        .opcode   (opcode),
        .funct3   (funct3),
        .funct7   (funct7),
        .rs2_addr (rs2_addr),
        .Branch   (Branch),
        .MemRead  (MemRead),
        .MemToReg (MemToReg),
        .ALUOp    (ALUOp),
        .MemWrite (MemWrite),
        .ALUSrc   (ALUSrc),
        .RegWrite (RegWrite),
        .CSRWrite (CSRWrite),
        .CSROp    (CSROp),
        .IsECALL  (IsECALL),
        .IsEBREAK (IsEBREAK),
        .IsMRET   (IsMRET)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    task run_vectors(input [8*64-1:0] filename);
        reg [6:0] op_tmp;
        reg [2:0] f3_tmp;
        reg [6:0] f7_tmp;
        reg [4:0] rs2_tmp;
        reg        exp_Branch, exp_MemRead, exp_MemToReg;
        reg [1:0]  exp_ALUOp;
        reg        exp_MemWrite, exp_ALUSrc, exp_RegWrite, exp_CSRWrite;
        reg [1:0]  exp_CSROp;
        reg        exp_IsECALL, exp_IsEBREAK, exp_IsMRET;
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
                        r = $sscanf(line, "%h %h %h %h %b %b %b %h %b %b %b %b %h %b %b %b",
                                    op_tmp, f3_tmp, f7_tmp, rs2_tmp,
                                    exp_Branch, exp_MemRead, exp_MemToReg,
                                    exp_ALUOp,
                                    exp_MemWrite, exp_ALUSrc, exp_RegWrite,
                                    exp_CSRWrite, exp_CSROp,
                                    exp_IsECALL, exp_IsEBREAK, exp_IsMRET);
                        if (r == 16) begin
                            opcode   = op_tmp;
                            funct3   = f3_tmp;
                            funct7   = f7_tmp;
                            rs2_addr = rs2_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (Branch   !== exp_Branch   ||
                                MemRead  !== exp_MemRead  ||
                                MemToReg !== exp_MemToReg ||
                                ALUOp    !== exp_ALUOp    ||
                                MemWrite !== exp_MemWrite ||
                                ALUSrc   !== exp_ALUSrc   ||
                                RegWrite !== exp_RegWrite ||
                                CSRWrite !== exp_CSRWrite ||
                                CSROp    !== exp_CSROp    ||
                                IsECALL  !== exp_IsECALL  ||
                                IsEBREAK !== exp_IsEBREAK ||
                                IsMRET   !== exp_IsMRET) begin
                                $display("FAIL test %0d: op=%02h f3=%h f7=%02h rs2=%02h",
                                          test_num, op_tmp, f3_tmp, f7_tmp, rs2_tmp);
                                $display("  got  Br=%b MR=%b M2R=%b AOp=%h MW=%b AS=%b RW=%b CSRw=%b CSROp=%h ECALL=%b EBREAK=%b MRET=%b",
                                          Branch, MemRead, MemToReg, ALUOp, MemWrite, ALUSrc, RegWrite,
                                          CSRWrite, CSROp, IsECALL, IsEBREAK, IsMRET);
                                $display("  exp  Br=%b MR=%b M2R=%b AOp=%h MW=%b AS=%b RW=%b CSRw=%b CSROp=%h ECALL=%b EBREAK=%b MRET=%b",
                                          exp_Branch, exp_MemRead, exp_MemToReg, exp_ALUOp,
                                          exp_MemWrite, exp_ALUSrc, exp_RegWrite,
                                          exp_CSRWrite, exp_CSROp,
                                          exp_IsECALL, exp_IsEBREAK, exp_IsMRET);
                                failed = failed + 1;
                            end else begin
                                $display("PASS test %0d: op=%02h f3=%h f7=%02h rs2=%02h | Br=%b MR=%b M2R=%b AOp=%h MW=%b AS=%b RW=%b CSRw=%b CSROp=%h ECALL=%b EBREAK=%b MRET=%b",
                                          test_num, op_tmp, f3_tmp, f7_tmp, rs2_tmp,
                                          Branch, MemRead, MemToReg, ALUOp, MemWrite, ALUSrc, RegWrite,
                                          CSRWrite, CSROp, IsECALL, IsEBREAK, IsMRET);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    initial begin
        opcode   = 7'h0;
        funct3   = 3'h0;
        funct7   = 7'h0;
        rs2_addr = 5'h0;

        run_vectors("tb/vectors/main_control_unit_vectors.txt");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
