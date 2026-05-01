// 8N1 UART receiver (optional oversampling / majority vote later).
module uart_rx (
    input             clk,
    input             rst_n,
    input             baud_tick,
    input             uart_rx,
    output      [7:0] rx_data,
    output            rx_valid,
    input             rx_data_read_strobe
);

    localparam IDLE = 2'b00;
    localparam START = 2'b01;
    localparam DATA = 2'b10;
    localparam STOP = 2'b11;

    reg [1:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;
    reg [7:0] rx_data_reg;
    reg rx_valid_reg;

    // 2-FF synchronizer
    reg rx_ff1, rx_ff2;
    wire rx_sync = rx_ff2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_ff1 <= 1'b1;
            rx_ff2 <= 1'b1;
        end else begin
            rx_ff1 <= uart_rx;
            rx_ff2 <= rx_ff1;
        end
    end


    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;

    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            shift_reg <= 8'h0;
            bit_cnt <= 3'd0;
            rx_data_reg <= 8'h0;
            rx_valid_reg<= 1'b0;
        end else begin

            if (rx_data_read_strobe) begin
                rx_valid_reg <= 1'b0;
            end

            case (state)
                IDLE: begin
                    if (rx_sync == 1'b0) begin
                        state <= START;
                    end
                end

                START: begin
                    if (baud_tick) begin
                        bit_cnt <= 3'd0;
                        state <= DATA;
                    end
                end

                DATA: begin
                    if (baud_tick) begin
                        shift_reg <= {rx_sync, shift_reg[7:1]};
                        if (bit_cnt == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                STOP: begin
                    if (baud_tick) begin
                        if (rx_sync == 1'b1) begin
                            rx_data_reg <= shift_reg;
                            rx_valid_reg <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end
            endcase
        end
    end


endmodule
