`timescale 1ns/1ps
//
// adder_32bit_tb: add/subtract, carry-out and signed overflow (Phase 2).
// Vector: a(hex) b(hex) sub(bin) result(hex) cout(bin) overflow(bin).
//
module adder_32bit_tb;

    reg  [31:0] a, b;
    reg         sub;
    wire [31:0] result;
    wire        cout, overflow;

    adder_32bit dut (
        .a        (a),
        .b        (b),
        .sub      (sub),
        .result   (result),
        .cout     (cout),
        .overflow (overflow)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp_result;
    reg             exp_cout, exp_ovf;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        a = 32'b0;
        b = 32'b0;
        sub = 1'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/adder_32bit_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/adder_32bit_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %b %h %b %b", a, b, sub, exp_result, exp_cout, exp_ovf) == 6) begin
                    #10;
                    total = total + 1;
                    if (result !== exp_result || cout !== exp_cout || overflow !== exp_ovf) begin
                        failed = failed + 1;
                        $display("FAIL a=%h b=%h sub=%b | got %h c=%b v=%b | expected %h c=%b v=%b",
                                 a, b, sub, result, cout, overflow, exp_result, exp_cout, exp_ovf);
                    end else
                        $display("PASS a=%h b=%h sub=%b | %h c=%b v=%b",
                                 a, b, sub, result, cout, overflow);
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
