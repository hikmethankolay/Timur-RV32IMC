`timescale 1ns/1ps
//
// forwarding_unit_tb: 10 (EX/MEM) and 01 (WB) forwarding, EX/MEM priority,
// no forwarding for rd = x0 or RegWrite = 0 (Phase 7).
// Vector: id_ex_rs1 id_ex_rs2 ex_mem_rd (hex) ex_mem_regwrite(bin)
//         mem_wb_rd(hex) mem_wb_regwrite(bin) forwardA forwardB (bin)
//
module forwarding_unit_tb;

    reg  [4:0] id_ex_rs1, id_ex_rs2, ex_mem_rd, mem_wb_rd;
    reg        ex_mem_regwrite, mem_wb_regwrite;
    wire [1:0] forwardA, forwardB;

    forwarding_unit dut (
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_regwrite (ex_mem_regwrite),
        .mem_wb_rd       (mem_wb_rd),
        .mem_wb_regwrite (mem_wb_regwrite),
        .forwardA        (forwardA),
        .forwardB        (forwardB)
    );

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [1:0]       exp_a, exp_b;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        {id_ex_rs1, id_ex_rs2, ex_mem_rd, mem_wb_rd} = 20'b0;
        {ex_mem_regwrite, mem_wb_regwrite} = 2'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/forwarding_unit_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/forwarding_unit_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %h %h %b %h %b %b %b", id_ex_rs1, id_ex_rs2, ex_mem_rd,
                            ex_mem_regwrite, mem_wb_rd, mem_wb_regwrite, exp_a, exp_b) == 8) begin
                    #10;
                    total = total + 1;
                    if (forwardA !== exp_a || forwardB !== exp_b) begin
                        failed = failed + 1;
                        $display("FAIL rs1=%h rs2=%h ex_rd=%h/%b wb_rd=%h/%b | got A=%b B=%b | expected A=%b B=%b",
                                 id_ex_rs1, id_ex_rs2, ex_mem_rd, ex_mem_regwrite, mem_wb_rd, mem_wb_regwrite,
                                 forwardA, forwardB, exp_a, exp_b);
                    end else
                        $display("PASS rs1=%h rs2=%h ex_rd=%h/%b wb_rd=%h/%b | A=%b B=%b",
                                 id_ex_rs1, id_ex_rs2, ex_mem_rd, ex_mem_regwrite, mem_wb_rd, mem_wb_regwrite,
                                 forwardA, forwardB);
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
