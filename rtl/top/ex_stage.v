module ex_stage(
    input         clk,
    input         rst_n,
    input  [31:0] rs1_data,
    input  [31:0] rs2_data,
    input  [31:0] imm,
    input  [6:0]  opcode,
    input  [2:0]  funct3,
    input  [4:0]  ALUControl,
    input         ALUSrc,
    input         Branch,
    input  [31:0] pc_current,
    input  [31:0] pc_plus4,
    output [31:0] alu_result,
    output [31:0] pc_next
);
    wire [31:0] alu_a, alu_b, alu_a_premux;
    wire        zero, cout, overflow;
    wire        div_busy, div_done;
    wire        BranchTaken;
    wire [31:0] branch_target, jump_target;

    wire IsJAL  = (opcode == 7'b1101111);
    wire IsJALR = (opcode == 7'b1100111);

    mux2 #(.WIDTH(32)) ALUB_Mux(
        .in0(rs2_data),
        .in1(imm),
        .sel(ALUSrc),
        .out(alu_b)
    );

    mux2 #(.WIDTH(32)) ALUA_Mux(
        .in0(rs1_data),
        .in1(pc_current),
        .sel(opcode == 7'b0010111),   // AUIPC
        .out(alu_a_premux)
    );

    // LUI: force alu_a to 0 so result = 0 + imm = imm
    mux2 #(.WIDTH(32)) ALUA_LUI_Mux(
        .in0(alu_a_premux),
        .in1(32'b0),
        .sel(opcode == 7'b0110111),   // LUI
        .out(alu_a)
    );

    alu arithmetic_logic_unit(
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (alu_a),
        .b         (alu_b),
        .ALUControl(ALUControl),
        .div_start (1'b0),
        .result    (alu_result),
        .zero      (zero),
        .cout      (cout),
        .overflow  (overflow),
        .div_busy  (div_busy),
        .div_done  (div_done)
    );

    branch_condition_evaluator bce(
        .zero          (zero),
        .alu_result_msb(alu_result[31]),
        .overflow      (overflow),
        .cout          (cout),
        .BranchType    (funct3),
        .BranchTaken   (BranchTaken)
    );

    adder_32bit branch_adder(
        .a       (pc_current),
        .b       (imm),
        .sub     (1'b0),
        .result  (branch_target),
        .cout    (),
        .overflow()
    );

    // JALR target = (rs1 + imm) with bit 0 forced to 0
    wire [31:0] jalr_target = {alu_result[31:1], 1'b0};

    // JAL uses branch_target (PC + imm_j); JALR uses jalr_target (rs1+imm_i & ~1)
    mux2 #(.WIDTH(32)) jalr_target_mux(
        .in0(branch_target),
        .in1(jalr_target),
        .sel(IsJALR),
        .out(jump_target)
    );

    mux2 #(.WIDTH(32)) pc_next_mux(
        .in0(pc_plus4),
        .in1(jump_target),
        .sel((Branch & BranchTaken) | IsJAL | IsJALR),
        .out(pc_next)
    );
endmodule
