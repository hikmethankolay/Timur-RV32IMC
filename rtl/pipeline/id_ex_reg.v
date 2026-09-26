// ID/EX pipeline register (Phase 6; CSR and trap fields for Phase 10,
// is_compressed for Phase 11).
// Priority: reset -> flush (bubble: valid = 0 and every control 0) -> hold
// (enable = 0) -> capture.
// All fields are packed into one vector and unpacked straight after it.
module id_ex_reg (
    input         clk,
    input         rst_n,
    input         enable,
    input         flush,

    input  [31:0] pc_in,
    input  [31:0] rs1_data_in,
    input  [31:0] rs2_data_in,
    input  [31:0] imm_in,
    input  [4:0]  rs1_addr_in,
    input  [4:0]  rs2_addr_in,
    input  [4:0]  rd_addr_in,
    input  [2:0]  funct3_in,
    input  [11:0] csr_addr_in,
    input  [4:0]  ALUControl_in,
    input  [1:0]  ALUSrcA_in,
    input         ALUSrcB_in,
    input         Branch_in,
    input         Jump_in,
    input         Jalr_in,
    input         MemRead_in,
    input         MemWrite_in,
    input         MemToReg_in,
    input         RegWrite_in,
    input         CSRAccess_in,
    input  [1:0]  CSROp_in,
    input         CSRImm_in,
    input         IsECALL_in,
    input         IsEBREAK_in,
    input         IsMRET_in,
    input         Illegal_in,
    input         is_compressed_in,
    input         valid_in,

    output [31:0] pc_out,
    output [31:0] rs1_data_out,
    output [31:0] rs2_data_out,
    output [31:0] imm_out,
    output [4:0]  rs1_addr_out,
    output [4:0]  rs2_addr_out,
    output [4:0]  rd_addr_out,
    output [2:0]  funct3_out,
    output [11:0] csr_addr_out,
    output [4:0]  ALUControl_out,
    output [1:0]  ALUSrcA_out,
    output        ALUSrcB_out,
    output        Branch_out,
    output        Jump_out,
    output        Jalr_out,
    output        MemRead_out,
    output        MemWrite_out,
    output        MemToReg_out,
    output        RegWrite_out,
    output        CSRAccess_out,
    output [1:0]  CSROp_out,
    output        CSRImm_out,
    output        IsECALL_out,
    output        IsEBREAK_out,
    output        IsMRET_out,
    output        Illegal_out,
    output        is_compressed_out,
    output        valid_out
);

    localparam W = 32 + 32 + 32 + 32 + 5 + 5 + 5 + 3 + 12   // data and addresses
                 + 5 + 2 + 1                                // ALU controls
                 + 3                                        // Branch, Jump, Jalr
                 + 4                                        // MemRead, MemWrite, MemToReg, RegWrite
                 + 1 + 2 + 1                                // CSRAccess, CSROp, CSRImm
                 + 4                                        // IsECALL, IsEBREAK, IsMRET, Illegal
                 + 1                                        // is_compressed
                 + 1;                                       // valid

    wire [W-1:0] d = {pc_in, rs1_data_in, rs2_data_in, imm_in,
                      rs1_addr_in, rs2_addr_in, rd_addr_in, funct3_in, csr_addr_in,
                      ALUControl_in, ALUSrcA_in, ALUSrcB_in,
                      Branch_in, Jump_in, Jalr_in,
                      MemRead_in, MemWrite_in, MemToReg_in, RegWrite_in,
                      CSRAccess_in, CSROp_in, CSRImm_in,
                      IsECALL_in, IsEBREAK_in, IsMRET_in, Illegal_in,
                      is_compressed_in, valid_in};

    reg [W-1:0] q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q <= {W{1'b0}};
        else if (flush)
            q <= {W{1'b0}};
        else if (enable)
            q <= d;
    end

    assign {pc_out, rs1_data_out, rs2_data_out, imm_out,
            rs1_addr_out, rs2_addr_out, rd_addr_out, funct3_out, csr_addr_out,
            ALUControl_out, ALUSrcA_out, ALUSrcB_out,
            Branch_out, Jump_out, Jalr_out,
            MemRead_out, MemWrite_out, MemToReg_out, RegWrite_out,
            CSRAccess_out, CSROp_out, CSRImm_out,
            IsECALL_out, IsEBREAK_out, IsMRET_out, Illegal_out,
            is_compressed_out, valid_out} = q;

endmodule
