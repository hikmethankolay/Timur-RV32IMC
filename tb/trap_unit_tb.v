`timescale 1ns/1ps
//
// trap_unit_tb: trap decision in EX (Phase 10). Every cause alone, the
// misalignment rules for each access size, the interrupt and its priority,
// bubbles, and a random section checked against a model.
// Combinational: apply, wait 10 ns, compare.
// Vector: see vectors/trap_unit_vectors.txt (x = don't care).
//
module trap_unit_tb;

    reg         valid, illegal, is_ecall, is_ebreak, csr_access, csr_illegal;
    reg         mem_read, mem_write, irq_pending, irq_allowed;
    reg  [31:0] pc, mem_addr;
    reg  [2:0]  funct3;
    reg  [1:0]  mem_addr_lo;
    wire        trap_req;
    wire [31:0] trap_cause, trap_val;

    trap_unit dut (
        .valid           (valid),
        .pc              (pc),
        .illegal         (illegal),
        .is_ecall        (is_ecall),
        .is_ebreak       (is_ebreak),
        .csr_access      (csr_access),
        .csr_illegal     (csr_illegal),
        .mem_read        (mem_read),
        .mem_write       (mem_write),
        .funct3          (funct3),
        .mem_addr_lo     (mem_addr_lo),
        .mem_addr        (mem_addr),
        .irq_pending     (irq_pending),
        .irq_allowed     (irq_allowed),
        .trap_req        (trap_req),
        .trap_cause      (trap_cause),
        .trap_val        (trap_val)
    );

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
    reg             e_req;
    reg [31:0]      e_cause, e_val;
    reg             ok;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        {valid, illegal, is_ecall, is_ebreak, csr_access, csr_illegal} = 6'b0;
        {mem_read, mem_write, irq_pending, irq_allowed} = 4'b0;
        {pc, mem_addr} = 64'b0;
        funct3 = 3'b0;
        mem_addr_lo = 2'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/trap_unit_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/trap_unit_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %h %b %b %b %b %b %b %b %b %b %h %b %b %b %h %h",
                            valid, pc, illegal, is_ecall, is_ebreak, csr_access, csr_illegal,
                            mem_read, mem_write, funct3, mem_addr_lo, mem_addr,
                            irq_pending, irq_allowed, e_req, e_cause, e_val) == 17) begin
                    #10;
                    ok = (trap_req === e_req) && match(trap_cause, e_cause) && match(trap_val, e_val);
                    total = total + 1;
                    if (!ok) begin
                        failed = failed + 1;
                        $display("FAIL v=%b ill=%b ecall=%b ebreak=%b csr=%b/%b rd=%b wr=%b f3=%b lo=%b irq=%b/%b | got %b %h %h | expected %b %h %h",
                                 valid, illegal, is_ecall, is_ebreak, csr_access, csr_illegal, mem_read, mem_write,
                                 funct3, mem_addr_lo, irq_pending, irq_allowed,
                                 trap_req, trap_cause, trap_val, e_req, e_cause, e_val);
                    end else
                        $display("PASS v=%b ill=%b ecall=%b ebreak=%b rd=%b wr=%b f3=%b lo=%b irq=%b/%b | trap=%b cause=%h val=%h",
                                 valid, illegal, is_ecall, is_ebreak, mem_read, mem_write, funct3, mem_addr_lo,
                                 irq_pending, irq_allowed, trap_req, trap_cause, trap_val);
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
