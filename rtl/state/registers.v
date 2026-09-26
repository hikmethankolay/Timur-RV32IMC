// Register file (Phase 3): 32 x 32 in logic, two asynchronous read ports,
// one synchronous write port.
// Write-through bypass: a same-cycle write to a register being read is
// returned on that read port, so an instruction in ID never captures a stale
// value from a writer that is leaving WB.
module registers (
    input         clk,
    input  [4:0]  rs1_addr,
    input  [4:0]  rs2_addr,
    input  [4:0]  rd_addr,
    input  [31:0] rd_data,
    input         reg_write,
    output [31:0] rs1_data,
    output [31:0] rs2_data
);

    reg [31:0] regs [31:0];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
    end

    always @(posedge clk) begin
        if (reg_write && rd_addr != 5'b00000)
            regs[rd_addr] <= rd_data;
    end

    wire bypass_rs1 = reg_write && (rd_addr != 5'b00000) && (rs1_addr == rd_addr);
    wire bypass_rs2 = reg_write && (rd_addr != 5'b00000) && (rs2_addr == rd_addr);

    wire [31:0] rs1_value = bypass_rs1 ? rd_data : regs[rs1_addr];
    wire [31:0] rs2_value = bypass_rs2 ? rd_data : regs[rs2_addr];

    // Reads of x0 return 0 through a mux2 per port.
    mux2 #(.WIDTH(32)) u_rs1_x0 (
        .in0 (rs1_value),
        .in1 (32'b0),
        .sel (rs1_addr == 5'b00000),
        .out (rs1_data)
    );

    mux2 #(.WIDTH(32)) u_rs2_x0 (
        .in0 (rs2_value),
        .in1 (32'b0),
        .sel (rs2_addr == 5'b00000),
        .out (rs2_data)
    );

endmodule
