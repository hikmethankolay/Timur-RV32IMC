module Timur_RV32IMC (
    input         ADC_CLK_10,
    input         MAX10_CLK1_50,
    input         MAX10_CLK2_50,
    input         rst_n_i,
    output [31:0] pc_dbg_o,

    input         uart_rx_i,
    output        uart_tx_o,

    inout  [31:0] gpio_io
);
    wire clk_cpu_w;
    wire pll_ok_w;
    wire cpu_rst_n_w = rst_n_i & pll_ok_w;

    cpu_pll pll (
        .areset (~rst_n_i),
        .inclk0 (MAX10_CLK1_50),
        .c0     (clk_cpu_w),
        .locked (pll_ok_w)
    );

    wire [31:0] gpio_out_w, gpio_oe_w;

    genvar i;
    generate for (i = 0; i < 32; i++) begin : gpio_buf
        assign gpio_io[i] = gpio_oe_w[i] ? gpio_out_w[i] : 1'bz;
    end endgenerate

    soc u_soc (
        .HCLK       (clk_cpu_w),
        .HRESETn    (cpu_rst_n_w),
        .pc_dbg_o   (pc_dbg_o),
        .uart_rx_i  (uart_rx_i),
        .uart_tx_o  (uart_tx_o),
        .gpio_in_i  (gpio_io),
        .gpio_out_o (gpio_out_w),
        .gpio_oe_o  (gpio_oe_w)
    );
endmodule
