# ============================================================
# Timur RV32IMC - regression runner (ModelSim command-line mode)
# Started by run_tests.bat:  vsim -c -do run_tests.tcl
#
#  1. Collects rtl/*.v and rtl/*/*.v (dropping every *_bb.v) and tb/*_tb.v;
#     each testbench module name is its file name.
#  2. Deletes, recreates and maps the work library.
#  3. Compiles everything once and aborts on any compile error.
#  4. Runs every testbench with a temporary do-file (run -all, quit -sim),
#     its transcript redirected to logs/<testbench>.log.
#  5. A test passes only if its log contains "ALL n TESTS PASSED" with
#     n > 0 and no FAIL line. A missing summary (crash, missing vector
#     file, watchdog) counts as a failure.
#  6. Prints a pass/fail summary and deletes the temporary do-files.
# Vector files (vectors/...) and memory images (rom.hex) are read relative
# to the project root.
# ============================================================

set rtl_files [lsort [concat [glob -nocomplain rtl/*.v] [glob -nocomplain rtl/*/*.v]]]
set rtl_files [lsearch -all -inline -not -glob $rtl_files *_bb.v]
set tb_files  [lsort [glob -nocomplain tb/*_tb.v]]

if {[llength $tb_files] == 0} {
    puts "ERROR: no testbenches found in tb/"
    quit -f
}

# Compiling without a fresh, mapped library fails with
# "Execution of vlib.exe failed".
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

puts "Compiling [llength $rtl_files] RTL files and [llength $tb_files] testbenches..."
if {[catch {eval vlog -quiet -timescale 1ns/1ps $rtl_files $tb_files} err]} {
    puts "COMPILE ERROR: $err"
    quit -f
}
puts "Compile OK."

file mkdir logs
set passed      0
set failed_list {}

foreach f $tb_files {
    set tb       [file rootname [file tail $f]]
    set do_file  "${tb}_run.do"
    set log_file "logs/${tb}.log"

    set fh [open $do_file w]
    puts $fh "onbreak {resume}"
    puts $fh "onerror {resume}"
    puts $fh "run -all"
    puts $fh "quit -sim"
    close $fh

    file delete -force $log_file
    transcript file $log_file
    if {[catch {vsim -quiet work.$tb -do $do_file} err]} {
        puts "LOAD ERROR ($tb): $err"
    }
    transcript file ""

    set log ""
    if {[file exists $log_file]} {
        set fh [open $log_file r]
        set log [read $fh]
        close $fh
    }

    set count 0
    set ok [regexp {ALL ([0-9]+) TESTS PASSED} $log -> count]
    if {$ok && $count > 0 && [string first "FAIL" $log] < 0} {
        puts "PASS  $tb ($count tests)"
        incr passed
    } else {
        puts "FAIL  $tb (see $log_file)"
        lappend failed_list $tb
    }

    file delete -force $do_file
}

puts ""
puts "============================================"
puts " REGRESSION SUMMARY"
puts "============================================"
puts " PASSED : $passed"
puts " FAILED : [llength $failed_list]"
foreach tb $failed_list {
    puts "   - $tb"
}
puts "============================================"
quit -f
