module wb_stage(
    input  [31:0] alu_result,
    input  [31:0] mem_read_data,
    input  [31:0] pc_plus4,
    input         MemToReg,
    input  [6:0]  opcode,
    output [31:0] reg_write_data
);

    mux2 #(.WIDTH(32)) memory_to_reg_mux(
        .in0(alu_result),
        .in1(mem_read_data),
        .sel(MemToReg),
        .out(reg_write_data)
    );
endmodule
