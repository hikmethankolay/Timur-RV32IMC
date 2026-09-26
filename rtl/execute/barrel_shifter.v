// 32-bit barrel shifter (Phase 2).
// A left shifter and a right shifter run side by side, each five cascaded
// mux2 stages (shift by 1, 2, 4, 8, 16; one shamt bit per stage). A final mux4
// on shift_type picks the result. Keeping the direction out of the stages
// leaves every stage one 2:1 mux deep; a direction select inside each stage
// doubles the depth, and the shift amount can be forwarded load data that
// arrives late in EX.
// The right shifter fills with the original in[31] for SRA and 0 for SRL;
// shift_type 11 passes the input through.
module barrel_shifter (
    input  [31:0] in,
    input  [4:0]  shamt,
    input  [1:0]  shift_type,   // 00 SLL, 01 SRL, 10 SRA, 11 pass-through
    output [31:0] out
);

    wire        fill = (shift_type == 2'b10) & in[31];
    wire [31:0] l0, l1, l2, l3, l4;      // left stage outputs
    wire [31:0] r0, r1, r2, r3, r4;      // right stage outputs

    // Left: SLL
    mux2 #(.WIDTH(32)) u_left0 (.in0(in), .in1({in[30:0], 1'b0}),  .sel(shamt[0]), .out(l0));
    mux2 #(.WIDTH(32)) u_left1 (.in0(l0), .in1({l0[29:0], 2'b0}),  .sel(shamt[1]), .out(l1));
    mux2 #(.WIDTH(32)) u_left2 (.in0(l1), .in1({l1[27:0], 4'b0}),  .sel(shamt[2]), .out(l2));
    mux2 #(.WIDTH(32)) u_left3 (.in0(l2), .in1({l2[23:0], 8'b0}),  .sel(shamt[3]), .out(l3));
    mux2 #(.WIDTH(32)) u_left4 (.in0(l3), .in1({l3[15:0], 16'b0}), .sel(shamt[4]), .out(l4));

    // Right: SRL, SRA
    mux2 #(.WIDTH(32)) u_right0 (.in0(in), .in1({fill, in[31:1]}),         .sel(shamt[0]), .out(r0));
    mux2 #(.WIDTH(32)) u_right1 (.in0(r0), .in1({{2{fill}}, r0[31:2]}),    .sel(shamt[1]), .out(r1));
    mux2 #(.WIDTH(32)) u_right2 (.in0(r1), .in1({{4{fill}}, r1[31:4]}),    .sel(shamt[2]), .out(r2));
    mux2 #(.WIDTH(32)) u_right3 (.in0(r2), .in1({{8{fill}}, r2[31:8]}),    .sel(shamt[3]), .out(r3));
    mux2 #(.WIDTH(32)) u_right4 (.in0(r3), .in1({{16{fill}}, r3[31:16]}),  .sel(shamt[4]), .out(r4));

    mux4 #(.WIDTH(32)) u_type (
        .in0 (l4),
        .in1 (r4),
        .in2 (r4),
        .in3 (in),
        .sel (shift_type),
        .out (out)
    );

endmodule
