// MEM/WB pipeline register (Phase 6).
// Does not capture load data: with synchronous memory the data only appears
// in the AHB data phase, while the load is in WB.
// Priority: reset -> flush (bubble) -> hold (enable = 0) -> capture.
module mem_wb_reg (
    input         clk,
    input         rst_n,
    input         enable,
    input         flush,

    input  [31:0] result_in,   // write-back value for non-loads; address bits [1:0] for loads
    input  [4:0]  rd_addr_in,
    input  [2:0]  funct3_in,   // load type
    input         MemToReg_in,
    input         RegWrite_in,
    input         valid_in,

    output [31:0] result_out,
    output [4:0]  rd_addr_out,
    output [2:0]  funct3_out,
    output        MemToReg_out,
    output        RegWrite_out,
    output        valid_out
);

    localparam W = 32 + 5 + 3 + 2 + 1;

    wire [W-1:0] d = {result_in, rd_addr_in, funct3_in, MemToReg_in, RegWrite_in, valid_in};

    reg [W-1:0] q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q <= {W{1'b0}};
        else if (flush)
            q <= {W{1'b0}};
        else if (enable)
            q <= d;
    end

    assign {result_out, rd_addr_out, funct3_out, MemToReg_out, RegWrite_out, valid_out} = q;

endmodule
