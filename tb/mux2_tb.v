`timescale 1ns/1ps
//
// mux2_tb — multi-width regression for the mux2 primitive.
// Instantiates three DUTs in parallel (WIDTH = 1, 5, 32) and drives
// each one from its own vector file.  Pass/fail counters are shared
// so the outer runner sees a single (failed, total) pair.
//
module mux2_tb;

    // ─── WIDTH = 1 DUT ──────────────────────────────────────────
    reg         in0_w1, in1_w1, sel_w1;
    wire        out_w1;
    mux2 #(.WIDTH(1)) dut_w1 (
        .in0(in0_w1), .in1(in1_w1), .sel(sel_w1), .out(out_w1)
    );

    // ─── WIDTH = 5 DUT ──────────────────────────────────────────
    reg  [4:0]  in0_w5, in1_w5;
    reg         sel_w5;
    wire [4:0]  out_w5;
    mux2 #(.WIDTH(5)) dut_w5 (
        .in0(in0_w5), .in1(in1_w5), .sel(sel_w5), .out(out_w5)
    );

    // ─── WIDTH = 32 DUT ─────────────────────────────────────────
    reg  [31:0] in0_w32, in1_w32;
    reg         sel_w32;
    wire [31:0] out_w32;
    mux2 #(.WIDTH(32)) dut_w32 (
        .in0(in0_w32), .in1(in1_w32), .sel(sel_w32), .out(out_w32)
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
    task run_width_1(input [8*64-1:0] filename);
        reg [31:0] in0_tmp, in1_tmp, exp_tmp;
        reg        sel_tmp;
        begin
            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("ERROR: could not open mux2_w1_vectors.txt");
                failed = failed + 1;
            end else begin
                while (!$feof(file)) begin
                    line = 0;
                    slen = $fgets(line, file);
                    if (slen > 0) begin
                        r = $sscanf(line, "%h %h %b %h",
                                    in0_tmp, in1_tmp, sel_tmp, exp_tmp);
                        if (r == 4) begin
                            in0_w1 = in0_tmp[0];
                            in1_w1 = in1_tmp[0];
                            sel_w1 = sel_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (out_w1 !== exp_tmp[0]) begin
                                $display("FAIL [W=1]  test %0d: in0=%b in1=%b sel=%b | got=%b exp=%b",
                                          test_num, in0_w1, in1_w1, sel_w1, out_w1, exp_tmp[0]);
                                failed = failed + 1;
                            end else begin
                                $display("PASS [W=1]  test %0d: in0=%b in1=%b sel=%b | out=%b",
                                          test_num, in0_w1, in1_w1, sel_w1, out_w1);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    task run_width_5(input [8*64-1:0] filename);
        reg [31:0] in0_tmp, in1_tmp, exp_tmp;
        reg        sel_tmp;
        begin
            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("ERROR: could not open mux2_w5_vectors.txt");
                failed = failed + 1;
            end else begin
                while (!$feof(file)) begin
                    line = 0;
                    slen = $fgets(line, file);
                    if (slen > 0) begin
                        r = $sscanf(line, "%h %h %b %h",
                                    in0_tmp, in1_tmp, sel_tmp, exp_tmp);
                        if (r == 4) begin
                            in0_w5 = in0_tmp[4:0];
                            in1_w5 = in1_tmp[4:0];
                            sel_w5 = sel_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (out_w5 !== exp_tmp[4:0]) begin
                                $display("FAIL [W=5]  test %0d: in0=%h in1=%h sel=%b | got=%h exp=%h",
                                          test_num, in0_w5, in1_w5, sel_w5, out_w5, exp_tmp[4:0]);
                                failed = failed + 1;
                            end else begin
                                $display("PASS [W=5]  test %0d: in0=%h in1=%h sel=%b | out=%h",
                                          test_num, in0_w5, in1_w5, sel_w5, out_w5);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    task run_width_32(input [8*64-1:0] filename);
        reg [31:0] in0_tmp, in1_tmp, exp_tmp;
        reg        sel_tmp;
        begin
            file = $fopen(filename, "r");
            if (file == 0) begin
                $display("ERROR: could not open mux2_w32_vectors.txt");
                failed = failed + 1;
            end else begin
                while (!$feof(file)) begin
                    line = 0;
                    slen = $fgets(line, file);
                    if (slen > 0) begin
                        r = $sscanf(line, "%h %h %b %h",
                                    in0_tmp, in1_tmp, sel_tmp, exp_tmp);
                        if (r == 4) begin
                            in0_w32 = in0_tmp;
                            in1_w32 = in1_tmp;
                            sel_w32 = sel_tmp;
                            #10;
                            test_num = test_num + 1;
                            total    = total    + 1;
                            if (out_w32 !== exp_tmp) begin
                                $display("FAIL [W=32] test %0d: in0=%h in1=%h sel=%b | got=%h exp=%h",
                                          test_num, in0_w32, in1_w32, sel_w32, out_w32, exp_tmp);
                                failed = failed + 1;
                            end else begin
                                $display("PASS [W=32] test %0d: in0=%h in1=%h sel=%b | out=%h",
                                          test_num, in0_w32, in1_w32, sel_w32, out_w32);
                            end
                        end
                    end
                end
                $fclose(file);
            end
        end
    endtask

    initial begin
        run_width_1 ("vectors/mux2_w1_vectors.txt");
        run_width_5 ("vectors/mux2_w5_vectors.txt");
        run_width_32("vectors/mux2_w32_vectors.txt");

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");
        $finish;
    end

endmodule
