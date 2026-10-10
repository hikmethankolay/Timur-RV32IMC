// Board wrapper template for porting Timur to another FPGA board.
// The DE10-Lite wrapper is rtl/top/Timur_RV32IMC.v; this one uses no vendor
// IP, so it builds with any tool. Copy it into the new board's project,
// rename the ports to the board's signal names and write the pin file.
//
//   clk_50mhz : timur_soc must run at 50 MHz (TIMUR_CLOCK_HZ in
//               sw/runtime/include/timur_defs.h, the UART divider and the
//               VGA timing assume it). On a board with another oscillator
//               (100 MHz on Basys 3 and Arty), generate 50 MHz with the
//               vendor's PLL / clocking wizard and AND its locked output
//               into async_rst_n below, as the DE10-Lite wrapper does.
//   Memories  : define TIMUR_PORTABLE for synthesis (drops the Intel M9K
//               attributes and loads the ROM with $readmemh) and add
//               rom_lo.hex and rom_hi.hex to the project. Quartus builds
//               keep the .mif files and leave TIMUR_PORTABLE undefined.
//   Unused    : tie sw to 0 and uart_rx to 1 (idle line) if the board lacks
//               them; leave leds, uart_tx and the vga_* outputs unconnected.
//
// Keep the timur_soc port list in step with rtl/top/Timur_RV32IMC.v.
module timur_board_top (
    input        clk_50mhz,   // 50 MHz board clock (or PLL output)
    input        rst_btn_n,   // active-low push button; invert an active-high one
    input  [9:0] sw,          // slide switches -> GPIO_IN
    output [9:0] leds,        // LEDs <- GPIO_OUT
    output       uart_tx,     // to the USB-UART bridge's RX (3.3 V)
    input        uart_rx,     // from the USB-UART bridge's TX (3.3 V)
    output [3:0] vga_r,       // 4 bits per colour, as on DE10-Lite and Basys 3
    output [3:0] vga_g,
    output [3:0] vga_b,
    output       vga_hs,
    output       vga_vs
);

    wire sync_rst_n;

    reset_sync u_reset_sync (
        .clk         (clk_50mhz),
        .async_rst_n (rst_btn_n),
        .sync_rst_n  (sync_rst_n)
    );

    timur_soc u_soc (
        .clk      (clk_50mhz),
        .rst_n    (sync_rst_n),
        .gpio_in  (sw),
        .gpio_out (leds),
        .uart_rx  (uart_rx),
        .uart_tx  (uart_tx),
        .vga_r    (vga_r),
        .vga_g    (vga_g),
        .vga_b    (vga_b),
        .vga_hs   (vga_hs),
        .vga_vs   (vga_vs)
    );

endmodule
