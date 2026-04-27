module datapath(
    input  clk,
    input  rst_n,
    output [31:0] pc_out
);
    // ─── IF stage wires ──────────────────────────────────────────────
    wire [31:0] if_pc_current, if_pc_instr, if_pc_plus4, if_instruction;
    wire [31:0] pc_next;

    // ─── IF/ID register wires ────────────────────────────────────────
    wire [31:0] id_pc, id_instruction;

    // ─── ID stage / control wires ────────────────────────────────────
    wire [6:0]  id_opcode;
    wire [4:0]  id_rd;
    wire [2:0]  id_funct3;
    wire [4:0]  id_rs1_addr, id_rs2_addr;
    wire [6:0]  id_funct7;
    wire [31:0] id_imm, id_rs1_data, id_rs2_data;
    wire        id_Branch, id_MemRead, id_MemToReg, id_MemWrite, id_ALUSrc, id_RegWrite;
    wire        id_CSRWrite, id_IsECALL, id_IsEBREAK, id_IsMRET;
    wire [1:0]  id_ALUOp, id_CSROp;
    wire [4:0]  id_ALUControl;

    // ─── ID/EX register wires ────────────────────────────────────────
    wire [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [6:0]  ex_opcode;
    wire [4:0]  ex_ALUControl;
    wire        ex_ALUSrc, ex_Branch, ex_MemRead, ex_MemWrite, ex_MemToReg, ex_RegWrite;
    wire [2:0]  ex_funct3;
    wire        ex_CSRWrite, ex_IsECALL, ex_IsEBREAK, ex_IsMRET;
    wire [1:0]  ex_CSROp;
    wire [11:0] ex_csr_addr;

    // ─── EX stage wires ──────────────────────────────────────────────
    wire [31:0] ex_alu_result, ex_pc_plus4, ex_branch_target, ex_jump_target;
    wire        ex_BranchTaken;
    wire [1:0]  fwd_a, fwd_b;

    // ─── EX/MEM register wires ───────────────────────────────────────
    wire [31:0] mem_alu_result, mem_rs2_data, mem_branch_target, mem_pc_plus4;
    wire [4:0]  mem_rd_addr;
    wire [6:0]  mem_opcode;
    wire        mem_BranchTaken, mem_MemRead, mem_MemWrite, mem_MemToReg, mem_RegWrite;
    wire [2:0]  mem_funct3;
    wire        mem_Branch;
    wire [31:0] mem_csr_wdata;
    wire [11:0] mem_csr_addr;
    wire        mem_CSRWrite;
    wire [1:0]  mem_CSROp;
    wire        mem_IsECALL, mem_IsEBREAK, mem_IsMRET;

    // ─── MEM stage / MEM/WB wires ────────────────────────────────────
    wire [31:0] mem_read_data;
    wire [31:0] wb_mem_read_data, wb_alu_result, wb_pc_plus4, wb_csr_rdata;
    wire [4:0]  wb_rd_addr;
    wire [6:0]  wb_opcode;
    wire        wb_MemToReg, wb_RegWrite, wb_CSRToReg;

    // ─── WB output ───────────────────────────────────────────────────
    wire [31:0] reg_write_data;

    // ─── Hazard / handshake wires ────────────────────────────────────
    wire hready_rom, hready_ram;
    wire stall, bubble_stall, freeze_stall, div_busy;
    wire hready_combined = hready_rom & hready_ram;

    // ─── Branch resolution (2-cycle, evaluated in MEM) ───────────────
    // branch_flush is the 1-cycle "redirect" pulse: it is HIGH during the
    // cycle the branch sits in MEM. Used to:
    //   - select mem_branch_target into PC,
    //   - clear pc_instr_reg (the AHB-ROM data-phase shadow PC),
    //   - flush the speculative instruction in IF/ID,
    //   - flush the speculative instruction in ID/EX,
    //   - flush the speculative instruction already in EX/MEM (Bug #2).
    //
    // Because the AHB ROM has 1-cycle read latency, the cycle AFTER a
    // redirect still has stale HRDATA (the wrong-path fetch). Without
    // a second flush cycle, that stale instruction would be latched
    // into IF/ID. branch_flush_d extends the IF/ID flush window by one
    // cycle so that stale instruction is dropped (Bug #3).
    wire branch_flush = mem_Branch & mem_BranchTaken;
    reg  branch_flush_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) branch_flush_d <= 1'b0;
        else        branch_flush_d <= branch_flush;
    end
    wire if_id_flush = branch_flush | branch_flush_d;

    // ─── IF stage ────────────────────────────────────────────────────
    if_stage fetch(
        .clk        (clk),
        .rst_n      (rst_n),
        .pc_en      (~stall),
        .if_flush   (branch_flush),
        .pc_next    (pc_next),
        .instruction(if_instruction),
        .pc_current (if_pc_current),
        .pc_instr   (if_pc_instr),
        .pc_plus4   (if_pc_plus4),
        .HREADY_ROM (hready_rom)
    );

    if_id_reg if_id_pipe(
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (~stall),
        .flush    (if_id_flush),
        .pc_in    (if_pc_instr),
        .instr_in (if_instruction),
        .pc_out   (id_pc),
        .instr_out(id_instruction)
    );

    // ─── ID stage ────────────────────────────────────────────────────
    id_stage decode(
        .clk        (clk),
        .instruction(id_instruction),
        .rd_addr_wb (wb_rd_addr),
        .rd_data    (reg_write_data),
        .RegWrite   (wb_RegWrite),
        .opcode     (id_opcode),
        .rd         (id_rd),
        .funct3     (id_funct3),
        .rs1_addr   (id_rs1_addr),
        .rs2_addr   (id_rs2_addr),
        .funct7     (id_funct7),
        .imm        (id_imm),
        .rs1_data   (id_rs1_data),
        .rs2_data   (id_rs2_data)
    );

    main_control_unit control(
        .opcode   (id_opcode),
        .funct3   (id_funct3),
        .funct7   (id_funct7),
        .rs2_addr (id_rs2_addr),
        .Branch   (id_Branch),
        .MemRead  (id_MemRead),
        .MemToReg (id_MemToReg),
        .ALUOp    (id_ALUOp),
        .MemWrite (id_MemWrite),
        .ALUSrc   (id_ALUSrc),
        .RegWrite (id_RegWrite),
        .CSRWrite (id_CSRWrite),
        .CSROp    (id_CSROp),
        .IsECALL  (id_IsECALL),
        .IsEBREAK (id_IsEBREAK),
        .IsMRET   (id_IsMRET)
    );

    // alu_decoder takes opcode now to honour RISC-V ISA: funct7[5] is
    // only meaningful for R-type (and the I-arith shift forms). For
    // ADDI/XORI/etc the funct7 bits are part of imm[11:5] and must be
    // ignored. (Bug #1)
    alu_decoder alu_dec(
        .opcode    (id_opcode),
        .ALUOp     (id_ALUOp),
        .funct3    (id_funct3),
        .funct7    (id_funct7),
        .ALUControl(id_ALUControl)
    );

    // ─── ID/EX register ──────────────────────────────────────────────
    // Split-stall semantics:
    //   - freeze_stall (DIV in flight): hold ID/EX so the multi-cycle
    //     EX-stage operation finishes against frozen operands.
    //   - bubble_stall (load-use, bus-wait): inject a NOP into EX so the
    //     stalling instruction stays in IF/ID and the consumer waits.
    //   - branch_flush: take precedence to flush the speculative slot.
    id_ex_reg id_ex_pipe(
        .clk          (clk),
        .rst_n        (rst_n),
        .enable       (~freeze_stall),
        .flush        (branch_flush | bubble_stall),
        .pc_in        (id_pc),
        .rs1_data_in  (id_rs1_data),
        .rs2_data_in  (id_rs2_data),
        .imm_in       (id_imm),
        .rs1_addr_in  (id_rs1_addr),
        .rs2_addr_in  (id_rs2_addr),
        .rd_addr_in   (id_rd),
        .opcode_in    (id_opcode),
        .ALUControl_in(id_ALUControl),
        .ALUSrc_in    (id_ALUSrc),
        .Branch_in    (id_Branch),
        .MemRead_in   (id_MemRead),
        .MemWrite_in  (id_MemWrite),
        .MemToReg_in  (id_MemToReg),
        .RegWrite_in  (id_RegWrite),
        .funct3_in    (id_funct3),
        .CSRWrite_in  (id_CSRWrite),
        .CSROp_in     (id_CSROp),
        .csr_addr_in  (id_instruction[31:20]),
        .IsECALL_in   (id_IsECALL),
        .IsEBREAK_in  (id_IsEBREAK),
        .IsMRET_in    (id_IsMRET),
        .pc_out        (ex_pc),
        .rs1_data_out  (ex_rs1_data),
        .rs2_data_out  (ex_rs2_data),
        .imm_out       (ex_imm),
        .rs1_addr_out  (ex_rs1_addr),
        .rs2_addr_out  (ex_rs2_addr),
        .rd_addr_out   (ex_rd_addr),
        .opcode_out    (ex_opcode),
        .ALUControl_out(ex_ALUControl),
        .ALUSrc_out    (ex_ALUSrc),
        .Branch_out    (ex_Branch),
        .MemRead_out   (ex_MemRead),
        .MemWrite_out  (ex_MemWrite),
        .MemToReg_out  (ex_MemToReg),
        .RegWrite_out  (ex_RegWrite),
        .funct3_out    (ex_funct3),
        .CSRWrite_out  (ex_CSRWrite),
        .CSROp_out     (ex_CSROp),
        .csr_addr_out  (ex_csr_addr),
        .IsECALL_out   (ex_IsECALL),
        .IsEBREAK_out  (ex_IsEBREAK),
        .IsMRET_out    (ex_IsMRET)
    );

    adder_32bit ex_pc_plus4_adder(
        .a       (ex_pc),
        .b       (32'h00000004),
        .sub     (1'b0),
        .result  (ex_pc_plus4),
        .cout    (),
        .overflow()
    );

    forwarding_unit forward(
        .id_ex_rs1      (ex_rs1_addr),
        .id_ex_rs2      (ex_rs2_addr),
        .ex_mem_rd      (mem_rd_addr),
        .ex_mem_regwrite(mem_RegWrite),
        .mem_wb_rd      (wb_rd_addr),
        .mem_wb_regwrite(wb_RegWrite),
        .forwardA       (fwd_a),
        .forwardB       (fwd_b)
    );

    hazard_detection_unit hdu(
        .id_ex_memread(ex_MemRead),
        .id_ex_rd     (ex_rd_addr),
        .if_id_rs1    (id_instruction[19:15]),
        .if_id_rs2    (id_instruction[24:20]),
        .hready       (hready_combined),
        .div_busy     (div_busy),
        .stall        (stall),
        .bubble_stall (bubble_stall),
        .freeze_stall (freeze_stall)
    );

    // ─── EX stage ────────────────────────────────────────────────────
    ex_stage execute(
        .clk               (clk),
        .rst_n             (rst_n),
        .rs1_data          (ex_rs1_data),
        .rs2_data          (ex_rs2_data),
        .imm               (ex_imm),
        .opcode            (ex_opcode),
        .funct3            (ex_funct3),
        .ALUControl        (ex_ALUControl),
        .ALUSrc            (ex_ALUSrc),
        .Branch            (ex_Branch),
        .pc_current        (ex_pc),
        .pc_plus4          (ex_pc_plus4),
        .alu_result        (ex_alu_result),
        .jump_target_out   (ex_jump_target),
        .branch_target_out (ex_branch_target),
        .BranchTaken_out   (ex_BranchTaken),
        .forwardA          (fwd_a),
        .forwardB          (fwd_b),
        .mem_alu_result_fwd(mem_alu_result),
        .wb_value_fwd      (reg_write_data),
        .div_busy          (div_busy)
    );

    // PC redirect: branch_flush drives a 1-cycle redirect to the branch
    // target captured in EX/MEM. Otherwise PC advances by 4.
    mux2 #(.WIDTH(32)) pc_next_mux(
        .in0(if_pc_plus4),
        .in1(mem_branch_target),
        .sel(branch_flush),
        .out(pc_next)
    );

    // ─── EX/MEM register ─────────────────────────────────────────────
    // - flush=branch_flush so the speculative instruction in EX is
    //   killed when the branch redirect fires (Bug #2).
    // - enable=~freeze_stall so the whole back end of the pipeline
    //   freezes during a multi-cycle DIV in EX (Bug #4).
    ex_mem_reg ex_mem_pipe(
        .clk              (clk),
        .rst_n            (rst_n),
        .flush            (branch_flush),
        .enable           (~freeze_stall),
        .alu_result_in    (ex_alu_result),
        .rs2_data_in      (ex_rs2_data),
        .rd_addr_in       (ex_rd_addr),
        .pc_plus4_in      (ex_pc_plus4),
        .opcode_in        (ex_opcode),
        .branch_target_in (ex_branch_target),
        .BranchTaken_in   (ex_BranchTaken),
        .MemRead_in       (ex_MemRead),
        .MemWrite_in      (ex_MemWrite),
        .MemToReg_in      (ex_MemToReg),
        .RegWrite_in      (ex_RegWrite),
        .funct3_in        (ex_funct3),
        .Branch_in        (ex_Branch),
        .csr_wdata_in     (ex_rs1_data),
        .csr_addr_in      (ex_csr_addr),
        .CSRWrite_in      (ex_CSRWrite),
        .CSROp_in         (ex_CSROp),
        .IsECALL_in       (ex_IsECALL),
        .IsEBREAK_in      (ex_IsEBREAK),
        .IsMRET_in        (ex_IsMRET),
        .alu_result_out   (mem_alu_result),
        .rs2_data_out     (mem_rs2_data),
        .rd_addr_out      (mem_rd_addr),
        .pc_plus4_out     (mem_pc_plus4),
        .opcode_out       (mem_opcode),
        .branch_target_out(mem_branch_target),
        .BranchTaken_out  (mem_BranchTaken),
        .MemRead_out      (mem_MemRead),
        .MemWrite_out     (mem_MemWrite),
        .MemToReg_out     (mem_MemToReg),
        .RegWrite_out     (mem_RegWrite),
        .funct3_out       (mem_funct3),
        .Branch_out       (mem_Branch),
        .csr_wdata_out    (mem_csr_wdata),
        .csr_addr_out     (mem_csr_addr),
        .CSRWrite_out     (mem_CSRWrite),
        .CSROp_out        (mem_CSROp),
        .IsECALL_out      (mem_IsECALL),
        .IsEBREAK_out     (mem_IsEBREAK),
        .IsMRET_out       (mem_IsMRET)
    );

    // ─── MEM stage ───────────────────────────────────────────────────
    mem_stage memory(
        .clk          (clk),
        .rst_n        (rst_n),
        .alu_result   (mem_alu_result),
        .rs2_data     (mem_rs2_data),
        .MemRead      (mem_MemRead),
        .MemWrite     (mem_MemWrite),
        .funct3       (mem_funct3),
        .mem_read_data(mem_read_data),
        .HREADY_RAM   (hready_ram)
    );

    // ─── MEM/WB register ─────────────────────────────────────────────
    // enable=~freeze_stall to keep the whole back end frozen during DIV.
    mem_wb_reg mem_wb_pipe(
        .clk              (clk),
        .rst_n            (rst_n),
        .flush            (1'b0),
        .enable           (~freeze_stall),
        .mem_read_data_in (mem_read_data),
        .alu_result_in    (mem_alu_result),
        .rd_addr_in       (mem_rd_addr),
        .pc_plus4_in      (mem_pc_plus4),
        .opcode_in        (mem_opcode),
        .MemToReg_in      (mem_MemToReg),
        .RegWrite_in      (mem_RegWrite),
        .csr_rdata_in     (32'b0),
        .CSRToReg_in      (1'b0),
        .mem_read_data_out(wb_mem_read_data),
        .alu_result_out   (wb_alu_result),
        .rd_addr_out      (wb_rd_addr),
        .pc_plus4_out     (wb_pc_plus4),
        .opcode_out       (wb_opcode),
        .MemToReg_out     (wb_MemToReg),
        .RegWrite_out     (wb_RegWrite),
        .csr_rdata_out    (wb_csr_rdata),
        .CSRToReg_out     (wb_CSRToReg)
    );

    // ─── WB stage ────────────────────────────────────────────────────
    wb_stage writeback(
        .alu_result    (wb_alu_result),
        .mem_read_data (wb_mem_read_data),
        .pc_plus4      (wb_pc_plus4),
        .MemToReg      (wb_MemToReg),
        .opcode        (wb_opcode),
        .reg_write_data(reg_write_data)
    );

    assign pc_out = if_pc_current;
endmodule
