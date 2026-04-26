# Copyright (C) 2025  Altera Corporation. All rights reserved.
# Your use of Altera Corporation's design tools, logic functions 
# and other software and tools, and any partner logic 
# functions, and any output files from any of the foregoing 
# (including device programming or simulation files), and any 
# associated documentation or information are expressly subject 
# to the terms and conditions of the Altera Program License 
# Subscription Agreement, the Altera Quartus Prime License Agreement,
# the Altera IP License Agreement, or other applicable license
# agreement, including, without limitation, that your use is for
# the sole purpose of programming logic devices manufactured by
# Altera and sold by Altera or its authorized distributors.  Please
# refer to the Altera Software License Subscription Agreements 
# on the Quartus Prime software download page.

# Quartus Prime: Generate Tcl File for Project
# File: Timur_RV32IMC.tcl
# Generated on: Sun Apr 26 18:53:07 2026

# Load Quartus Prime Tcl Project package
package require ::quartus::project

set need_to_close_project 0
set make_assignments 1

# Check that the right project is open
if {[is_project_open]} {
	if {[string compare $quartus(project) "Timur_RV32IMC"]} {
		puts "Project Timur_RV32IMC is not open"
		set make_assignments 0
	}
} else {
	# Only open if not already open
	if {[project_exists Timur_RV32IMC]} {
		project_open -revision Timur_RV32IMC Timur_RV32IMC
	} else {
		project_new -revision Timur_RV32IMC Timur_RV32IMC
	}
	set need_to_close_project 1
}

# Make assignments
if {$make_assignments} {
	set_global_assignment -name FAMILY "MAX 10"
	set_global_assignment -name DEVICE 10M50DAF484C7G
	set_global_assignment -name ORIGINAL_QUARTUS_VERSION 25.1STD.0
	set_global_assignment -name PROJECT_CREATION_TIME_DATE "22:12:28  APRIL 06, 2026"
	set_global_assignment -name LAST_QUARTUS_VERSION "25.1std.0 Lite Edition"
	set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
	set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
	set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85
	set_global_assignment -name ERROR_CHECK_FREQUENCY_DIVISOR 256
	set_global_assignment -name EDA_SIMULATION_TOOL "Questa Altera FPGA (Verilog)"
	set_global_assignment -name EDA_TIME_SCALE "1 ps" -section_id eda_simulation
	set_global_assignment -name EDA_OUTPUT_DATA_FORMAT "VERILOG HDL" -section_id eda_simulation
	set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST OFF -section_id eda_board_design_timing
	set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST OFF -section_id eda_board_design_symbol
	set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST OFF -section_id eda_board_design_signal_integrity
	set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST OFF -section_id eda_board_design_boundary_scan
	set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
	set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"
	set_global_assignment -name EDA_TEST_BENCH_ENABLE_STATUS TEST_BENCH_MODE -section_id eda_simulation
	set_global_assignment -name EDA_NATIVELINK_SIMULATION_TEST_BENCH d_ff_tb -section_id eda_simulation
	set_global_assignment -name EDA_TEST_BENCH_NAME mux2_tb -section_id eda_simulation
	set_global_assignment -name EDA_DESIGN_INSTANCE_NAME NA -section_id mux2_tb
	set_global_assignment -name EDA_TEST_BENCH_MODULE_NAME mux2_tb -section_id mux2_tb
	set_global_assignment -name EDA_TEST_BENCH_NAME mux4_tb -section_id eda_simulation
	set_global_assignment -name EDA_DESIGN_INSTANCE_NAME NA -section_id mux4_tb
	set_global_assignment -name EDA_TEST_BENCH_MODULE_NAME mux4_tb -section_id mux4_tb
	set_global_assignment -name EDA_TEST_BENCH_FILE tb/mux2_tb.v -section_id mux2_tb
	set_global_assignment -name EDA_TEST_BENCH_FILE rtl/primitives/mux2.v -section_id mux2_tb
	set_global_assignment -name EDA_TEST_BENCH_FILE tb/mux4_tb.v -section_id mux4_tb
	set_global_assignment -name EDA_TEST_BENCH_FILE rtl/primitives/mux4.v -section_id mux4_tb
	set_global_assignment -name EDA_TEST_BENCH_NAME d_ff_tb -section_id eda_simulation
	set_global_assignment -name EDA_DESIGN_INSTANCE_NAME NA -section_id d_ff_tb
	set_global_assignment -name EDA_TEST_BENCH_MODULE_NAME d_ff_tb -section_id d_ff_tb
	set_global_assignment -name EDA_TEST_BENCH_FILE tb/d_ff_tb.v -section_id d_ff_tb
	set_global_assignment -name EDA_TEST_BENCH_FILE rtl/primitives/d_ff.v -section_id d_ff_tb
	set_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id Top
	set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id Top
	set_global_assignment -name PARTITION_COLOR 16764057 -section_id Top
	set_global_assignment -name VERILOG_FILE rtl/pipeline/mem_wb_reg.v
	set_global_assignment -name VERILOG_FILE rtl/pipeline/if_id_reg.v
	set_global_assignment -name VERILOG_FILE rtl/pipeline/id_ex_reg.v
	set_global_assignment -name VERILOG_FILE rtl/pipeline/ex_mem_reg.v
	set_global_assignment -name VERILOG_FILE tb/Timur_RV32IMC_tb.v
	set_global_assignment -name VERILOG_FILE rtl/top/wb_stage.v
	set_global_assignment -name VERILOG_FILE rtl/top/mem_stage.v
	set_global_assignment -name VERILOG_FILE rtl/top/if_stage.v
	set_global_assignment -name VERILOG_FILE rtl/top/id_stage.v
	set_global_assignment -name VERILOG_FILE rtl/top/ex_stage.v
	set_global_assignment -name SDC_FILE Timur_RV32IMC.sdc
	set_global_assignment -name MIF_FILE rom.mif
	set_global_assignment -name MIF_FILE ram.mif
	set_global_assignment -name VERILOG_FILE tb/ram_ahb_tb.v
	set_global_assignment -name VERILOG_FILE tb/main_control_unit_tb.v
	set_global_assignment -name VERILOG_FILE tb/instr_parser_tb.v
	set_global_assignment -name VERILOG_FILE tb/imm_gen_tb.v
	set_global_assignment -name VERILOG_FILE tb/alu_decoder_tb.v
	set_global_assignment -name VERILOG_FILE rtl/memory/ram_ahb.v
	set_global_assignment -name VERILOG_FILE rtl/decode/main_control_unit.v
	set_global_assignment -name VERILOG_FILE rtl/decode/instr_parser.v
	set_global_assignment -name VERILOG_FILE rtl/decode/imm_gen.v
	set_global_assignment -name VERILOG_FILE rtl/decode/alu_decoder.v
	set_global_assignment -name VERILOG_FILE tb/rom_ahb_tb.v
	set_global_assignment -name VERILOG_FILE tb/registers_tb.v
	set_global_assignment -name VERILOG_FILE tb/pc_tb.v
	set_global_assignment -name VERILOG_FILE rtl/memory/rom_ahb.v
	set_global_assignment -name VERILOG_FILE rtl/memory/registers.v
	set_global_assignment -name VERILOG_FILE rtl/memory/pc.v
	set_global_assignment -name VERILOG_FILE rtl/execution/multiplier.v
	set_global_assignment -name VERILOG_FILE rtl/execution/divider.v
	set_global_assignment -name VERILOG_FILE rtl/execution/branch_condition_evaluator.v
	set_global_assignment -name VERILOG_FILE tb/multiplier_tb.v
	set_global_assignment -name VERILOG_FILE tb/divider_tb.v
	set_global_assignment -name VERILOG_FILE tb/branch_condition_evaluator_tb.v
	set_global_assignment -name VERILOG_FILE tb/alu_tb.v
	set_global_assignment -name VERILOG_FILE tb/barrel_shifter_tb.v
	set_global_assignment -name VERILOG_FILE tb/adder_32bit_tb.v
	set_global_assignment -name VERILOG_FILE rtl/execution/barrel_shifter.v
	set_global_assignment -name VERILOG_FILE rtl/execution/alu.v
	set_global_assignment -name VERILOG_FILE rtl/execution/adder_32bit.v
	set_global_assignment -name VERILOG_FILE rtl/primitives/d_ff.v
	set_global_assignment -name VERILOG_FILE tb/d_ff_tb.v
	set_global_assignment -name VERILOG_FILE rtl/primitives/mux2.v
	set_global_assignment -name VERILOG_FILE tb/mux2_tb.v
	set_global_assignment -name VERILOG_FILE rtl/top/Timur_RV32IMC.v
	set_global_assignment -name VERILOG_FILE rtl/top/datapath.v
	set_global_assignment -name VERILOG_FILE rtl/primitives/mux4.v
	set_global_assignment -name VERILOG_FILE tb/mux4_tb.v
	set_global_assignment -name QIP_FILE rtl/primitives/cpu_pll.qip
	set_global_assignment -name SOURCE_FILE db/Timur_RV32IMC.cmp.rdb
	set_instance_assignment -name PARTITION_HIERARCHY root_partition -to | -section_id Top

	# Including default assignments
	set_global_assignment -name TIMING_ANALYZER_MULTICORNER_ANALYSIS ON -family "MAX 10"
	set_global_assignment -name TIMING_ANALYZER_REPORT_WORST_CASE_TIMING_PATHS OFF -family "MAX 10"
	set_global_assignment -name TIMING_ANALYZER_CCPP_TRADEOFF_TOLERANCE 0 -family "MAX 10"
	set_global_assignment -name TDC_CCPP_TRADEOFF_TOLERANCE 0 -family "MAX 10"
	set_global_assignment -name TIMING_ANALYZER_DO_CCPP_REMOVAL ON -family "MAX 10"
	set_global_assignment -name DISABLE_LEGACY_TIMING_ANALYZER OFF -family "MAX 10"
	set_global_assignment -name SYNTH_TIMING_DRIVEN_SYNTHESIS ON -family "MAX 10"
	set_global_assignment -name SYNCHRONIZATION_REGISTER_CHAIN_LENGTH 2 -family "MAX 10"
	set_global_assignment -name SYNTH_RESOURCE_AWARE_INFERENCE_FOR_BLOCK_RAM ON -family "MAX 10"
	set_global_assignment -name OPTIMIZE_HOLD_TIMING "ALL PATHS" -family "MAX 10"
	set_global_assignment -name OPTIMIZE_MULTI_CORNER_TIMING ON -family "MAX 10"
	set_global_assignment -name AUTO_DELAY_CHAINS ON -family "MAX 10"
	set_global_assignment -name CRC_ERROR_OPEN_DRAIN OFF -family "MAX 10"
	set_global_assignment -name USE_CONFIGURATION_DEVICE ON -family "MAX 10"
	set_global_assignment -name ENABLE_OCT_DONE ON -family "MAX 10"

	# Commit assignments
	export_assignments

	# Close project
	if {$need_to_close_project} {
		project_close
	}
}
