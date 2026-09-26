`timescale 1ns/1ps
//
// store_aligner_tb: SB/SH replicate the data onto every lane, SW passes it
// through (Phase 3).
// Vector: funct3(bin) rs2(hex) hwdata(hex).
//
module store_aligner_tb;

    reg  [2:0]  funct3;
    reg  [31:0] rs2;
    wire [31:0] hwdata;

    store_aligner dut (
        .funct3 (funct3),
        .rs2    (rs2),
        .hwdata (hwdata)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp_hwdata;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        funct3 = 3'b0;
        rs2 = 32'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/store_aligner_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/store_aligner_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %h %h", funct3, rs2, exp_hwdata) == 3) begin
                    #10;
                    total = total + 1;
                    if (hwdata !== exp_hwdata) begin
                        failed = failed + 1;
                        $display("FAIL funct3=%b rs2=%h | got=%h expected=%h", funct3, rs2, hwdata, exp_hwdata);
                    end else
                        $display("PASS funct3=%b rs2=%h | hwdata=%h", funct3, rs2, hwdata);
                end
            end
            $fclose(fd);
        end

        if (total == 0)
            $display("FAIL no test vectors were applied");
        if (failed == 0 && total > 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $stop;
    end

endmodule
