module uart_baud_gen (
    input             clk,
    input             rst_n,
    input      [15:0] divisor,
    output reg        baud_tick
);

    reg [15:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count     <= 16'd1;
            baud_tick <= 1'b0;
        end else if (divisor == 16'd0) begin
            baud_tick <= 1'b0;
            count     <= 16'd0;
        end else begin
            if (count == 16'd0) begin
                baud_tick <= 1'b1;
                count     <= divisor;
            end else begin
                baud_tick <= 1'b0;
                count     <= count - 16'd1;
            end
        end
    end

endmodule
