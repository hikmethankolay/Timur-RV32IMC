// Writeback mux: non-load instructions use latched ALU result; loads use aligned memory data.
module wb_stage (
    input  [31:0] alu_res_w_i,
    input  [31:0] ld_data_w_i,
    input         wb_from_ld_w_i, // 1 = LW/LH/LB path
    output [31:0] rf_wdata_w_o
);
    mux2 #(.WIDTH(32)) u_wb_mux (
        .in0(alu_res_w_i),
        .in1(ld_data_w_i),
        .sel(wb_from_ld_w_i),
        .out(rf_wdata_w_o)
    );
endmodule
