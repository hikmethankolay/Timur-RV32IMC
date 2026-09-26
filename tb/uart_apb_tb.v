`timescale 1ns/1ps
//
// uart_apb_tb: UART at 115200 baud with the 50 MHz divider (Phase 8):
// transmit frame timing and bits, tx_busy for the whole frame, receive by
// loopback and from testbench-driven frames, rx_valid / rx_overrun, glitch
// and framing-error rejection, receiver disabled after reset, irq.
// Vector: op(dec) a(hex) b(hex) c(hex), see vectors/uart_apb_vectors.txt.
//
module uart_apb_tb;

    localparam BIT = 434;   // DIVIDER + 1 cycles per bit

    reg         clk, rst_n;
    reg         PSEL, PENABLE, PWRITE;
    reg  [31:0] PADDR, PWDATA;
    wire [31:0] PRDATA;
    wire        PREADY, PSLVERR;
    wire        uart_tx;
    wire        irq;
    reg         loopback;
    reg         rx_drive;
    wire        uart_rx = loopback ? uart_tx : rx_drive;

    uart_apb dut (
        .PCLK    (clk),
        .PRESETn (rst_n),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PADDR   (PADDR),
        .PWDATA  (PWDATA),
        .PRDATA  (PRDATA),
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx),
        .irq     (irq)
    );

    always #5 clk = ~clk;

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

    // Check the frame that started on the preceding ACCESS edge: every cycle
    // of the 10 bits must carry the expected level (start 0, data LSB first,
    // stop 1), which checks both the bits and the 434-cycle bit time, and
    // tx_busy must be high for exactly the 4340 cycles of the frame.
    reg        frame_ok;
    reg [7:0]  frame_byte;
    reg [9:0]  frame;
    integer    k, busy_cycles, wait_start;
    task check_tx_frame;
        input [7:0] expected;
        begin
            frame = {1'b1, expected, 1'b0};
            frame_ok = 1'b1;
            frame_byte = 8'h00;
            wait_start = 0;
            while (uart_tx !== 1'b0 && wait_start < 20) begin
                @(posedge clk);
                #1 wait_start = wait_start + 1;
            end
            busy_cycles = 0;
            for (k = 0; k < 10 * BIT; k = k + 1) begin
                if (uart_tx !== frame[k / BIT])
                    frame_ok = 1'b0;
                if (k / BIT >= 1 && k / BIT <= 8 && k % BIT == BIT / 2)
                    frame_byte[k / BIT - 1] = uart_tx;
                if (dut.tx_busy === 1'b1)
                    busy_cycles = busy_cycles + 1;
                @(posedge clk);
                #1;
            end
            if (busy_cycles != 10 * BIT)
                frame_ok = 1'b0;
            if (dut.tx_busy !== 1'b0 || uart_tx !== 1'b1)   // frame over after 10 bits
                frame_ok = 1'b0;
        end
    endtask

    task send_frame;
        input [7:0] data;
        input       stop;
        integer     i;
        begin
            rx_drive = 1'b0;
            repeat (BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_drive = data[i];
                repeat (BIT) @(posedge clk);
            end
            rx_drive = stop;
            repeat (BIT) @(posedge clk);
            rx_drive = 1'b1;
            repeat (BIT) @(posedge clk);
            #1;
        end
    endtask

    integer         fd, n, op;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      a, b, c;
    reg             ok;

    initial begin : watchdog
        repeat (200000) @(posedge clk);
        $display("FAIL watchdog: no summary after 200000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        {PSEL, PENABLE, PWRITE} = 3'b0;
        PADDR = 32'b0;
        PWDATA = 32'b0;
        loopback = 1'b0;
        rx_drive = 1'b1;
        total = 0;
        failed = 0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;

        fd = $fopen("vectors/uart_apb_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/uart_apb_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%d %h %h %h", op, a, b, c) == 4) begin
                    ok = 1'b1;
                    case (op)
                        0: begin apb_transfer(1'b0, a, 32'b0); ok = apb_ok && ((rdata & c) === (b & c)); end
                        1: begin apb_transfer(1'b1, a, b);     ok = apb_ok; end
                        2: loopback = a[0];
                        3: begin repeat (a) @(posedge clk); #1; end
                        4: begin check_tx_frame(a[7:0]); ok = frame_ok; end
                        5: send_frame(a[7:0], 1'b1);
                        6: begin
                               rx_drive = 1'b0;
                               repeat (a) @(posedge clk);
                               rx_drive = 1'b1;
                               #1;
                           end
                        7: ok = (irq === a[0]);
                        8: begin
                               repeat (a) begin
                                   @(posedge clk);
                                   if (uart_tx !== 1'b1) ok = 1'b0;
                               end
                               #1;
                           end
                        9: send_frame(a[7:0], 1'b0);
                        default: ok = 1'b0;
                    endcase
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL op=%0d a=%h b=%h c=%h | prdata=%h tx=%b irq=%b frame=%h busy_cycles=%0d",
                                 op, a, b, c, rdata, uart_tx, irq, frame_byte, busy_cycles);
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
