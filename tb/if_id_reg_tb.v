`timescale 1ns/1ps
//
// if_id_reg_tb: capture, hold, flush and reset of IF/ID (Phase 6, with
// is_compressed from Phase 11); a bubble is valid = 0 and is_compressed = 0
// with the NOP 00000013.
// Vector: rst_n enable flush (bin) in_seed(hex) expect(bin) exp_seed(hex) wait_type
// Inputs are derived from in_seed; expect = 1 checks the fields of exp_seed,
// expect = 0 checks a bubble.
//
module if_id_reg_tb;

    reg         clk, rst_n, enable, flush;
    reg  [31:0] pc_in, instr_in;
    reg         is_compressed_in, valid_in;
    wire [31:0] pc_out, instr_out;
    wire        is_compressed_out, valid_out;

    if_id_reg dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .flush     (flush),
        .pc_in     (pc_in),
        .instr_in          (instr_in),
        .is_compressed_in  (is_compressed_in),
        .valid_in          (valid_in),
        .pc_out            (pc_out),
        .instr_out         (instr_out),
        .is_compressed_out (is_compressed_out),
        .valid_out         (valid_out)
    );

    always #5 clk = ~clk;

    function [65:0] fields;
        input [31:0] s;
        fields = {s, ~s, s[30], s[31]};   // pc, instr, is_compressed, valid
    endfunction

    wire [65:0] got = {pc_out, instr_out, is_compressed_out, valid_out};

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      in_seed, exp_seed;
    reg             expect_fields, wait_type;
    reg [65:0]      exp;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b1;
        enable = 1'b0;
        flush = 1'b0;
        {pc_in, instr_in, is_compressed_in, valid_in} = 66'b0;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/if_id_reg_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/if_id_reg_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b %h %b %h %b", rst_n, enable, flush, in_seed,
                            expect_fields, exp_seed, wait_type) == 7) begin
                    {pc_in, instr_in, is_compressed_in, valid_in} = fields(in_seed);
                    exp = expect_fields ? fields(exp_seed) : {32'h00000000, 32'h00000013, 1'b0, 1'b0};
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (got !== exp) begin
                        failed = failed + 1;
                        $display("FAIL rst_n=%b en=%b flush=%b seed=%h | got pc=%h instr=%h c=%b v=%b | expected pc=%h instr=%h c=%b v=%b",
                                 rst_n, enable, flush, in_seed, pc_out, instr_out, is_compressed_out, valid_out,
                                 exp[65:34], exp[33:2], exp[1], exp[0]);
                    end else
                        $display("PASS rst_n=%b en=%b flush=%b seed=%h | pc=%h instr=%h v=%b",
                                 rst_n, enable, flush, in_seed, pc_out, instr_out, valid_out);
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
