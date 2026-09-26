// 32-bit barrel shifter (Phase 2).
// Five cascaded stages. In each stage a mux4 (select shift_type) forms the
// shifted candidate from the previous stage output, and a mux2 (select one
// shamt bit) chooses between that candidate and the unshifted value.
// SRA fills with the original in[31]; shift_type 11 passes the input through.
module barrel_shifter (
    input  [31:0] in,
    input  [4:0]  shamt,
    input  [1:0]  shift_type,   // 00 SLL, 01 SRL, 10 SRA, 11 pass-through
    output [31:0] out
);

    wire        sign = in[31];
    wire [31:0] s0, s1, s2, s3;          // stage outputs
    wire [31:0] c0, c1, c2, c3, c4;      // shifted candidates

    // Stage 0: shift by 1
    mux4 #(.WIDTH(32)) u_type0 (
        .in0 ({in[30:0], 1'b0}),
        .in1 ({1'b0, in[31:1]}),
        .in2 ({sign, in[31:1]}),
        .in3 (in),
        .sel (shift_type),
        .out (c0)
    );
    mux2 #(.WIDTH(32)) u_amt0 (.in0(in), .in1(c0), .sel(shamt[0]), .out(s0));

    // Stage 1: shift by 2
    mux4 #(.WIDTH(32)) u_type1 (
        .in0 ({s0[29:0], 2'b0}),
        .in1 ({2'b0, s0[31:2]}),
        .in2 ({{2{sign}}, s0[31:2]}),
        .in3 (s0),
        .sel (shift_type),
        .out (c1)
    );
    mux2 #(.WIDTH(32)) u_amt1 (.in0(s0), .in1(c1), .sel(shamt[1]), .out(s1));

    // Stage 2: shift by 4
    mux4 #(.WIDTH(32)) u_type2 (
        .in0 ({s1[27:0], 4'b0}),
        .in1 ({4'b0, s1[31:4]}),
        .in2 ({{4{sign}}, s1[31:4]}),
        .in3 (s1),
        .sel (shift_type),
        .out (c2)
    );
    mux2 #(.WIDTH(32)) u_amt2 (.in0(s1), .in1(c2), .sel(shamt[2]), .out(s2));

    // Stage 3: shift by 8
    mux4 #(.WIDTH(32)) u_type3 (
        .in0 ({s2[23:0], 8'b0}),
        .in1 ({8'b0, s2[31:8]}),
        .in2 ({{8{sign}}, s2[31:8]}),
        .in3 (s2),
        .sel (shift_type),
        .out (c3)
    );
    mux2 #(.WIDTH(32)) u_amt3 (.in0(s2), .in1(c3), .sel(shamt[3]), .out(s3));

    // Stage 4: shift by 16
    mux4 #(.WIDTH(32)) u_type4 (
        .in0 ({s3[15:0], 16'b0}),
        .in1 ({16'b0, s3[31:16]}),
        .in2 ({{16{sign}}, s3[31:16]}),
        .in3 (s3),
        .sel (shift_type),
        .out (c4)
    );
    mux2 #(.WIDTH(32)) u_amt4 (.in0(s3), .in1(c4), .sel(shamt[4]), .out(out));

endmodule
