module multiplier (
    input         clk,
    input         rst_n,
    input         start,
    input  [31:0] a,
    input  [31:0] b,
    input  [1:0]  mul_op,
    output reg [31:0] result,
    output reg        busy,
    output reg        done
);

    wire a_is_signed = (mul_op == 2'b01) || (mul_op == 2'b10); // MULH, MULHSU
    wire b_is_signed = (mul_op == 2'b01);                      // MULH only

    // Stage-1 registered operands (map to DSP input registers)
    reg signed [32:0] a_reg, b_reg;
    reg [1:0]         mul_op_reg;
    reg               stage1_valid;

    // Combinational product from registered operands — Quartus infers DSP
    (* multstyle = "dsp" *) wire signed [65:0] product = a_reg * b_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg        <= 33'sb0;
            b_reg        <= 33'sb0;
            mul_op_reg   <= 2'b00;
            stage1_valid <= 1'b0;
            result       <= 32'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;                    // default: clear pulse

            if (start && !busy) begin
                // ── Stage 1: register inputs ──────────────────────
                a_reg        <= {a_is_signed & a[31], a};
                b_reg        <= {b_is_signed & b[31], b};
                mul_op_reg   <= mul_op;
                stage1_valid <= 1'b1;
                busy         <= 1'b1;
            end else if (stage1_valid) begin
                // ── Stage 2: capture product, output result ───────
                result       <= (mul_op_reg == 2'b00) ? product[31:0]
                                                      : product[63:32];
                stage1_valid <= 1'b0;
                busy         <= 1'b0;
                done         <= 1'b1;
            end
        end
    end

endmodule