`timescale 1ns/1ps
//
// ex_mem_reg_tb: EX/MEM capture, hold (enable = 0, bus freeze), flush and
// reset (Phase 6).
// Vector: rst_n enable flush (bin) in_seed(hex) expect(bin) exp_seed(hex) wait_type
//
module ex_mem_reg_tb;

    reg         clk, rst_n, enable, flush;
    reg  [31:0] result_in, store_data_in;
    reg  [4:0]  rd_addr_in;
    reg  [2:0]  funct3_in;
    reg         MemRead_in, MemWrite_in, MemToReg_in, RegWrite_in, valid_in;
    wire [31:0] result_out, store_data_out;
    wire [4:0]  rd_addr_out;
    wire [2:0]  funct3_out;
    wire        MemRead_out, MemWrite_out, MemToReg_out, RegWrite_out, valid_out;

    ex_mem_reg dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .flush          (flush),
        .result_in      (result_in),
        .store_data_in  (store_data_in),
        .rd_addr_in     (rd_addr_in),
        .funct3_in      (funct3_in),
        .MemRead_in     (MemRead_in),
        .MemWrite_in    (MemWrite_in),
        .MemToReg_in    (MemToReg_in),
        .RegWrite_in    (RegWrite_in),
        .valid_in       (valid_in),
        .result_out     (result_out),
        .store_data_out (store_data_out),
        .rd_addr_out    (rd_addr_out),
        .funct3_out     (funct3_out),
        .MemRead_out    (MemRead_out),
        .MemWrite_out   (MemWrite_out),
        .MemToReg_out   (MemToReg_out),
        .RegWrite_out   (RegWrite_out),
        .valid_out      (valid_out)
    );

    always #5 clk = ~clk;

    function [76:0] fields;
        input [31:0] s;
        fields = {s, ~s, s[4:0], s[7:5], s[8], s[9], s[10], s[11], s[31]};
    endfunction

    wire [76:0] got = {result_out, store_data_out, rd_addr_out, funct3_out,
                       MemRead_out, MemWrite_out, MemToReg_out, RegWrite_out, valid_out};

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      in_seed, exp_seed;
    reg             expect_fields, wait_type;
    reg [76:0]      exp;

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
        {result_in, store_data_in, rd_addr_in, funct3_in,
         MemRead_in, MemWrite_in, MemToReg_in, RegWrite_in, valid_in} = 77'b0;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/ex_mem_reg_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/ex_mem_reg_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %b %h %b %h %b", rst_n, enable, flush, in_seed,
                            expect_fields, exp_seed, wait_type) == 7) begin
                    {result_in, store_data_in, rd_addr_in, funct3_in,
                     MemRead_in, MemWrite_in, MemToReg_in, RegWrite_in, valid_in} = fields(in_seed);
                    exp = expect_fields ? fields(exp_seed) : 77'b0;
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (got !== exp) begin
                        failed = failed + 1;
                        $display("FAIL rst_n=%b en=%b flush=%b seed=%h | got=%h | expected=%h",
                                 rst_n, enable, flush, in_seed, got, exp);
                    end else
                        $display("PASS rst_n=%b en=%b flush=%b seed=%h | result=%h valid=%b",
                                 rst_n, enable, flush, in_seed, result_out, valid_out);
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
