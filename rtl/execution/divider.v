module divider (
    input clk,
    input rst_n,
    input start,
    input [31:0] a,
    input [31:0] b,
    input [1:0] div_op,
    output reg [31:0] quotient,
    output reg [31:0] remainder,
    output reg busy,
    output reg done
);

    wire is_signed = !div_op[0];
    wire a_negative = a[31] & is_signed;
    wire b_negative = b[31] & is_signed;
    wire [31:0] a_abs = a_negative ? (~a + 1) : a;
    wire [31:0] b_abs = b_negative ? (~b + 1) : b;
    
    wire div_by_zero = (b == 32'b0);
    wire signed_overflow = is_signed && (a == 32'h80000000) && (b == 32'hFFFFFFFF);
    
    localparam IDLE = 2'b00;
    localparam RUNNING = 2'b01;
    localparam DONE = 2'b10;

    reg [1:0] state;
    reg [5:0] bit_counter;
    reg [31:0] dividend_reg;
    reg [31:0] divisor_reg;
    reg [31:0] quotient_reg;
    reg [32:0] remainder_reg;
    reg a_neg_reg;
    reg b_neg_reg;
    reg is_signed_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            busy          <= 0;
            done          <= 0;
            quotient      <= 0;
            remainder     <= 0;
            bit_counter   <= 0;
            dividend_reg  <= 0;
            divisor_reg   <= 0;
            quotient_reg  <= 0;
            remainder_reg <= 0;
            a_neg_reg     <= 0;
            b_neg_reg     <= 0;
            is_signed_reg <= 0;
        end else begin
            done <= 0;

            case (state)

                IDLE: begin
                    if (start) begin
                        if (div_by_zero) begin
                            quotient <= 32'hFFFFFFFF;
                            remainder <= a;
                            done <= 1;
                        end else if (signed_overflow) begin
                            quotient <= 32'h80000000;
                            remainder <= 32'h00000000;
                            done <= 1;
                        end else begin
                            busy <= 1;
                            bit_counter <= 31;
                            dividend_reg <= a_abs;
                            divisor_reg <= b_abs;
                            quotient_reg <= 0;
                            remainder_reg <= 0;
                            a_neg_reg <= a_negative;
                            b_neg_reg <= b_negative;
                            is_signed_reg <= is_signed;
                            state <= RUNNING;
                        end
                    end
                end

                RUNNING: begin
                    remainder_reg <= {remainder_reg[31:0], dividend_reg[bit_counter]};

                    if ({remainder_reg[31:0], dividend_reg[bit_counter]} >= {1'b0, divisor_reg}) begin
                        remainder_reg <= {remainder_reg[31:0], dividend_reg[bit_counter]} - {1'b0, divisor_reg};
                        quotient_reg[bit_counter] <= 1;
                    end else begin
                        quotient_reg[bit_counter] <= 0;
                    end

                    if (bit_counter == 0) begin
                        state <= DONE;
                    end else begin
                        bit_counter <= bit_counter - 1;
                    end
                end

                DONE: begin
                    busy <= 0;
                    done <= 1;

                    if (is_signed_reg) begin
                        quotient <= (a_neg_reg ^ b_neg_reg) ? (~quotient_reg + 1) : quotient_reg;
                        remainder <= a_neg_reg ? (~remainder_reg[31:0] + 1) : remainder_reg[31:0];
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