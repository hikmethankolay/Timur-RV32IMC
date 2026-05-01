// 8N1 UART transmitter bit serializer.
module uart_tx (
    input             clk,
    input             rst_n,
    input             baud_tick,
    input      [7:0] tx_data,
    input             tx_start,
    output            tx_busy,
    output reg        uart_tx
);

    localparam IDLE = 2'b00;
    localparam START = 2'b01;
    localparam DATA = 2'b10;
    localparam STOP = 2'b11;

    reg [1:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;

    assign tx_busy = (state != IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            uart_tx <= 1'b1;
            shift_reg <= 8'h0;
            bit_cnt <= 3'd0;
        end else begin
            case (state)
                IDLE: begin
                    uart_tx <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        state <= START;
                    end
                end

                START: begin
                    uart_tx <= 1'b0;
                    if (baud_tick) begin
                        bit_cnt <= 3'd0;
                        state <= DATA;
                    end
                end

                DATA: begin
                    uart_tx <= shift_reg[0];
                    if (baud_tick) begin
                        shift_reg <= shift_reg >> 1;
                        if (bit_cnt == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                STOP: begin
                    uart_tx <= 1'b1;
                    if (baud_tick) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
