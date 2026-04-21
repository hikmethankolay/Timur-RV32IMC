`timescale 1ns/1ps
module rom_ahb_tb;

    reg         HCLK, HRESETn, HSEL, HWRITE;
    reg  [31:0] HADDR, HWDATA;
    reg  [1:0]  HTRANS;
    reg  [2:0]  HSIZE;
    wire [31:0] HRDATA;
    wire        HREADY, HRESP;

    rom_ahb dut (
        .HCLK   (HCLK),
        .HRESETn(HRESETn),
        .HSEL   (HSEL),
        .HADDR  (HADDR),
        .HTRANS (HTRANS),
        .HWRITE (HWRITE),
        .HSIZE  (HSIZE),
        .HWDATA (HWDATA),
        .HRDATA (HRDATA),
        .HREADY (HREADY),
        .HRESP  (HRESP)
    );

    always #5 HCLK = ~HCLK;

    integer file, r, slen;
    reg [31:0] exp_hrdata;
    reg        wait_type;   // 0 = async check (no clock), 1 = clock then check
    reg [8*256-1:0] line;
    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    initial begin
        HCLK    = 0;
        HRESETn = 0;
        HSEL    = 0;
        HADDR   = 32'h0000_0000;
        HTRANS  = 2'b00;
        HWRITE  = 0;
        HSIZE   = 3'b010;
        HWDATA  = 32'h0000_0000;

        // Let ROM's initial block (fill + $readmemh) finish before
        // overriding specific words with known test values.
        #1;
        dut.mem[0] = 32'h00000013;  // NOP  — byte addr 0x000
        dut.mem[1] = 32'hAABBCCDD;  //        byte addr 0x004
        dut.mem[2] = 32'hDEADBEEF;  //        byte addr 0x008
        dut.mem[3] = 32'hCAFEBABE;  //        byte addr 0x00C
        dut.mem[4] = 32'h12345678;  //        byte addr 0x010
        dut.mem[5] = 32'hABCDABCD;  //        byte addr 0x014

        file = $fopen("tb/vectors/rom_ahb_vectors.txt", "r");
        if (file == 0) begin
            $display("ERROR: could not open rom_ahb_vectors.txt");
            $finish;
        end

        while (!$feof(file)) begin
            line = 0;
            slen = $fgets(line, file);
            if (slen > 0) begin
                r = $sscanf(line, "%b %b %h %h %h %b",
                            HRESETn, HSEL, HADDR, HTRANS,
                            exp_hrdata, wait_type);
                if (r == 6) begin
                    test_num = test_num + 1;
                    total    = total    + 1;

                    if (wait_type == 1'b0) begin
                        #3;
                    end else begin
                        @(posedge HCLK); #1;
                    end

                    if (HRDATA !== exp_hrdata) begin
                        $display("FAIL test %0d: HRESETn=%b HSEL=%b HADDR=%h HTRANS=%h | HRDATA=%h (exp %h)",
                                  test_num, HRESETn, HSEL, HADDR, HTRANS, HRDATA, exp_hrdata);
                        failed = failed + 1;
                    end else begin
                        $display("PASS test %0d: HRESETn=%b HSEL=%b HADDR=%h HTRANS=%h | HRDATA=%h",
                                  test_num, HRESETn, HSEL, HADDR, HTRANS, HRDATA);
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
