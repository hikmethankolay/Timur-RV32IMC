`timescale 1ns/1ps
//
// divider_tb: results, corner cases, latency and the done/ack handshake
// (Phase 2). For each vector the testbench pulses start for one cycle,
// counts cycles until done, checks both results and the latency, checks that
// done stays at 1 without ack (fast path included), then pulses ack and
// checks that done clears.
// Vector: a(hex) b(hex) div_op(dec) quotient(hex) remainder(hex) cycles_in_ex(dec)
// cycles_in_ex counts the start cycle through the cycle in which done is seen.
//
module divider_tb;

    reg         clk, rst_n, start, ack;
    reg  [31:0] a, b;
    reg  [1:0]  div_op;
    wire [31:0] quotient, remainder;
    wire        busy, done;

    divider dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .ack       (ack),
        .a         (a),
        .b         (b),
        .div_op    (div_op),
        .quotient  (quotient),
        .remainder (remainder),
        .busy      (busy),
        .done      (done)
    );

    always #5 clk = ~clk;

    integer         fd, n;
    integer         total, failed;
    integer         cycles, exp_cycles, held;
    reg [8*256-1:0] line;
    reg [31:0]      exp_q, exp_r;
    reg             ok;

    initial begin : watchdog
        repeat (20000) @(posedge clk);
        $display("FAIL watchdog: no summary after 20000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        ack = 1'b0;
        a = 32'b0;
        b = 32'b0;
        div_op = 2'b0;
        total = 0;
        failed = 0;
        @(posedge clk);
        #1 rst_n = 1'b1;

        fd = $fopen("vectors/divider_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/divider_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %d %h %h %d", a, b, div_op, exp_q, exp_r, exp_cycles) == 6) begin
                    ok = 1'b1;

                    // start cycle: the DIV's first cycle in EX
                    start = 1'b1;
                    cycles = 1;
                    @(posedge clk);
                    #1 start = 1'b0;
                    cycles = cycles + 1;
                    while (!done && cycles < 100) begin
                        @(posedge clk);
                        #1 cycles = cycles + 1;
                    end

                    if (quotient !== exp_q || remainder !== exp_r || cycles !== exp_cycles || busy !== 1'b0)
                        ok = 1'b0;

                    // done is a level: it must stay at 1 while no ack arrives
                    held = 0;
                    repeat (3) begin
                        @(posedge clk);
                        #1 if (done === 1'b1) held = held + 1;
                    end
                    if (held != 3)
                        ok = 1'b0;

                    // ack (the DIV leaves EX) clears done on the next edge
                    ack = 1'b1;
                    @(posedge clk);
                    #1 ack = 1'b0;
                    if (done !== 1'b0 || busy !== 1'b0)
                        ok = 1'b0;

                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL a=%h b=%h op=%0d | got q=%h r=%h cycles=%0d held=%0d done_after_ack=%b | expected q=%h r=%h cycles=%0d",
                                 a, b, div_op, quotient, remainder, cycles, held, done, exp_q, exp_r, exp_cycles);
                    end else
                        $display("PASS a=%h b=%h op=%0d | q=%h r=%h cycles=%0d",
                                 a, b, div_op, quotient, remainder, cycles);
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
