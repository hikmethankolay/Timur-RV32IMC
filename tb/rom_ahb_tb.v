`timescale 1ns/1ps
//
// rom_ahb_tb: instruction ROM (Phase 3, split banks from Phase 11).
//   1. The LO and HI banks hold the low and high halves of the words of
//      rom.hex over a zero fill, and the first word comes out of the fetch port.
//   2. With a known pattern in the banks: fetch port latency, 32-bit windows
//      at word and halfword alignment, AHB address phase registered only with
//      HSEL & HTRANS[1] & HREADY, writes ignored, both ports independent,
//      HREADYOUT = 1, HRESP = 0.
// The testbench plays the fetch logic: for byte address A it presents
// LO index (A + 2) >> 2, HI index A >> 2 and A[1].
// Vector: fetch_addr HSEL HTRANS HWRITE HREADY HADDR HWDATA check exp_fetch exp_HRDATA wait_type
//
module rom_ahb_tb;

    reg         clk, rst_n;
    reg  [31:0] fetch_addr;
    wire [31:0] fetch_instr;
    wire [31:0] fetch_plus2 = fetch_addr + 32'd2;
    reg         HSEL, HWRITE, HREADY;
    reg  [1:0]  HTRANS;
    reg  [2:0]  HSIZE;
    reg  [31:0] HADDR, HWDATA;
    wire [31:0] HRDATA;
    wire        HREADYOUT, HRESP;

    rom_ahb dut (
        .HCLK        (clk),
        .HRESETn     (rst_n),
        .fetch_lo_index (fetch_plus2[15:2]),
        .fetch_hi_index (fetch_addr[15:2]),
        .fetch_odd      (fetch_addr[1]),
        .fetch_window   (fetch_instr),
        .HSEL        (HSEL),
        .HADDR       (HADDR),
        .HTRANS      (HTRANS),
        .HWRITE      (HWRITE),
        .HSIZE       (HSIZE),
        .HWDATA      (HWDATA),
        .HREADY      (HREADY),
        .HRDATA      (HRDATA),
        .HREADYOUT   (HREADYOUT),
        .HRESP       (HRESP)
    );

    always #5 clk = ~clk;

    reg [31:0] image [0:16383];

    integer         fd, n, i, mismatches;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [1:0]       check;
    reg [31:0]      exp_fetch, exp_hrdata;
    reg             wait_type;
    reg             ok;

    initial begin : watchdog
        repeat (2000) @(posedge clk);
        $display("FAIL watchdog: no summary after 2000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        fetch_addr = 32'b0;
        HSEL = 1'b0;
        HTRANS = 2'b00;
        HWRITE = 1'b0;
        HSIZE = 3'b010;
        HREADY = 1'b1;
        HADDR = 32'b0;
        HWDATA = 32'b0;
        total = 0;
        failed = 0;
        #1 rst_n = 1'b1;

        // ---- 1. ROM image ------------------------------------------------
        for (i = 0; i < 16384; i = i + 1)
            image[i] = 32'h00000000;
        $readmemh("rom.hex", image);
        mismatches = 0;
        for (i = 0; i < 16384; i = i + 1)
            if (dut.lo[i] !== image[i][15:0] || dut.hi[i] !== image[i][31:16])
                mismatches = mismatches + 1;
        total = total + 1;
        if (mismatches != 0) begin
            failed = failed + 1;
            $display("FAIL ROM image: %0d words of rom_lo.hex/rom_hi.hex differ from rom.hex over a zero fill", mismatches);
        end else
            $display("PASS ROM banks equal rom.hex over a zero fill (LO = low halves, HI = high halves)");

        @(posedge clk);
        #1;
        total = total + 1;
        if (fetch_instr !== image[0]) begin
            failed = failed + 1;
            $display("FAIL first word: fetch_instr=%h expected=%h (rom.hex word 0)", fetch_instr, image[0]);
        end else
            $display("PASS first word from the fetch port matches rom.hex: %h", fetch_instr);

        // ---- 2. vectors on a known pattern -------------------------------
        for (i = 0; i < 16384; i = i + 1) begin
            dut.hi[i] = {2'b01, i[13:0]};
            dut.lo[i] = {2'b10, i[13:0]};
        end

        fd = $fopen("vectors/rom_ahb_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/rom_ahb_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%h %b %b %b %b %h %h %b %h %h %b", fetch_addr, HSEL, HTRANS, HWRITE,
                            HREADY, HADDR, HWDATA, check, exp_fetch, exp_hrdata, wait_type) == 11) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    ok = (HREADYOUT === 1'b1) && (HRESP === 1'b0);
                    if (check[0] && fetch_instr !== exp_fetch)
                        ok = 1'b0;
                    if (check[1] && HRDATA !== exp_hrdata)
                        ok = 1'b0;
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL fetch_addr=%h hsel=%b htrans=%b hwrite=%b hready=%b haddr=%h | got fetch=%h hrdata=%h ready=%b resp=%b | expected fetch=%h hrdata=%h (check=%b)",
                                 fetch_addr, HSEL, HTRANS, HWRITE, HREADY, HADDR, fetch_instr, HRDATA,
                                 HREADYOUT, HRESP, exp_fetch, exp_hrdata, check);
                    end else
                        $display("PASS fetch_addr=%h hsel=%b htrans=%b hwrite=%b hready=%b haddr=%h | fetch=%h hrdata=%h (check=%b)",
                                 fetch_addr, HSEL, HTRANS, HWRITE, HREADY, HADDR, fetch_instr, HRDATA, check);
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
