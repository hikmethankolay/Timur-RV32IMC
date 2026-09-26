`timescale 1ns/1ps
//
// hazard_detection_unit_tb: every enable, flush, multiplier and divider
// handshake and qualified redirect/trap for the stall classes of Phase 7.
// Vector: id_ex_valid id_ex_memread (bin) id_ex_rd if_id_rs1 if_id_rs2 (hex)
//         mul_in_ex mul_done div_in_ex div_busy div_done bus_wait redirect_req
//         trap_req (bin), then the 14 expected outputs (bin), see the vector
//         file header.
//
module hazard_detection_unit_tb;

    reg        id_ex_valid, id_ex_memread;
    reg  [4:0] id_ex_rd, if_id_rs1, if_id_rs2;
    reg        mul_in_ex, mul_done;
    reg        div_in_ex, div_busy, div_done, bus_wait, redirect_req, trap_req;
    wire       pc_load, if_id_enable, if_id_flush, id_ex_enable, id_ex_flush;
    wire       ex_mem_enable, ex_mem_flush, mem_wb_enable;
    wire       mul_start, mul_ack, div_start, div_ack, take_redirect, take_trap;

    hazard_detection_unit dut (
        .id_ex_valid   (id_ex_valid),
        .id_ex_memread (id_ex_memread),
        .id_ex_rd      (id_ex_rd),
        .if_id_rs1     (if_id_rs1),
        .if_id_rs2     (if_id_rs2),
        .mul_in_ex     (mul_in_ex),
        .mul_done      (mul_done),
        .div_in_ex     (div_in_ex),
        .div_busy      (div_busy),
        .div_done      (div_done),
        .bus_wait      (bus_wait),
        .redirect_req  (redirect_req),
        .trap_req      (trap_req),
        .pc_load       (pc_load),
        .if_id_enable  (if_id_enable),
        .if_id_flush   (if_id_flush),
        .id_ex_enable  (id_ex_enable),
        .id_ex_flush   (id_ex_flush),
        .ex_mem_enable (ex_mem_enable),
        .ex_mem_flush  (ex_mem_flush),
        .mem_wb_enable (mem_wb_enable),
        .mul_start     (mul_start),
        .mul_ack       (mul_ack),
        .div_start     (div_start),
        .div_ack       (div_ack),
        .take_redirect (take_redirect),
        .take_trap     (take_trap)
    );

    wire [13:0] got = {pc_load, if_id_enable, if_id_flush, id_ex_enable, id_ex_flush,
                       ex_mem_enable, ex_mem_flush, mem_wb_enable,
                       mul_start, mul_ack, div_start, div_ack, take_redirect, take_trap};

    integer         fd, n;
    integer         total, failed;
    reg [8*256-1:0] line;
    reg             e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13;
    reg [13:0]      exp;

    initial begin : watchdog
        #100000;
        $display("FAIL watchdog: no summary after 100 us");
        $stop;
    end

    initial begin
        {id_ex_valid, id_ex_memread} = 2'b0;
        {id_ex_rd, if_id_rs1, if_id_rs2} = 15'b0;
        {mul_in_ex, mul_done} = 2'b0;
        {div_in_ex, div_busy, div_done, bus_wait, redirect_req, trap_req} = 6'b0;
        total = 0;
        failed = 0;

        fd = $fopen("vectors/hazard_detection_unit_vectors.txt", "r");
        if (fd == 0)
            $display("FAIL cannot open vectors/hazard_detection_unit_vectors.txt");
        else begin
            while (!$feof(fd)) begin
                line = 0;
                n = $fgets(line, fd);
                if ($sscanf(line, "%b %b %h %h %h %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b %b",
                            id_ex_valid, id_ex_memread, id_ex_rd, if_id_rs1, if_id_rs2,
                            mul_in_ex, mul_done, div_in_ex, div_busy, div_done, bus_wait, redirect_req, trap_req,
                            e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13) == 27) begin
                    exp = {e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13};
                    #10;
                    total = total + 1;
                    if (got !== exp) begin
                        failed = failed + 1;
                        $display("FAIL v=%b mr=%b rd=%h rs1=%h rs2=%h mix=%b mdone=%b dix=%b busy=%b done=%b bw=%b rr=%b tr=%b | got=%b expected=%b",
                                 id_ex_valid, id_ex_memread, id_ex_rd, if_id_rs1, if_id_rs2,
                                 mul_in_ex, mul_done, div_in_ex, div_busy, div_done, bus_wait, redirect_req, trap_req, got, exp);
                    end else
                        $display("PASS v=%b mr=%b rd=%h rs1=%h rs2=%h mix=%b mdone=%b dix=%b busy=%b done=%b bw=%b rr=%b tr=%b | %b",
                                 id_ex_valid, id_ex_memread, id_ex_rd, if_id_rs1, if_id_rs2,
                                 mul_in_ex, mul_done, div_in_ex, div_busy, div_done, bus_wait, redirect_req, trap_req, got);
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
