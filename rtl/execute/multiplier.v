// Multiplier (Phase 2), two cycles in EX.
// Each operand is extended to 33 bits with its sign bit or a zero, then one
// signed 33 x 33 multiply produces every variant. The low 32 bits are the same
// for all signedness combinations, so MUL needs no special case.
// start registers the extended operands in the first EX cycle; the product is
// formed from those registers in the second. A forwarded operand can arrive
// late in the cycle (load data from WB), so the register sits in front of the
// multiply array, where Quartus packs it into the embedded multipliers' input
// registers. done is a level: it stays at 1 until ack (the MUL leaves EX), so
// a done that falls into a bus freeze is never lost.
module multiplier (
    input             clk,
    input             rst_n,
    input             start,    // first EX cycle of a MUL: capture the operands
    input             ack,      // the MUL leaves EX this cycle; clears done
    input      [31:0] a,
    input      [31:0] b,
    input      [1:0]  mul_op,   // 00 MUL, 01 MULH, 10 MULHSU, 11 MULHU
    output     [31:0] result,   // valid while done = 1
    output reg        done
);

    wire a_signed = (mul_op != 2'b11);   // MUL, MULH, MULHSU
    wire b_signed = ~mul_op[1];          // MUL, MULH

    reg signed [32:0] a_ext;
    reg signed [32:0] b_ext;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_ext <= 33'b0;
            b_ext <= 33'b0;
            done  <= 1'b0;
        end else begin
            if (start) begin
                a_ext <= {a_signed & a[31], a};
                b_ext <= {b_signed & b[31], b};
            end

            if (start)
                done <= 1'b1;
            else if (ack)
                done <= 1'b0;
        end
    end

    // mul_op is held in ID/EX while the MUL waits, so it still selects the half.
    wire signed [65:0] product = a_ext * b_ext;

    assign result = (mul_op == 2'b00) ? product[31:0] : product[63:32];

endmodule
