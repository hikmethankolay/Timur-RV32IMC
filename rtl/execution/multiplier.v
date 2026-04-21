module multiplier (
    input  [31:0] a,
    input  [31:0] b,
    input  [1:0]  mul_op,
    output [31:0] result
);

wire signed [32:0] a_signed   = {a[31], a};
wire signed [32:0] b_signed   = {b[31], b};
wire        [32:0] a_unsigned = {1'b0,  a};
wire        [32:0] b_unsigned = {1'b0,  b};

wire signed [65:0] product_ss = a_signed   * b_signed;
wire        [65:0] product_uu = a_unsigned * b_unsigned;
wire signed [65:0] product_su = a_signed   * $signed({1'b0, b});

mux4 #(.WIDTH(32)) result_mux (
    .in0 (product_ss[31:0]),
    .in1 (product_ss[63:32]),
    .in2 (product_su[63:32]),
    .in3 (product_uu[63:32]),
    .sel (mul_op),
    .out (result)
);

endmodule