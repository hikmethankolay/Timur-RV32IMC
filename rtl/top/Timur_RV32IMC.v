module Timur_RV32IMC (
    input  clk,
    input  rst_n,
    output [31:0] pc_out
);

    wire clk_cpu;
    wire pll_locked;

    // Hold CPU in reset until PLL locks
    wire cpu_rst_n = rst_n & pll_locked;

    // PLL: areset is active-high, rst_n is active-low
    cpu_pll pll (
        .areset (~rst_n),
        .inclk0 (clk),
        .c0     (clk_cpu),
        .locked (pll_locked)
    );

    datapath cpu (
        .clk    (clk_cpu),
        .rst_n  (cpu_rst_n),
        .pc_out (pc_out)
    );

endmodule
