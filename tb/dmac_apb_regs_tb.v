`timescale 1ns/1ps
//
// dmac_apb_regs_tb: DMAC control registers (Phase 8): read/write
// registers, one-cycle start pulse on a CTRL write (ignored while busy),
// STATUS mirrors the engine's busy, done sticky until the next CTRL write,
// irq = done AND irq_enable.
// Vector: op(dec) a(hex) b(hex) c(hex), see vectors/dmac_apb_regs_vectors.txt.
//
module dmac_apb_regs_tb;

    reg         clk, rst_n;
    reg         PSEL, PENABLE, PWRITE;
    reg  [31:0] PADDR, PWDATA;
    wire [31:0] PRDATA;
    wire        PREADY, PSLVERR;
    wire [31:0] dmac_src, dmac_dst, dmac_len;
    wire        dmac_start;
    reg         dmac_busy, dmac_done;
    wire        irq;

    dmac_apb_regs dut (
        .PCLK       (clk),
        .PRESETn    (rst_n),
        .PSEL       (PSEL),
        .PENABLE    (PENABLE),
        .PWRITE     (PWRITE),
        .PADDR      (PADDR),
        .PWDATA     (PWDATA),
        .PRDATA     (PRDATA),
        .PREADY     (PREADY),
        .PSLVERR    (PSLVERR),
        .dmac_src   (dmac_src),
        .dmac_dst   (dmac_dst),
        .dmac_len   (dmac_len),
        .dmac_start (dmac_start),
        .dmac_busy  (dmac_busy),
        .dmac_done  (dmac_done),
        .irq        (irq)
    );

    always #5 clk = ~clk;

    // start-pulse monitor
    integer start_pulses;
    reg     start_prev;
    reg     long_pulse;
    always @(posedge clk) begin
        if (dmac_start === 1'b1) begin
            start_pulses = start_pulses + 1;
            if (start_prev === 1'b1)
                long_pulse = 1'b1;
        end
        start_prev = dmac_start;
    end

    reg        apb_ok;
    reg [31:0] rdata;

    task apb_transfer;
        input        write;
        input [31:0] addr;
        input [31:0] data;
        input        done_in_access;
        begin
            apb_ok = 1'b1;
            PSEL = 1'b1; PENABLE = 1'b0; PWRITE = write; PADDR = addr; PWDATA = data;
            @(posedge clk);
            #1 PENABLE = 1'b1;
            dmac_done = done_in_access;
            #3 rdata = PRDATA;
            if (PREADY !== 1'b1 || PSLVERR !== 1'b0)
                apb_ok = 1'b0;
            @(posedge clk);
            #1 PSEL = 1'b0; PENABLE = 1'b0; PWRITE = 1'b0;
            dmac_done = 1'b0;
            // let a start pulse from this write complete before the next check
            @(posedge clk);
            #1;
        end
    endtask

    integer         fd, n, op;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      a, b, c;
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
        dmac_busy = 1'b0;
        dmac_done = 1'b0;
        start_pulses = 0;
        start_prev = 1'b0;
        long_pulse = 1'b0;
        total = 0;
        failed = 0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        fd = $fopen("vectors/dmac_apb_regs_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/dmac_apb_regs_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%d %h %h %h", op, a, b, c) == 4) begin
                    ok = 1'b1;
                    case (op)
                        0: begin apb_transfer(1'b0, a, 32'b0, 1'b0); ok = apb_ok && (rdata === b); end
                        1: begin apb_transfer(1'b1, a, b, 1'b0);     ok = apb_ok; end
                        2: dmac_busy = a[0];
                        3: begin
                               dmac_done = 1'b1;
                               @(posedge clk);
                               #1 dmac_done = 1'b0;
                           end
                        4: begin
                               ok = (start_pulses == a) && !long_pulse;
                               start_pulses = 0;
                           end
                        5: ok = (dmac_src === a) && (dmac_dst === b) && (dmac_len === c);
                        6: ok = (irq === a[0]);
                        7: begin apb_transfer(1'b1, a, b, 1'b1);     ok = apb_ok; end
                        default: ok = 1'b0;
                    endcase
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL op=%0d a=%h b=%h c=%h | prdata=%h src=%h dst=%h len=%h pulses=%0d irq=%b",
                                 op, a, b, c, rdata, dmac_src, dmac_dst, dmac_len, start_pulses, irq);
                    end else
                        $display("PASS op=%0d a=%h b=%h c=%h | prdata=%h", op, a, b, c, rdata);
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
