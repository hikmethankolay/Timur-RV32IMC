`timescale 1ns/1ps
//
// decompressor_tb: every 16-bit encoding with instr[1:0] != 11 (Phase 11),
// against expansions produced by the GNU toolchain
// (sw/gen_decompressor_vectors.py). Combinational: apply, wait 1 ns, compare.
// Vector: instr16(hex) instr32(hex) illegal(bin).
//
module decompressor_tb;

    reg  [15:0] instr16;
    wire [31:0] instr32;
    wire        illegal;

    decompressor dut (
        .instr16 (instr16),
        .instr32 (instr32),
        .illegal (illegal)
    );

    integer         fd, n;
    integer         total, failed, legal_count;
    reg [8*256-1:0] line;
    reg [31:0]      e_instr32;
    reg             e_illegal;

    initial begin : watchdog
        #10000000;
        $display("FAIL watchdog: no summary after 10 ms");
        $stop;
    end

    initial begin
        instr16 = 16'b0;
        total = 0;
        failed = 0;
        legal_count = 0;

        fd = $fopen("vectors/decompressor_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/decompressor_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %b", instr16, e_instr32, e_illegal) == 3) begin
                    #1;
                    total = total + 1;
                    if (!e_illegal)
                        legal_count = legal_count + 1;
                    if (instr32 !== e_instr32 || illegal !== e_illegal) begin
                        failed = failed + 1;
                        $display("FAIL %h | got %h illegal=%b | expected %h illegal=%b",
                                 instr16, instr32, illegal, e_instr32, e_illegal);
                    end
                end
            end
            $fclose(fd);
        end

        // one summary PASS line instead of 49152
        if (failed == 0 && total > 0)
            $display("PASS %0d encodings (%0d legal, %0d illegal) match the toolchain",
                     total, legal_count, total - legal_count);
        if (total == 0)
            $display("FAIL no test vectors were applied");
        if (failed == 0 && total > 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $stop;
    end

endmodule
