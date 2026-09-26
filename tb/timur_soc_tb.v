`timescale 1ns/1ps
//
// timur_soc_tb: system tests of the pipelined SoC (Phases 5-11).
// vectors/timur_soc_vectors.txt lists the test programs (ROM images) and
// their expected results; sw/gen_soc_tests.py generates both. For each PROG
// the testbench loads the image into the ROM, clears the RAM, resets the SoC
// and runs it until the halt instruction leaves EX, then checks the
// directives that follow (registers, RAM, LEDs, UART bytes or text, divider
// starts, the order in which instructions left EX). A UARTIN directive before
// a PROG gives the program input on uart_rx: each byte is sent once the
// receiver is enabled and the previous byte has been read. UARTSHOW only
// prints what the program sent (for programs whose output nothing predicts).
// Parameters: VECTORS (the vector file) and UART_DIVIDER (the SoC's UART,
// f_clk / baud - 1). tb/timur_sw_tb.v reuses this testbench for the C
// programs of Phase 12 with a faster UART.
// Checked every cycle during a run:
//   - the fetch window holds the 32 bits at the PC, and IF/ID holds the
//     instruction at its pc (the expansion of a 16-bit instruction, from a
//     reference decompressor), through load-use, EX and bus stalls
//   - each MUL gets one multiplier start and stalls exactly one cycle
//   - exactly one divider start per DIV
//   - a load-use costs exactly one bubble
//   - no CPU bus access with a misaligned address (such accesses trap in EX)
//   - no interrupt is taken while a MUL or DIV is in EX
// Run with +trace to print PC, instruction and x1-x14 every cycle.
// With hready_waits = 1 the RAM's HREADYOUT is forced low for three cycles
// in the data phase of every RAM load, so HREADY is low for three cycles
// while the load is in WB, with garbage on HRDATA until the last cycle.
//
module timur_soc_tb;

    parameter  VECTORS      = "vectors/timur_soc_vectors.txt";
    parameter  UART_DIVIDER = 433;              // 115200 baud at 50 MHz
    localparam BIT          = UART_DIVIDER + 1; // UART cycles per bit
    localparam TRACE_MAX    = 4096;
    localparam UART_MAX     = 16384;            // bytes kept per program, each direction

    reg        clk, rst_n;
    reg  [9:0] gpio_in;
    wire [9:0] gpio_out;
    wire       uart_tx;
    reg        uart_rx;

    timur_soc #(.UART_DIVIDER(UART_DIVIDER)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .gpio_in  (gpio_in),
        .gpio_out (gpio_out),
        .uart_rx  (uart_rx),
        .uart_tx  (uart_tx)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Per-cycle monitors
    // ------------------------------------------------------------------
    reg         running;
    reg         halted;
    reg  [31:0] halt_pc;
    integer     cycles, retired;
    reg  [31:0] trace [0:TRACE_MAX-1];
    integer     align_errors, mul_count, mul_errors, mul_starts_pending, mul_stall_cycles;
    integer     div_starts, div_errors, starts_pending, lu_errors;
    integer     misaligned_accesses, irq_errors, irq_held;
    reg         last_load_use;

    reg print_trace;
    initial print_trace = $test$plusargs("trace");

    // Reference fetch: the 32 bits at a byte address A are LO[(A + 2) >> 2] and
    // HI[A >> 2], ordered by A[1] (the ROM's split banks).
    wire [31:0] if_pc2    = dut.if_pc + 32'd2;
    wire [31:0] exp_fetch = dut.if_pc[1] ? {dut.u_rom.lo[if_pc2[15:2]], dut.u_rom.hi[dut.if_pc[15:2]]}
                                         : {dut.u_rom.hi[dut.if_pc[15:2]], dut.u_rom.lo[dut.if_pc[15:2]]};
    wire [31:0] id_pc2    = dut.if_id_pc + 32'd2;
    wire [31:0] id_window = dut.if_id_pc[1] ? {dut.u_rom.lo[id_pc2[15:2]], dut.u_rom.hi[dut.if_id_pc[15:2]]}
                                            : {dut.u_rom.hi[dut.if_id_pc[15:2]], dut.u_rom.lo[dut.if_id_pc[15:2]]};
    wire [31:0] id_expanded;
    wire        id_is_16  = (id_window[1:0] != 2'b11);
    wire [31:0] exp_id    = id_is_16 ? id_expanded : id_window;

    decompressor u_ref_decompressor (
        .instr16 (id_window[15:0]),
        .instr32 (id_expanded),
        .illegal ()
    );

    always @(posedge clk) begin
        if (running && rst_n) begin
            cycles = cycles + 1;

            if (print_trace)
                $display("cycle %0d  IF pc=%h | ID pc=%h instr=%h v=%b | x1-x14: %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                         cycles, dut.if_pc, dut.if_id_pc, dut.if_id_instr, dut.if_id_valid,
                         dut.u_regs.regs[1], dut.u_regs.regs[2], dut.u_regs.regs[3], dut.u_regs.regs[4],
                         dut.u_regs.regs[5], dut.u_regs.regs[6], dut.u_regs.regs[7], dut.u_regs.regs[8],
                         dut.u_regs.regs[9], dut.u_regs.regs[10], dut.u_regs.regs[11], dut.u_regs.regs[12],
                         dut.u_regs.regs[13], dut.u_regs.regs[14]);

            if (dut.fetch_window !== exp_fetch)
                align_errors = align_errors + 1;
            if (dut.if_id_valid && (dut.if_id_instr !== exp_id || dut.if_id_compressed !== id_is_16))
                align_errors = align_errors + 1;

            if (dut.mul_start)
                mul_starts_pending = mul_starts_pending + 1;
            if (dut.id_ex_valid && dut.id_ex_alucontrol[4:2] == 3'b100 && !dut.bus_wait && !dut.pc_load)
                mul_stall_cycles = mul_stall_cycles + 1;
            if (dut.mul_ack) begin
                mul_count = mul_count + 1;
                if (mul_starts_pending != 1 || mul_stall_cycles != 1)
                    mul_errors = mul_errors + 1;
                mul_starts_pending = 0;
                mul_stall_cycles = 0;
            end

            if (dut.div_start) begin
                div_starts = div_starts + 1;
                starts_pending = starts_pending + 1;
            end
            if (dut.div_ack) begin
                if (starts_pending != 1)
                    div_errors = div_errors + 1;
                starts_pending = 0;
            end

            if (!dut.bus_wait) begin
                if (dut.u_hazard.load_use && last_load_use)
                    lu_errors = lu_errors + 1;
                last_load_use = dut.u_hazard.load_use;
            end

            // a load or store address phase with an address not aligned to its size
            if (dut.cpu_htrans[1] && ((dut.cpu_hsize == 3'b010 && dut.cpu_haddr[1:0] != 2'b00) ||
                                      (dut.cpu_hsize == 3'b001 && dut.cpu_haddr[0])))
                misaligned_accesses = misaligned_accesses + 1;
            if (dut.take_trap && dut.trap_cause[31] && (dut.mul_in_ex || dut.div_in_ex))
                irq_errors = irq_errors + 1;
            if (dut.csr_irq_pending && (dut.mul_in_ex || dut.div_in_ex))
                irq_held = irq_held + 1;

            if (!halted && dut.ex_mem_enable && !dut.ex_mem_flush && dut.id_ex_valid) begin
                if (retired < TRACE_MAX)
                    trace[retired] = dut.id_ex_pc;
                retired = retired + 1;
                if (dut.id_ex_pc == halt_pc)
                    halted = 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    // UART monitor: 8N1 at BIT cycles per bit, sampled at the bit centres
    // ------------------------------------------------------------------
    reg  [7:0] uart_bytes [0:UART_MAX-1];
    integer    uart_count, uart_errors, ui;
    reg        uart_active;
    reg  [7:0] ubyte;

    initial begin
        uart_count = 0;
        uart_errors = 0;
        uart_active = 1'b0;
        forever begin
            @(negedge uart_tx);
            if (rst_n === 1'b1) begin
                uart_active = 1'b1;
                repeat (BIT / 2) @(posedge clk);
                if (uart_tx !== 1'b0)
                    uart_errors = uart_errors + 1;
                for (ui = 0; ui < 8; ui = ui + 1) begin
                    repeat (BIT) @(posedge clk);
                    ubyte[ui] = uart_tx;
                end
                repeat (BIT) @(posedge clk);
                if (uart_tx !== 1'b1)
                    uart_errors = uart_errors + 1;
                if (uart_count < UART_MAX)
                    uart_bytes[uart_count] = ubyte;
                uart_count = uart_count + 1;
                uart_active = 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // UART input: the bytes of the last UARTIN, 8N1 at BIT cycles per bit.
    // A byte is sent only while the receiver is enabled and holds no unread
    // byte, as if typed slowly enough that nothing is ever overrun.
    // ------------------------------------------------------------------
    reg  [7:0] rx_bytes [0:UART_MAX-1];
    integer    rx_total, rx_sent, rj;

    initial begin
        uart_rx = 1'b1;
        rx_total = 0;
        rx_sent = 0;
        forever begin
            @(posedge clk);
            if (running && rst_n && rx_sent < rx_total && dut.u_uart.rx_enable && !dut.u_uart.rx_valid) begin
                uart_rx = 1'b0;                          // start bit
                repeat (BIT) @(posedge clk);
                for (rj = 0; rj < 8; rj = rj + 1) begin  // data, LSB first
                    uart_rx = rx_bytes[rx_sent][rj];
                    repeat (BIT) @(posedge clk);
                end
                uart_rx = 1'b1;                          // stop bit
                repeat (BIT) @(posedge clk);
                rx_sent = rx_sent + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // HREADY wait injection: the RAM inserts three wait states into the
    // data phase of every CPU load it accepts. AHB only guarantees HRDATA in
    // the last cycle of a data phase, so HRDATA carries garbage while
    // HREADY is low: anything that uses the load data early (for example a
    // divider start during the wait) computes a wrong result.
    // ------------------------------------------------------------------
    reg     inject;
    integer injected;

    always @(posedge clk) begin
        if (inject && running && rst_n && dut.u_cpu_master.accepted && !dut.cpu_hwrite && dut.hsel_ram) begin
            #1;
            force dut.hreadyout_ram = 1'b0;
            force dut.hrdata_ram = 32'hDEADBEEF;
            repeat (3) @(posedge clk);
            #1;
            release dut.hreadyout_ram;
            release dut.hrdata_ram;
            injected = injected + 1;
        end
    end

    // ------------------------------------------------------------------
    // One program
    // ------------------------------------------------------------------
    integer i, guard;
    reg [31:0] image_words [0:16383];

    task run_program;
        input [8*64-1:0] file;
        input integer    limit;
        input [31:0]     halt;
        input            waits;
        begin
            running = 1'b0;
            rst_n = 1'b0;
            for (i = 0; i < 16384; i = i + 1) begin
                image_words[i]     = 32'h00000000;
                dut.u_ram.lane0[i] = 8'h00;
                dut.u_ram.lane1[i] = 8'h00;
                dut.u_ram.lane2[i] = 8'h00;
                dut.u_ram.lane3[i] = 8'h00;
            end
            $readmemh(file, image_words);
            for (i = 0; i < 16384; i = i + 1) begin
                dut.u_rom.lo[i] = image_words[i][15:0];
                dut.u_rom.hi[i] = image_words[i][31:16];
            end
            // the register file has no reset: start every program from zero
            for (i = 0; i < 32; i = i + 1)
                dut.u_regs.regs[i] = 32'h00000000;
            halt_pc = halt;
            halted = 1'b0;
            cycles = 0;
            retired = 0;
            align_errors = 0;
            mul_count = 0;
            mul_errors = 0;
            mul_starts_pending = 0;
            mul_stall_cycles = 0;
            div_starts = 0;
            div_errors = 0;
            starts_pending = 0;
            lu_errors = 0;
            misaligned_accesses = 0;
            irq_errors = 0;
            irq_held = 0;
            last_load_use = 1'b0;
            uart_count = 0;
            uart_errors = 0;
            injected = 0;
            inject = waits;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            running = 1'b1;
            while (!halted && cycles < limit)
                @(posedge clk);
            guard = 0;
            if (halt == 32'hFFFFFFFF) begin
                // endless loop: finish the UART frame being decoded
                while (uart_active && guard < 50000) begin
                    @(posedge clk);
                    guard = guard + 1;
                end
            end else begin
                repeat (20) @(posedge clk);             // drain MEM and WB
                while ((dut.u_uart.tx_busy || uart_active) && guard < 50000) begin
                    @(posedge clk);
                    guard = guard + 1;
                end
            end
            running = 1'b0;
            inject = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // Directives
    // ------------------------------------------------------------------
    integer         fd, n, total, failed;
    integer         max_cycles, waits, idx, expected, count, trace_pos, uart_pos;
    integer         tfd, ch, mismatch, k;
    reg [7:0]       exp_byte;
    reg [8*256-1:0] line;
    reg [8*16-1:0]  kw;
    reg [8*64-1:0]  image, textfile;
    reg [31:0]      addr, value, got;

    // the bytes decoded from uart_tx, as text lines (CR dropped)
    task print_uart;
        begin
            $write("  | ");
            for (k = 0; k < uart_count && k < UART_MAX; k = k + 1)
                if (uart_bytes[k] == 8'h0A) begin
                    if (k + 1 < uart_count)
                        $write("\n  | ");
                    else
                        $write("\n");
                end else if (uart_bytes[k] != 8'h0D)
                    $write("%c", uart_bytes[k]);
            if (uart_count == 0 || uart_bytes[uart_count - 1] != 8'h0A)
                $write("\n");
        end
    endtask

    task result;
        input pass;
        begin
            total = total + 1;
            if (!pass)
                failed = failed + 1;
        end
    endtask

    initial begin : watchdog
        repeat (100000000) @(posedge clk);
        $display("FAIL watchdog: no summary after 100000000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        gpio_in = 10'h15A;
        running = 1'b0;
        halted = 1'b0;
        inject = 1'b0;
        total = 0;
        failed = 0;
        trace_pos = 0;
        uart_pos = 0;

        fd = $fopen(VECTORS, "r");
        if (fd == 0)
            $display("FAIL cannot open %0s", VECTORS);
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                kw = 0;
                n = $sscanf(line, "%s", kw);

                if (kw == "PROG") begin
                    n = $sscanf(line, "%s %s %d %h %d", kw, image, max_cycles, addr, waits);
                    run_program(image, max_cycles, addr, waits);
                    trace_pos = 0;
                    uart_pos = 0;
                    result(halted || addr == 32'hFFFFFFFF);
                    if (addr == 32'hFFFFFFFF)
                        $display("PASS PROG %0s: ran %0d cycles (endless loop, no halt expected), %0d instructions left EX",
                                 image, cycles, retired);
                    else if (halted)
                        $display("PASS PROG %0s: halt at %h reached after %0d cycles, %0d instructions left EX, %0d injected waits",
                                 image, addr, cycles, retired, injected);
                    else
                        $display("FAIL PROG %0s: halt at %h not reached within %0d cycles (%0d instructions left EX)",
                                 image, addr, max_cycles, retired);
                    result(align_errors == 0);
                    if (align_errors == 0)
                        $display("PASS PROG %0s: fetch window and IF/ID instruction always matched their PC", image);
                    else
                        $display("FAIL PROG %0s: %0d cycles with a fetch window or IF/ID instruction not matching its PC", image, align_errors);
                    result(mul_errors == 0);
                    if (mul_errors == 0)
                        $display("PASS PROG %0s: one start and one stall cycle per MUL (%0d MULs)", image, mul_count);
                    else
                        $display("FAIL PROG %0s: %0d of %0d MULs left EX without exactly one start and one stall cycle",
                                 image, mul_errors, mul_count);
                    result(div_errors == 0);
                    if (div_errors == 0)
                        $display("PASS PROG %0s: one divider start per DIV (%0d starts)", image, div_starts);
                    else
                        $display("FAIL PROG %0s: %0d DIVs left EX without exactly one start", image, div_errors);
                    result(lu_errors == 0);
                    if (lu_errors == 0)
                        $display("PASS PROG %0s: every load-use cost one bubble", image);
                    else
                        $display("FAIL PROG %0s: %0d load-use stalls longer than one bubble", image, lu_errors);
                    result(misaligned_accesses == 0);
                    if (misaligned_accesses == 0)
                        $display("PASS PROG %0s: no misaligned CPU bus access", image);
                    else
                        $display("FAIL PROG %0s: %0d misaligned CPU bus accesses reached the bus", image, misaligned_accesses);
                    result(irq_errors == 0);
                    if (irq_errors == 0)
                        $display("PASS PROG %0s: no interrupt taken with a MUL or DIV in EX", image);
                    else
                        $display("FAIL PROG %0s: %0d interrupts taken with a MUL or DIV in EX", image, irq_errors);
                    result(uart_errors == 0);
                    if (uart_errors == 0)
                        $display("PASS PROG %0s: UART frames well formed", image);
                    else
                        $display("FAIL PROG %0s: %0d UART framing errors", image, uart_errors);
                    if (waits) begin
                        result(injected > 0);
                        if (injected > 0)
                            $display("PASS PROG %0s: %0d loads saw HREADY low for three cycles", image, injected);
                        else
                            $display("FAIL PROG %0s: no HREADY waits were injected", image);
                    end
                    if (rx_total > 0) begin
                        result(rx_sent == rx_total && !dut.u_uart.rx_valid);
                        if (rx_sent == rx_total && !dut.u_uart.rx_valid)
                            $display("PASS PROG %0s: all %0d input bytes were sent on uart_rx and read", image, rx_total);
                        else
                            $display("FAIL PROG %0s: %0d of %0d input bytes sent, rx_valid = %b at the end",
                                     image, rx_sent, rx_total, dut.u_uart.rx_valid);
                    end
                    rx_total = 0;
                    rx_sent = 0;
                end

                else if (kw == "UARTIN") begin
                    n = $sscanf(line, "%s %s", kw, textfile);
                    rx_total = 0;
                    rx_sent = 0;
                    tfd = $fopen(textfile, "rb");
                    if (tfd == 0) begin
                        result(1'b0);
                        $display("FAIL UARTIN: cannot open %0s", textfile);
                    end else begin
                        ch = $fgetc(tfd);
                        while (ch != -1 && rx_total < UART_MAX) begin
                            rx_bytes[rx_total] = ch[7:0];
                            rx_total = rx_total + 1;
                            ch = $fgetc(tfd);
                        end
                        $fclose(tfd);
                    end
                end

                else if (kw == "UARTSHOW") begin
                    print_uart;
                    result(1'b1);
                    $display("PASS UARTSHOW: %0d bytes sent on uart_tx (shown above, not checked)", uart_count);
                end

                else if (kw == "UARTTEXT") begin
                    n = $sscanf(line, "%s %s", kw, textfile);
                    tfd = $fopen(textfile, "rb");
                    count = 0;
                    mismatch = -1;
                    if (tfd != 0) begin
                        ch = $fgetc(tfd);
                        while (ch != -1) begin
                            if (mismatch < 0 && (count >= uart_count || count >= UART_MAX || uart_bytes[count] !== ch[7:0])) begin
                                mismatch = count;
                                exp_byte = ch[7:0];
                            end
                            count = count + 1;
                            ch = $fgetc(tfd);
                        end
                        $fclose(tfd);
                    end
                    if (mismatch < 0 && count != uart_count) begin
                        mismatch = count;
                        exp_byte = 8'hxx;                // the program sent more than expected
                    end
                    print_uart;
                    result(tfd != 0 && mismatch < 0);
                    if (tfd == 0)
                        $display("FAIL UARTTEXT: cannot open %0s", textfile);
                    else if (mismatch < 0)
                        $display("PASS UARTTEXT: the %0d bytes sent on uart_tx match %0s", uart_count, textfile);
                    else
                        $display("FAIL UARTTEXT: uart_tx differs from %0s at byte %0d (got %0d bytes, expected %0d); got %h, expected %h",
                                 textfile, mismatch, uart_count, count,
                                 mismatch < uart_count ? uart_bytes[mismatch] : 8'hxx, exp_byte);
                end

                else if (kw == "REG") begin
                    n = $sscanf(line, "%s %d %h", kw, idx, value);
                    got = dut.u_regs.regs[idx];
                    result(got === value);
                    if (got === value)
                        $display("PASS REG x%0d = %h", idx, got);
                    else
                        $display("FAIL REG x%0d: got=%h expected=%h", idx, got, value);
                end

                else if (kw == "REGNZ") begin
                    n = $sscanf(line, "%s %d", kw, idx);
                    got = dut.u_regs.regs[idx];
                    result(got !== 32'b0 && ^got !== 1'bx);
                    if (got !== 32'b0 && ^got !== 1'bx)
                        $display("PASS REGNZ x%0d = %h (not zero)", idx, got);
                    else
                        $display("FAIL REGNZ x%0d: got=%h, expected a non-zero value", idx, got);
                end

                else if (kw == "RAM") begin
                    n = $sscanf(line, "%s %h %h", kw, addr, value);
                    got = {dut.u_ram.lane3[addr[15:2]], dut.u_ram.lane2[addr[15:2]],
                           dut.u_ram.lane1[addr[15:2]], dut.u_ram.lane0[addr[15:2]]};
                    result(got === value);
                    if (got === value)
                        $display("PASS RAM %h = %h", addr, got);
                    else
                        $display("FAIL RAM %h: got=%h expected=%h", addr, got, value);
                end

                else if (kw == "RAMNZ") begin
                    n = $sscanf(line, "%s %d", kw, expected);
                    count = 0;
                    for (i = 0; i < 1024; i = i + 1)
                        if ({dut.u_ram.lane3[i], dut.u_ram.lane2[i], dut.u_ram.lane1[i], dut.u_ram.lane0[i]} !== 32'b0)
                            count = count + 1;
                    result(count == expected);
                    if (count == expected)
                        $display("PASS RAMNZ %0d non-zero words in the first 4 KB of RAM", count);
                    else
                        $display("FAIL RAMNZ: got=%0d expected=%0d non-zero words", count, expected);
                end

                else if (kw == "LEDS") begin
                    n = $sscanf(line, "%s %h", kw, value);
                    result(gpio_out === value[9:0]);
                    if (gpio_out === value[9:0])
                        $display("PASS LEDS = %h", gpio_out);
                    else
                        $display("FAIL LEDS: got=%h expected=%h", gpio_out, value[9:0]);
                end

                else if (kw == "UART") begin
                    n = $sscanf(line, "%s %h", kw, value);
                    got = (uart_pos < uart_count && uart_pos < UART_MAX) ? {24'b0, uart_bytes[uart_pos]} : 32'hFFFFFFFF;
                    result(got === value);
                    if (got === value)
                        $display("PASS UART byte %0d = %h", uart_pos, got[7:0]);
                    else
                        $display("FAIL UART byte %0d: got=%h expected=%h", uart_pos, got, value);
                    uart_pos = uart_pos + 1;
                end

                else if (kw == "UARTN") begin
                    n = $sscanf(line, "%s %d", kw, expected);
                    result(uart_count == expected);
                    if (uart_count == expected)
                        $display("PASS UARTN %0d bytes sent", uart_count);
                    else
                        $display("FAIL UARTN: got=%0d expected=%0d bytes", uart_count, expected);
                end

                else if (kw == "DIVS") begin
                    n = $sscanf(line, "%s %d", kw, expected);
                    result(div_starts == expected);
                    if (div_starts == expected)
                        $display("PASS DIVS %0d divider starts", div_starts);
                    else
                        $display("FAIL DIVS: got=%0d expected=%0d divider starts", div_starts, expected);
                end

                else if (kw == "IRQHELD") begin
                    n = $sscanf(line, "%s %d", kw, expected);
                    result(irq_held >= expected);
                    if (irq_held >= expected)
                        $display("PASS IRQHELD: interrupt pending for %0d cycles with a MUL or DIV in EX", irq_held);
                    else
                        $display("FAIL IRQHELD: interrupt pending for %0d cycles with a MUL or DIV in EX, expected at least %0d",
                                 irq_held, expected);
                end

                else if (kw == "RETIRED") begin
                    n = $sscanf(line, "%s %d", kw, expected);
                    result(retired == expected);
                    if (retired == expected)
                        $display("PASS RETIRED %0d instructions left EX", retired);
                    else
                        $display("FAIL RETIRED: got=%0d expected=%0d", retired, expected);
                end

                else if (kw == "TRACE") begin
                    n = $sscanf(line, "%s %h", kw, value);
                    got = (trace_pos < retired && trace_pos < TRACE_MAX) ? trace[trace_pos] : 32'hFFFFFFFF;
                    result(got === value);
                    if (got === value)
                        $display("PASS TRACE %0d: %h", trace_pos, got);
                    else
                        $display("FAIL TRACE %0d: got=%h expected=%h", trace_pos, got, value);
                    trace_pos = trace_pos + 1;
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
