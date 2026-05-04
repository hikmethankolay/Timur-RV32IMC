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

    // Stage 1 — registered operands (DSP input registers)
    reg signed [32:0] a_reg, b_reg;
    reg [1:0]         mul_op_reg;
    reg               stage1_valid;

    // Stage 2 — registered product (DSP output register) and forwarded mul_op
    (* multstyle = "dsp" *) reg signed [65:0] product_q;
    reg [1:0]                                 mul_op_q2;
    reg                                       stage2_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg        <= 33'sb0;
            b_reg        <= 33'sb0;
            mul_op_reg   <= 2'b00;
            mul_op_q2    <= 2'b00;
            product_q    <= 66'sb0;
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            result       <= 32'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;                       // default: clear pulse

            if (start && !busy) begin
                // ── Stage 1: register inputs ──────────────────────
                a_reg        <= {a_is_signed & a[31], a};
                b_reg        <= {b_is_signed & b[31], b};
                mul_op_reg   <= mul_op;
                stage1_valid <= 1'b1;
                busy         <= 1'b1;
            end else if (stage1_valid) begin
                // ── Stage 2: capture product into DSP output reg ──
                product_q    <= a_reg * b_reg;
                mul_op_q2    <= mul_op_reg;
                stage1_valid <= 1'b0;
                stage2_valid <= 1'b1;
            end else if (stage2_valid) begin
                // ── Stage 3: select half, output result ───────────
                result       <= (mul_op_q2 == 2'b00) ? product_q[31:0]
                                                     : product_q[63:32];
                stage2_valid <= 1'b0;
                busy         <= 1'b0;
                done         <= 1'b1;
            end
        end
    end

endmodule
