#!/usr/bin/env bash
# ============================================================
# Timur RV32IMC - regression runner for Icarus Verilog (Linux)
# The counterpart of run_tests.bat / run_tests.tcl (ModelSim).
#
#  1. Compiles every testbench tb/<name>_tb.v with the RTL (rtl/*/*.v without
#     the *_bb.v files and without cpu_pll and the board wrapper, which need
#     the Altera megafunction library); timur_sw_tb also gets tb/timur_soc_tb.v.
#  2. Runs it and keeps its output in logs/<name>_tb.log.
#  3. Counts it as passed only if the log contains "ALL n TESTS PASSED" with
#     n > 0 and no line starting with FAIL.
#
# Usage:  ./run_tests.sh                     every testbench
#         ./run_tests.sh alu_tb timur_soc_tb only these
# Paths inside testbenches are relative to the project root; the script
# changes there first. Needs iverilog and vvp (sudo dnf install iverilog).
# ============================================================
set -u
cd "$(dirname "$0")" || exit 2

if ! command -v iverilog > /dev/null || ! command -v vvp > /dev/null; then
    echo "iverilog / vvp not found: install Icarus Verilog (sudo dnf install iverilog)"
    exit 2
fi

RTL=$(ls rtl/*.v rtl/*/*.v 2> /dev/null | grep -v -e '_bb\.v$' -e '/cpu_pll\.v$' -e '/Timur_RV32IMC\.v$')
if [ $# -gt 0 ]; then
    TBS=("$@")
else
    TBS=($(ls tb/*_tb.v | xargs -n1 basename | sed 's/\.v$//'))
fi

mkdir -p logs
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=()
for tb in "${TBS[@]}"; do
    extra=""
    [ "$tb" = timur_sw_tb ] && extra=tb/timur_soc_tb.v
    log="logs/$tb.log"
    start=$(date +%s)
    if ! iverilog -g2001 -o "$WORK/$tb.vvp" -s "$tb" "tb/$tb.v" $extra $RTL > "$log" 2>&1; then
        printf "FAIL  %-32s compile error, see %s\n" "$tb" "$log"
        failed+=("$tb")
        continue
    fi
    vvp -n "$WORK/$tb.vvp" >> "$log" 2>&1
    count=$(grep -oE 'ALL [0-9]+ TESTS PASSED' "$log" | tail -1 | grep -oE '[0-9]+')
    secs=$(( $(date +%s) - start ))
    if [ -n "$count" ] && [ "$count" -gt 0 ] && ! grep -q '^FAIL' "$log"; then
        printf "PASS  %-32s %6d tests  %4d s\n" "$tb" "$count" "$secs"
        passed=$((passed + 1))
    else
        printf "FAIL  %-32s see %s\n" "$tb" "$log"
        failed+=("$tb")
    fi
done

echo
echo "$passed of ${#TBS[@]} testbenches passed"
if [ ${#failed[@]} -gt 0 ]; then
    echo "failed: ${failed[*]}"
    exit 1
fi
