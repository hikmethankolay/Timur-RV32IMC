// Sequential restoring divider (Phase 2).
// Normal path: start, 32 iterations, sign restore -> done (the DIV sits in EX
// for 35 cycles). Corner cases (divide by zero, signed overflow) load their
// results directly in IDLE and raise done on the next cycle (2 cycles in EX).
// done is a level: it stays at 1 until ack (the DIV leaves EX), so a done that
// falls into a bus freeze is never lost.
module divider (
    input             clk,
    input             rst_n,
    input             start,      // one-cycle start pulse
    input             ack,        // the DIV leaves EX this cycle; clears done
    input      [31:0] a,          // dividend
    input      [31:0] b,          // divisor
    input      [1:0]  div_op,     // 00 DIV, 01 DIVU, 10 REM, 11 REMU
    output reg [31:0] quotient,
    output reg [31:0] remainder,
    output reg        busy,       // 1 while iterating
    output reg        done        // results valid; held until ack
);

    wire        is_signed  = !div_op[0];
    wire        a_negative = a[31] & is_signed;
    wire        b_negative = b[31] & is_signed;
    wire [31:0] a_abs      = a_negative ? (~a + 32'd1) : a;
    wire [31:0] b_abs      = b_negative ? (~b + 32'd1) : b;

    wire div_by_zero     = (b == 32'b0);
    wire signed_overflow = is_signed && (a == 32'h80000000) && (b == 32'hFFFFFFFF);

    localparam IDLE    = 2'b00;
    localparam RUNNING = 2'b01;
    localparam DONE    = 2'b10;

    reg [1:0]  state;
    reg [5:0]  bit_counter;
    reg [31:0] dividend_reg;
    reg [31:0] divisor_reg;
    reg [31:0] quotient_reg;
    reg [32:0] remainder_reg;
    reg        a_neg_reg;
    reg        b_neg_reg;
    reg        is_signed_reg;

    // Shift the partial remainder left and bring in the next dividend bit.
    wire [32:0] shifted = {remainder_reg[31:0], dividend_reg[31]};
    wire [33:0] trial   = {1'b0, shifted} - {2'b0, divisor_reg};
    wire        fits    = ~trial[33];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            busy          <= 1'b0;
            done          <= 1'b0;
            quotient      <= 32'b0;
            remainder     <= 32'b0;
            bit_counter   <= 6'd0;
            dividend_reg  <= 32'b0;
            divisor_reg   <= 32'b0;
            quotient_reg  <= 32'b0;
            remainder_reg <= 33'b0;
            a_neg_reg     <= 1'b0;
            b_neg_reg     <= 1'b0;
            is_signed_reg <= 1'b0;
        end else begin
            if (ack)
                done <= 1'b0;

            case (state)

                IDLE: begin
                    if (start) begin
                        if (div_by_zero) begin
                            quotient  <= 32'hFFFFFFFF;
                            remainder <= a;
                            done      <= 1'b1;
                        end else if (signed_overflow) begin
                            quotient  <= 32'h80000000;
                            remainder <= 32'h00000000;
                            done      <= 1'b1;
                        end else begin
                            busy          <= 1'b1;
                            bit_counter   <= 6'd31;
                            dividend_reg  <= a_abs;
                            divisor_reg   <= b_abs;
                            quotient_reg  <= 32'b0;
                            remainder_reg <= 33'b0;
                            a_neg_reg     <= a_negative;
                            b_neg_reg     <= b_negative;
                            is_signed_reg <= is_signed;
                            state         <= RUNNING;
                        end
                    end
                end

                RUNNING: begin
                    if (fits) begin
                        remainder_reg             <= {1'b0, trial[31:0]};
                        quotient_reg[bit_counter[4:0]] <= 1'b1;
                    end else begin
                        remainder_reg             <= shifted;
                        quotient_reg[bit_counter[4:0]] <= 1'b0;
                    end
                    dividend_reg <= {dividend_reg[30:0], 1'b0};

                    if (bit_counter == 6'd0)
                        state <= DONE;
                    else
                        bit_counter <= bit_counter - 6'd1;
                end

                DONE: begin
                    // Quotient is negative when the operand signs differ;
                    // the remainder takes the dividend's sign.
                    busy <= 1'b0;
                    done <= 1'b1;
                    if (is_signed_reg) begin
                        quotient  <= (a_neg_reg ^ b_neg_reg) ? (~quotient_reg + 32'd1) : quotient_reg;
                        remainder <= a_neg_reg ? (~remainder_reg[31:0] + 32'd1) : remainder_reg[31:0];
                    end else begin
                        quotient  <= quotient_reg;
                        remainder <= remainder_reg[31:0];
                    end
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
