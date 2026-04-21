`timescale 1ns/1ps
module pc_tb;

    reg         clk, rst_n, en;
    reg  [31:0] pc_next;
    wire [31:0] pc;

    pc dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (en),
        .pc_next(pc_next),
        .pc     (pc)
    );

    always #5 clk = ~clk;

    integer file, r, slen;
    reg [31:0] exp;
    reg        wait_type;   // 0 = async check (no clock), 1 = clock then check
    reg [8*256-1:0] line;
    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    initial begin
        clk     = 0;
        rst_n   = 1;
        en      = 0;
        pc_next = 32'h0000_0000;

        file = $fopen("tb/vectors/pc_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open pc_vectors.txt");
            $finish;
        end

        while (!$feof(file)) begin
            line = 0;
            slen = $fgets(line, file);
            if (slen > 0) begin
                r = $sscanf(line, "%b %b %h %h %b", rst_n, en, pc_next, exp, wait_type);
                if (r == 5) begin
                    test_num = test_num + 1;
                    total    = total    + 1;

                    if (wait_type == 1'b0) begin
                        #3;
                    end else begin
                        @(posedge clk); #1;
                    end

                    if (pc !== exp) begin
                        $display("FAIL test %0d: rst_n=%b en=%b pc_next=%h | got=%h expected=%h",
                                  test_num, rst_n, en, pc_next, pc, exp);
                        failed = failed + 1;
                    end else begin
                        $display("PASS test %0d: rst_n=%b en=%b pc_next=%h | pc=%h",
                                  test_num, rst_n, en, pc_next, pc);
                    end
                end
            end
        end

        $fclose(file);

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");

        $finish;
    end

endmodule
