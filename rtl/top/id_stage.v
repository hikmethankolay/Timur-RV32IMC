module id_stage(
    input         clk,
    input  [31:0] instruction,
    // Writeback feedback
    input  [31:0] rd_data,
    input         RegWrite,
    // Outputs
    output [6:0]  opcode,
    output [4:0]  rd,
    output [2:0]  funct3,
    output [4:0]  rs1_addr,
    output [4:0]  rs2_addr,
    output [6:0]  funct7,
    output [31:0] imm,
    output [31:0] rs1_data,
    output [31:0] rs2_data
);
    instr_parser instruction_parser(
        .instruction(instruction),
        .opcode     (opcode),
        .rd         (rd),
        .funct3     (funct3),
        .rs1        (rs1_addr),
        .rs2        (rs2_addr),
        .funct7     (funct7)
    );

    imm_gen immediate_generator(
        .instruction(instruction),
        .opcode     (opcode),
        .imm        (imm)
    );

    registers register_file(
        .clk      (clk),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rd_addr  (rd),
        .rd_data  (rd_data),
        .reg_write(RegWrite),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );
endmodule
