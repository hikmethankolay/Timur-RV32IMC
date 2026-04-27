module mem_wb_reg (
    input         clk,
    input         rst_n,
    input         flush,
    input         enable,
    input  [31:0] alu_result_in,
    input  [4:0]  rd_addr_in,
    input  [31:0] pc_plus4_in,
    input  [6:0]  opcode_in,
    input         MemToReg_in,
    input         RegWrite_in,
    input  [31:0] csr_rdata_in,
    input         CSRToReg_in,
    output reg [31:0] alu_result_out,
    output reg [4:0]  rd_addr_out,
    output reg [31:0] pc_plus4_out,
    output reg [6:0]  opcode_out,
    output reg        MemToReg_out,
    output reg        RegWrite_out,
    output reg [31:0] csr_rdata_out,
    output reg        CSRToReg_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_out    <= 32'b0;
            rd_addr_out       <= 5'b0;
            pc_plus4_out      <= 32'b0;
            opcode_out        <= 7'b0;
            MemToReg_out      <= 1'b0;
            RegWrite_out      <= 1'b0;
            csr_rdata_out     <= 32'b0;
            CSRToReg_out      <= 1'b0;
        end else if (flush) begin
            alu_result_out    <= 32'b0;
            rd_addr_out       <= 5'b0;
            pc_plus4_out      <= 32'b0;
            opcode_out        <= 7'b0;
            MemToReg_out      <= 1'b0;
            RegWrite_out      <= 1'b0;
            csr_rdata_out     <= 32'b0;
            CSRToReg_out      <= 1'b0;
        end else if (enable) begin
            alu_result_out    <= alu_result_in;
            rd_addr_out       <= rd_addr_in;
            pc_plus4_out      <= pc_plus4_in;
            opcode_out        <= opcode_in;
            MemToReg_out      <= MemToReg_in;
            RegWrite_out      <= RegWrite_in;
            csr_rdata_out     <= csr_rdata_in;
            CSRToReg_out      <= CSRToReg_in;
        end
    end
endmodule
