// EX/MEM pipeline register (Phase 6).
// No branch or CSR fields: redirects and CSR accesses complete in EX.
// Priority: reset -> flush (bubble) -> hold (enable = 0) -> capture.
module ex_mem_reg (
    input         clk,
    input         rst_n,
    input         enable,
    input         flush,

    input  [31:0] result_in,       // ALU result, link value or old CSR value; also the address
    input  [31:0] store_data_in,   // forwarded rs2
    input  [4:0]  rd_addr_in,
    input  [2:0]  funct3_in,
    input         MemRead_in,
    input         MemWrite_in,
    input         MemToReg_in,
    input         RegWrite_in,
    input         valid_in,

    output [31:0] result_out,
    output [31:0] store_data_out,
    output [4:0]  rd_addr_out,
    output [2:0]  funct3_out,
    output        MemRead_out,
    output        MemWrite_out,
    output        MemToReg_out,
    output        RegWrite_out,
    output        valid_out
);

    localparam W = 32 + 32 + 5 + 3 + 4 + 1;

    wire [W-1:0] d = {result_in, store_data_in, rd_addr_in, funct3_in,
                      MemRead_in, MemWrite_in, MemToReg_in, RegWrite_in,
                      valid_in};

    reg [W-1:0] q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q <= {W{1'b0}};
        else if (flush)
            q <= {W{1'b0}};
        else if (enable)
            q <= d;
    end

    assign {result_out, store_data_out, rd_addr_out, funct3_out,
            MemRead_out, MemWrite_out, MemToReg_out, RegWrite_out,
            valid_out} = q;

endmodule
