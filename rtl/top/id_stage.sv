import pipeline_pkg::*;

module id_stage(
    input  logic        clk,
    input  logic [31:0] instruction,

    // Writeback feedback
    input  logic [4:0]  rd_addr_wb,
    input  logic [31:0] rd_data,
    input  logic        RegWrite,

    // Single bundled output for the rest of the pipeline
    output id_decoded_t id_decoded
);

    // ─── Parsed fields ───────────────────────────────────────────────
    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [6:0] funct7;

    instr_parser instruction_parser(
        .instruction(instruction),
        .opcode     (opcode),
        .rd         (rd),
        .funct3     (funct3),
        .rs1        (rs1_addr),
        .rs2        (rs2_addr),
        .funct7     (funct7)
    );

    // ─── Immediate generator ─────────────────────────────────────────
    wire [31:0] imm;

    imm_gen immediate_generator(
        .instruction(instruction),
        .opcode     (opcode),
        .imm        (imm)
    );

    // ─── Register file ───────────────────────────────────────────────
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    registers register_file(
        .clk      (clk),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rd_addr  (rd_addr_wb),
        .rd_data  (rd_data),
        .reg_write(RegWrite),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    // ─── Main control unit ───────────────────────────────────────────
    wire        Branch, MemRead, MemToReg, MemWrite, ALUSrc, RegWrite_id;
    wire        CSRWrite, IsECALL, IsEBREAK, IsMRET;
    wire [1:0]  ALUOp, CSROp;

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
        .RegWrite (RegWrite_id),
        .CSRWrite (CSRWrite),
        .CSROp    (CSROp),
        .IsECALL  (IsECALL),
        .IsEBREAK (IsEBREAK),
        .IsMRET   (IsMRET)
    );

    wire [4:0] ALUControl;

    alu_decoder alu_dec(
        .opcode    (opcode),
        .ALUOp     (ALUOp),
        .funct3    (funct3),
        .funct7    (funct7),
        .ALUControl(ALUControl)
    );

    // ─── Pack the ID-stage bundle ────────────────────────────────────
    assign id_decoded.opcode     = opcode;
    assign id_decoded.rd         = rd;
    assign id_decoded.funct3     = funct3;
    assign id_decoded.rs1_addr   = rs1_addr;
    assign id_decoded.rs2_addr   = rs2_addr;
    assign id_decoded.funct7     = funct7;
    assign id_decoded.imm        = imm;
    assign id_decoded.rs1_data   = rs1_data;
    assign id_decoded.rs2_data   = rs2_data;
    assign id_decoded.ALUControl = ALUControl;
    assign id_decoded.ALUSrc     = ALUSrc;
    assign id_decoded.Branch     = Branch;
    assign id_decoded.MemRead    = MemRead;
    assign id_decoded.MemWrite   = MemWrite;
    assign id_decoded.MemToReg   = MemToReg;
    assign id_decoded.RegWrite   = RegWrite_id;
    assign id_decoded.csr_addr   = instruction[31:20];
    assign id_decoded.CSRWrite   = CSRWrite;
    assign id_decoded.CSROp      = CSROp;
    assign id_decoded.IsECALL    = IsECALL;
    assign id_decoded.IsEBREAK   = IsEBREAK;
    assign id_decoded.IsMRET     = IsMRET;

endmodule
