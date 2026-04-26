module if_id_reg (
    input         clk,
    input         rst_n,
    input         enable,
    input         flush,
    input  [31:0] pc_in,
    input  [31:0] instr_in,
    output reg [31:0] pc_out,
    output reg [31:0] instr_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out    <= 32'b0;
            instr_out <= 32'h00000013;  // NOP
        end else if (flush) begin
            pc_out    <= 32'b0;
            instr_out <= 32'h00000013;  // NOP
        end else if (enable) begin
            pc_out    <= pc_in;
            instr_out <= instr_in;
        end
    end
endmodule