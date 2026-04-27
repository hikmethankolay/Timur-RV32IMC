module ex_stage(
    input         clk,
    input         rst_n,

    // Operands (from ID/EX register)
    input  [31:0] rs1_data,
    input  [31:0] rs2_data,
    input  [31:0] imm,
    input  [31:0] pc_current,
    input  [31:0] pc_plus4,

    // Decoded fields
    input  [6:0]  opcode,
    input  [2:0]  funct3,
    input  [4:0]  ALUControl,
    input         ALUSrc,
    input         Branch,

    // Forwarding inputs (from forwarding_unit + later pipeline stages)
    input  [1:0]  forwardA,
    input  [1:0]  forwardB,
    input  [31:0] mem_alu_result_fwd,    // EX/MEM stage producer value
    input  [31:0] wb_value_fwd,          // MEM/WB writeback bus

    // Outputs
    output [31:0] alu_result,
    output [31:0] jump_target_out,
    output [31:0] branch_target_out,
    output        BranchTaken_out,
    output        div_busy
);

    // ─── opcode constants & predicates ─────────────────────────────
    localparam [6:0] OPC_LUI   = 7'b0110111;
    localparam [6:0] OPC_AUIPC = 7'b0010111;
    localparam [6:0] OPC_JAL   = 7'b1101111;
    localparam [6:0] OPC_JALR  = 7'b1100111;

    wire is_lui   = (opcode == OPC_LUI);
    wire is_auipc = (opcode == OPC_AUIPC);
    wire is_jal   = (opcode == OPC_JAL);
    wire is_jalr  = (opcode == OPC_JALR);

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
    //   alu_a:  rs1_forwarded (default) / pc_current (AUIPC) / 0 (LUI)
    //   alu_b:  rs2_forwarded (default) / imm (ALUSrc=1)
    wire [1:0] alu_a_sel = is_auipc ? 2'b01 :
                           is_lui   ? 2'b10 :
                                      2'b00;

    wire [31:0] alu_a, alu_b;

    mux4 #(.WIDTH(32)) ALUA_SrcMux(
        .in0(rs1_forwarded),
        .in1(pc_current),
        .in2(32'b0),
        .in3(32'b0),
        .sel(alu_a_sel),
        .out(alu_a)
    );

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
    wire        div_done;

    // Divide ops: ALUControl[4:2] == 3'b101 covers DIV/DIVU/REM/REMU.
    // div_inflight prevents the divider from being restarted while the
    // same DIV instruction sits in EX during the stall. It rises when
    // start fires and falls one cycle after the divider asserts done,
    // by which point the pipeline has advanced and is_div_op is no
    // longer asserted (or refers to a fresh DIV instruction).
    wire is_div_op = (ALUControl[4:2] == 3'b101);
    reg  div_inflight;
    wire div_start = is_div_op & ~div_busy & ~div_inflight;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             div_inflight <= 1'b0;
        else if (div_done)      div_inflight <= 1'b0;
        else if (div_start)     div_inflight <= 1'b1;
    end

    alu arithmetic_logic_unit(
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (alu_a),
        .b         (alu_b),
        .ALUControl(ALUControl),
        .div_start (div_start),
        .result    (alu_raw),
        .zero      (zero),
        .cout      (cout),
        .overflow  (overflow),
        .div_busy  (div_busy),
        .div_done  (div_done)
    );

    // ─── Branch evaluation ─────────────────────────────────────────
    wire BranchTaken;

    branch_condition_evaluator bce(
        .zero          (zero),
        .alu_result_msb(alu_raw[31]),
        .overflow      (overflow),
        .cout          (cout),
        .BranchType    (funct3),
        .BranchTaken   (BranchTaken)
    );

    // ─── Branch / jump target computation ──────────────────────────
    //   branch_target = pc + imm           (B-type and JAL)
    //   jalr_target   = (rs1+imm) & ~1     (JALR; uses raw ALU output)
    //   jump_target   = JALR ? jalr_target : branch_target
    wire [31:0] branch_target;
    wire [31:0] jalr_target = {alu_raw[31:1], 1'b0};
    wire [31:0] jump_target;

    adder_32bit branch_adder(
        .a       (pc_current),
        .b       (imm),
        .sub     (1'b0),
        .result  (branch_target),
        .cout    (),
        .overflow()
    );

    mux2 #(.WIDTH(32)) jalr_target_mux(
        .in0(branch_target),
        .in1(jalr_target),
        .sel(is_jalr),
        .out(jump_target)
    );

    // ─── Outputs ───────────────────────────────────────────────────
    // JAL/JALR ride the same EX/MEM-resolved redirect path as B-type:
    //   - branch_target_out carries the JALR-corrected jump target
    //     (mux already selects jalr_target when is_jalr).
    //   - BranchTaken_out is forced 1 so the EX/MEM flush rail fires
    //     unconditionally for JAL/JALR.
    assign alu_result        = (is_jal | is_jalr) ? pc_plus4 : alu_raw;
    assign jump_target_out   = jump_target;
    assign branch_target_out = jump_target;
    assign BranchTaken_out   = BranchTaken | is_jal | is_jalr;

endmodule
