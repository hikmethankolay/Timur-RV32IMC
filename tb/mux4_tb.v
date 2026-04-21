`timescale 1ns/1ps
//
// mux4_tb — multi-width regression for the mux4 primitive.
// Instantiates two DUTs (WIDTH = 8, 32) and drives each from its own
// vector file. Pass/fail counters are shared so the outer runner sees
// a single (failed, total) pair.
//
module mux4_tb;

    // ─── WIDTH = 8 DUT ──────────────────────────────────────────
    reg  [7:0]  in0_w8, in1_w8, in2_w8, in3_w8;
    reg  [1:0]  sel_w8;
    wire [7:0]  out_w8;
    mux4 #(.WIDTH(8)) dut_w8 (
        .in0(in0_w8), .in1(in1_w8), .in2(in2_w8), .in3(in3_w8),
        .sel(sel_w8), .out(out_w8)
    );

    // ─── WIDTH = 32 DUT ─────────────────────────────────────────
    reg  [31:0] in0_w32, in1_w32, in2_w32, in3_w32;
    reg  [1:0]  sel_w32;
    wire [31:0] out_w32;
    mux4 #(.WIDTH(32)) dut_w32 (
        .in0(in0_w32), .in1(in1_w32), .in2(in2_w32), .in3(in3_w32),
        .sel(sel_w32), .out(out_w32)
    );

    // ─── shared bookkeeping ─────────────────────────────────────
    integer          file, r, slen;
    reg [8*256-1:0]  line;
    integer          failed   = 0;
    integer          total    = 0;
    integer          test_num = 0;

    // ------------------------------------------------------------
    // One task per width. Each parses its own vector file and
    // drives its own DUT, updating the shared counters.
    // ------------------------------------------------------------
    task run_width_8(input [8*64-1:0] filename);
        reg [31:0] in0_tmp, in1_tmp, in2_tmp, in3_tmp, exp_tmp;
        reg [1:0]  sel_tmp;
        begin
            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("ERROR: could not open mux4_w8_vectors.txt");
                failed = failed + 1;
            end else begin
                while (!$feof(file)) begin
                    line = 0;
                    slen = $fgets(line, file);
                    if (slen > 0) begin
                        r = $sscanf(line, "%h %h %h %h %b %h",
                                    in0_tmp, in1_tmp, in2_tmp, in3_tmp,
                                    sel_tmp, exp_tmp);
                        if (r == 6) begin
                            in0_w8 = in0_tmp[7:0];
                            in1_w8 = in1_tmp[7:0];
                            in2_w8 = in2_tmp[7:0];
                            in3_w8 = in3_tmp[7:0];
                            sel_w8 = sel_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (out_w8 !== exp_tmp[7:0]) begin
                                $display("FAIL [W=8]  test %0d: sel=%b | got=%h exp=%h",
                                          test_num, sel_w8, out_w8, exp_tmp[7:0]);
                                failed = failed + 1;
                            end else begin
                                $display("PASS [W=8]  test %0d: sel=%b | out=%h",
                                          test_num, sel_w8, out_w8);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    task run_width_32(input [8*64-1:0] filename);
        reg [31:0] in0_tmp, in1_tmp, in2_tmp, in3_tmp, exp_tmp;
        reg [1:0]  sel_tmp;
        begin
            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("ERROR: could not open mux4_w32_vectors.txt");
                failed = failed + 1;
            end else begin
                while (!$feof(file)) begin
                    line = 0;
                    slen = $fgets(line, file);
                    if (slen > 0) begin
                        r = $sscanf(line, "%h %h %h %h %b %h",
                                    in0_tmp, in1_tmp, in2_tmp, in3_tmp,
                                    sel_tmp, exp_tmp);
                        if (r == 6) begin
                            in0_w32 = in0_tmp;
                            in1_w32 = in1_tmp;
                            in2_w32 = in2_tmp;
                            in3_w32 = in3_tmp;
                            sel_w32 = sel_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (out_w32 !== exp_tmp) begin
                                $display("FAIL [W=32] test %0d: sel=%b | got=%h exp=%h",
                                          test_num, sel_w32, out_w32, exp_tmp);
                                failed = failed + 1;
                            end else begin
                                $display("PASS [W=32] test %0d: sel=%b | out=%h",
                                          test_num, sel_w32, out_w32);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    initial begin
        run_width_8 ("vectors/mux4_w8_vectors.txt");
        run_width_32("vectors/mux4_w32_vectors.txt");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
