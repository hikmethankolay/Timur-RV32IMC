// 32-bit adder / subtractor (Phase 2).
// sub = 1 inverts b with an XOR and supplies the carry-in (two's complement).
module adder_32bit (
    input  [31:0] a,
    input  [31:0] b,
    input         sub,       // 0 = add, 1 = subtract; also the carry-in
    output [31:0] result,
    output        cout,      // bit 32; for subtraction 1 = no borrow (a >= b unsigned)
    output        overflow   // signed overflow
);

    // The carry-in rides in an extra low bit (1 + sub carries out exactly
    // sub), so a + b_eff + sub is one carry chain; a separate "+ sub" term
    // synthesises as a second adder in series.
    wire [31:0] b_eff = b ^ {32{sub}};
    wire [33:0] sum   = {1'b0, a, 1'b1} + {1'b0, b_eff, sub};

    assign result   = sum[32:1];
    assign cout     = sum[33];
    assign overflow = (b_eff[31] == a[31]) && (result[31] != a[31]);

endmodule
