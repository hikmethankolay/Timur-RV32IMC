`timescale 1ns/1ps
//
// divider_tb — vector-driven regression for DIV / DIVU (quotient + remainder).
// The divider is sequential; each test pulses start for one cycle then waits
// for done while counting clock cycles.
//
// Latency model (10 ns clock):
//   trivial path (div-by-zero / signed-overflow): done fires in the IDLE cycle
//     itself — cycle_count = 0.
//   normal path (32 shift-subtract iterations):
//     P0  : IDLE samples start, busy<=1, state->RUNNING, bit_counter=31
//     P1-P32 : RUNNING (32 iterations, bit 31..0)
//     P33 : DONE, busy<=0, done<=1
//     => cycle_count = 33 (P1..P33 counted in the while loop)
//   Expected: cycle_count == 33 for all normal (non-trivial) divisions.
//
module divider_tb;

    reg         clk, rst_n, start;
    reg  [31:0] a, b;
    reg  [1:0]  div_op;
    wire [31:0] quotient, remainder;
    wire        busy, done;

    divider dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .a        (a),
        .b        (b),
        .div_op   (div_op),
        .quotient (quotient),
        .remainder(remainder),
        .busy     (busy),
        .done     (done)
    );

    always #5 clk = ~clk;

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    reg [31:0]       exp_quot, exp_rem;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    integer          cycle_count;
    reg              is_trivial;

    // Expected cycle count for a normal (non-trivial) 32-bit division.
    localparam EXPECTED_CYCLES = 33;

    initial begin
        clk    = 0;
        rst_n  = 0;
        start  = 0;
        a      = 32'h0;
        b      = 32'h0;
        div_op = 2'h0;

        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        file = $fopen("tb/vectors/divider_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open divider_vectors.txt");
            failed = failed + 1;
        end else begin
            while (!$feof(file)) begin
                line = 0;
                slen = $fgets(line, file);
                if (slen > 0) begin
                    r = $sscanf(line, "%h %h %d %h %h",
                                a, b, div_op, exp_quot, exp_rem);
                    if (r == 5) begin
                        test_num  = test_num + 1;
                        total     = total    + 1;

                        // Trivial path: div-by-zero or signed overflow
                        // (done fires in the same IDLE cycle as start).
                        is_trivial = (b == 32'h0) ||
                                     (!div_op[0] &&
                                      (a == 32'h80000000) &&
                                      (b == 32'hFFFFFFFF));

                        // Pulse start for one clock; count cycles until done.
                        @(posedge clk); #1;
                        start = 1;
                        @(posedge clk); #1;   // P0: divider samples start
                        start = 0;
                        cycle_count = 0;
                        while (!done) begin
                            @(posedge clk); #1;
                            cycle_count = cycle_count + 1;
                        end

                        // Latency assertion for normal (non-trivial) divisions.
                        if (!is_trivial && cycle_count !== EXPECTED_CYCLES) begin
                            $display("FAIL test %0d [LATENCY]: a=%h b=%h div_op=%0d | cycles=%0d exp=%0d",
                                      test_num, a, b, div_op, cycle_count, EXPECTED_CYCLES);
                            failed = failed + 1;
                            total  = total  + 1;
                        end

                        if (quotient !== exp_quot || remainder !== exp_rem) begin
                            $display("FAIL test %0d: a=%h b=%h div_op=%0d | got quot=%h rem=%h | exp quot=%h rem=%h (cycles=%0d)",
                                      test_num, a, b, div_op,
                                      quotient, remainder,
                                      exp_quot, exp_rem, cycle_count);
                            failed = failed + 1;
                        end else begin
                            $display("PASS test %0d: a=%h b=%h div_op=%0d | quot=%h rem=%h (cycles=%0d)",
                                      test_num, a, b, div_op,
                                      quotient, remainder, cycle_count);
                        end
                    end
                end
            end
            $fclose(file);
        end

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
