#!/usr/bin/env bash
# ============================================================
# Timur RV32IMC - put the current ROM image on the DE10-Lite
#
#   sw/program_board.sh               rebuild the programming files with the ROM
#                                     contents of rom_lo.mif / rom_hi.mif and
#                                     program the .sof over JTAG (lost at power-off)
#   sw/program_board.sh --flash       program the .pof into the MAX 10's
#                                     configuration flash instead (kept at power-off)
#   sw/program_board.sh --full        force a full compilation first
#   sw/program_board.sh --no-program  only rebuild the programming files
#
# Without --full, the ROM contents are swapped into the last full compilation
# (quartus_cdb --update_mif, then the assembler): a few seconds, and timing is
# unchanged because only memory contents change. A full compilation (about
# 1.5 minutes) runs instead when there is none yet, or when a file in rtl/,
# the .qsf or the .sdc is newer than the last fit. After a full compilation
# the script stops if setup or hold slack is negative.
# Quartus comes from PATH, $QUARTUS_BIN, or ~/altera_standard/25.1std/quartus/bin.
# Logs: logs/quartus_*.log.
# ============================================================
set -u
cd "$(dirname "$0")/.." || exit 2
PROJECT=Timur_RV32IMC

full=0; flash=0; program=1
for arg in "$@"; do
    case "$arg" in
        --full)       full=1 ;;
        --flash)      flash=1 ;;
        --no-program) program=0 ;;
        -h|--help)    sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "unknown option $arg (see --help)"; exit 2 ;;
    esac
done

if ! command -v quartus_sh > /dev/null; then
    for dir in "${QUARTUS_BIN:-}" "$HOME/altera_standard/25.1std/quartus/bin" \
               "$HOME"/intelFPGA_lite/*/quartus/bin "$HOME"/altera_lite/*/quartus/bin; do
        if [ -n "$dir" ] && [ -x "$dir/quartus_sh" ]; then
            PATH="$dir:$PATH"
            break
        fi
    done
fi
if ! command -v quartus_sh > /dev/null; then
    echo "Quartus not found: add its bin folder to PATH or set QUARTUS_BIN"
    exit 2
fi

for f in rom_lo.mif rom_hi.mif; do
    [ -f "$f" ] || { echo "$f is missing (python3 sw/build.py --install ... writes it)"; exit 2; }
done
mkdir -p logs

run() {     # run <log name> <command...>: quiet unless it fails
    local log="logs/quartus_$1.log"
    shift
    if ! "$@" > "$log" 2>&1; then
        echo "FAILED: $* (see $log)"
        grep -E "^Error|Error \(" "$log" | head -10
        exit 1
    fi
}

fit="output_files/$PROJECT.fit.rpt"
reason=""
if [ $full = 1 ]; then
    reason="requested with --full"
elif [ ! -f "$fit" ] || [ ! -d db ]; then
    reason="there is no earlier compilation"
else
    newer=$(find rtl "$PROJECT.qsf" "$PROJECT.sdc" -newer "$fit" -type f \( -name '*.v' -o -name '*.qip' -o -name '*.qsf' -o -name '*.sdc' \) 2> /dev/null | head -3)
    [ -n "$newer" ] && reason="changed since the last fit: $(echo $newer)"
fi

if [ -n "$reason" ]; then
    echo "== full compilation, about 1.5 minutes ($reason)"
    run compile quartus_sh --flow compile "$PROJECT"
    summary="output_files/$PROJECT.sta.summary"
    grep -A1 "^Type" "$summary" | grep -E "Type|Slack" | paste - - | grep -E "Model (Setup|Hold) " | \
        sed -E "s/Type +: (.*) Model (Setup|Hold).*Slack +: (.*)/   \1 \2 slack \3 ns/"
    if grep -A1 "^Type" "$summary" | grep -q "Slack : -"; then
        echo "STOP: negative slack, the design would fail on the board (see the Timing Analyzer)"
        exit 1
    fi
else
    echo "== swapping rom_lo.mif / rom_hi.mif into the last compilation"
    run update_mif quartus_cdb "$PROJECT" -c "$PROJECT" --update_mif
    run assembler quartus_asm "$PROJECT" -c "$PROJECT"
fi
echo "   programming files: output_files/$PROJECT.sof, output_files/$PROJECT.pof"

[ $program = 1 ] || exit 0

if ! jtagconfig 2> /dev/null | grep -q "^1)"; then
    echo "No JTAG cable found: plug in the board's USB cable. On Linux the USB-Blaster also needs"
    echo "a udev rule, /etc/udev/rules.d/92-usbblaster.rules (Quartus: drivers/"
    echo "linux_drivers_install_instruction.txt). jtagconfig says:"
    jtagconfig 2>&1 | sed 's/^/   /'
    exit 1
fi
if [ $flash = 1 ]; then
    echo "== programming and verifying the configuration flash (.pof); this can take a minute"
    run program quartus_pgm -m jtag -o "pv;output_files/$PROJECT.pof"
    echo "   done: the design starts now and after every power-up"
else
    echo "== programming the FPGA (.sof)"
    run program quartus_pgm -m jtag -o "p;output_files/$PROJECT.sof"
    echo "   done: the program runs now (press KEY0 to restart it); power-off erases it"
fi
