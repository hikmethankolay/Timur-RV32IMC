// Execute: operand forwarding, ALU (+ mul/div), branch test, PC redirect target for MEM.
module ex_stage (
    input         clk_i,
    input         rst_n_i,
    input  [31:0] rs1_val_x_i,
    input  [31:0] rs2_val_x_i,
    input         alu_a_use_id_x_i, // LUI/AUIPC: ALU A from alu_a_id (precomputed in ID)
    input  [31:0] alu_a_id_x_i,
    input  [31:0] imm32_x_i,
    input  [31:0] pc_plus4_x_i,     // Link value for JAL/JALR
    input  [31:0] btarget_pc_x_i,   // PC+imm for B-type and JAL (from ID)
    input  [6:0]  opc7_x_i,
    input  [2:0]  funct3_x_i,
    input  [4:0]  alu_ctl_x_i,
    input         alu_imm_b_x_i,
    input  [1:0]  fwd_rs1_sel_i,    // 00 reg, 01 WB, 10 EX/MEM ALU
    input  [1:0]  fwd_rs2_sel_i,
    input  [31:0] alu_res_m_fwd_i,
    input  [31:0] rf_wdata_w_fwd_i,
    output [31:0] alu_res_x_o,      // To EX/MEM (or PC+4 for J/JR)
    output [31:0] pc_plus4_x_o,     // Pass-through for MEM/WB / link
    output [31:0] jmp_pc_x_o,       // Next PC if redirect
    output        br_taken_x_o,     // Combined with br_jmp in MEM for final redirect
    output        div_busy_o,
    output        mul_busy_o
);
    assign pc_plus4_x_o = pc_plus4_x_i;

    localparam [6:0] OPC_BRANCH = 7'b1100011;
    localparam [6:0] OPC_JAL    = 7'b1101111;
    localparam [6:0] OPC_JALR   = 7'b1100111;

    wire is_bcond_w       = (opc7_x_i == OPC_BRANCH);
    wire is_jal_w         = (opc7_x_i == OPC_JAL);
    wire is_jalr_w        = (opc7_x_i == OPC_JALR);
    wire is_j_w           = is_jal_w | is_jalr_w;

    wire [31:0] rs1_fwd_w, rs2_fwd_w;
    mux4 #(.WIDTH(32)) u_fwd_rs1 (
        .in0(rs1_val_x_i),
        .in1(rf_wdata_w_fwd_i),
        .in2(alu_res_m_fwd_i),
        .in3(32'b0),
        .sel(fwd_rs1_sel_i),
        .out(rs1_fwd_w)
    );
    mux4 #(.WIDTH(32)) u_fwd_rs2 (
        .in0(rs2_val_x_i),
        .in1(rf_wdata_w_fwd_i),
        .in2(alu_res_m_fwd_i),
        .in3(32'b0),
        .sel(fwd_rs2_sel_i),
        .out(rs2_fwd_w)
    );

    // ALU A: LUI (0) / AUIPC (PC@ID) prepared in decode; else forwarded rs1.
    wire [31:0] alu_a_eff_w = alu_a_use_id_x_i ? alu_a_id_x_i : rs1_fwd_w;
    wire [31:0] alu_b_w;
    mux2 #(.WIDTH(32)) u_alu_b (
        .in0(rs2_fwd_w),
        .in1(imm32_x_i),
        .sel(alu_imm_b_x_i),
        .out(alu_b_w)
    );

    wire [31:0] jalr_sum_w;
    wire        jalr_cout_unused;
    wire        jalr_ovf_unused;

    adder_32bit u_jalr_add (
        .a       (rs1_fwd_w),
        .b       (imm32_x_i),
        .sub     (1'b0),
        .result  (jalr_sum_w),
        .cout    (jalr_cout_unused),
        .overflow(jalr_ovf_unused)
    );
    wire [31:0] jalr_pc_w = {jalr_sum_w[31:1], 1'b0};

    wire [31:0] alu_raw_w;
    wire        zero_w, adder_zero_w, cout_w, ovf_w;
    wire        div_done_w, mul_done_w;

    wire is_div_w    = (alu_ctl_x_i[4:2] == 3'b101);
    wire div_busy_raw_w;
    reg  div_inflight_q;
    wire div_start_w = is_div_w & ~div_busy_raw_w & ~div_inflight_q;
    assign div_busy_o = div_busy_raw_w | div_start_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)         div_inflight_q <= 1'b0;
        else if (div_done_w)  div_inflight_q <= 1'b0;
        else if (div_start_w) div_inflight_q <= 1'b1;
    end

    wire is_mul_w    = (alu_ctl_x_i[4:2] == 3'b100);
    wire mul_busy_raw_w;
    reg  mul_inflight_q;
    wire mul_start_w = is_mul_w & ~mul_busy_raw_w & ~mul_inflight_q;
    assign mul_busy_o = mul_busy_raw_w | mul_start_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)         mul_inflight_q <= 1'b0;
        else if (mul_done_w)  mul_inflight_q <= 1'b0;
        else if (mul_start_w) mul_inflight_q <= 1'b1;
    end

    alu u_alu (
        .clk       (clk_i),
        .rst_n     (rst_n_i),
        .a         (alu_a_eff_w),
        .b         (alu_b_w),
        .ALUControl(alu_ctl_x_i),
        .div_start (div_start_w),
        .mul_start (mul_start_w),
        .result      (alu_raw_w),
        .zero        (zero_w),
        .adder_zero  (adder_zero_w),
        .cout        (cout_w),
        .overflow  (ovf_w),
        .div_busy  (div_busy_raw_w),
        .div_done  (div_done_w),
        .mul_busy  (mul_busy_raw_w),
        .mul_done  (mul_done_w)
    );

    // funct3 is branch condition only for OPC_BRANCH; JAL reuses [14:12] as immediate.
    wire br_cond_taken_w;
    branch_condition_evaluator u_bcond (
        .zero          (adder_zero_w),
        .alu_result_msb(alu_raw_w[31]),
        .overflow      (ovf_w),
        .cout          (cout_w),
        .BranchType    (funct3_x_i),
        .BranchTaken   (br_cond_taken_w)
    );

    wire [31:0] jmp_pc_w = is_jalr_w ? jalr_pc_w : btarget_pc_x_i;

    assign alu_res_x_o   = is_j_w ? pc_plus4_x_i : alu_raw_w;
    assign jmp_pc_x_o   = jmp_pc_w;
    assign br_taken_x_o = (is_bcond_w & br_cond_taken_w) | is_j_w;
endmodule
