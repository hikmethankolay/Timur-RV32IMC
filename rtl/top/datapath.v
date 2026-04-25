module datapath(
    input  clk,
    input  rst_n,
    output [31:0] pc_out
);
    // IF → ID
    wire [31:0] pc_current, pc_plus4, pc_next;
    wire [31:0] instruction;

    // ID → control + EX
    wire [6:0]  opcode;
    wire [4:0]  rd;
    wire [2:0]  funct3;
    wire [4:0]  rs1_addr, rs2_addr;
    wire [6:0]  funct7;
    wire [31:0] imm, rs1_data, rs2_data;

    // Control → EX / MEM / WB
    wire        Branch, MemRead, MemToReg, MemWrite, ALUSrc, RegWrite;
    wire        CSRWrite, IsECALL, IsEBREAK, IsMRET;
    wire [1:0]  ALUOp, CSROp;
    wire [4:0]  ALUControl;

    // EX → MEM / WB
    wire [31:0] alu_result;

    // MEM → WB
    wire [31:0] mem_read_data;

    // WB → ID (writeback)
    wire [31:0] reg_write_data;

    if_stage fetch(
        .clk        (clk),
        .rst_n      (rst_n),
        .pc_next    (pc_next),
        .instruction(instruction),
        .pc_current (pc_current),
        .pc_plus4   (pc_plus4)
    );

    id_stage decode(
        .clk      (clk),
        .instruction(instruction),
        .rd_data  (reg_write_data),
        .RegWrite (RegWrite),
        .opcode   (opcode),
        .rd       (rd),
        .funct3   (funct3),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .funct7   (funct7),
        .imm      (imm),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    main_control_unit control(
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

    alu_decoder alu_dec(
        .ALUOp     (ALUOp),
        .funct3    (funct3),
        .funct7    (funct7),
        .ALUControl(ALUControl)
    );

    ex_stage execute(
        .clk        (clk),
        .rst_n      (rst_n),
        .rs1_data   (rs1_data),
        .rs2_data   (rs2_data),
        .imm        (imm),
        .opcode     (opcode),
        .funct3     (funct3),
        .ALUControl (ALUControl),
        .ALUSrc     (ALUSrc),
        .Branch     (Branch),
        .pc_current (pc_current),
        .pc_plus4   (pc_plus4),
        .alu_result (alu_result),
        .pc_next    (pc_next)
    );

    mem_stage memory(
        .clk          (clk),
        .rst_n        (rst_n),
        .alu_result   (alu_result),
        .rs2_data     (rs2_data),
        .MemRead      (MemRead),
        .MemWrite     (MemWrite),
        .funct3       (funct3),
        .mem_read_data(mem_read_data)
    );

    wb_stage writeback(
        .alu_result    (alu_result),
        .mem_read_data (mem_read_data),
        .pc_plus4      (pc_plus4),
        .MemToReg      (MemToReg),
        .opcode        (opcode),
        .reg_write_data(reg_write_data)
    );

    assign pc_out = pc_current;
endmodule
