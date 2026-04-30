// FPGA top: DE10-Lite clock port names (match QSF + Terasic SDC); PLL from MAX10_CLK1_50.
module Timur_RV32IMC (
    input         ADC_CLK_10,
    input         MAX10_CLK1_50,
    input         MAX10_CLK2_50,
    input         rst_n_i,
    output [31:0] pc_dbg_o
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

    datapath cpu (
        .clk_i    (clk_cpu_w),
        .rst_n_i  (cpu_rst_n_w),
        .pc_dbg_o (pc_dbg_o)
    );
endmodule
