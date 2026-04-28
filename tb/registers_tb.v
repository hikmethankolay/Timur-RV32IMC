`timescale 1ns/1ps
module registers_tb;

    reg         clk;
    reg  [4:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] rd_data;
    reg         reg_write;
    wire [31:0] rs1_data, rs2_data;

    registers dut (
        .clk      (clk),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .reg_write(reg_write),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    always #5 clk = ~clk;

    integer file, r, slen;
    reg [31:0] exp_rs1, exp_rs2;
    reg        wait_type;   // 0 = async check (no clock), 1 = clock then check
    reg [8*256-1:0] line;
    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    initial begin
        clk       = 0;
        reg_write = 0;
        rd_addr   = 5'h00;
        rd_data   = 32'h0000_0000;
        rs1_addr  = 5'h00;
        rs2_addr  = 5'h00;

        file = $fopen("tb/vectors/registers_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open registers_vectors.txt");
            $finish;
        end

        while (!$feof(file)) begin
            line = 0;
            slen = $fgets(line, file);
            if (slen > 0) begin
                r = $sscanf(line, "%b %h %h %h %h %h %h %b",
                            reg_write, rd_addr, rd_data,
                            rs1_addr, rs2_addr,
                            exp_rs1, exp_rs2, wait_type);
                if (r == 8) begin
                    test_num = test_num + 1;
                    total    = total    + 1;

                    if (wait_type == 1'b0) begin
                        #3;
                    end else begin
                        @(negedge clk); #1;
                    end

                    if (rs1_data !== exp_rs1 || rs2_data !== exp_rs2) begin
                        $display("FAIL test %0d: reg_write=%b rd_addr=%h rd_data=%h rs1_addr=%h rs2_addr=%h | rs1=%h (exp %h)  rs2=%h (exp %h)",
                                  test_num, reg_write, rd_addr, rd_data,
                                  rs1_addr, rs2_addr,
                                  rs1_data, exp_rs1, rs2_data, exp_rs2);
                        failed = failed + 1;
                    end else begin
                        $display("PASS test %0d: reg_write=%b rd_addr=%h rd_data=%h rs1_addr=%h rs2_addr=%h | rs1=%h rs2=%h",
                                  test_num, reg_write, rd_addr, rd_data,
                                  rs1_addr, rs2_addr,
                                  rs1_data, rs2_data);
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
