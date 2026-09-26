`timescale 1ns/1ps
//
// timur_sw_tb: the C programs of Phase 12 (sw/tests/*.c, built for
// rv32im_zicsr and rv32imc_zicsr) on timur_soc. It is timur_soc_tb with the
// program list vectors/timur_sw_vectors.txt (sw/gen_sw_tests.py) and a UART
// of 16 cycles per bit instead of 434, so that printf output costs little
// simulation time; the programs only poll the UART's status flags and never
// depend on the baud rate. Compile it together with tb/timur_soc_tb.v.
// Each program's UART output is printed in the log, prefixed with "  | ".
//
module timur_sw_tb;

    timur_soc_tb #(
        .VECTORS      ("vectors/timur_sw_vectors.txt"),
        .UART_DIVIDER (15)
    ) run ();

endmodule
