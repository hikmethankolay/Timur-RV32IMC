`timescale 1ns/1ps
//
// timur_soc_tb: system tests of the pipelined SoC (Phases 5-9).
// vectors/timur_soc_vectors.txt lists the test programs (ROM images) and
// their expected results; sw/gen_soc_tests.py generates both. For each PROG
// the testbench loads the image into the ROM, clears the RAM, resets the SoC
// and runs it until the halt instruction leaves EX, then checks the
// directives that follow (registers, RAM, LEDs, UART bytes, divider starts,
// the order in which instructions left EX).
// Checked every cycle during a run:
//   - the fetch word belongs to the PC and the IF/ID word to IF/ID's pc,
//     through load-use, divider and bus stalls
//   - MUL never stalls
//   - exactly one divider start per DIV
//   - a load-use costs exactly one bubble
// Run with +trace to print PC, instruction and x1-x14 every cycle.
// With hready_waits = 1 the RAM's HREADYOUT is forced low for three cycles
// in the data phase of every RAM load, so HREADY is low for three cycles
// while the load is in WB, with garbage on HRDATA until the last cycle.
//
module timur_soc_tb;

    localparam BIT       = 434;    // UART cycles per bit (UART_DIVIDER = 433)
    localparam TRACE_MAX = 4096;

    reg        clk, rst_n;
    reg  [9:0] gpio_in;
    wire [9:0] gpio_out;
    wire       uart_tx;

    timur_soc dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .gpio_in  (gpio_in),
        .gpio_out (gpio_out),
        .uart_rx  (1'b1),
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
    integer     align_errors, mul_stalls, div_starts, div_errors, starts_pending, lu_errors;
    reg         last_load_use;

    reg print_trace;
    initial print_trace = $test$plusargs("trace");

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

            if (dut.fetch_instr !== dut.u_rom.mem[dut.if_pc[15:2]])
                align_errors = align_errors + 1;
            if (dut.if_id_valid && dut.if_id_instr !== dut.u_rom.mem[dut.if_id_pc[15:2]])
                align_errors = align_errors + 1;

            if (dut.id_ex_valid && dut.id_ex_alucontrol[4:2] == 3'b100 && !dut.bus_wait && !dut.pc_load)
                mul_stalls = mul_stalls + 1;

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
    // UART monitor: 8N1 at 434 cycles per bit, sampled at the bit centres
    // ------------------------------------------------------------------
    reg  [7:0] uart_bytes [0:63];
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
                if (uart_count < 64)
                    uart_bytes[uart_count] = ubyte;
                uart_count = uart_count + 1;
                uart_active = 1'b0;
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

    task run_program;
        input [8*64-1:0] file;
        input integer    limit;
        input [31:0]     halt;
        input            waits;
        begin
            running = 1'b0;
            rst_n = 1'b0;
            for (i = 0; i < 16384; i = i + 1) begin
                dut.u_rom.mem[i]   = 32'h00000000;
                dut.u_ram.lane0[i] = 8'h00;
                dut.u_ram.lane1[i] = 8'h00;
                dut.u_ram.lane2[i] = 8'h00;
                dut.u_ram.lane3[i] = 8'h00;
            end
            $readmemh(file, dut.u_rom.mem);
            // the register file has no reset: start every program from zero
            for (i = 0; i < 32; i = i + 1)
                dut.u_regs.regs[i] = 32'h00000000;
            halt_pc = halt;
            halted = 1'b0;
            cycles = 0;
            retired = 0;
            align_errors = 0;
            mul_stalls = 0;
            div_starts = 0;
            div_errors = 0;
            starts_pending = 0;
            lu_errors = 0;
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
    reg [8*256-1:0] line;
    reg [8*16-1:0]  kw;
    reg [8*64-1:0]  image;
    reg [31:0]      addr, value, got;

    task result;
        input pass;
        begin
            total = total + 1;
            if (!pass)
                failed = failed + 1;
        end
    endtask

    initial begin : watchdog
        repeat (1000000) @(posedge clk);
        $display("FAIL watchdog: no summary after 1000000 cycles");
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

        fd = $fopen("vectors/timur_soc_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/timur_soc_vectors.txt");
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
                        $display("PASS PROG %0s: fetch and IF/ID words always matched their PC", image);
                    else
                        $display("FAIL PROG %0s: %0d cycles with a fetch or IF/ID word not matching its PC", image, align_errors);
                    result(mul_stalls == 0);
                    if (mul_stalls == 0)
                        $display("PASS PROG %0s: MUL never stalled", image);
                    else
                        $display("FAIL PROG %0s: MUL stalled the pipeline in %0d cycles", image, mul_stalls);
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
                    got = (uart_pos < uart_count && uart_pos < 64) ? {24'b0, uart_bytes[uart_pos]} : 32'hFFFFFFFF;
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
