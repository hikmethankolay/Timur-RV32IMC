module uart_apb_regs (
    input             PCLK,
    input             PRESETn,
    input             PSEL,
    input             PENABLE,
    input             PWRITE,
    input      [7:0]  PADDR,
    input      [31:0] PWDATA,
    output     [31:0] PRDATA,
    output            PREADY,
    output            PSLVERR,

    output     [15:0] baud_divisor,
    output     [7:0]  tx_data,
    output            tx_start,
    input             tx_busy,
    input      [7:0]  rx_data,
    input             rx_valid,
    output            rx_data_read_strobe
);

    localparam ADDR_UART_DATA   = 8'h00;
    localparam ADDR_UART_STATUS = 8'h04;
    localparam ADDR_UART_CTRL   = 8'h08;

    wire transfer = PSEL & PENABLE;

    reg [15:0] baud_divisor_reg;
    reg [7:0] tx_data_reg;
    reg tx_start_reg;
    reg rx_strobe_reg;

    assign PREADY = 1'b1;
    assign PSLVERR = 1'b0;
    assign baud_divisor = baud_divisor_reg;
    assign tx_data              = tx_data_reg;
    assign tx_start             = tx_start_reg;
    assign rx_data_read_strobe  = rx_strobe_reg;

    assign PRDATA = (PADDR == ADDR_UART_DATA) ? {24'b0, rx_data}:
                    (PADDR == ADDR_UART_STATUS) ? {30'b0, rx_valid, tx_busy}:
                    32'b0;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            baud_divisor_reg <= 16'b0;
            tx_data_reg <= 0;
            tx_start_reg <= 0;
            rx_strobe_reg <= 0;
        end else begin
            tx_start_reg  <= 1'b0;
            rx_strobe_reg <= 1'b0;
            
            if (transfer & PWRITE) begin
                case (PADDR)
                    ADDR_UART_DATA: begin
                        if (!tx_busy) begin
                            tx_data_reg <= PWDATA[7:0];
                            tx_start_reg <= 1'b1;
                        end
                    end

                    ADDR_UART_CTRL: begin
                        baud_divisor_reg <= PWDATA[15:0];
                    end
                endcase
            end

            if (transfer & ~PWRITE) begin
                if (PADDR == ADDR_UART_DATA) begin
                    rx_strobe_reg <= 1'b1;
                end
            end
        end
    end
endmodule
