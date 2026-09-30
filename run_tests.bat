@echo off
rem Timur RV32IMC regression runner (ModelSim-Intel FPGA Starter Edition 2020.1).
rem Runs from this folder so the relative paths in run_tests.tcl resolve.
rem Set VSIM to the full path of vsim.exe if ModelSim is installed elsewhere.
cd /d "%~dp0"
echo ============================================
echo  Timur RV32IMC Regression Runner
echo ============================================

if not defined VSIM set "VSIM=C:\intelFPGA\20.1\modelsim_ase\win32aloem\vsim.exe"
"%VSIM%" -c -do run_tests.tcl

pause
