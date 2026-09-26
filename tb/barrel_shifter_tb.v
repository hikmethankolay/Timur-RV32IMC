`timescale 1ns/1ps
//
// barrel_shifter_tb: SLL, SRL, SRA and pass-through (Phase 2).
// Vector: in(hex) shamt(dec) shift_type(bin) out(hex).
//
module barrel_shifter_tb;

    reg  [31:0] din;
    reg  [4:0]  shamt;
    reg  [1:0]  shift_type;
    wire [31:0] dout;

    barrel_shifter dut (
        .in         (din),
        .shamt      (shamt),
        .shift_type (shift_type),
        .out        (dout)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp_out;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        din = 32'b0;
        shamt = 5'b0;
        shift_type = 2'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/barrel_shifter_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/barrel_shifter_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %d %b %h", din, shamt, shift_type, exp_out) == 4) begin
                    #10;
                    total = total + 1;
                    if (dout !== exp_out) begin
                        failed = failed + 1;
                        $display("FAIL in=%h shamt=%0d type=%b | got=%h expected=%h",
                                 din, shamt, shift_type, dout, exp_out);
                    end else
                        $display("PASS in=%h shamt=%0d type=%b | out=%h",
                                 din, shamt, shift_type, dout);
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
