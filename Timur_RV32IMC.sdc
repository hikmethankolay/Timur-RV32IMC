#**************************************************************
# Timur RV32IMC timing constraints (Phase 1)
# Register under Assignments -> Settings -> Timing Analyzer.
#**************************************************************

#**************************************************************
# Board clock: MAX10_CLK1_50, 50 MHz
#**************************************************************
create_clock -name clk_50mhz -period 20.000 [get_ports {clk_50mhz}]

#**************************************************************
# PLL output clocks (cpu_pll c0)
#**************************************************************
derive_pll_clocks

#**************************************************************
# Jitter and clock uncertainty
#**************************************************************
derive_clock_uncertainty

#**************************************************************
# Asynchronous inputs, synchronised inside the design:
# reset button (reset_sync), switches (GPIO synchroniser),
# uart_rx (UART receiver synchroniser)
#**************************************************************
set_false_path -from [get_ports {rst_btn_n sw[*] uart_rx}]

#**************************************************************
# Slow outputs
#**************************************************************
set_false_path -to [get_ports {leds[*] uart_tx}]
