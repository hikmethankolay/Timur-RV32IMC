// 32-bit logarithmic barrel: three type-specific trees, one 4-way type mux at output
// (shift_type 11 = bypass to in, matching prior per-stage in3=in behaviour).
module barrel_shifter (
    input [31:0] in,
    input [4:0] shamt,
    input [1:0] shift_type,
    output [31:0] out
);

    // --- SLL path ------------------------------------------------------------
    wire [31:0] ls0, ls1, ls2, ls3;
    wire [31:0] lsll0 = {in[30:0], 1'b0};
    mux2 #(.WIDTH(32)) lm0 (.in0(in), .in1(lsll0), .sel(shamt[0]), .out(ls0));
    wire [31:0] lsll1 = {ls0[29:0], 2'b0};
    mux2 #(.WIDTH(32)) lm1 (.in0(ls0), .in1(lsll1), .sel(shamt[1]), .out(ls1));
    wire [31:0] lsll2 = {ls1[27:0], 4'b0};
    mux2 #(.WIDTH(32)) lm2 (.in0(ls1), .in1(lsll2), .sel(shamt[2]), .out(ls2));
    wire [31:0] lsll3 = {ls2[23:0], 8'b0};
    mux2 #(.WIDTH(32)) lm3 (.in0(ls2), .in1(lsll3), .sel(shamt[3]), .out(ls3));
    wire [31:0] lsll4 = {ls3[15:0], 16'b0};
    wire [31:0] out_sll;
    mux2 #(.WIDTH(32)) lm4 (.in0(ls3), .in1(lsll4), .sel(shamt[4]), .out(out_sll));

    // --- SRL path ------------------------------------------------------------
    wire [31:0] rs0, rs1, rs2, rs3;
    wire [31:0] lsrl0 = {1'b0, in[31:1]};
    mux2 #(.WIDTH(32)) rm0 (.in0(in), .in1(lsrl0), .sel(shamt[0]), .out(rs0));
    wire [31:0] lsrl1 = {2'b0, rs0[31:2]};
    mux2 #(.WIDTH(32)) rm1 (.in0(rs0), .in1(lsrl1), .sel(shamt[1]), .out(rs1));
    wire [31:0] lsrl2 = {4'b0, rs1[31:4]};
    mux2 #(.WIDTH(32)) rm2 (.in0(rs1), .in1(lsrl2), .sel(shamt[2]), .out(rs2));
    wire [31:0] lsrl3 = {8'b0, rs2[31:8]};
    mux2 #(.WIDTH(32)) rm3 (.in0(rs2), .in1(lsrl3), .sel(shamt[3]), .out(rs3));
    wire [31:0] lsrl4 = {16'b0, rs3[31:16]};
    wire [31:0] out_srl;
    mux2 #(.WIDTH(32)) rm4 (.in0(rs3), .in1(lsrl4), .sel(shamt[4]), .out(out_srl));

    // --- SRA path (sign MSB from original input, same as prior RTL) --------
    wire [31:0] as0, as1, as2, as3;
    wire [31:0] lsra0 = {{1{in[31]}}, in[31:1]};
    mux2 #(.WIDTH(32)) am0 (.in0(in), .in1(lsra0), .sel(shamt[0]), .out(as0));
    wire [31:0] lsra1 = {{2{in[31]}}, as0[31:2]};
    mux2 #(.WIDTH(32)) am1 (.in0(as0), .in1(lsra1), .sel(shamt[1]), .out(as1));
    wire [31:0] lsra2 = {{4{in[31]}}, as1[31:4]};
    mux2 #(.WIDTH(32)) am2 (.in0(as1), .in1(lsra2), .sel(shamt[2]), .out(as2));
    wire [31:0] lsra3 = {{8{in[31]}}, as2[31:8]};
    mux2 #(.WIDTH(32)) am3 (.in0(as2), .in1(lsra3), .sel(shamt[3]), .out(as3));
    wire [31:0] lsra4 = {{16{in[31]}}, as3[31:16]};
    wire [31:0] out_sra;
    mux2 #(.WIDTH(32)) am4 (.in0(as3), .in1(lsra4), .sel(shamt[4]), .out(out_sra));

    mux4 #(.WIDTH(32)) u_type (
        .in0(out_sll),
        .in1(out_srl),
        .in2(out_sra),
        .in3(in      ),
        .sel (shift_type),
        .out (out     )
    );

endmodule
