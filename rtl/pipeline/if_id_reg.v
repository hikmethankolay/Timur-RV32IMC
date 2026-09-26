// IF/ID pipeline register (Phase 6).
// Priority: reset -> flush (bubble: valid = 0, instruction = NOP) -> hold
// (enable = 0) -> capture.
module if_id_reg (
    input             clk,
    input             rst_n,
    input             enable,
    input             flush,
    input      [31:0] pc_in,
    input      [31:0] instr_in,
    input             valid_in,
    output reg [31:0] pc_out,
    output reg [31:0] instr_out,
    output reg        valid_out
);

    localparam [31:0] NOP = 32'h00000013;   // ADDI x0, x0, 0

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out    <= 32'b0;
            instr_out <= NOP;
            valid_out <= 1'b0;
        end else if (flush) begin
            pc_out    <= 32'b0;
            instr_out <= NOP;
            valid_out <= 1'b0;
        end else if (enable) begin
            pc_out    <= pc_in;
            instr_out <= instr_in;
            valid_out <= valid_in;
        end
    end

endmodule
