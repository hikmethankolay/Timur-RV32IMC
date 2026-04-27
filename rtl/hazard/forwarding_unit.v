module forwarding_unit (
    input [4:0] id_ex_rs1,
    input [4:0] id_ex_rs2,
    input [4:0] ex_mem_rd,
    input ex_mem_regwrite,
    input [4:0] mem_wb_rd,
    input mem_wb_regwrite,
    output reg [1:0] forwardA,
    output reg [1:0] forwardB
);

    always @(*) begin
        if (ex_mem_regwrite && ex_mem_rd != 5'b00000 && ex_mem_rd == id_ex_rs1) begin
            forwardA = 2'b10;
        end else if (mem_wb_regwrite && mem_wb_rd != 5'b00000 && mem_wb_rd == id_ex_rs1) begin
            forwardA = 2'b01;
        end else begin
            forwardA = 2'b00;
        end
    end

    always @(*) begin
        if (ex_mem_regwrite && ex_mem_rd != 5'b00000 && ex_mem_rd == id_ex_rs2) begin
            forwardB = 2'b10;
        end else if (mem_wb_regwrite && mem_wb_rd != 5'b00000 && mem_wb_rd == id_ex_rs2) begin
            forwardB = 2'b01;
        end else begin
            forwardB = 2'b00;
        end
    end
    
endmodule