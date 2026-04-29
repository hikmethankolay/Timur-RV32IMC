module hazard_detection_unit (
    input id_ex_memread,
    input [4:0] id_ex_rd,
    input [4:0] if_id_rs1,
    input [4:0] if_id_rs2,
    input hready,
    input div_busy,
    output stall,
    output bubble_stall,
    output freeze_stall
);

    wire load_use;
    wire bus_wait;

    assign load_use = id_ex_memread
               && (id_ex_rd != 5'b0)
               && ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    assign bus_wait = ~hready;

    // Two stall classes with different ID/EX semantics:
    //   bubble_stall: ID/EX must be replaced with NOP (load-use, bus-wait).
    //                 The stalling instruction has already advanced; we need
    //                 to keep the consumer in IF/ID and inject a bubble.
    //   freeze_stall: ID/EX must be held (multi-cycle execute: DIV only; MUL is 1 cycle).
    //                 The instruction is still computing in EX and must not
    //                 leave ID/EX until its result is valid.
    assign bubble_stall = load_use | bus_wait;
    assign freeze_stall = div_busy;

    // Aggregate stall — used by PC and IF/ID, both of which always freeze
    // on any stall regardless of class.
    assign stall = bubble_stall | freeze_stall;

endmodule