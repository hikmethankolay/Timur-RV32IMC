# 40 MHz board oscillator — 25 ns period (port name must match Timur_RV32IMC.sv)
create_clock -name {clk_board} -period 25.0 [get_ports {clk_i}]

# Automatically derive PLL output clocks (clk_cpu)
derive_pll_clocks

# Apply standard clock uncertainty
derive_clock_uncertainty
