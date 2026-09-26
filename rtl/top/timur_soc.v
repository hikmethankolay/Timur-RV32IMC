// Timur SoC: everything below the board wrapper, clocked by the CPU clock.
// Testbenches instantiate this module and drive its clock and reset directly.
//
//   CPU     : 5-stage pipeline IF, ID, EX, MEM, WB with full forwarding;
//             branches, jumps, MRET and traps redirect from EX; machine-mode
//             CSRs, precise traps and an external interrupt (Phase 10)
//   Fetch   : private port into the split-bank ROM (Harvard fetch, never
//             waits); 16-bit instructions are expanded in IF (Phase 11)
//   Data bus: AHB-Lite slaves behind a 2-master arbiter (CPU data port with
//             priority, DMAC), AHB-to-APB bridge for UART, GPIO, DMAC registers
//
// Address map
//   0x0000_0000 - 0x0000_FFFF  ROM (fetch port + AHB data port)
//   0x2000_0000 - 0x2000_FFFF  RAM
//   0x4000_0000 - 0x4000_00FF  UART   (APB)
//   0x4000_0100 - 0x4000_01FF  GPIO   (APB)
//   0x4000_0200 - 0x4000_02FF  DMAC   (APB)
//   anything else              default slave: reads 0, writes ignored
module timur_soc #(
    parameter UART_DIVIDER = 433   // f_clk / baud - 1: 115200 baud at 50 MHz
) (
    input        clk,
    input        rst_n,      // synchronised reset
    input  [9:0] gpio_in,    // SW[9:0]
    output [9:0] gpio_out,   // LEDR[9:0]
    input        uart_rx,
    output       uart_tx
);

    // =====================================================================
    // Hazard control (Phase 7)
    // =====================================================================
    wire pc_load;
    wire if_id_enable,  if_id_flush;
    wire id_ex_enable,  id_ex_flush;
    wire ex_mem_enable, ex_mem_flush;
    wire mem_wb_enable;
    wire mul_start, mul_ack;
    wire div_start, div_ack;
    wire take_redirect;
    wire redirect_req;
    wire trap_req;
    wire take_trap;
    // take_redirect OR take_trap, built for timing (see EX). The keep
    // attributes here and below stop synthesis from merging these nets into
    // the logic around them, which would put more levels after the late
    // branch compare.
    (* keep = 1 *) wire fetch_go;
    wire bus_wait;
    wire mul_in_ex, mul_done;
    wire div_in_ex, div_busy, div_done;

    // =====================================================================
    // IF: next PC, split-bank ROM fetch, decompressor (Phase 11)
    // =====================================================================
    wire [31:0] if_pc;
    wire [31:0] if_pc_plus2;
    wire [31:0] if_pc_plus4;
    wire [31:0] if_pc_seq;           // PC + 2 or PC + 4: length of the instruction in IF
    wire [31:0] jump_pc;             // mtvec on a trap, else the redirect target
    wire [31:0] pc_next;
    wire [31:0] redirect_target;
    wire [28:0] redirect_index;      // fetch indexes of redirect_target, see below
    wire [31:0] csr_mtvec;
    wire [31:0] csr_mepc;
    wire [31:0] fetch_window;        // 32 bits starting at the PC
    wire        if_compressed;
    wire [31:0] if_expanded;
    wire [31:0] if_instr;

    pc u_pc (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (pc_load),
        .pc_next (pc_next),
        .pc      (if_pc)
    );

    adder_32bit u_pc_plus2 (
        .a        (if_pc),
        .b        (32'd2),
        .sub      (1'b0),
        .result   (if_pc_plus2),
        .cout     (),
        .overflow ()
    );

    adder_32bit u_pc_plus4 (
        .a        (if_pc),
        .b        (32'd4),
        .sub      (1'b0),
        .result   (if_pc_plus4),
        .cout     (),
        .overflow ()
    );

    // The instruction in IF is 16-bit when its low bits are not 11; IF/ID
    // only ever receives the 32-bit form.
    assign if_compressed = (fetch_window[1:0] != 2'b11);

    decompressor u_decompressor (
        .instr16 (fetch_window[15:0]),
        .instr32 (if_expanded),
        .illegal ()                  // an illegal encoding expands to 00000000
    );

    mux2 #(.WIDTH(32)) u_if_instr (
        .in0 (fetch_window),
        .in1 (if_expanded),
        .sel (if_compressed),
        .out (if_instr)
    );

    mux2 #(.WIDTH(32)) u_pc_seq_len (
        .in0 (if_pc_plus4),
        .in1 (if_pc_plus2),
        .sel (if_compressed),
        .out (if_pc_seq)
    );

    // Next PC. A trap wins over a redirect in the same cycle (an interrupt can
    // arrive while a branch is in EX): the priority sits on the data side, so
    // the late select fetch_go (redirect or trap) is applied last.
    mux2 #(.WIDTH(32)) u_jump_pc (
        .in0 (redirect_target),
        .in1 (csr_mtvec),
        .sel (take_trap),
        .out (jump_pc)
    );

    mux2 #(.WIDTH(32)) u_pc_next_mux (
        .in0 (if_pc_seq),
        .in1 (jump_pc),
        .sel (fetch_go),
        .out (pc_next)
    );

    // ---------------------------------------------------------------------
    // ROM fetch indexes. The 32 bits at byte address A are LO[(A + 2) >> 2]
    // and HI[A >> 2], ordered by A[1]; an index triple is {lo, hi, A[1]}.
    // The ROM registers the triple of the address the PC register will hold
    // after the edge, so fetch_window always belongs to the current PC:
    //   fetch address = NOT rst_n ? 0 : (pc_load ? pc_next : pc)
    // Without a redirect or trap the PC loads exactly when IF/ID does. Every
    // candidate address gets its triple before the final select, so no adder
    // sits after the redirect decision: the sequential triple (and reset) on
    // one side, the trap or redirect triple on the other, and fetch_go with
    // one mux level before the ROM address registers.
    // ---------------------------------------------------------------------
    wire [13:0] pc_w  = if_pc[15:2];
    wire [13:0] pc_w1 = pc_w + 14'd1;
    wire [13:0] pc_w2 = pc_w + 14'd2;
    wire        pc_b  = if_pc[1];

    wire [28:0] index_hold = {pc_b ? pc_w1 : pc_w, pc_w,               pc_b};    // A = PC
    wire [28:0] index_pc2  = {pc_w1,               pc_b ? pc_w1 : pc_w, !pc_b};   // A = PC + 2
    wire [28:0] index_pc4  = {pc_b ? pc_w2 : pc_w1, pc_w1,             pc_b};    // A = PC + 4
    wire [28:0] index_mtvec = {csr_mtvec[15:2], csr_mtvec[15:2], 1'b0};
    wire [28:0] index_len, index_seq, index_fetch;
    (* keep = 1 *) wire [28:0] index_pre;
    (* keep = 1 *) wire [28:0] index_jump;

    mux2 #(.WIDTH(29)) u_index_len (
        .in0 (index_pc4),
        .in1 (index_pc2),
        .sel (if_compressed),
        .out (index_len)
    );

    mux2 #(.WIDTH(29)) u_index_seq (
        .in0 (index_hold),
        .in1 (index_len),
        .sel (if_id_enable),
        .out (index_seq)
    );

    // During reset the ROM reads address 0, so the first word is ready when
    // reset releases (fetch_go is 0 during reset).
    mux2 #(.WIDTH(29)) u_index_reset (
        .in0 (29'b0),
        .in1 (index_seq),
        .sel (rst_n),
        .out (index_pre)
    );

    mux2 #(.WIDTH(29)) u_index_jump (
        .in0 (redirect_index),
        .in1 (index_mtvec),
        .sel (take_trap),
        .out (index_jump)
    );

    mux2 #(.WIDTH(29)) u_index_fetch (
        .in0 (index_pre),
        .in1 (index_jump),
        .sel (fetch_go),
        .out (index_fetch)
    );

    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;
    wire        if_id_compressed;
    wire        if_id_valid;

    if_id_reg u_if_id (
        .clk               (clk),
        .rst_n             (rst_n),
        .enable            (if_id_enable),
        .flush             (if_id_flush),
        .pc_in             (if_pc),
        .instr_in          (if_instr),
        .is_compressed_in  (if_compressed),
        .valid_in          (1'b1),
        .pc_out            (if_id_pc),
        .instr_out         (if_id_instr),
        .is_compressed_out (if_id_compressed),
        .valid_out         (if_id_valid)
    );

    // =====================================================================
    // ID: parse, immediate, control, ALU decode, register read
    // =====================================================================
    wire [6:0]  id_opcode;
    wire [4:0]  id_rd;
    wire [2:0]  id_funct3;
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [6:0]  id_funct7;
    wire [31:0] id_imm;
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;

    wire        id_regwrite;
    wire [1:0]  id_alusrca;
    wire        id_alusrcb;
    wire [1:0]  id_aluop;
    wire        id_memread;
    wire        id_memwrite;
    wire        id_memtoreg;
    wire        id_branch;
    wire        id_jump;
    wire        id_jalr;
    wire        id_csraccess;
    wire [1:0]  id_csrop;
    wire        id_csrimm;
    wire        id_isecall;
    wire        id_isebreak;
    wire        id_ismret;
    wire        id_illegal;
    wire [4:0]  id_alucontrol;

    // write-back port (WB stage)
    wire [4:0]  mem_wb_rd;
    wire        mem_wb_regwrite;
    wire        mem_wb_valid;
    wire [31:0] wb_data;

    instr_parser u_parser (
        .instruction (if_id_instr),
        .opcode      (id_opcode),
        .rd          (id_rd),
        .funct3      (id_funct3),
        .rs1         (id_rs1),
        .rs2         (id_rs2),
        .funct7      (id_funct7)
    );

    imm_gen u_imm_gen (
        .instruction (if_id_instr),
        .opcode      (id_opcode),
        .imm         (id_imm)
    );

    main_control_unit u_control (
        .opcode    (id_opcode),
        .funct3    (id_funct3),
        .funct7    (id_funct7),
        .rs2_addr  (id_rs2),
        .RegWrite  (id_regwrite),
        .ALUSrcA   (id_alusrca),
        .ALUSrcB   (id_alusrcb),
        .ALUOp     (id_aluop),
        .MemRead   (id_memread),
        .MemWrite  (id_memwrite),
        .MemToReg  (id_memtoreg),
        .Branch    (id_branch),
        .Jump      (id_jump),
        .Jalr      (id_jalr),
        .CSRAccess (id_csraccess),
        .CSROp     (id_csrop),
        .CSRImm    (id_csrimm),
        .IsECALL   (id_isecall),
        .IsEBREAK  (id_isebreak),
        .IsMRET    (id_ismret),
        .Illegal   (id_illegal)
    );

    alu_decoder u_alu_decoder (
        .ALUOp      (id_aluop),
        .funct3     (id_funct3),
        .funct7     (id_funct7),
        .op5        (id_opcode[5]),
        .ALUControl (id_alucontrol)
    );

    // Written by WB with RegWrite and valid; the write-through bypass covers
    // an instruction in ID reading a register that WB writes in the same cycle.
    registers u_regs (
        .clk       (clk),
        .rs1_addr  (id_rs1),
        .rs2_addr  (id_rs2),
        .rd_addr   (mem_wb_rd),
        .rd_data   (wb_data),
        .reg_write (mem_wb_regwrite && mem_wb_valid),
        .rs1_data  (id_rs1_data),
        .rs2_data  (id_rs2_data)
    );

    wire [31:0] id_ex_pc;
    wire [31:0] id_ex_rs1_data;
    wire [31:0] id_ex_rs2_data;
    wire [31:0] id_ex_imm;
    wire [4:0]  id_ex_rs1;
    wire [4:0]  id_ex_rs2;
    wire [4:0]  id_ex_rd;
    wire [2:0]  id_ex_funct3;
    wire [11:0] id_ex_csr_addr;
    wire [4:0]  id_ex_alucontrol;
    wire [1:0]  id_ex_alusrca;
    wire        id_ex_alusrcb;
    wire        id_ex_branch;
    wire        id_ex_jump;
    wire        id_ex_jalr;
    wire        id_ex_memread;
    wire        id_ex_memwrite;
    wire        id_ex_memtoreg;
    wire        id_ex_regwrite;
    wire        id_ex_csraccess;
    wire [1:0]  id_ex_csrop;
    wire        id_ex_csrimm;
    wire        id_ex_isecall;
    wire        id_ex_isebreak;
    wire        id_ex_ismret;
    wire        id_ex_illegal;
    wire        id_ex_compressed;
    wire        id_ex_valid;

    id_ex_reg u_id_ex (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (id_ex_enable),
        .flush          (id_ex_flush),
        .pc_in          (if_id_pc),
        .rs1_data_in    (id_rs1_data),
        .rs2_data_in    (id_rs2_data),
        .imm_in         (id_imm),
        .rs1_addr_in    (id_rs1),
        .rs2_addr_in    (id_rs2),
        .rd_addr_in     (id_rd),
        .funct3_in      (id_funct3),
        .csr_addr_in    (if_id_instr[31:20]),
        .ALUControl_in  (id_alucontrol),
        .ALUSrcA_in     (id_alusrca),
        .ALUSrcB_in     (id_alusrcb),
        .Branch_in      (id_branch),
        .Jump_in        (id_jump),
        .Jalr_in        (id_jalr),
        .MemRead_in     (id_memread),
        .MemWrite_in    (id_memwrite),
        .MemToReg_in    (id_memtoreg),
        .RegWrite_in    (id_regwrite),
        .CSRAccess_in   (id_csraccess),
        .CSROp_in       (id_csrop),
        .CSRImm_in      (id_csrimm),
        .IsECALL_in     (id_isecall),
        .IsEBREAK_in    (id_isebreak),
        .IsMRET_in      (id_ismret),
        .Illegal_in     (id_illegal),
        .is_compressed_in (if_id_compressed),
        .valid_in       (if_id_valid),
        .pc_out         (id_ex_pc),
        .rs1_data_out   (id_ex_rs1_data),
        .rs2_data_out   (id_ex_rs2_data),
        .imm_out        (id_ex_imm),
        .rs1_addr_out   (id_ex_rs1),
        .rs2_addr_out   (id_ex_rs2),
        .rd_addr_out    (id_ex_rd),
        .funct3_out     (id_ex_funct3),
        .csr_addr_out   (id_ex_csr_addr),
        .ALUControl_out (id_ex_alucontrol),
        .ALUSrcA_out    (id_ex_alusrca),
        .ALUSrcB_out    (id_ex_alusrcb),
        .Branch_out     (id_ex_branch),
        .Jump_out       (id_ex_jump),
        .Jalr_out       (id_ex_jalr),
        .MemRead_out    (id_ex_memread),
        .MemWrite_out   (id_ex_memwrite),
        .MemToReg_out   (id_ex_memtoreg),
        .RegWrite_out   (id_ex_regwrite),
        .CSRAccess_out  (id_ex_csraccess),
        .CSROp_out      (id_ex_csrop),
        .CSRImm_out     (id_ex_csrimm),
        .IsECALL_out    (id_ex_isecall),
        .IsEBREAK_out   (id_ex_isebreak),
        .IsMRET_out     (id_ex_ismret),
        .Illegal_out    (id_ex_illegal),
        .is_compressed_out (id_ex_compressed),
        .valid_out      (id_ex_valid)
    );

    // =====================================================================
    // EX: forwarding, operand select, ALU, branch evaluation, redirect
    // =====================================================================
    wire [4:0]  ex_mem_rd;
    wire        ex_mem_regwrite;
    wire [31:0] ex_mem_result;

    wire [1:0]  forwardA;
    wire [1:0]  forwardB;
    wire [31:0] ex_rs1;          // forwarded rs1
    wire [31:0] ex_rs2;          // forwarded rs2: ALU operand B and store data
    wire [31:0] alu_a;
    wire [31:0] alu_b;
    wire [31:0] alu_result;
    (* keep = 1 *) wire cmp_equal;
    wire        cmp_cout;
    (* keep = 1 *) wire cmp_less;
    wire        taken_if_eq, taken_if_lt, taken_if_gt;
    wire [31:0] branch_target;
    wire [31:0] jalr_sum;
    wire [31:0] jalr_target;
    wire [31:0] transfer_target;
    wire [31:0] link_addr;
    wire [31:0] ex_result;

    forwarding_unit u_forwarding (
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_regwrite (ex_mem_regwrite),
        .mem_wb_rd       (mem_wb_rd),
        .mem_wb_regwrite (mem_wb_regwrite),
        .forwardA        (forwardA),
        .forwardB        (forwardB)
    );

    // 00 ID/EX value, 01 WB write-back value, 10 EX/MEM result
    mux4 #(.WIDTH(32)) u_forward_a (
        .in0 (id_ex_rs1_data),
        .in1 (wb_data),
        .in2 (ex_mem_result),
        .in3 (32'b0),
        .sel (forwardA),
        .out (ex_rs1)
    );

    mux4 #(.WIDTH(32)) u_forward_b (
        .in0 (id_ex_rs2_data),
        .in1 (wb_data),
        .in2 (ex_mem_result),
        .in3 (32'b0),
        .sel (forwardB),
        .out (ex_rs2)
    );

    // ALUSrcA: 00 rs1, 01 PC, 10 zero
    mux4 #(.WIDTH(32)) u_alu_src_a (
        .in0 (ex_rs1),
        .in1 (id_ex_pc),
        .in2 (32'b0),
        .in3 (32'b0),
        .sel (id_ex_alusrca),
        .out (alu_a)
    );

    // ALUSrcB: 0 rs2, 1 immediate
    mux2 #(.WIDTH(32)) u_alu_src_b (
        .in0 (ex_rs2),
        .in1 (id_ex_imm),
        .sel (id_ex_alusrcb),
        .out (alu_b)
    );

    alu u_alu (
        .clk        (clk),
        .rst_n      (rst_n),
        .a          (alu_a),
        .b          (alu_b),
        .ALUControl (id_ex_alucontrol),
        .mul_start  (mul_start),
        .mul_ack    (mul_ack),
        .div_start  (div_start),
        .div_ack    (div_ack),
        .result     (alu_result),
        .zero       (),
        .cout       (),
        .overflow   (),
        .mul_done   (mul_done),
        .div_busy   (div_busy),
        .div_done   (div_done)
    );

    // Branch compare and jump targets have their own adders on the forwarded
    // operands. The redirect ends at the ROM fetch address registers, so it is
    // the longest path in EX; taking it through the ALU would add the operand
    // select and the full result mux.
    // One subtraction gives "less" for every branch: inverting both operand
    // MSBs turns the unsigned compare into a signed one (BLT, BGE have
    // funct3[1] = 0). The equality compare does not wait for the carry chain.
    wire        cmp_signed = !id_ex_funct3[1];

    adder_32bit u_branch_cmp (
        .a        ({ex_rs1[31] ^ cmp_signed, ex_rs1[30:0]}),
        .b        ({ex_rs2[31] ^ cmp_signed, ex_rs2[30:0]}),
        .sub      (1'b1),
        .result   (),
        .cout     (cmp_cout),
        .overflow ()
    );

    assign cmp_less  = !cmp_cout;                  // borrow: rs1 < rs2
    assign cmp_equal = (ex_rs1 == ex_rs2);

    // The branch type is known at the start of EX, the compare results only
    // late. The decision is therefore evaluated in advance for each possible
    // compare result (equal; less; greater) and the results only select.
    branch_condition_evaluator u_taken_if_eq (
        .equal       (1'b1),
        .less        (1'b0),
        .BranchType  (id_ex_funct3),
        .BranchTaken (taken_if_eq)
    );

    branch_condition_evaluator u_taken_if_lt (
        .equal       (1'b0),
        .less        (1'b1),
        .BranchType  (id_ex_funct3),
        .BranchTaken (taken_if_lt)
    );

    branch_condition_evaluator u_taken_if_gt (
        .equal       (1'b0),
        .less        (1'b0),
        .BranchType  (id_ex_funct3),
        .BranchTaken (taken_if_gt)
    );

    // Branch and JAL target: PC + imm
    adder_32bit u_branch_target (
        .a        (id_ex_pc),
        .b        (id_ex_imm),
        .sub      (1'b0),
        .result   (branch_target),
        .cout     (),
        .overflow ()
    );

    // Link value: PC + 2 for C.JAL and C.JALR, PC + 4 otherwise.
    adder_32bit u_link_addr (
        .a        (id_ex_pc),
        .b        (id_ex_compressed ? 32'd2 : 32'd4),
        .sub      (1'b0),
        .result   (link_addr),
        .cout     (),
        .overflow ()
    );

    // JALR target: rs1 + imm with bit 0 cleared
    adder_32bit u_jalr_target (
        .a        (ex_rs1),
        .b        (id_ex_imm),
        .sub      (1'b0),
        .result   (jalr_sum),
        .cout     (),
        .overflow ()
    );

    assign jalr_target = {jalr_sum[31:1], 1'b0};

    // Redirects from EX: taken branch, JAL, JALR and MRET (PC <- mepc).
    wire always_redirect = id_ex_jump || id_ex_jalr || id_ex_ismret;
    wire redirect_if_eq  = always_redirect || (id_ex_branch && taken_if_eq);
    wire redirect_if_lt  = always_redirect || (id_ex_branch && taken_if_lt);
    wire redirect_if_gt  = always_redirect || (id_ex_branch && taken_if_gt);

    assign redirect_req = cmp_equal ? redirect_if_eq : (cmp_less ? redirect_if_lt : redirect_if_gt);

    // fetch_go = take_redirect OR take_trap for the PC and fetch multiplexers,
    // with the bus freeze and the trap (both decided earlier) folded into the
    // per-result terms, so the compare results are the last two levels.
    (* keep = 1 *) wire go_if_eq = !bus_wait && (redirect_if_eq || trap_req);
    (* keep = 1 *) wire go_if_lt = !bus_wait && (redirect_if_lt || trap_req);
    (* keep = 1 *) wire go_if_gt = !bus_wait && (redirect_if_gt || trap_req);

    assign fetch_go = cmp_equal ? go_if_eq : (cmp_less ? go_if_lt : go_if_gt);

    // Fetch index triples of the three targets (see IF), each from its own
    // adder: the LO index of an address A is (A + 2) >> 2. For JALR,
    // ((rs1 + imm) & ~1) + 2 and rs1 + imm + 2 agree in bits [15:2].
    wire [15:0] imm_plus2    = id_ex_imm[15:0] + 16'd2;
    wire [15:0] branch_plus2 = id_ex_pc[15:0] + imm_plus2;
    wire [15:0] jalr_plus2   = ex_rs1[15:0] + imm_plus2;
    wire [15:0] mepc_plus2   = csr_mepc[15:0] + 16'd2;
    wire [28:0] index_branch = {branch_plus2[15:2], branch_target[15:2], branch_target[1]};
    wire [28:0] index_jalr   = {jalr_plus2[15:2], jalr_target[15:2], jalr_target[1]};
    wire [28:0] index_mepc   = {mepc_plus2[15:2], csr_mepc[15:2], csr_mepc[1]};
    wire [28:0] index_transfer;

    mux2 #(.WIDTH(29)) u_index_transfer (
        .in0 (index_branch),
        .in1 (index_jalr),
        .sel (id_ex_jalr),
        .out (index_transfer)
    );

    mux2 #(.WIDTH(29)) u_index_redirect (
        .in0 (index_transfer),
        .in1 (index_mepc),
        .sel (id_ex_ismret),
        .out (redirect_index)
    );

    mux2 #(.WIDTH(32)) u_transfer_target (
        .in0 (branch_target),
        .in1 (jalr_target),
        .sel (id_ex_jalr),
        .out (transfer_target)
    );

    mux2 #(.WIDTH(32)) u_redirect_target (
        .in0 (transfer_target),
        .in1 (csr_mepc),
        .sel (id_ex_ismret),
        .out (redirect_target)
    );

    // ---------------------------------------------------------------------
    // CSR access and traps (Phase 10). A CSR instruction reads the old value
    // and writes the new one in the cycle it leaves EX: once, even across a
    // bus freeze, and never when it is killed by a trap. SET and CLEAR with
    // rs1 = x0 (or uimm = 0) write nothing, so csrr of a read-only CSR does
    // not trap.
    // ---------------------------------------------------------------------
    wire [31:0] csr_rdata;
    wire [31:0] csr_wdata;
    wire        csr_illegal;
    wire        csr_write_attempt;
    wire        csr_we;
    wire        csr_irq_pending;
    wire [31:0] trap_cause;
    wire [31:0] trap_val;
    wire        uart_irq;
    wire        dmac_irq;
    wire [1:0]  mem_addr_lo;

    assign csr_wdata         = id_ex_csrimm ? {27'b0, id_ex_rs1} : ex_rs1;
    assign csr_write_attempt = id_ex_csraccess && !(id_ex_csrop != 2'b00 && id_ex_rs1 == 5'b00000);
    assign csr_we            = csr_write_attempt && id_ex_valid && ex_mem_enable && !ex_mem_flush;

    csr_file u_csr (
        .clk               (clk),
        .rst_n             (rst_n),
        .csr_addr          (id_ex_csr_addr),
        .csr_op            (id_ex_csrop),
        .csr_wdata         (csr_wdata),
        .csr_write_attempt (csr_write_attempt),
        .csr_we            (csr_we),
        .csr_rdata         (csr_rdata),
        .csr_illegal       (csr_illegal),
        .trap_take         (take_trap),
        .trap_cause        (trap_cause),
        .trap_epc          (id_ex_pc),
        .trap_val          (trap_val),
        .mret_take         (take_redirect && id_ex_ismret && !take_trap),
        .retire            (mem_wb_valid && mem_wb_enable),
        .irq_lines         ({dmac_irq, uart_irq}),
        .mtvec_out         (csr_mtvec),
        .mepc_out          (csr_mepc),
        .irq_pending       (csr_irq_pending)
    );

    // Low address bits of a load or store, from their own 2-bit adder: the
    // misalignment check feeds the trap decision, which feeds the fetch
    // address, so it does not wait for the ALU result mux.
    assign mem_addr_lo = ex_rs1[1:0] + id_ex_imm[1:0];

    trap_unit u_trap (
        .valid           (id_ex_valid),
        .pc              (id_ex_pc),
        .illegal         (id_ex_illegal),
        .is_ecall        (id_ex_isecall),
        .is_ebreak       (id_ex_isebreak),
        .csr_access      (id_ex_csraccess),
        .csr_illegal     (csr_illegal),
        .mem_read        (id_ex_memread),
        .mem_write       (id_ex_memwrite),
        .funct3          (id_ex_funct3),
        .mem_addr_lo     (mem_addr_lo),
        .mem_addr        (alu_result),
        .irq_pending     (csr_irq_pending),
        .irq_allowed     (!(mul_in_ex || div_in_ex)),
        .trap_req        (trap_req),
        .trap_cause      (trap_cause),
        .trap_val        (trap_val)
    );

    // EX result: JAL/JALR -> PC + 4; CSR access -> old CSR value; else the
    // ALU result.
    assign ex_result = (id_ex_jump || id_ex_jalr) ? link_addr :
                       id_ex_csraccess            ? csr_rdata :
                                                    alu_result;

    // MUL, MULH, MULHSU, MULHU: ALUControl 100xx; DIV, DIVU, REM, REMU: 101xx
    assign mul_in_ex = id_ex_valid && (id_ex_alucontrol[4:2] == 3'b100);
    assign div_in_ex = id_ex_valid && (id_ex_alucontrol[4:2] == 3'b101);

    // =====================================================================
    // MEM: store alignment, AHB address phase
    // =====================================================================
    wire [31:0] ex_mem_store_data;
    wire [2:0]  ex_mem_funct3;
    wire        ex_mem_memread;
    wire        ex_mem_memwrite;
    wire        ex_mem_memtoreg;
    wire        ex_mem_valid;

    ex_mem_reg u_ex_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (ex_mem_enable),
        .flush          (ex_mem_flush),
        .result_in      (ex_result),
        .store_data_in  (ex_rs2),
        .rd_addr_in     (id_ex_rd),
        .funct3_in      (id_ex_funct3),
        .MemRead_in     (id_ex_memread),
        .MemWrite_in    (id_ex_memwrite),
        .MemToReg_in    (id_ex_memtoreg),
        .RegWrite_in    (id_ex_regwrite),
        .valid_in       (id_ex_valid),
        .result_out     (ex_mem_result),
        .store_data_out (ex_mem_store_data),
        .rd_addr_out    (ex_mem_rd),
        .funct3_out     (ex_mem_funct3),
        .MemRead_out    (ex_mem_memread),
        .MemWrite_out   (ex_mem_memwrite),
        .MemToReg_out   (ex_mem_memtoreg),
        .RegWrite_out   (ex_mem_regwrite),
        .valid_out      (ex_mem_valid)
    );

    wire [31:0] store_wdata;

    store_aligner u_store_aligner (
        .funct3 (ex_mem_funct3),
        .rs2    (ex_mem_store_data),
        .hwdata (store_wdata)
    );

    // AHB data bus
    wire        hmaster;
    wire        hmaster_data;
    wire [1:0]  hgrant;
    wire [31:0] haddr;
    wire [1:0]  htrans;
    wire        hwrite;
    wire [2:0]  hsize;
    wire [31:0] hwdata;
    wire [31:0] hrdata;
    wire        hready;

    wire [31:0] cpu_haddr;
    wire [1:0]  cpu_htrans;
    wire        cpu_hwrite;
    wire [2:0]  cpu_hsize;
    wire [31:0] cpu_hwdata;
    wire        cpu_hbusreq;
    wire [31:0] cpu_load_data;

    cpu_ahb_master u_cpu_master (
        .HCLK       (clk),
        .HRESETn    (rst_n),
        .addr       (ex_mem_result),
        .store_data (store_wdata),
        .funct3     (ex_mem_funct3),
        .mem_read   (ex_mem_memread),
        .mem_write  (ex_mem_memwrite),
        .mem_valid  (ex_mem_valid),
        .HGRANT     (hgrant[0]),
        .HREADY     (hready),
        .HRDATA     (hrdata),
        .HADDR      (cpu_haddr),
        .HTRANS     (cpu_htrans),
        .HWRITE     (cpu_hwrite),
        .HSIZE      (cpu_hsize),
        .HBURST     (),
        .HPROT      (),
        .HMASTLOCK  (),
        .HWDATA     (cpu_hwdata),
        .HBUSREQ    (cpu_hbusreq),
        .load_data  (cpu_load_data),
        .bus_wait   (bus_wait)
    );

    // =====================================================================
    // WB: AHB data phase, load formatting, register write
    // =====================================================================
    wire [31:0] mem_wb_result;
    wire [2:0]  mem_wb_funct3;
    wire        mem_wb_memtoreg;
    wire [31:0] load_value;

    mem_wb_reg u_mem_wb (
        .clk          (clk),
        .rst_n        (rst_n),
        .enable       (mem_wb_enable),
        .flush        (1'b0),
        .result_in    (ex_mem_result),
        .rd_addr_in   (ex_mem_rd),
        .funct3_in    (ex_mem_funct3),
        .MemToReg_in  (ex_mem_memtoreg),
        .RegWrite_in  (ex_mem_regwrite),
        .valid_in     (ex_mem_valid),
        .result_out   (mem_wb_result),
        .rd_addr_out  (mem_wb_rd),
        .funct3_out   (mem_wb_funct3),
        .MemToReg_out (mem_wb_memtoreg),
        .RegWrite_out (mem_wb_regwrite),
        .valid_out    (mem_wb_valid)
    );

    load_formatter u_load_formatter (
        .hrdata    (cpu_load_data),
        .addr      (mem_wb_result[1:0]),
        .funct3    (mem_wb_funct3),
        .load_data (load_value)
    );

    // Write-back value; also the WB forwarding source.
    mux2 #(.WIDTH(32)) u_wb_mux (
        .in0 (mem_wb_result),
        .in1 (load_value),
        .sel (mem_wb_memtoreg),
        .out (wb_data)
    );

    hazard_detection_unit u_hazard (
        .id_ex_valid   (id_ex_valid),
        .id_ex_memread (id_ex_memread),
        .id_ex_rd      (id_ex_rd),
        .if_id_rs1     (id_rs1),
        .if_id_rs2     (id_rs2),
        .mul_in_ex     (mul_in_ex),
        .mul_done      (mul_done),
        .div_in_ex     (div_in_ex),
        .div_busy      (div_busy),
        .div_done      (div_done),
        .bus_wait      (bus_wait),
        .redirect_req  (redirect_req),
        .trap_req      (trap_req),
        .pc_load       (pc_load),
        .if_id_enable  (if_id_enable),
        .if_id_flush   (if_id_flush),
        .id_ex_enable  (id_ex_enable),
        .id_ex_flush   (id_ex_flush),
        .ex_mem_enable (ex_mem_enable),
        .ex_mem_flush  (ex_mem_flush),
        .mem_wb_enable (mem_wb_enable),
        .mul_start     (mul_start),
        .mul_ack       (mul_ack),
        .div_start     (div_start),
        .div_ack       (div_ack),
        .take_redirect (take_redirect),
        .take_trap     (take_trap)
    );

    // =====================================================================
    // DMA engine (master 1) and bus fabric
    // =====================================================================
    wire [31:0] dmac_haddr;
    wire [1:0]  dmac_htrans;
    wire        dmac_hwrite;
    wire [2:0]  dmac_hsize;
    wire [31:0] dmac_hwdata;
    wire        dmac_hbusreq;

    wire [31:0] dmac_src;
    wire [31:0] dmac_dst;
    wire [31:0] dmac_len;
    wire        dmac_start;
    wire        dmac_busy;
    wire        dmac_done;

    dmac_ahb_master u_dmac (
        .HCLK       (clk),
        .HRESETn    (rst_n),
        .dmac_src   (dmac_src),
        .dmac_dst   (dmac_dst),
        .dmac_len   (dmac_len),
        .dmac_start (dmac_start),
        .dmac_busy  (dmac_busy),
        .dmac_done  (dmac_done),
        .HGRANT     (hgrant[1]),
        .HREADY     (hready),
        .HRDATA     (hrdata),
        .HBUSREQ    (dmac_hbusreq),
        .HADDR      (dmac_haddr),
        .HTRANS     (dmac_htrans),
        .HWRITE     (dmac_hwrite),
        .HSIZE      (dmac_hsize),
        .HWDATA     (dmac_hwdata)
    );

    ahb_arbiter u_arbiter (
        .HCLK         (clk),
        .HRESETn      (rst_n),
        .HBUSREQ      ({dmac_hbusreq, cpu_hbusreq}),
        .HREADY       (hready),
        .HMASTER      (hmaster),
        .HMASTER_DATA (hmaster_data),
        .HGRANT       (hgrant)
    );

    ahb_bus_mux u_bus_mux (
        .HMASTER      (hmaster),
        .HMASTER_DATA (hmaster_data),
        .HADDR_CPU    (cpu_haddr),
        .HTRANS_CPU   (cpu_htrans),
        .HWRITE_CPU   (cpu_hwrite),
        .HSIZE_CPU    (cpu_hsize),
        .HWDATA_CPU   (cpu_hwdata),
        .HADDR_DMAC   (dmac_haddr),
        .HTRANS_DMAC  (dmac_htrans),
        .HWRITE_DMAC  (dmac_hwrite),
        .HSIZE_DMAC   (dmac_hsize),
        .HWDATA_DMAC  (dmac_hwdata),
        .HADDR        (haddr),
        .HTRANS       (htrans),
        .HWRITE       (hwrite),
        .HSIZE        (hsize),
        .HWDATA       (hwdata)
    );

    wire        hsel_rom;
    wire        hsel_ram;
    wire        hsel_apb;
    wire [31:0] hrdata_rom;
    wire [31:0] hrdata_ram;
    wire [31:0] hrdata_apb;
    wire        hreadyout_rom;
    wire        hreadyout_ram;
    wire        hreadyout_apb;

    ahb_decoder u_decoder (
        .HCLK          (clk),
        .HRESETn       (rst_n),
        .HADDR         (haddr),
        .HSEL_ROM      (hsel_rom),
        .HSEL_RAM      (hsel_ram),
        .HSEL_APB      (hsel_apb),
        .HRDATA_ROM    (hrdata_rom),
        .HRDATA_RAM    (hrdata_ram),
        .HRDATA_APB    (hrdata_apb),
        .HREADYOUT_ROM (hreadyout_rom),
        .HREADYOUT_RAM (hreadyout_ram),
        .HREADYOUT_APB (hreadyout_apb),
        .HRDATA        (hrdata),
        .HREADY        (hready)
    );

    // =====================================================================
    // Memories
    // =====================================================================
    rom_ahb u_rom (
        .HCLK        (clk),
        .HRESETn     (rst_n),
        .fetch_lo_index (index_fetch[28:15]),
        .fetch_hi_index (index_fetch[14:1]),
        .fetch_odd      (index_fetch[0]),
        .fetch_window   (fetch_window),
        .HSEL        (hsel_rom),
        .HADDR       (haddr),
        .HTRANS      (htrans),
        .HWRITE      (hwrite),
        .HSIZE       (hsize),
        .HWDATA      (hwdata),
        .HREADY      (hready),
        .HRDATA      (hrdata_rom),
        .HREADYOUT   (hreadyout_rom),
        .HRESP       ()
    );

    ram_ahb u_ram (
        .HCLK      (clk),
        .HRESETn   (rst_n),
        .HSEL      (hsel_ram),
        .HADDR     (haddr),
        .HTRANS    (htrans),
        .HWRITE    (hwrite),
        .HSIZE     (hsize),
        .HWDATA    (hwdata),
        .HREADY    (hready),
        .HRDATA    (hrdata_ram),
        .HREADYOUT (hreadyout_ram),
        .HRESP     ()
    );

    // =====================================================================
    // APB peripherals
    // =====================================================================
    wire [31:0] paddr;
    wire        pwrite;
    wire [31:0] pwdata;
    wire        penable;
    wire        psel_uart;
    wire        psel_gpio;
    wire        psel_dmac;
    wire [31:0] prdata_uart;
    wire [31:0] prdata_gpio;
    wire [31:0] prdata_dmac;
    wire        pready_uart;
    wire        pready_gpio;
    wire        pready_dmac;

    ahb_apb_bridge u_bridge (
        .HCLK        (clk),
        .HRESETn     (rst_n),
        .HSEL        (hsel_apb),
        .HADDR       (haddr),
        .HTRANS      (htrans),
        .HWRITE      (hwrite),
        .HSIZE       (hsize),
        .HWDATA      (hwdata),
        .HREADY      (hready),
        .HRDATA      (hrdata_apb),
        .HREADYOUT   (hreadyout_apb),
        .HRESP       (),
        .PADDR       (paddr),
        .PWRITE      (pwrite),
        .PWDATA      (pwdata),
        .PENABLE     (penable),
        .PSEL_UART   (psel_uart),
        .PSEL_GPIO   (psel_gpio),
        .PSEL_DMAC   (psel_dmac),
        .PRDATA_UART (prdata_uart),
        .PRDATA_GPIO (prdata_gpio),
        .PRDATA_DMAC (prdata_dmac),
        .PREADY_UART (pready_uart),
        .PREADY_GPIO (pready_gpio),
        .PREADY_DMAC (pready_dmac)
    );

    uart_apb #(.DIVIDER(UART_DIVIDER)) u_uart (
        .PCLK    (clk),
        .PRESETn (rst_n),
        .PSEL    (psel_uart),
        .PENABLE (penable),
        .PWRITE  (pwrite),
        .PADDR   (paddr),
        .PWDATA  (pwdata),
        .PRDATA  (prdata_uart),
        .PREADY  (pready_uart),
        .PSLVERR (),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx),
        .irq     (uart_irq)
    );

    gpio_apb u_gpio (
        .PCLK     (clk),
        .PRESETn  (rst_n),
        .PSEL     (psel_gpio),
        .PENABLE  (penable),
        .PWRITE   (pwrite),
        .PADDR    (paddr),
        .PWDATA   (pwdata),
        .PRDATA   (prdata_gpio),
        .PREADY   (pready_gpio),
        .PSLVERR  (),
        .gpio_out (gpio_out),
        .gpio_in  (gpio_in)
    );

    dmac_apb_regs u_dmac_regs (
        .PCLK       (clk),
        .PRESETn    (rst_n),
        .PSEL       (psel_dmac),
        .PENABLE    (penable),
        .PWRITE     (pwrite),
        .PADDR      (paddr),
        .PWDATA     (pwdata),
        .PRDATA     (prdata_dmac),
        .PREADY     (pready_dmac),
        .PSLVERR    (),
        .dmac_src   (dmac_src),
        .dmac_dst   (dmac_dst),
        .dmac_len   (dmac_len),
        .dmac_start (dmac_start),
        .dmac_busy  (dmac_busy),
        .dmac_done  (dmac_done),
        .irq        (dmac_irq)
    );

endmodule
