`timescale 1ns/1ps
//
// forwarding_unit_tb — vector-driven regression for the forwarding_unit module.
// Purely combinational: apply the 6 inputs, wait #10, check {forwardA, forwardB}.
//
// Vector format (one test per line):
//   id_ex_rs1 id_ex_rs2 ex_mem_rd ex_mem_regwrite mem_wb_rd mem_wb_regwrite expA expB
//     - rs1/rs2/ex_rd/wb_rd : 5-bit, hex (2 digits)
//     - ex_rw/wb_rw         : 1-bit, binary
//     - expA/expB           : 2-bit, binary
//
module forwarding_unit_tb;

    reg  [4:0] id_ex_rs1;
    reg  [4:0] id_ex_rs2;
    reg  [4:0] ex_mem_rd;
    reg        ex_mem_regwrite;
    reg  [4:0] mem_wb_rd;
    reg        mem_wb_regwrite;
    wire [1:0] forwardA;
    wire [1:0] forwardB;

    forwarding_unit dut (
        .id_ex_rs1      (id_ex_rs1),
        .id_ex_rs2      (id_ex_rs2),
        .ex_mem_rd      (ex_mem_rd),
        .ex_mem_regwrite(ex_mem_regwrite),
        .mem_wb_rd      (mem_wb_rd),
        .mem_wb_regwrite(mem_wb_regwrite),
        .forwardA       (forwardA),
        .forwardB       (forwardB)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    task run_vectors(input [8*64-1:0] filename);
        reg [4:0] rs1_tmp, rs2_tmp, exrd_tmp, wbrd_tmp;
        reg       exrw_tmp, wbrw_tmp;
        reg [1:0] expA, expB;
        begin
            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("ERROR: could not open %0s", filename);
                failed = failed + 1;
            end else begin
                while (!$feof(file)) begin
                    line = 0;
                    slen = $fgets(line, file);
                    if (slen > 0) begin
                        r = $sscanf(line, "%h %h %h %b %h %b %b %b",
                                    rs1_tmp, rs2_tmp,
                                    exrd_tmp, exrw_tmp,
                                    wbrd_tmp, wbrw_tmp,
                                    expA, expB);
                        if (r == 8) begin
                            id_ex_rs1       = rs1_tmp;
                            id_ex_rs2       = rs2_tmp;
                            ex_mem_rd       = exrd_tmp;
                            ex_mem_regwrite = exrw_tmp;
                            mem_wb_rd       = wbrd_tmp;
                            mem_wb_regwrite = wbrw_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (forwardA !== expA || forwardB !== expB) begin
                                $display("FAIL test %0d: rs1=%h rs2=%h | exrd=%h rw=%b | wbrd=%h rw=%b | got A=%b B=%b | exp A=%b B=%b",
                                          test_num,
                                          id_ex_rs1, id_ex_rs2,
                                          ex_mem_rd, ex_mem_regwrite,
                                          mem_wb_rd, mem_wb_regwrite,
                                          forwardA, forwardB, expA, expB);
                                failed = failed + 1;
                            end else begin
                                $display("PASS test %0d: rs1=%h rs2=%h | exrd=%h rw=%b | wbrd=%h rw=%b | A=%b B=%b",
                                          test_num,
                                          id_ex_rs1, id_ex_rs2,
                                          ex_mem_rd, ex_mem_regwrite,
                                          mem_wb_rd, mem_wb_regwrite,
                                          forwardA, forwardB);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    initial begin
        id_ex_rs1       = 5'b0;
        id_ex_rs2       = 5'b0;
        ex_mem_rd       = 5'b0;
        ex_mem_regwrite = 1'b0;
        mem_wb_rd       = 5'b0;
        mem_wb_regwrite = 1'b0;

        run_vectors("tb/vectors/forwarding_unit_vectors.txt");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
