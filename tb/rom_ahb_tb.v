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
    reg [31:0] raw_word;
    reg        wait_type;   // 0 = async check (no clock), 1 = clock then check
    reg [8*256-1:0] line;
    integer failed   = 0;
    integer total    = 0;
    integer test_num = 0;

    task ahb_read_word;
        input [31:0] addr;
        input [2:0]  size;
        output [31:0] data;
        begin
            HSEL   = 1'b1;
            HWRITE = 1'b0;
            HADDR  = addr;
            HSIZE  = size;
            HTRANS = 2'b10;
            @(posedge HCLK); #1;
            data = HRDATA;
            HSEL   = 1'b0;
            HTRANS = 2'b00;
        end
    endtask

    function [31:0] lsu_load_format;
        input [31:0] word;
        input [1:0]  addr_lsb;
        input [2:0]  f3;
        reg   [7:0]  b;
        reg   [15:0] h;
        begin
            case (addr_lsb)
                2'b00: b = word[7:0];
                2'b01: b = word[15:8];
                2'b10: b = word[23:16];
                default: b = word[31:24];
            endcase

            if (addr_lsb[1] == 1'b0)
                h = word[15:0];
            else
                h = word[31:16];

            case (f3)
                3'b000:  lsu_load_format = {{24{b[7]}}, b};
                3'b100:  lsu_load_format = {24'b0, b};
                3'b001:  lsu_load_format = {{16{h[15]}}, h};
                3'b101:  lsu_load_format = {16'b0, h};
                default: lsu_load_format = word;
            endcase
        end
    endfunction

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

        // Extra directed checks for new behavior:
        // ROM must return full aligned word irrespective of HSIZE and HADDR[1:0].
        raw_word = 32'b0;
        ahb_read_word(32'h0000_0005, 3'b000, raw_word); // byte-sized read to unaligned address
        test_num = test_num + 1; total = total + 1;
        if (raw_word !== 32'hAABBCCDD) begin
            $display("FAIL test %0d: raw HRDATA=%h (exp AABBCCDD)", test_num, raw_word);
            failed = failed + 1;
        end else begin
            $display("PASS test %0d: raw HRDATA=%h", test_num, raw_word);
        end

        test_num = test_num + 1; total = total + 1;
        if (lsu_load_format(raw_word, 2'b01, 3'b000) !== 32'hFFFF_FFCC) begin
            $display("FAIL test %0d: LSU LB result=%h (exp FFFFFFCC)", test_num,
                     lsu_load_format(raw_word, 2'b01, 3'b000));
            failed = failed + 1;
        end else begin
            $display("PASS test %0d: LSU LB result=%h", test_num,
                     lsu_load_format(raw_word, 2'b01, 3'b000));
        end

        raw_word = 32'b0;
        ahb_read_word(32'h0000_0006, 3'b101, raw_word); // halfword-sized read to unaligned address
        test_num = test_num + 1; total = total + 1;
        if (raw_word !== 32'hAABBCCDD) begin
            $display("FAIL test %0d: raw HRDATA=%h (exp AABBCCDD)", test_num, raw_word);
            failed = failed + 1;
        end else begin
            $display("PASS test %0d: raw HRDATA=%h", test_num, raw_word);
        end

        test_num = test_num + 1; total = total + 1;
        if (lsu_load_format(raw_word, 2'b10, 3'b101) !== 32'h0000_AABB) begin
            $display("FAIL test %0d: LSU LHU result=%h (exp 0000AABB)", test_num,
                     lsu_load_format(raw_word, 2'b10, 3'b101));
            failed = failed + 1;
        end else begin
            $display("PASS test %0d: LSU LHU result=%h", test_num,
                     lsu_load_format(raw_word, 2'b10, 3'b101));
        end

        $display("-----------------------------");
        if (failed == 0)
            $display("ALL %0d TESTS PASSED", total);
        else
            $display("%0d / %0d TESTS FAILED", failed, total);
        $display("-----------------------------");

        $finish;
    end

endmodule
