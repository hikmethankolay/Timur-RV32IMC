module ex_mem_reg (
    input         clk,
    input         rst_n,
    input         flush,
    // datapath
    input  [31:0] alu_result_in,
    input  [31:0] rs2_data_in,
    input  [4:0]  rd_addr_in,
    input  [31:0] pc_plus4_in,
    input  [6:0]  opcode_in,
    input  [31:0] branch_target_in,
    input         BranchTaken_in,
    // control
    input         MemRead_in,
    input         MemWrite_in,
    input         MemToReg_in,
    input         RegWrite_in,
    input  [2:0]  funct3_in,
    input         Branch_in,
    // CSR / privileged
    input  [31:0] csr_wdata_in,
    input  [11:0] csr_addr_in,
    input         CSRWrite_in,
    input  [1:0]  CSROp_in,
    input         IsECALL_in,
    input         IsEBREAK_in,
    input         IsMRET_in,
    // outputs
    output reg [31:0] alu_result_out,
    output reg [31:0] rs2_data_out,
    output reg [4:0]  rd_addr_out,
    output reg [31:0] pc_plus4_out,
    output reg [6:0]  opcode_out,
    output reg [31:0] branch_target_out,
    output reg        BranchTaken_out,
    output reg        MemRead_out,
    output reg        MemWrite_out,
    output reg        MemToReg_out,
    output reg        RegWrite_out,
    output reg [2:0]  funct3_out,
    output reg        Branch_out,
    output reg [31:0] csr_wdata_out,
    output reg [11:0] csr_addr_out,
    output reg        CSRWrite_out,
    output reg [1:0]  CSROp_out,
    output reg        IsECALL_out,
    output reg        IsEBREAK_out,
    output reg        IsMRET_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_out  <= 32'b0;
            rs2_data_out    <= 32'b0;
            rd_addr_out     <= 5'b0;
            pc_plus4_out    <= 32'b0;
            opcode_out      <= 7'b0;
            branch_target_out <= 32'b0;
            BranchTaken_out <= 1'b0;
            MemRead_out     <= 1'b0;
            MemWrite_out    <= 1'b0;
            MemToReg_out    <= 1'b0;
            RegWrite_out    <= 1'b0;
            funct3_out      <= 3'b0;
            Branch_out      <= 1'b0;
            csr_wdata_out   <= 32'b0;
            csr_addr_out    <= 12'b0;
            CSRWrite_out    <= 1'b0;
            CSROp_out       <= 2'b0;
            IsECALL_out     <= 1'b0;
            IsEBREAK_out    <= 1'b0;
            IsMRET_out      <= 1'b0;
        end else if (flush) begin
            alu_result_out  <= 32'b0;
            rs2_data_out    <= 32'b0;
            rd_addr_out     <= 5'b0;
            pc_plus4_out    <= 32'b0;
            opcode_out      <= 7'b0;
            branch_target_out <= 32'b0;
            BranchTaken_out <= 1'b0;
            MemRead_out     <= 1'b0;
            MemWrite_out    <= 1'b0;
            MemToReg_out    <= 1'b0;
            RegWrite_out    <= 1'b0;
            funct3_out      <= 3'b0;
            Branch_out      <= 1'b0;
            csr_wdata_out   <= 32'b0;
            csr_addr_out    <= 12'b0;
            CSRWrite_out    <= 1'b0;
            CSROp_out       <= 2'b0;
            IsECALL_out     <= 1'b0;
            IsEBREAK_out    <= 1'b0;
            IsMRET_out      <= 1'b0;
        end else begin
            alu_result_out  <= alu_result_in;
            rs2_data_out    <= rs2_data_in;
            rd_addr_out     <= rd_addr_in;
            pc_plus4_out    <= pc_plus4_in;
            opcode_out      <= opcode_in;
            branch_target_out <= branch_target_in;
            BranchTaken_out <= BranchTaken_in;
            MemRead_out     <= MemRead_in;
            MemWrite_out    <= MemWrite_in;
            MemToReg_out    <= MemToReg_in;
            RegWrite_out    <= RegWrite_in;
            funct3_out      <= funct3_in;
            Branch_out      <= Branch_in;
            csr_wdata_out   <= csr_wdata_in;
            csr_addr_out    <= csr_addr_in;
            CSRWrite_out    <= CSRWrite_in;
            CSROp_out       <= CSROp_in;
            IsECALL_out     <= IsECALL_in;
            IsEBREAK_out    <= IsEBREAK_in;
            IsMRET_out      <= IsMRET_in;
        end
    end
endmodule