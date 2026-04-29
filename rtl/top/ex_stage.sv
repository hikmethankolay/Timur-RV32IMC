module ex_stage(
    input         clk,
    input         rst_n,

    // Operands (from ID/EX register)
    input  [31:0] rs1_data,
    input  [31:0] rs2_data,
    input  [31:0] imm,
    input  [31:0] pc_current,

    // Pre-computed values from ID stage (threaded through ID/EX)
    input  [31:0] pc_plus4_in,
    input  [31:0] branch_target_in,

    // Decoded fields
    input  [6:0]  opcode,
    input  [2:0]  funct3,
    input  [4:0]  ALUControl,
    input         ALUSrc,

    // Forwarding inputs
    input  [1:0]  forwardA,
    input  [1:0]  forwardB,
    input  [31:0] mem_alu_result_fwd,    // EX/MEM stage producer value
    input  [31:0] wb_value_fwd,          // MEM/WB writeback bus

    // Outputs
    output [31:0] alu_result,
    output [31:0] pc_plus4,
    output [31:0] branch_target_out,
    output        BranchTaken_out,
    output        div_busy,
    output        mul_busy
);

    assign pc_plus4 = pc_plus4_in;

    // ─── opcode constants & predicates ─────────────────────────────
    localparam [6:0] OPC_LUI     = 7'b0110111;
    localparam [6:0] OPC_AUIPC   = 7'b0010111;
    localparam [6:0] OPC_BRANCH  = 7'b1100011;
    localparam [6:0] OPC_JAL     = 7'b1101111;
    localparam [6:0] OPC_JALR    = 7'b1100111;

    wire is_lui          = (opcode == OPC_LUI);
    wire is_auipc        = (opcode == OPC_AUIPC);
    wire is_cond_branch  = (opcode == OPC_BRANCH);
    wire is_jal         = (opcode == OPC_JAL);
    wire is_jalr        = (opcode == OPC_JALR);
    wire is_uncond_jump = is_jal | is_jalr;

    // ─── Stage 1: forwarding muxes ─────────────────────────────────
    // forwardA/B encoding:
    //   00 = regfile,  01 = MEM/WB bus,  10 = EX/MEM alu_result,  11 = unused
    wire [31:0] rs1_forwarded, rs2_forwarded;

    mux4 #(.WIDTH(32)) FwdA_Mux(
        .in0(rs1_data),
        .in1(wb_value_fwd),
        .in2(mem_alu_result_fwd),
        .in3(32'b0),
        .sel(forwardA),
        .out(rs1_forwarded)
    );

    mux4 #(.WIDTH(32)) FwdB_Mux(
        .in0(rs2_data),
        .in1(wb_value_fwd),
        .in2(mem_alu_result_fwd),
        .in3(32'b0),
        .sel(forwardB),
        .out(rs2_forwarded)
    );

    // ─── Stage 2: ALU operand source select ────────────────────────
    //   alu_a:  rs1 (default) / pc (AUIPC) / 0 (LUI — instr[19:15] is imm, not rs1)
    //   alu_b:  rs2_forwarded (default) / imm (ALUSrc=1)

    wire [31:0] alu_a, alu_b;

    assign alu_a = is_auipc ? pc_current
                 : is_lui   ? 32'b0
                            : rs1_forwarded;

    mux2 #(.WIDTH(32)) ALUB_SrcMux(
        .in0(rs2_forwarded),
        .in1(imm),
        .sel(ALUSrc),
        .out(alu_b)
    );

    // ─── ALU + flags ───────────────────────────────────────────────
    //   alu_raw is the unmodified ALU output. It feeds the branch
    //   evaluator (needs flags) and the JALR target computation.
    //   The exposed alu_result OUTPUT is muxed below so EX/MEM
    //   latches the correct writeback value for JAL/JALR.
    wire [31:0] alu_raw;
    wire        zero, cout, overflow;
    wire        div_done, mul_done;

    // ── Divide ops ────────────────────────────────────────────────
    // ALUControl[4:2] == 3'b101 covers DIV/DIVU/REM/REMU.
    // div_inflight prevents the divider from being restarted while the
    // same DIV instruction sits in EX during the stall.
    wire is_div_op = (ALUControl[4:2] == 3'b101);
    wire div_busy_raw;
    reg  div_inflight;
    wire div_start = is_div_op & ~div_busy_raw & ~div_inflight;

    // Extend div_busy to include the start cycle.
    assign div_busy = div_busy_raw | div_start;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             div_inflight <= 1'b0;
        else if (div_done)      div_inflight <= 1'b0;
        else if (div_start)     div_inflight <= 1'b1;
    end

    // ── Multiply ops ─────────────────────────────────────────────
    // ALUControl[4:2] == 3'b100 covers MUL/MULH/MULHSU/MULHU.
    // Same inflight pattern as divider to prevent re-start.
    wire is_mul_op = (ALUControl[4:2] == 3'b100);
    wire mul_busy_raw;
    reg  mul_inflight;
    wire mul_start = is_mul_op & ~mul_busy_raw & ~mul_inflight;

    // Extend mul_busy to include the start cycle.
    assign mul_busy = mul_busy_raw | mul_start;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             mul_inflight <= 1'b0;
        else if (mul_done)      mul_inflight <= 1'b0;
        else if (mul_start)     mul_inflight <= 1'b1;
    end

    alu arithmetic_logic_unit(
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (alu_a),
        .b         (alu_b),
        .ALUControl(ALUControl),
        .div_start (div_start),
        .mul_start (mul_start),
        .result    (alu_raw),
        .zero      (zero),
        .cout      (cout),
        .overflow  (overflow),
        .div_busy  (div_busy_raw),
        .div_done  (div_done),
        .mul_busy  (mul_busy_raw),
        .mul_done  (mul_done)
    );

    // ─── Conditional branches (B-type only) ────────────────────────
    // branch_condition_evaluator encodings match opcode BRANCH. JAL
    // reuses [14:12] for immediate bits; mask with is_cond_branch.
    wire cond_branch_taken;

    branch_condition_evaluator bce(
        .zero          (zero),
        .alu_result_msb(alu_raw[31]),
        .overflow      (overflow),
        .cout          (cout),
        .BranchType    (funct3),
        .BranchTaken   (cond_branch_taken)
    );

    // ─── PC redirect: B & JAL = PC+imm (ID); JALR = (rs1+imm)&~1 ───
    wire [31:0] redirect_pc = is_jalr ? {alu_raw[31:1], 1'b0}
                                       : branch_target_in;

    // ─── Outputs ───────────────────────────────────────────────────
    // MEM uses Branch & BranchTaken for redirect; JAL/JALR force taken.
    assign alu_result        = is_uncond_jump ? pc_plus4 : alu_raw;
    assign branch_target_out = redirect_pc;
    assign BranchTaken_out   = (is_cond_branch & cond_branch_taken)
                              | is_uncond_jump;

endmodule
