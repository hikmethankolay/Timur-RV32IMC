`timescale 1ns/1ps
//
// mux2_tb: mux2 at widths 1, 5, 8 and 32 (Phase 1).
// Vector: width(dec) in0(hex) in1(hex) sel(bin) expected(hex); each vector
// drives the DUT of its width, waits 10 ns and compares.
//
module mux2_tb;

    reg         in0_w1,  in1_w1,  sel_w1;
    wire        out_w1;
    reg  [4:0]  in0_w5,  in1_w5;
    reg         sel_w5;
    wire [4:0]  out_w5;
    reg  [7:0]  in0_w8,  in1_w8;
    reg         sel_w8;
    wire [7:0]  out_w8;
    reg  [31:0] in0_w32, in1_w32;
    reg         sel_w32;
    wire [31:0] out_w32;

    mux2 #(.WIDTH(1))  dut_w1  (.in0(in0_w1),  .in1(in1_w1),  .sel(sel_w1),  .out(out_w1));
    mux2 #(.WIDTH(5))  dut_w5  (.in0(in0_w5),  .in1(in1_w5),  .sel(sel_w5),  .out(out_w5));
    mux2 #(.WIDTH(8))  dut_w8  (.in0(in0_w8),  .in1(in1_w8),  .sel(sel_w8),  .out(out_w8));
    mux2 #(.WIDTH(32)) dut_w32 (.in0(in0_w32), .in1(in1_w32), .sel(sel_w32), .out(out_w32));

    integer         fd, n, width;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      in0, in1, exp, got;
    reg             sel;
    reg             known;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        total = 0;
        failed = 0;
        {in0_w1, in1_w1, sel_w1} = 3'b0;
        {in0_w5, in1_w5, sel_w5} = 11'b0;
        {in0_w8, in1_w8, sel_w8} = 17'b0;
        {in0_w32, in1_w32, sel_w32} = 65'b0;

        fd = $fopen("vectors/mux2_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/mux2_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%d %h %h %b %h", width, in0, in1, sel, exp) == 5) begin
                    known = 1'b1;
                    case (width)
                        1:  begin in0_w1  = in0[0];   in1_w1  = in1[0];   sel_w1  = sel; end
                        5:  begin in0_w5  = in0[4:0]; in1_w5  = in1[4:0]; sel_w5  = sel; end
                        8:  begin in0_w8  = in0[7:0]; in1_w8  = in1[7:0]; sel_w8  = sel; end
                        32: begin in0_w32 = in0;      in1_w32 = in1;      sel_w32 = sel; end
                        default: known = 1'b0;
                    endcase
                    #10;
                    case (width)
                        1:       got = {31'b0, out_w1};
                        5:       got = {27'b0, out_w5};
                        8:       got = {24'b0, out_w8};
                        default: got = out_w32;
                    endcase
                    total = total + 1;
                    if (!known || got !== exp) begin
                        failed = failed + 1;
                        $display("FAIL [W=%0d] in0=%h in1=%h sel=%b | got=%h expected=%h",
                                 width, in0, in1, sel, got, exp);
                    end else
                        $display("PASS [W=%0d] in0=%h in1=%h sel=%b | out=%h",
                                 width, in0, in1, sel, got);
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
