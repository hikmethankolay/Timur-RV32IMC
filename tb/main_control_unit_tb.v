`timescale 1ns/1ps
//
// main_control_unit_tb: every row of the opcode and SYSTEM tables, and
// illegal encodings with every side-effect control disabled (Phase 4).
// Vector: opcode funct3 funct7 rs2_addr (bin) followed by the expected
// RegWrite ALUSrcA ALUSrcB ALUOp MemRead MemWrite MemToReg Branch Jump Jalr
// CSRAccess CSROp CSRImm IsECALL IsEBREAK IsMRET Illegal (bin).
//
module main_control_unit_tb;

    reg  [6:0] opcode;
    reg  [2:0] funct3;
    reg  [6:0] funct7;
    reg  [4:0] rs2_addr;
    wire       RegWrite, ALUSrcB, MemRead, MemWrite, MemToReg, Branch, Jump, Jalr;
    wire       CSRAccess, CSRImm, IsECALL, IsEBREAK, IsMRET, Illegal;
    wire [1:0] ALUSrcA, ALUOp, CSROp;

    main_control_unit dut (
        .opcode    (opcode),
        .funct3    (funct3),
        .funct7    (funct7),
        .rs2_addr  (rs2_addr),
        .RegWrite  (RegWrite),
        .ALUSrcA   (ALUSrcA),
        .ALUSrcB   (ALUSrcB),
        .ALUOp     (ALUOp),
        .MemRead   (MemRead),
        .MemWrite  (MemWrite),
        .MemToReg  (MemToReg),
        .Branch    (Branch),
        .Jump      (Jump),
        .Jalr      (Jalr),
        .CSRAccess (CSRAccess),
        .CSROp     (CSROp),
        .CSRImm    (CSRImm),
        .IsECALL   (IsECALL),
        .IsEBREAK  (IsEBREAK),
        .IsMRET    (IsMRET),
        .Illegal   (Illegal)
    );

    // outputs packed in the order of the vector file (20 bits)
    wire [19:0] got = {RegWrite, ALUSrcA, ALUSrcB, ALUOp, MemRead, MemWrite, MemToReg,
                       Branch, Jump, Jalr, CSRAccess, CSROp, CSRImm,
                       IsECALL, IsEBREAK, IsMRET, Illegal};

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg             e_rw, e_srcb, e_mr, e_mw, e_m2r, e_br, e_j, e_jr;
    reg             e_csr, e_csrimm, e_ecall, e_ebreak, e_mret, e_ill;
    reg [1:0]       e_srca, e_aluop, e_csrop;
    reg [19:0]      exp;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        opcode = 7'b0;
        funct3 = 3'b0;
        funct7 = 7'b0;
        rs2_addr = 5'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/main_control_unit_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/main_control_unit_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b",
                            opcode, funct3, funct7, rs2_addr,
                            e_rw, e_srca, e_srcb, e_aluop, e_mr, e_mw, e_m2r, e_br, e_j, e_jr,
                            e_csr, e_csrop, e_csrimm, e_ecall, e_ebreak, e_mret, e_ill) == 21) begin
                    exp = {e_rw, e_srca, e_srcb, e_aluop, e_mr, e_mw, e_m2r, e_br, e_j, e_jr,
                           e_csr, e_csrop, e_csrimm, e_ecall, e_ebreak, e_mret, e_ill};
                    #10;
                    total = total + 1;
                    if (got !== exp) begin
                        failed = failed + 1;
                        $display("FAIL opcode=%b funct3=%b funct7=%b rs2=%b | got=%b expected=%b",
                                 opcode, funct3, funct7, rs2_addr, got, exp);
                    end else
                        $display("PASS opcode=%b funct3=%b funct7=%b rs2=%b | controls=%b",
                                 opcode, funct3, funct7, rs2_addr, got);
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
