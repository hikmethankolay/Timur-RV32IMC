@echo off
echo ============================================
echo  Timur RV32IMC Regression Runner
echo ============================================

vsim -c -do run_tests.tcl

pause