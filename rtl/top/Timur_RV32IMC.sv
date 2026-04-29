// FPGA top: generate core clock with PLL; hold core in reset until lock; export PC for debug/LEDs.
module Timur_RV32IMC (
    input  clk_i,
    input  rst_n_i,
    output [31:0] pc_dbg_o
);
    wire clk_cpu_w;
    wire pll_ok_w;
    wire cpu_rst_n_w = rst_n_i & pll_ok_w;

    cpu_pll pll (
        .areset (~rst_n_i),
        .inclk0 (clk_i),
        .c0     (clk_cpu_w),
        .locked (pll_ok_w)
    );

    datapath cpu (
        .clk_i    (clk_cpu_w),
        .rst_n_i  (cpu_rst_n_w),
        .pc_dbg_o (pc_dbg_o)
    );
endmodule
