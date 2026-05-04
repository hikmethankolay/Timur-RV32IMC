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

    // Posedge write — full-cycle path from EX/MEM/WB into the regfile.
    always @(posedge clk) begin
        if (reg_write && rd_addr != 5'b00000) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // Write-port bypass: same-cycle WB→ID forwarding. Read returns the value
    // about to be written instead of the stale RAM cell when src == dst.
    wire bypass_rs1 = reg_write && (rd_addr != 5'b00000) && (rs1_addr == rd_addr);
    wire bypass_rs2 = reg_write && (rd_addr != 5'b00000) && (rs2_addr == rd_addr);

    assign rs1_data = (rs1_addr == 5'b00000) ? 32'b0       :
                      bypass_rs1             ? rd_data     :
                                               regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b00000) ? 32'b0       :
                      bypass_rs2             ? rd_data     :
                                               regs[rs2_addr];

endmodule
