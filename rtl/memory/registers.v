module registers (
    input clk,
    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    input [4:0] rd_addr,
    input [31:0] rd_data,
    input reg_write,
    output [31:0] rs1_data,
    output [31:0] rs2_data
);

    reg [31:0] regs [31:0];

    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1 ) begin
            regs[i] = 32'b0;
        end
    end

    always @(posedge clk) begin
        if (reg_write && rd_addr != 5'b00000) begin
            regs[rd_addr] <= rd_data;
        end
    end


    mux2 #(.WIDTH(32)) rs1_mux (
        .in0 (regs[rs1_addr]),
        .in1 (32'b0),
        .sel (rs1_addr == 5'b00000),
        .out (rs1_data)
    );

    mux2 #(.WIDTH(32)) rs2_mux (
        .in0 (regs[rs2_addr]),
        .in1 (32'b0),
        .sel (rs2_addr == 5'b00000),
        .out (rs2_data)
    );
    
endmodule