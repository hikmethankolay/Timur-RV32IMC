// Program counter (Phase 3): a named 32-bit d_ff. All next-PC selection
// lives outside; en is pc_load from the hazard logic.
module pc (
    input         clk,
    input         rst_n,
    input         en,
    input  [31:0] pc_next,
    output [31:0] pc
);

    d_ff #(.WIDTH(32)) pc_reg (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .d     (pc_next),
        .q     (pc)
    );

endmodule
