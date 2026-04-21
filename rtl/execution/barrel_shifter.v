module barrel_shifter (
    input [31:0] in,
    input [4:0] shamt,
    input [1:0] shift_type,
    output [31:0] out
);

    wire [31:0] s0, s1, s2, s3;

    wire [31:0] sll0 = {in[30:0], 1'b0};
    wire [31:0] srl0 = {1'b0, in[31:1]};
    wire [31:0] sra0 = {{1{in[31]}}, in[31:1]};

    wire [31:0] sll1 = {s0[29:0], 2'b0};
    wire [31:0] srl1 = {2'b0, s0[31:2]};
    wire [31:0] sra1 = {{2{in[31]}}, s0[31:2]};

    wire [31:0] sll2 = {s1[27:0], 4'b0};
    wire [31:0] srl2 = {4'b0, s1[31:4]};
    wire [31:0] sra2 = {{4{in[31]}}, s1[31:4]};

    wire [31:0] sll3 = {s2[23:0], 8'b0};
    wire [31:0] srl3 = {8'b0, s2[31:8]};
    wire [31:0] sra3 = {{8{in[31]}}, s2[31:8]};

    wire [31:0] sll4 = {s3[15:0], 16'b0};
    wire [31:0] srl4 = {16'b0, s3[31:16]};
    wire [31:0] sra4 = {{16{in[31]}}, s3[31:16]};

    wire [31:0] shifted0, shifted1, shifted2, shifted3, shifted4;

    mux4 #(.WIDTH(32)) type_mux0 (.in0(sll0), .in1(srl0), .in2(sra0), .in3(in), .sel(shift_type), .out(shifted0));
    mux4 #(.WIDTH(32)) type_mux1 (.in0(sll1), .in1(srl1), .in2(sra1), .in3(in), .sel(shift_type), .out(shifted1));
    mux4 #(.WIDTH(32)) type_mux2 (.in0(sll2), .in1(srl2), .in2(sra2), .in3(in), .sel(shift_type), .out(shifted2));
    mux4 #(.WIDTH(32)) type_mux3 (.in0(sll3), .in1(srl3), .in2(sra3), .in3(in), .sel(shift_type), .out(shifted3));
    mux4 #(.WIDTH(32)) type_mux4 (.in0(sll4), .in1(srl4), .in2(sra4), .in3(in), .sel(shift_type), .out(shifted4));

    mux2 #(.WIDTH(32)) stage0 (.in0(in),  .in1(shifted0),.sel(shamt[0]),.out(s0));
    mux2 #(.WIDTH(32)) stage1 (.in0(s0),  .in1(shifted1),.sel(shamt[1]),.out(s1));
    mux2 #(.WIDTH(32)) stage2 (.in0(s1),  .in1(shifted2),.sel(shamt[2]),.out(s2));
    mux2 #(.WIDTH(32)) stage3 (.in0(s2),  .in1(shifted3),.sel(shamt[3]),.out(s3));
    mux2 #(.WIDTH(32)) stage4 (.in0(s3),  .in1(shifted4),.sel(shamt[4]),.out(out));


endmodule