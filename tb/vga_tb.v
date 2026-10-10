`timescale 1ns/1ps
//
// vga_tb: VGA controller. APB registers (reset values, palette, SCROLL range,
// STATUS, FRAME), the framebuffer through AHB (every size, out-of-range
// accesses, write-then-read bypass, reads that collide with the video fetch
// slot and take one wait state), sync timing, and pixels on the outputs at
// chosen beam positions (palette, 2x2 scaling, SCROLL wrap, ENABLE).
// Vector: op(dec) a(hex) b(hex) c(hex), see vectors/vga_vectors.txt.
//
module vga_tb;

    reg         clk, rst_n;
    reg         HSEL, HWRITE;
    reg  [1:0]  HTRANS;
    reg  [2:0]  HSIZE;
    reg  [31:0] HADDR, HWDATA;
    wire [31:0] HRDATA;
    wire        HREADYOUT, HRESP;
    reg         PSEL, PENABLE, PWRITE;
    reg  [31:0] PADDR, PWDATA;
    wire [31:0] PRDATA;
    wire        PREADY, PSLVERR;
    wire [3:0]  vga_r, vga_g, vga_b;
    wire        vga_hs, vga_vs;

    // The testbench is the only master and the VGA the only slave.
    wire HREADY = HREADYOUT;

    vga dut (
        .HCLK      (clk),
        .HRESETn   (rst_n),
        .HSEL      (HSEL),
        .HADDR     (HADDR),
        .HTRANS    (HTRANS),
        .HWRITE    (HWRITE),
        .HSIZE     (HSIZE),
        .HWDATA    (HWDATA),
        .HREADY    (HREADY),
        .HRDATA    (HRDATA),
        .HREADYOUT (HREADYOUT),
        .HRESP     (HRESP),
        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PADDR     (PADDR),
        .PWDATA    (PWDATA),
        .PRDATA    (PRDATA),
        .PREADY    (PREADY),
        .PSLVERR   (PSLVERR),
        .vga_r     (vga_r),
        .vga_g     (vga_g),
        .vga_b     (vga_b),
        .vga_hs    (vga_hs),
        .vga_vs    (vga_vs)
    );

    always #5 clk = ~clk;

    // ---- APB ---------------------------------------------------------------
    reg        apb_ok;
    reg [31:0] rdata;

    task apb_transfer;
        input        write;
        input [31:0] addr;
        input [31:0] data;
        begin
            apb_ok = 1'b1;
            PSEL = 1'b1; PENABLE = 1'b0; PWRITE = write; PADDR = addr; PWDATA = data;
            @(posedge clk);
            #1 PENABLE = 1'b1;
            #3 rdata = PRDATA;
            if (PREADY !== 1'b1 || PSLVERR !== 1'b0)
                apb_ok = 1'b0;
            @(posedge clk);
            #1 PSEL = 1'b0; PENABLE = 1'b0; PWRITE = 1'b0;
        end
    endtask

    // ---- AHB: single transfers, address phase then data phase ---------------
    // Inputs change 1 ns after a rising edge. ahb_waits counts the data-phase
    // cycles with HREADYOUT = 0; HRESP must stay OKAY.
    reg     ahb_ok;
    integer ahb_waits;

    function [31:0] replicate;    // what the store aligner puts on HWDATA
        input [31:0] data;
        input [2:0]  size;
        begin
            case (size)
                3'b000:  replicate = {4{data[7:0]}};
                3'b001:  replicate = {2{data[15:0]}};
                default: replicate = data;
            endcase
        end
    endfunction

    task ahb_address;
        input        write;
        input [31:0] addr;
        input [2:0]  size;
        begin
            HSEL = 1'b1; HTRANS = 2'b10; HWRITE = write; HADDR = addr; HSIZE = size;
        end
    endtask

    task ahb_idle;
        begin
            HSEL = 1'b0; HTRANS = 2'b00; HWRITE = 1'b0;
        end
    endtask

    // Wait out the data phase: on return the final data-phase cycle is under
    // way (HREADYOUT = 1) and HRDATA is valid; the next edge ends it.
    task ahb_data_phase;
        begin
            ahb_waits = 0;
            #2;
            while (HREADYOUT !== 1'b1) begin
                @(posedge clk);
                #3;
                ahb_waits = ahb_waits + 1;
            end
            if (HRESP !== 1'b0)
                ahb_ok = 1'b0;
        end
    endtask

    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        input [2:0]  size;
        begin
            ahb_ok = 1'b1;
            ahb_address(1'b1, addr, size);
            @(posedge clk);
            #1 ahb_idle;
            HWDATA = replicate(data, size);
            ahb_data_phase;
            @(posedge clk);
            #1;
        end
    endtask

    task ahb_read;
        input [31:0] addr;
        input [2:0]  size;
        begin
            ahb_ok = 1'b1;
            ahb_address(1'b0, addr, size);
            @(posedge clk);
            #1 ahb_idle;
            ahb_data_phase;
            rdata = HRDATA;
            @(posedge clk);
            #1;
        end
    endtask

    // A word write followed at once by a read of addr2: the read's address
    // phase is the write's data phase.
    task ahb_write_read;
        input [31:0] addr;
        input [31:0] data;
        input [31:0] addr2;
        begin
            ahb_ok = 1'b1;
            ahb_address(1'b1, addr, 3'b010);
            @(posedge clk);
            #1 ahb_address(1'b0, addr2, 3'b010);
            HWDATA = data;
            @(posedge clk);
            #1 ahb_idle;
            ahb_data_phase;
            rdata = HRDATA;
            @(posedge clk);
            #1;
        end
    endtask

    // ---- beam position -------------------------------------------------------
    // Wait for the second clock of pixel (h, v); the outputs registered at the
    // next edge show that pixel.
    task wait_pixel;
        input [9:0] h;
        input [9:0] v;
        begin
            @(negedge clk);
            while (!(dut.h == h && dut.v == v && dut.phase == 1'b1))
                @(negedge clk);
            @(posedge clk);
            #1;
        end
    endtask

    // ---- sync timing ---------------------------------------------------------
    // Period and low time, in clocks, of hs (which = 0) or vs (which = 1).
    integer period, low_time, t_fall, t_rise, t_next;
    task measure_sync;
        input which;
        begin
            if (which) begin
                @(negedge vga_vs); t_fall = $time;
                @(posedge vga_vs); t_rise = $time;
                @(negedge vga_vs); t_next = $time;
            end else begin
                @(negedge vga_hs); t_fall = $time;
                @(posedge vga_hs); t_rise = $time;
                @(negedge vga_hs); t_next = $time;
            end
            period   = (t_next - t_fall) / 10;
            low_time = (t_rise - t_fall) / 10;
            #1;
        end
    endtask

    integer         fd, n, op, k, waited;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      a, b, c;
    reg             ok;
    reg [31:0]      frame0;

    initial begin : watchdog
        repeat (30000000) @(posedge clk);
        $display("FAIL watchdog: no summary after 30000000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        {PSEL, PENABLE, PWRITE} = 3'b0;
        PADDR = 32'b0;
        PWDATA = 32'b0;
        HSEL = 1'b0;
        HTRANS = 2'b00;
        HWRITE = 1'b0;
        HSIZE = 3'b010;
        HADDR = 32'b0;
        HWDATA = 32'b0;
        rdata = 32'b0;
        frame0 = 32'b0;
        ahb_waits = 0;
        low_time = 0;
        total = 0;
        failed = 0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        fd = $fopen("vectors/vga_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/vga_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%d %h %h %h", op, a, b, c) == 4) begin
                    ok = 1'b1;
                    case (op)
                        // APB read a, expect b under mask c
                        0: begin apb_transfer(1'b0, a, 32'b0); ok = apb_ok && ((rdata & c) === (b & c)); end
                        // APB write b to a
                        1: begin apb_transfer(1'b1, a, b); ok = apb_ok; end
                        // AHB write b to a with size c: never waits
                        2: begin ahb_write(a, b, c[2:0]); ok = ahb_ok && ahb_waits == 0; end
                        // AHB read a with size c, expect the raw word b
                        3: begin ahb_read(a, c[2:0]); ok = ahb_ok && rdata === b; end
                        // wait a clocks
                        4: begin repeat (a) @(posedge clk); #1; end
                        // pixel h = a[9:0], v = a[25:16] shows colour b
                        5: begin
                               wait_pixel(a[9:0], a[25:16]);
                               rdata = {20'b0, vga_r, vga_g, vga_b};
                               ok = (rdata[11:0] === b[11:0]);
                           end
                        // sync a (0 hs, 1 vs): period b and low time c, in clocks
                        6: begin
                               measure_sync(a[0]);
                               rdata = period;
                               ok = (period == b) && (low_time == c);
                           end
                        // word write b to a, then at once a read of c: expect b
                        7: begin ahb_write_read(a, b, c); ok = ahb_ok && rdata === b; end
                        // a word reads of c, each expecting b, with gaps of 0..3
                        // clocks so that some address phases meet the video
                        // fetch slot: every read correct, none waits more than
                        // once, at least one waited
                        8: begin
                               waited = 0;
                               for (k = 0; k < a; k = k + 1) begin
                                   ahb_read(c, 3'b010);
                                   if (!ahb_ok || rdata !== b || ahb_waits > 1)
                                       ok = 1'b0;
                                   waited = waited + ahb_waits;
                                   repeat (k % 4) @(posedge clk);
                                   #1;
                               end
                               rdata = waited;
                               ok = ok && waited > 0;
                           end
                        // fill the whole framebuffer with word b
                        9: begin
                               for (k = 0; k < 9600; k = k + 1) begin
                                   ahb_write(4 * k, b, 3'b010);
                                   if (!ahb_ok) ok = 1'b0;
                               end
                           end
                        // the beam reaches line a: STATUS.VBLANK = b, and FRAME
                        // advanced by c since the last op 11
                        10: begin
                               wait_pixel(10'd0, a[9:0]);
                               apb_transfer(1'b0, 32'h04, 32'b0);
                               ok = apb_ok && rdata[0] === b[0];
                               apb_transfer(1'b0, 32'h0C, 32'b0);
                               ok = ok && (rdata - frame0 == c);
                           end
                        // remember FRAME
                        11: begin apb_transfer(1'b0, 32'h0C, 32'b0); frame0 = rdata; ok = apb_ok; end
                        default: ok = 1'b0;
                    endcase
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL op=%0d a=%h b=%h c=%h | got %h waits=%0d low=%0d",
                                 op, a, b, c, rdata, ahb_waits, low_time);
                    end else
                        $display("PASS op=%0d a=%h b=%h c=%h | %h", op, a, b, c, rdata);
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
