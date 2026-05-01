module uart_apb (
    input         PCLK,
    input         PRESETn,
    input         PSEL,
    input         PENABLE,
    input         PWRITE,
    input  [7:0]  PADDR,
    input  [31:0] PWDATA,
    output [31:0] PRDATA,
    output        PREADY,
    output        PSLVERR,
    output        uart_tx,
    input         uart_rx
);

    wire [15:0] baud_divisor;
    wire        baud_tick;
    wire [7:0]  tx_data;
    wire        tx_start;
    wire        tx_busy;
    wire [7:0]  rx_data;
    wire        rx_valid;
    wire        rx_data_read_strobe;

    uart_baud_gen u_baud_gen (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .divisor  (baud_divisor),
        .baud_tick(baud_tick)
    );

    uart_tx u_tx (
        .clk      (PCLK),
        .rst_n    (PRESETn),
        .baud_tick(baud_tick),
        .tx_data  (tx_data),
        .tx_start (tx_start),
        .tx_busy  (tx_busy),
        .uart_tx  (uart_tx)
    );

    uart_rx u_rx (
        .clk                  (PCLK),
        .rst_n                (PRESETn),
        .baud_tick            (baud_tick),
        .uart_rx              (uart_rx),
        .rx_data              (rx_data),
        .rx_valid             (rx_valid),
        .rx_data_read_strobe  (rx_data_read_strobe)
    );

    uart_apb_regs u_apb_regs (
        .PCLK                  (PCLK),
        .PRESETn               (PRESETn),
        .PSEL                  (PSEL),
        .PENABLE               (PENABLE),
        .PWRITE                (PWRITE),
        .PADDR                 (PADDR),
        .PWDATA                (PWDATA),
        .PRDATA                (PRDATA),
        .PREADY                (PREADY),
        .PSLVERR               (PSLVERR),
        .baud_divisor          (baud_divisor),
        .tx_data               (tx_data),
        .tx_start              (tx_start),
        .tx_busy               (tx_busy),
        .rx_data               (rx_data),
        .rx_valid              (rx_valid),
        .rx_data_read_strobe   (rx_data_read_strobe)
    );

endmodule
