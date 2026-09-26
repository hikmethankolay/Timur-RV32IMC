`timescale 1ns/1ps
//
// pc_tb: asynchronous reset to 0, hold with en = 0, load with en = 1
// (Phase 3).
// Vector: rst_n(bin) en(bin) pc_next(hex) expected_pc(hex) wait_type.
//
module pc_tb;

    reg         clk, rst_n, en;
    reg  [31:0] pc_next;
    wire [31:0] pc;

    pc dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (en),
        .pc_next (pc_next),
        .pc      (pc)
    );

    always #5 clk = ~clk;

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp;
    reg             wait_type;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        en = 1'b0;
        pc_next = 32'b0;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/pc_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/pc_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %h %h %b", rst_n, en, pc_next, exp, wait_type) == 5) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (pc !== exp) begin
                        failed = failed + 1;
                        $display("FAIL rst_n=%b en=%b pc_next=%h wait=%b | got=%h expected=%h",
                                 rst_n, en, pc_next, wait_type, pc, exp);
                    end else
                        $display("PASS rst_n=%b en=%b pc_next=%h wait=%b | pc=%h",
                                 rst_n, en, pc_next, wait_type, pc);
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
