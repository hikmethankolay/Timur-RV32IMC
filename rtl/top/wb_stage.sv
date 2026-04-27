module wb_stage(
    input  [31:0] alu_result,
    input  [31:0] mem_read_data,
    input  [31:0] pc_plus4,
    input         MemToReg,
    input  [6:0]  opcode,
    output [31:0] reg_write_data
);
    wire IsJAL  = (opcode == 7'b1101111);
    wire IsJALR = (opcode == 7'b1100111);
    wire [31:0] wb_pre_mem;

    // JAL/JALR write PC+4 as the link address into rd
    mux2 #(.WIDTH(32)) jal_link_mux(
        .in0(alu_result),
        .in1(pc_plus4),
        .sel(IsJAL | IsJALR),
        .out(wb_pre_mem)
    );

    mux2 #(.WIDTH(32)) memory_to_reg_mux(
        .in0(wb_pre_mem),
        .in1(mem_read_data),
        .sel(MemToReg),
        .out(reg_write_data)
    );
endmodule
