`timescale 1ns/1ps
//
// mux4_tb: mux4 at widths 8 and 32 (Phase 1).
// Vector: width(dec) in0 in1 in2 in3 (hex) sel(bin) expected(hex).
//
module mux4_tb;

    reg  [7:0]  in0_w8, in1_w8, in2_w8, in3_w8;
    reg  [1:0]  sel_w8;
    wire [7:0]  out_w8;
    reg  [31:0] in0_w32, in1_w32, in2_w32, in3_w32;
    reg  [1:0]  sel_w32;
    wire [31:0] out_w32;

    mux4 #(.WIDTH(8)) dut_w8 (
        .in0(in0_w8), .in1(in1_w8), .in2(in2_w8), .in3(in3_w8), .sel(sel_w8), .out(out_w8)
    );

    mux4 #(.WIDTH(32)) dut_w32 (
        .in0(in0_w32), .in1(in1_w32), .in2(in2_w32), .in3(in3_w32), .sel(sel_w32), .out(out_w32)
    );

    integer         fd, n, width;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      in0, in1, in2, in3, exp, got;
    reg [1:0]       sel;
    reg             known;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        total = 0;
        failed = 0;
        {in0_w8, in1_w8, in2_w8, in3_w8, sel_w8} = 34'b0;
        {in0_w32, in1_w32, in2_w32, in3_w32, sel_w32} = 130'b0;

        fd = $fopen("vectors/mux4_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/mux4_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%d %h %h %h %h %b %h", width, in0, in1, in2, in3, sel, exp) == 7) begin
                    known = 1'b1;
                    case (width)
                        8: begin
                            in0_w8 = in0[7:0]; in1_w8 = in1[7:0];
                            in2_w8 = in2[7:0]; in3_w8 = in3[7:0];
                            sel_w8 = sel;
                        end
                        32: begin
                            in0_w32 = in0; in1_w32 = in1;
                            in2_w32 = in2; in3_w32 = in3;
                            sel_w32 = sel;
                        end
                        default: known = 1'b0;
                    endcase
                    #10;
                    got = (width == 8) ? {24'b0, out_w8} : out_w32;
                    total = total + 1;
                    if (!known || got !== exp) begin
                        failed = failed + 1;
                        $display("FAIL [W=%0d] in=%h/%h/%h/%h sel=%b | got=%h expected=%h",
                                 width, in0, in1, in2, in3, sel, got, exp);
                    end else
                        $display("PASS [W=%0d] in=%h/%h/%h/%h sel=%b | out=%h",
                                 width, in0, in1, in2, in3, sel, got);
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
