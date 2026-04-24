# 50 MHz board oscillator — 20 ns period
create_clock -name {clk} -period 20.000 [get_ports {clk}]

# Automatically derive PLL output clocks (clk_cpu)
derive_pll_clocks

# Apply standard clock uncertainty
derive_clock_uncertainty
