// Single-cycle RV32M multiply: MUL, MULH, MULHSU, MULHU (mul_op from ALUControl[1:0]).
// 33-bit sign/zero-extended operands; product is combinational for timing closure on one EX cycle.
module multiplier (
    input  [31:0] a,
    input  [31:0] b,
    input  [1:0]  mul_op,
    output [31:0] result
);

    wire a_is_signed = (mul_op == 2'b01) || (mul_op == 2'b10); // MULH, MULHSU
    wire b_is_signed = (mul_op == 2'b01);                      // MULH only

    wire signed [32:0] a_ext = {a_is_signed & a[31], a};
    wire signed [32:0] b_ext = {b_is_signed & b[31], b};

    (* multstyle = "dsp" *) wire signed [65:0] product = a_ext * b_ext;

    assign result = (mul_op == 2'b00) ? product[31:0] : product[63:32];

endmodule
