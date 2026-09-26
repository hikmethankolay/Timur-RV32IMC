// Multiplier (Phase 2), single cycle.
// Each operand is extended to 33 bits with its sign bit or a zero, then one
// signed 33 x 33 multiply produces every variant. The low 32 bits are the same
// for all signedness combinations, so MUL needs no special case.
module multiplier (
    input  [31:0] a,
    input  [31:0] b,
    input  [1:0]  mul_op,   // 00 MUL, 01 MULH, 10 MULHSU, 11 MULHU
    output [31:0] result
);

    wire a_signed = (mul_op != 2'b11);   // MUL, MULH, MULHSU
    wire b_signed = ~mul_op[1];          // MUL, MULH

    wire signed [32:0] a_ext   = {a_signed & a[31], a};
    wire signed [32:0] b_ext   = {b_signed & b[31], b};
    wire signed [65:0] product = a_ext * b_ext;

    assign result = (mul_op == 2'b00) ? product[31:0] : product[63:32];

endmodule
