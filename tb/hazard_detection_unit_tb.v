`timescale 1ns/1ps
//
// hazard_detection_unit_tb — vector-driven regression for the hazard_detection_unit module.
// Purely combinational: apply the 6 inputs, wait #10, check stall.
//
// Vector format (one test per line):
//   memread  id_ex_rd  if_id_rs1  if_id_rs2  hready  div_busy  exp_stall
//     - memread / hready / div_busy / exp_stall : 1-bit, binary
//     - id_ex_rd / if_id_rs1 / if_id_rs2       : 5-bit, hex (2 digits)
//
module hazard_detection_unit_tb;

    reg        id_ex_memread;
    reg  [4:0] id_ex_rd;
    reg  [4:0] if_id_rs1;
    reg  [4:0] if_id_rs2;
    reg        hready;
    reg        div_busy;
    wire       stall;

    hazard_detection_unit dut (
        .id_ex_memread(id_ex_memread),
        .id_ex_rd     (id_ex_rd),
        .if_id_rs1    (if_id_rs1),
        .if_id_rs2    (if_id_rs2),
        .hready       (hready),
        .div_busy     (div_busy),
        .stall        (stall)
    );

    integer          file, r, slen;
    reg [8*256-1:0]  line;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    task run_vectors(input [8*64-1:0] filename);
        reg       mr_tmp, hr_tmp, db_tmp;
        reg [4:0] rd_tmp, rs1_tmp, rs2_tmp;
        reg       exp_tmp;
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
                        r = $sscanf(line, "%b %h %h %h %b %b %b",
                                    mr_tmp,
                                    rd_tmp, rs1_tmp, rs2_tmp,
                                    hr_tmp, db_tmp,
                                    exp_tmp);
                        if (r == 7) begin
                            id_ex_memread = mr_tmp;
                            id_ex_rd      = rd_tmp;
                            if_id_rs1     = rs1_tmp;
                            if_id_rs2     = rs2_tmp;
                            hready        = hr_tmp;
                            div_busy      = db_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (stall !== exp_tmp) begin
                                $display("FAIL test %0d: mr=%b rd=%h rs1=%h rs2=%h hr=%b db=%b | got stall=%b | exp=%b",
                                          test_num,
                                          id_ex_memread,
                                          id_ex_rd, if_id_rs1, if_id_rs2,
                                          hready, div_busy,
                                          stall, exp_tmp);
                                failed = failed + 1;
                            end else begin
                                $display("PASS test %0d: mr=%b rd=%h rs1=%h rs2=%h hr=%b db=%b | stall=%b",
                                          test_num,
                                          id_ex_memread,
                                          id_ex_rd, if_id_rs1, if_id_rs2,
                                          hready, div_busy,
                                          stall);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    initial begin
        id_ex_memread = 1'b0;
        id_ex_rd      = 5'b0;
        if_id_rs1     = 5'b0;
        if_id_rs2     = 5'b0;
        hready        = 1'b1;
        div_busy      = 1'b0;

        run_vectors("tb/vectors/hazard_detection_unit_vectors.txt");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
