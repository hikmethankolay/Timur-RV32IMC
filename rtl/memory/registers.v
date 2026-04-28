module registers (
    input clk,
    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    input [4:0] rd_addr,
    input [31:0] rd_data,
    input reg_write,
    output [31:0] rs1_data,
    output [31:0] rs2_data
);

    reg [31:0] regs [31:0];

    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1 ) begin
            regs[i] = 32'b0;
        end
    end

    always @(negedge clk) begin
        if (reg_write && rd_addr != 5'b00000) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // Combinational read — x0 is hardwired to zero
    assign rs1_data = (rs1_addr == 5'b00000) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b00000) ? 32'b0 : regs[rs2_addr];

endmodule