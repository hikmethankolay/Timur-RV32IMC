# ============================================================
# Timur RV32IMC - Regression Testbench Runner
# Auto-discovers all *_tb.v files in tb/ folder
# No temp files / do files are created.
# ============================================================

# ── collect source files ──
# glob rtl/**/*.v is one level deep in Tcl; add a second pass for deeper dirs
set rtl_v_files  [concat [glob -nocomplain rtl/**/*.v] \
                          [glob -nocomplain rtl/**/**/*.v]]
set rtl_sv_files [concat [glob -nocomplain rtl/**/*.sv] \
                          [glob -nocomplain rtl/**/**/*.sv]]
set rtl_files    [lsort -unique [concat $rtl_v_files $rtl_sv_files]]
# Drop black-box stubs and the full PLL megafunction (cpu_pll.v instantiates
# altpll which requires altera_mf — not available in plain ModelSim).
# cpu_pll_bb.v is the simulation-safe stub; add it back explicitly.
set rtl_files [lsearch -all -inline -not $rtl_files *_bb.v]
set rtl_files [lsearch -all -inline -not $rtl_files */cpu_pll.v]
lappend rtl_files rtl/primitives/cpu_pll_bb.v

# SystemVerilog packages must compile before any module that imports them.
# Hoist rtl/include/pipeline_pkg.sv to the head of the file list.
set pkg_file rtl/include/pipeline_pkg.sv
set rtl_files [lsearch -all -inline -not $rtl_files $pkg_file]
set rtl_files [linsert $rtl_files 0 $pkg_file]

set tb_files  [glob -nocomplain tb/*.v]
set all_files [concat $rtl_files $tb_files]

# ── auto-discover testbench module names ──
set testbenches {}
foreach f $tb_files {
    lappend testbenches [file rootname [file tail $f]]
}

if {[llength $testbenches] == 0} {
    puts "ERROR: no *_tb.v files found in tb/ folder"
    return
}

# ── create work library ──
puts "Creating work library..."
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# ── compile all files once ──
# -sv enables SystemVerilog (packages, packed structs, import).
# +incdir lets `import pipeline_pkg::*;` resolve from rtl/include/.
puts "Compiling all sources..."
if {[catch {eval vlog -quiet -sv +incdir+rtl/include $all_files} err]} {
    puts "COMPILE ERROR: $err"
    return
}
puts "Compile OK."

# ── safety nets: any $stop / runtime error resumes instead of
#    parking at the VSIM> prompt and hanging the batch run. ──
onbreak {resume}
onerror {resume}

# ── results ──
set passed      0
set failed      0
set failed_list {}

puts ""
puts "============================================"
puts " Timur RV32IMC - Running All Tests"
puts " Found [llength $testbenches] testbench(es)"
puts "============================================"

foreach tb $testbenches {
    puts ""
    puts "--------------------------------------------"
    puts " Running: $tb"
    puts "--------------------------------------------"

    # Load the testbench. -onfinish stop makes $finish halt the
    # simulation (without killing vsim) so run -all can return.
    if {[catch {vsim -quiet -onfinish stop work.$tb} err]} {
        puts "LOAD ERROR ($tb): $err"
        incr failed
        lappend failed_list $tb
        continue
    }

    # Re-assert handlers inside this simulation context.
    onbreak {resume}
    onerror {resume}

    if {[catch {run -all} err]} {
        puts "RUN ERROR ($tb): $err"
    }

    # Read the testbench's internal counters directly - no log files.
    set f_val "?"
    set t_val "?"
    catch {set f_val [examine -radix decimal /${tb}/failed]}
    catch {set t_val [examine -radix decimal /${tb}/total]}

    catch {quit -sim}

    if {[string is integer -strict $f_val] && $f_val == 0
        && [string is integer -strict $t_val] && $t_val > 0} {
        puts "RESULT: PASSED - $tb ($t_val test(s))"
        incr passed
    } else {
        puts "RESULT: FAILED - $tb (failed=$f_val total=$t_val)"
        incr failed
        lappend failed_list $tb
    }
}

# ── summary ──
puts ""
puts "============================================"
puts " REGRESSION COMPLETE"
puts "============================================"
puts " PASSED : $passed"
puts " FAILED : $failed"
if {[llength $failed_list] > 0} {
    puts " Failed testbenches:"
    foreach f $failed_list {
        puts "   - $f"
    }
}
puts "============================================"
puts ""
