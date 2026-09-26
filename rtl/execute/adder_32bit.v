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

    wire [31:0] b_eff = b ^ {32{sub}};
    wire [32:0] sum   = {1'b0, a} + {1'b0, b_eff} + {32'b0, sub};

    assign result   = sum[31:0];
    assign cout     = sum[32];
    assign overflow = (b_eff[31] == a[31]) && (result[31] != a[31]);

endmodule
