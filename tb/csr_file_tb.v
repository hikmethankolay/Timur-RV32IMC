`timescale 1ns/1ps
//
// csr_file_tb: machine-mode CSRs (Phase 10). Read values and reset values,
// WRITE/SET/CLEAR on every writable CSR, WARL bits, read-only and
// unimplemented addresses, trap entry, MRET, write priority, irq_pending,
// the 64-bit counters, and a random sequence checked against a model.
// Vector: see vectors/csr_file_vectors.txt (x = don't care).
//
module csr_file_tb;

    reg         clk, rst_n;
    reg  [11:0] csr_addr;
    reg  [1:0]  csr_op;
    reg  [31:0] csr_wdata, trap_cause, trap_epc, trap_val;
    reg         csr_write_attempt, csr_we, trap_take, mret_take, retire;
    reg  [1:0]  irq_lines;
    wire [31:0] csr_rdata, mtvec_out, mepc_out;
    wire        csr_illegal, irq_pending;

    csr_file dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .csr_addr          (csr_addr),
        .csr_op            (csr_op),
        .csr_wdata         (csr_wdata),
        .csr_write_attempt (csr_write_attempt),
        .csr_we            (csr_we),
        .csr_rdata         (csr_rdata),
        .csr_illegal       (csr_illegal),
        .trap_take         (trap_take),
        .trap_cause        (trap_cause),
        .trap_epc          (trap_epc),
        .trap_val          (trap_val),
        .mret_take         (mret_take),
        .retire            (retire),
        .irq_lines         (irq_lines),
        .mtvec_out         (mtvec_out),
        .mepc_out          (mepc_out),
        .irq_pending       (irq_pending)
    );

    always #5 clk = ~clk;

    function match;
        input [31:0] got;
        input [31:0] exp;
        integer i;
        begin
            match = 1'b1;
            for (i = 0; i < 32; i = i + 1)
                if (exp[i] !== 1'bx && got[i] !== exp[i])
                    match = 1'b0;
        end
    endfunction

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg [31:0]      e_rdata, e_mtvec, e_mepc;
    reg             e_illegal, e_irq, wait_type;
    reg             ok;

    initial begin : watchdog
        repeat (20000) @(posedge clk);
        $display("FAIL watchdog: no summary after 20000 cycles");
        $stop;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        {csr_addr, csr_op, csr_wdata} = 46'b0;
        {csr_write_attempt, csr_we, trap_take, mret_take, retire} = 5'b0;
        {trap_cause, trap_epc, trap_val} = 96'b0;
        irq_lines = 2'b0;
        total = 0;
        failed = 0;
        #1;

        fd = $fopen("vectors/csr_file_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/csr_file_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %h %b %h %b %b %b %h %h %h %b %b %b %h %b %h %h %b %b",
                            rst_n, csr_addr, csr_op, csr_wdata, csr_write_attempt, csr_we,
                            trap_take, trap_cause, trap_epc, trap_val, mret_take, retire, irq_lines,
                            e_rdata, e_illegal, e_mtvec, e_mepc, e_irq, wait_type) == 19) begin
                    if (wait_type == 1'b0)
                        #3;
                    else begin
                        @(posedge clk);
                        #1;
                    end
                    ok = match(csr_rdata, e_rdata) && match({31'b0, csr_illegal}, {31'b0, e_illegal}) &&
                         match(mtvec_out, e_mtvec) && match(mepc_out, e_mepc) &&
                         match({31'b0, irq_pending}, {31'b0, e_irq});
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL addr=%h op=%b wdata=%h att=%b we=%b trap=%b mret=%b irq=%b | got %h %b %h %h %b | expected %h %b %h %h %b",
                                 csr_addr, csr_op, csr_wdata, csr_write_attempt, csr_we, trap_take, mret_take,
                                 irq_lines, csr_rdata, csr_illegal, mtvec_out, mepc_out, irq_pending,
                                 e_rdata, e_illegal, e_mtvec, e_mepc, e_irq);
                    end else
                        $display("PASS addr=%h op=%b wdata=%h att=%b we=%b trap=%b mret=%b wait_type=%b | rdata=%h illegal=%b",
                                 csr_addr, csr_op, csr_wdata, csr_write_attempt, csr_we, trap_take, mret_take,
                                 wait_type, csr_rdata, csr_illegal);
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
