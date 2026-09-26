@echo off
rem Timur RV32IMC regression runner (ModelSim-Intel FPGA Starter Edition 2020.1).
rem Runs from this folder so the relative paths in run_tests.tcl resolve.
cd /d "%~dp0"
echo ============================================
echo  Timur RV32IMC Regression Runner
echo ============================================

"C:\intelFPGA\20.1\modelsim_ase\win32aloem\vsim.exe" -c -do run_tests.tcl

pause
