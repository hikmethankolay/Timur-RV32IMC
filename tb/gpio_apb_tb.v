`timescale 1ns/1ps
//
// gpio_apb_tb: APB SETUP/ACCESS, GPIO_OUT drives the pins, GPIO_IN through
// the two-flop synchroniser, GPIO_DIR read/write (Phase 8).
// Vector: op(dec) a(hex) b(hex), see vectors/gpio_apb_vectors.txt.
//
module gpio_apb_tb;

    reg         clk, rst_n;
    reg         PSEL, PENABLE, PWRITE;
    reg  [31:0] PADDR, PWDATA;
    wire [31:0] PRDATA;
    wire        PREADY, PSLVERR;
    wire [9:0]  gpio_out;
    reg  [9:0]  gpio_in;

    gpio_apb dut (
        .PCLK     (clk),
        .PRESETn  (rst_n),
        .PSEL     (PSEL),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PADDR    (PADDR),
        .PWDATA   (PWDATA),
        .PRDATA   (PRDATA),
        .PREADY   (PREADY),
        .PSLVERR  (PSLVERR),
        .gpio_out (gpio_out),
        .gpio_in  (gpio_in)
    );

    always #5 clk = ~clk;

    reg        apb_ok;
    reg [31:0] rdata;

    // SETUP then ACCESS; PREADY = 1 and PSLVERR = 0 checked in ACCESS.
    task apb_transfer;
        input        sel;
        input        write;
        input [31:0] addr;
        input [31:0] data;
        reg   [9:0]  out_before;
        begin
            apb_ok = 1'b1;
            out_before = gpio_out;
            PSEL = sel; PENABLE = 1'b0; PWRITE = write; PADDR = addr; PWDATA = data;
            @(posedge clk);
            #1;
            if (gpio_out !== out_before)        // nothing may happen in SETUP
                apb_ok = 1'b0;
            PENABLE = 1'b1;
            #3;
            rdata = PRDATA;
            if (PREADY !== 1'b1 || PSLVERR !== 1'b0)
                apb_ok = 1'b0;
            @(posedge clk);
            #1;
            PSEL = 1'b0; PENABLE = 1'b0; PWRITE = 1'b0;
        end
    endtask

    integer         fd, n, op;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      a, b;
    reg             ok;

    initial begin : watchdog
        repeat (5000) @(posedge clk);
        $display("FAIL watchdog: no summary after 5000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        {PSEL, PENABLE, PWRITE} = 3'b0;
        PADDR = 32'b0;
        PWDATA = 32'b0;
        gpio_in = 10'b0;
        total = 0;
        failed = 0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        fd = $fopen("vectors/gpio_apb_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/gpio_apb_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%d %h %h", op, a, b) == 3) begin
                    ok = 1'b1;
                    case (op)
                        0: begin apb_transfer(1'b1, 1'b0, a, 32'b0); ok = apb_ok && (rdata === b); end
                        1: begin apb_transfer(1'b1, 1'b1, a, b);     ok = apb_ok; end
                        2: gpio_in = a[9:0];
                        3: ok = (gpio_out === a[9:0]);
                        4: repeat (a) @(posedge clk);
                        5: begin apb_transfer(1'b0, 1'b1, a, b);     ok = apb_ok; end
                        default: ok = 1'b0;
                    endcase
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL op=%0d a=%h b=%h | prdata=%h gpio_out=%h pready=%b pslverr=%b",
                                 op, a, b, rdata, gpio_out, PREADY, PSLVERR);
                    end else
                        $display("PASS op=%0d a=%h b=%h | prdata=%h gpio_out=%h", op, a, b, rdata, gpio_out);
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
