module adder_32bit (
    input [31:0] a,
    input [31:0] b,
    input sub,
    output [31:0] result,
    output cout,
    output overflow
);

    wire [31:0] b_inverted;
    wire [31:0] b_final;

    assign b_inverted = ~b;
    
    mux2 #(.WIDTH(32)) b_mux(
        .in0 (b),
        .in1 (b_inverted),
        .sel (sub),
        .out (b_final)
    );

    wire [32:0] sum = {1'b0, a} + {1'b0, b_final} + sub;    
    
    assign result = sum[31:0];
    assign cout   = sum[32];
    assign overflow = (~a[31] & ~b_final[31] & result[31]) | ( a[31] &  b_final[31] & ~result[31]);
    
endmodule