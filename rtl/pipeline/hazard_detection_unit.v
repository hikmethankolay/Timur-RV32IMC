// Hazard detection unit (Phase 7): produces every enable and flush, so the
// hazard policy lives in one place. Actions, highest priority first:
//   bus wait (freeze)  : every stage holds
//   trap (Phase 10)    : PC <- mtvec; IF/ID, ID/EX, EX/MEM bubble
//   redirect           : PC <- target; IF/ID, ID/EX bubble
//   divider EX stall   : PC, IF/ID, ID/EX hold; bubble into EX/MEM
//   load-use           : PC, IF/ID hold; bubble into ID/EX
// The top level holds the ROM fetch address with the PC:
//   fetch_addr = NOT rst_n ? 0 : (pc_load ? pc_next : pc)
module hazard_detection_unit (
    // instruction in EX
    input        id_ex_valid,
    input        id_ex_memread,
    input  [4:0] id_ex_rd,
    // sources of the instruction in ID
    input  [4:0] if_id_rs1,
    input  [4:0] if_id_rs2,
    // divider class in EX and divider status
    input        div_in_ex,
    input        div_busy,
    input        div_done,
    // CPU data-port master
    input        bus_wait,
    // requests from EX
    input        redirect_req,
    input        trap_req,

    output       pc_load,
    output       if_id_enable,
    output       if_id_flush,
    output       id_ex_enable,
    output       id_ex_flush,
    output       ex_mem_enable,
    output       ex_mem_flush,
    output       mem_wb_enable,
    output       div_start,
    output       div_ack,
    output       take_redirect,
    output       take_trap
);

    wire load_use  = id_ex_valid && id_ex_memread && (id_ex_rd != 5'b00000) &&
                     ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));
    wire div_stall = div_in_ex && !div_done;

    // Redirects and traps are only taken on cycles without a freeze.
    assign take_redirect = redirect_req && !bus_wait;
    assign take_trap     = trap_req && !bus_wait;

    assign pc_load       = !bus_wait && (take_trap || take_redirect || !(div_stall || load_use));

    assign if_id_enable  = !(bus_wait || div_stall || load_use);
    assign if_id_flush   = take_redirect || take_trap;

    assign id_ex_enable  = !(bus_wait || div_stall);
    assign id_ex_flush   = take_redirect || take_trap || (load_use && !bus_wait);

    assign ex_mem_enable = !bus_wait;
    assign ex_mem_flush  = take_trap || (div_stall && !bus_wait);

    assign mem_wb_enable = !bus_wait;

    // start needs NOT done (a start gated only by busy would fire again when
    // busy falls) and NOT bus_wait (the WB forwarding source is not valid yet
    // during a data-phase wait).
    assign div_start     = div_in_ex && !div_busy && !div_done && !bus_wait;
    assign div_ack       = div_in_ex && !div_stall && !bus_wait;

endmodule
