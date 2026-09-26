`timescale 1ns/1ps
//
// registers_tb: x0 hard-wired to 0, synchronous write, asynchronous reads and
// the same-cycle write-through bypass on both ports (Phase 3).
// Vector: reg_write(bin) rd_addr rd_data rs1_addr rs2_addr exp_rs1 exp_rs2 (hex) wait_type.
//
module registers_tb;

    reg         clk;
    reg  [4:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] rd_data;
    reg         reg_write;
    wire [31:0] rs1_data, rs2_data;

    registers dut (
        .clk       (clk),
        .rs1_addr  (rs1_addr),
        .rs2_addr  (rs2_addr),
        .rd_addr   (rd_addr),
        .rd_data   (rd_data),
        .reg_write (reg_write),
        .rs1_data  (rs1_data),
        .rs2_data  (rs2_data)
    );

    always #5 clk = ~clk;

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      exp_rs1, exp_rs2;
    reg             wait_type;

    initial begin : watchdog
        repeat (1000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        reg_write = 1'b0;
        rd_addr = 5'b0;
        rd_data = 32'b0;
        rs1_addr = 5'b0;
        rs2_addr = 5'b0;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/registers_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/registers_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %h %h %h %h %h %h %b", reg_write, rd_addr, rd_data,
                            rs1_addr, rs2_addr, exp_rs1, exp_rs2, wait_type) == 8) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    total = total + 1;
                    if (rs1_data !== exp_rs1 || rs2_data !== exp_rs2) begin
                        failed = failed + 1;
                        $display("FAIL we=%b rd=%h data=%h rs1=%h rs2=%h wait=%b | got %h %h | expected %h %h",
                                 reg_write, rd_addr, rd_data, rs1_addr, rs2_addr, wait_type,
                                 rs1_data, rs2_data, exp_rs1, exp_rs2);
                    end else
                        $display("PASS we=%b rd=%h data=%h rs1=%h rs2=%h wait=%b | %h %h",
                                 reg_write, rd_addr, rd_data, rs1_addr, rs2_addr, wait_type,
                                 rs1_data, rs2_data);
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
