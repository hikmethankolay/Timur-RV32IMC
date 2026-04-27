module hazard_detection_unit (
    input id_ex_memread,
    input [4:0] id_ex_rd,
    input [4:0] if_id_rs1,
    input [4:0] if_id_rs2,
    input hready,
    input div_busy,
    output stall
);

    wire load_use;
    wire bus_wait;

    assign load_use = id_ex_memread
               && (id_ex_rd != 5'b0)
               && ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));
    
    assign bus_wait = ~hready;

    assign stall    = load_use | bus_wait | div_busy;

endmodule