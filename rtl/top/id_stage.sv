import pipeline_pkg::*;

// Decode one instruction: split fields, immediates, regfile read, main decode -> dec_bus for ID/EX.
module id_stage (
    input  logic         clk_i,
    input  logic [31:0]  instr_d_i,   // From IF/ID
    input  logic [31:0]  pc_d_i,      // Architectural PC in ID (AUIPC ALU-A operand)
    input  logic [4:0]   rd_adr_w_i,  // WB destination
    input  logic [31:0]  rf_wdata_w_i,
    input  logic         rf_we_w_i,
    output dec_bus_t     dec_bus_o
);
    wire [6:0] opc7_w;
    wire [4:0] rd_idx_w;
    wire [2:0] funct3_w;
    wire [4:0] rs1_idx_w;
    wire [4:0] rs2_idx_w;
    wire [6:0] funct7_w;

    instr_parser u_parse (
        .instruction(instr_d_i),
        .opcode     (opc7_w),
        .rd         (rd_idx_w),
        .funct3     (funct3_w),
        .rs1        (rs1_idx_w),
        .rs2        (rs2_idx_w),
        .funct7     (funct7_w)
    );

    wire [31:0] imm32_w;
    imm_gen u_imm (
        .instruction(instr_d_i),
        .opcode     (opc7_w),
        .imm        (imm32_w)
    );

    wire [31:0] rs1_rdata_w;
    wire [31:0] rs2_rdata_w;
    registers u_rf (
        .clk      (clk_i),
        .rs1_addr (rs1_idx_w),
        .rs2_addr (rs2_idx_w),
        .rd_addr  (rd_adr_w_i),
        .rd_data  (rf_wdata_w_i),
        .reg_write(rf_we_w_i),
        .rs1_data (rs1_rdata_w),
        .rs2_data (rs2_rdata_w)
    );

    wire br_jmp_c, mem_rd_c, wb_ld_c, mem_we_c, alu_imm_c, rf_we_c;
    wire [1:0] csr_op_c;
    wire [1:0] alu_opc2_c;
    wire csr_we_c, trap_ecall_c, trap_ebreak_c, trap_mret_c;

    main_control_unit u_ctrl (
        .opcode   (opc7_w),
        .funct3   (funct3_w),
        .funct7   (funct7_w),
        .rs2_addr (rs2_idx_w),
        .Branch   (br_jmp_c),
        .MemRead  (mem_rd_c),
        .MemToReg (wb_ld_c),
        .ALUOp    (alu_opc2_c),
        .MemWrite (mem_we_c),
        .ALUSrc   (alu_imm_c),
        .RegWrite (rf_we_c),
        .CSRWrite (csr_we_c),
        .CSROp    (csr_op_c),
        .IsECALL  (trap_ecall_c),
        .IsEBREAK (trap_ebreak_c),
        .IsMRET   (trap_mret_c)
    );

    wire [4:0] alu_ctl_w;
    alu_decoder u_alu_dec (
        .opcode    (opc7_w),
        .ALUOp     (alu_opc2_c),
        .funct3    (funct3_w),
        .funct7    (funct7_w),
        .ALUControl(alu_ctl_w)
    );

    assign dec_bus_o.opc7           = opc7_w;
    assign dec_bus_o.rd_idx         = rd_idx_w;
    assign dec_bus_o.funct3         = funct3_w;
    assign dec_bus_o.rs1_idx        = rs1_idx_w;
    assign dec_bus_o.rs2_idx        = rs2_idx_w;
    assign dec_bus_o.funct7         = funct7_w;
    assign dec_bus_o.imm32          = imm32_w;
    assign dec_bus_o.rs1_rdata      = rs1_rdata_w;
    assign dec_bus_o.rs2_rdata      = rs2_rdata_w;
    assign dec_bus_o.alu_a_use_id   = (opc7_w == 7'b0110111) || (opc7_w == 7'b0010111);
    assign dec_bus_o.alu_a_id       = (opc7_w == 7'b0010111) ? pc_d_i : 32'b0;
    assign dec_bus_o.alu_ctrl5      = alu_ctl_w;
    assign dec_bus_o.alu_use_imm    = alu_imm_c;
    assign dec_bus_o.ctl_br_jmp     = br_jmp_c;
    assign dec_bus_o.ctl_mem_rd     = mem_rd_c;
    assign dec_bus_o.ctl_mem_we     = mem_we_c;
    assign dec_bus_o.ctl_wb_from_ld = wb_ld_c;
    assign dec_bus_o.ctl_rf_we      = rf_we_c;
    assign dec_bus_o.csr_adr12      = instr_d_i[31:20];
    assign dec_bus_o.csr_we         = csr_we_c;
    assign dec_bus_o.csr_op2        = csr_op_c;
    assign dec_bus_o.trap_ecall     = trap_ecall_c;
    assign dec_bus_o.trap_ebreak    = trap_ebreak_c;
    assign dec_bus_o.trap_mret      = trap_mret_c;
endmodule
