// Board wrapper for the Terasic DE10-Lite (Phases 5 and 9).
// cpu_pll -> reset gating (button AND locked) -> reset_sync -> timur_soc.
// Not used by testbenches: they instantiate timur_soc and drive its clock
// and reset directly (the PLL is not simulated).
module Timur_RV32IMC (
    input        clk_50mhz,   // MAX10_CLK1_50
    input        rst_btn_n,   // KEY[0], active-low push button
    input  [9:0] sw,          // SW[9:0]   -> GPIO_IN
    output [9:0] leds,        // LEDR[9:0] <- GPIO_OUT
    output       uart_tx,     // GPIO header -> 3.3 V USB-to-TTL adapter RX
    input        uart_rx      // GPIO header <- 3.3 V USB-to-TTL adapter TX
);

    wire clk_cpu;
    wire pll_locked;
    wire sync_rst_n;

    cpu_pll u_pll (
        .inclk0 (clk_50mhz),
        .areset (~rst_btn_n),     // active-high PLL reset
        .c0     (clk_cpu),
        .locked (pll_locked)
    );

    // The design stays in reset until the button is released and the PLL
    // has locked; release is aligned to clk_cpu.
    reset_sync u_reset_sync (
        .clk         (clk_cpu),
        .async_rst_n (rst_btn_n & pll_locked),
        .sync_rst_n  (sync_rst_n)
    );

    timur_soc u_soc (
        .clk      (clk_cpu),
        .rst_n    (sync_rst_n),
        .gpio_in  (sw),
        .gpio_out (leds),
        .uart_rx  (uart_rx),
        .uart_tx  (uart_tx)
    );

endmodule
