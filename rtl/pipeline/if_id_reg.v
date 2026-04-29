// IF/ID pipeline register: gate=advance when not stalled; flush squashes speculated instr to NOP.
module if_id_reg (
    input         clk_i,
    input         rst_n_i,
    input         gate_i,   // 1 = accept new PC/instr from IF
    input         flush_i,  // 1 = force NOP and clear PC field
    input  [31:0] pc_in,    // Delayed PC tag from fetch (pairs with instr_in)
    input  [31:0] instr_in,
    output reg [31:0] pc_out,
    output reg [31:0] instr_out
);
    localparam NOP = 32'h00000013;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pc_out    <= 32'b0;
            instr_out <= NOP;
        end else if (flush_i) begin
            pc_out    <= 32'b0;
            instr_out <= NOP;
        end else if (gate_i) begin
            pc_out    <= pc_in;
            instr_out <= instr_in;
        end
    end
endmodule
