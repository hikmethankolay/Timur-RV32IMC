import pipeline_pkg::*;

module rv32imc_core (
    input  clk_i,
    input  rst_n_i,
    output [31:0] pc_dbg_o,  // Live fetch PC (for debug); instr PC in ID is pc_d_w

    // I-fetch AHB master (→ ROM Port A, dedicated bus)
    output [31:0] HADDR_if_o,
    output [1:0]  HTRANS_if_o,
    output        HWRITE_if_o,
    output [2:0]  HSIZE_if_o,
    output [31:0] HWDATA_if_o,
    input  [31:0] HRDATA_if_i,
    input         HREADY_if_i,

    // D-access AHB master (→ shared data bus, arbitrated with DMAC)
    output [31:0] HADDR_dm_o,
    output [1:0]  HTRANS_dm_o,
    output        HWRITE_dm_o,
    output [2:0]  HSIZE_dm_o,
    output [31:0] HWDATA_dm_o,
    input  [31:0] HRDATA_dm_i,
    input         HREADY_dm_i,
    output        HBUSREQ_dm_o
);
    // --- Fetch (IF) ---
    wire [31:0] instr_f_w, pc_fetch_w, pc_tag_f_w;
    wire        flush_fd_w, rom_rdy_w; // flush: branch + shadow ROM cycle; rom_rdy: AHB ready

    // --- Decode (ID): after IF/ID register ---
    wire [31:0] pc_d_w, instr_d_w;
    dec_bus_t   dec_bus_w;
    wire [31:0] pc_plus4_d_w, btarget_pc_d_w; // pc+4 and pc+imm for branches/jal (ID adders)

    // --- After ID/EX register (EX stage inputs) ---
    wire [31:0] pc_x_w, pc_plus4_idex_w, btarget_pc_x_w;
    wire [31:0] rs1_val_x_w, rs2_val_x_w, imm32_x_w;
    wire [4:0]  rs1_adr_x_w, rs2_adr_x_w, rd_adr_x_w;
    wire [6:0]  opc7_x_w;
    wire [4:0]  alu_ctl_x_w;
    wire        alu_a_use_id_x_w;
    wire [31:0] alu_a_id_x_w;
    wire        alu_imm_b_x_w, br_jmp_x_w;
    wire        mem_rd_x_w, mem_we_x_w, wb_ld_x_w, rf_we_x_w;
    wire [2:0]  funct3_x_w;
    wire        csr_we_x_w;
    wire [1:0]  csr_op_x_w;
    wire [11:0] csr_adr_x_w;
    wire        trap_ecall_x_w, trap_ebreak_x_w, trap_mret_x_w;

    wire [31:0] alu_res_x_w, pc_plus4_x_w, jmp_pc_x_w;
    wire [31:0] rs2_fwd_x_w; // forwarded rs2 → SW store-data path
    wire        br_taken_x_w;
    wire [1:0]  fwd_rs1_sel_w, fwd_rs2_sel_w; // 00 RF, 01 WB bus, 10 EX/MEM ALU (see forwarding_unit)

    // --- After EX/MEM register (MEM stage inputs) ---
    wire [31:0] alu_res_m_w, rs2_store_m_w, pc_plus4_m_w, jmp_pc_m_w;
    wire [4:0]  rd_adr_m_w;
    wire [6:0]  opc7_m_w;
    wire        br_taken_m_w, mem_rd_m_w, mem_we_m_w, wb_ld_m_w, rf_we_m_w;
    wire [2:0]  funct3_m_w;
    wire        br_jmp_m_w;
    wire [31:0] csr_wdata_m_w;
    wire [11:0] csr_adr_m_w;
    wire        csr_we_m_w;
    wire [1:0]  csr_op_m_w;
    wire        trap_ecall_m_w, trap_ebreak_m_w, trap_mret_m_w;

    wire [31:0] ld_data_raw_w; // Load data from MEM formatters; aligns in time with MEM/WB controls

    // --- After MEM/WB register (WB stage inputs) ---
    wire [31:0] alu_res_w_w, pc_plus4_w_w;
    wire [4:0]  rd_adr_w_w;
    wire [6:0]  opc7_w_w;
    wire        wb_ld_w_w, rf_we_w_w;
    wire [31:0] csr_rdata_w_w;
    wire        csr_to_rf_w_w;

    wire [31:0] rf_wdata_w_w; // Data written to rd in register file (from WB)

    // --- Hazard / global stalls ---
    wire        ram_rdy_w, stall_all_w, stall_bubble_w, stall_freeze_ex_w;
    wire        div_busy_w, mul_busy_w;
    wire        mem_rdy_w = rom_rdy_w & ram_rdy_w;     // Both slaves ready → fetch can retire
    wire        br_exec_w   = br_jmp_m_w & br_taken_m_w; // Redirect when branch/jump “taken” resolved in MEM

    // Instruction ROM + PC; branch redirect from MEM-stage resolution.
    if_stage u_fetch (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .fetch_run_i     (~stall_all_w),
        .br_taken_i      (br_exec_w),
        .jmp_pc_i        (jmp_pc_m_w),
        .instr_f_o       (instr_f_w),
        .pc_fetch_o      (pc_fetch_w),
        .pc_tag_delay_o  (pc_tag_f_w),
        .rom_ready_o     (rom_rdy_w),
        .flush_if_id_o   (flush_fd_w),
        .HADDR_o         (HADDR_if_o),
        .HTRANS_o        (HTRANS_if_o),
        .HWRITE_o        (HWRITE_if_o),
        .HSIZE_o         (HSIZE_if_o),
        .HWDATA_o        (HWDATA_if_o),
        .HRDATA_i        (HRDATA_if_i),
        .HREADY_i        (HREADY_if_i)
    );

    // Latch instruction + PC tag into ID; hold on stall; NOP on flush (wrong path).
    if_id_reg u_fd (
        .clk_i    (clk_i),
        .rst_n_i  (rst_n_i),
        .gate_i   (~stall_all_w),
        .flush_i  (flush_fd_w),
        .pc_in    (pc_tag_f_w),
        .instr_in (instr_f_w),
        .pc_out   (pc_d_w),
        .instr_out(instr_d_w)
    );

    // Decode instruction word; writeback ports close the regfile timing loop from WB.
    id_stage u_dec (
        .clk_i       (clk_i),
        .instr_d_i   (instr_d_w),
        .pc_d_i      (pc_d_w),
        .rd_adr_w_i  (rd_adr_w_w),
        .rf_wdata_w_i(rf_wdata_w_w),
        .rf_we_w_i   (rf_we_w_w),
        .dec_bus_o   (dec_bus_w)
    );

    adder_32bit u_pc4 ( // Link / sequential PC+4 for current instr in ID
        .a       (pc_d_w),
        .b       (32'h4),
        .sub     (1'b0),
        .result  (pc_plus4_d_w),
        .cout    (),
        .overflow()
    );

    adder_32bit u_btarget ( // PC-relative target: PC + imm for B and JAL
        .a       (pc_d_w),
        .b       (dec_bus_w.imm32),
        .sub     (1'b0),
        .result  (btarget_pc_d_w),
        .cout    (),
        .overflow()
    );

    // Slip bubble into EX on load-use or bus wait; hold during DIV; flush on taken branch.
    id_ex_reg u_dx (
        .clk_i             (clk_i),
        .rst_n_i           (rst_n_i),
        .gate_i            (~stall_freeze_ex_w),
        .flush_i           (br_exec_w | stall_bubble_w),
        .pc_d_in           (pc_d_w),
        .pc_plus4_d_in     (pc_plus4_d_w),
        .btarget_pc_d_in   (btarget_pc_d_w),
        .rs1_val_d_in      (dec_bus_w.rs1_rdata),
        .rs2_val_d_in      (dec_bus_w.rs2_rdata),
        .imm32_d_in        (dec_bus_w.imm32),
        .rs1_adr_d_in      (dec_bus_w.rs1_idx),
        .rs2_adr_d_in      (dec_bus_w.rs2_idx),
        .rd_adr_d_in       (dec_bus_w.rd_idx),
        .opc7_d_in         (dec_bus_w.opc7),
        .alu_ctl_d_in      (dec_bus_w.alu_ctrl5),
        .alu_a_use_id_d_in (dec_bus_w.alu_a_use_id),
        .alu_a_id_d_in     (dec_bus_w.alu_a_id),
        .alu_imm_b_d_in    (dec_bus_w.alu_use_imm),
        .br_jmp_d_in       (dec_bus_w.ctl_br_jmp),
        .mem_rd_d_in       (dec_bus_w.ctl_mem_rd),
        .mem_we_d_in       (dec_bus_w.ctl_mem_we),
        .wb_from_ld_d_in   (dec_bus_w.ctl_wb_from_ld),
        .rf_we_d_in        (dec_bus_w.ctl_rf_we),
        .funct3_d_in       (dec_bus_w.funct3),
        .csr_we_d_in       (dec_bus_w.csr_we),
        .csr_op_d_in       (dec_bus_w.csr_op2),
        .csr_adr_d_in      (dec_bus_w.csr_adr12),
        .trap_ecall_d_in   (dec_bus_w.trap_ecall),
        .trap_ebreak_d_in  (dec_bus_w.trap_ebreak),
        .trap_mret_d_in    (dec_bus_w.trap_mret),
        .pc_x_out          (pc_x_w),
        .pc_plus4_x_out    (pc_plus4_idex_w),
        .btarget_pc_x_out  (btarget_pc_x_w),
        .rs1_val_x_out     (rs1_val_x_w),
        .rs2_val_x_out     (rs2_val_x_w),
        .imm32_x_out       (imm32_x_w),
        .rs1_adr_x_out     (rs1_adr_x_w),
        .rs2_adr_x_out     (rs2_adr_x_w),
        .rd_adr_x_out      (rd_adr_x_w),
        .opc7_x_out         (opc7_x_w),
        .alu_ctl_x_out      (alu_ctl_x_w),
        .alu_a_use_id_x_out(alu_a_use_id_x_w),
        .alu_a_id_x_out     (alu_a_id_x_w),
        .alu_imm_b_x_out    (alu_imm_b_x_w),
        .br_jmp_x_out      (br_jmp_x_w),
        .mem_rd_x_out      (mem_rd_x_w),
        .mem_we_x_out      (mem_we_x_w),
        .wb_from_ld_x_out  (wb_ld_x_w),
        .rf_we_x_out       (rf_we_x_w),
        .funct3_x_out      (funct3_x_w),
        .csr_we_x_out      (csr_we_x_w),
        .csr_op_x_out      (csr_op_x_w),
        .csr_adr_x_out     (csr_adr_x_w),
        .trap_ecall_x_out  (trap_ecall_x_w),
        .trap_ebreak_x_out (trap_ebreak_x_w),
        .trap_mret_x_out   (trap_mret_x_w)
    );

    forwarding_unit u_fwd ( // Resolve RS1/RS2 vs pending writes in M and W stages
        .id_ex_rs1      (rs1_adr_x_w),
        .id_ex_rs2      (rs2_adr_x_w),
        .ex_mem_rd      (rd_adr_m_w),
        .ex_mem_regwrite(rf_we_m_w),
        .mem_wb_rd      (rd_adr_w_w),
        .mem_wb_regwrite(rf_we_w_w),
        .forwardA       (fwd_rs1_sel_w),
        .forwardB       (fwd_rs2_sel_w)
    );

    hazard_detection_unit u_hdu ( // Load-use, AHB wait, mul/div multicycle
        .id_ex_memread(mem_rd_x_w),
        .id_ex_rd     (rd_adr_x_w),
        .if_id_rs1    (instr_d_w[19:15]),
        .if_id_rs2    (instr_d_w[24:20]),
        .hready       (mem_rdy_w),
        .div_busy     (div_busy_w),
        .mul_busy     (mul_busy_w),
        .stall        (stall_all_w),
        .bubble_stall (stall_bubble_w),
        .freeze_stall (stall_freeze_ex_w)
    );

    // ALU, compare, JAL/JALR target; forwarding muxes before ALU.
    ex_stage u_exec (
        .clk_i            (clk_i),
        .rst_n_i          (rst_n_i),
        .rs1_val_x_i      (rs1_val_x_w),
        .rs2_val_x_i      (rs2_val_x_w),
        .imm32_x_i         (imm32_x_w),
        .alu_a_use_id_x_i  (alu_a_use_id_x_w),
        .alu_a_id_x_i      (alu_a_id_x_w),
        .pc_plus4_x_i      (pc_plus4_idex_w),
        .btarget_pc_x_i   (btarget_pc_x_w),
        .opc7_x_i         (opc7_x_w),
        .funct3_x_i       (funct3_x_w),
        .alu_ctl_x_i      (alu_ctl_x_w),
        .alu_imm_b_x_i    (alu_imm_b_x_w),
        .fwd_rs1_sel_i    (fwd_rs1_sel_w),
        .fwd_rs2_sel_i    (fwd_rs2_sel_w),
        .alu_res_m_fwd_i  (alu_res_m_w),
        .rf_wdata_w_fwd_i (rf_wdata_w_w),
        .alu_res_x_o      (alu_res_x_w),
        .rs2_fwd_x_o      (rs2_fwd_x_w),
        .pc_plus4_x_o     (pc_plus4_x_w),
        .jmp_pc_x_o       (jmp_pc_x_w),
        .br_taken_x_o     (br_taken_x_w),
        .div_busy_o       (div_busy_w),
        .mul_busy_o       (mul_busy_w)
    );

    // Kill EX shadow on taken branch; freeze with backend on DIV busy.
    ex_mem_reg u_xm (
        .clk_i            (clk_i),
        .rst_n_i          (rst_n_i),
        .flush_i          (br_exec_w),
        .gate_i           (~stall_freeze_ex_w),
        .alu_res_x_in     (alu_res_x_w),
        .rs2_store_x_in   (rs2_fwd_x_w),
        .rd_adr_x_in      (rd_adr_x_w),
        .pc_plus4_x_in    (pc_plus4_x_w),
        .opc7_x_in        (opc7_x_w),
        .jmp_pc_x_in      (jmp_pc_x_w),
        .br_taken_x_in    (br_taken_x_w),
        .mem_rd_x_in      (mem_rd_x_w),
        .mem_we_x_in      (mem_we_x_w),
        .wb_from_ld_x_in (wb_ld_x_w),
        .rf_we_x_in       (rf_we_x_w),
        .funct3_x_in      (funct3_x_w),
        .br_jmp_x_in      (br_jmp_x_w),
        .csr_wdata_x_in   (rs1_val_x_w),
        .csr_adr_x_in     (csr_adr_x_w),
        .csr_we_x_in      (csr_we_x_w),
        .csr_op_x_in      (csr_op_x_w),
        .trap_ecall_x_in  (trap_ecall_x_w),
        .trap_ebreak_x_in (trap_ebreak_x_w),
        .trap_mret_x_in   (trap_mret_x_w),
        .alu_res_m_out    (alu_res_m_w),
        .rs2_store_m_out  (rs2_store_m_w),
        .rd_adr_m_out     (rd_adr_m_w),
        .pc_plus4_m_out   (pc_plus4_m_w),
        .opc7_m_out       (opc7_m_w),
        .jmp_pc_m_out     (jmp_pc_m_w),
        .br_taken_m_out   (br_taken_m_w),
        .mem_rd_m_out     (mem_rd_m_w),
        .mem_we_m_out     (mem_we_m_w),
        .wb_from_ld_m_out (wb_ld_m_w),
        .rf_we_m_out      (rf_we_m_w),
        .funct3_m_out     (funct3_m_w),
        .br_jmp_m_out     (br_jmp_m_w),
        .csr_wdata_m_out  (csr_wdata_m_w),
        .csr_adr_m_out    (csr_adr_m_w),
        .csr_we_m_out     (csr_we_m_w),
        .csr_op_m_out     (csr_op_m_w),
        .trap_ecall_m_out (trap_ecall_m_w),
        .trap_ebreak_m_out(trap_ebreak_m_w),
        .trap_mret_m_out  (trap_mret_m_w)
    );

    mem_stage u_mem ( // Data bus @ 0x2000_xxxx (RAM) / 0x4000_xxxx (APB); addr = EX/MEM ALU result
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .addr_m_i      (alu_res_m_w),
        .rs2_store_m_i (rs2_store_m_w),
        .mem_rd_m_i    (mem_rd_m_w),
        .mem_we_m_i    (mem_we_m_w),
        .funct3_m_i    (funct3_m_w),
        .ld_data_wb_o  (ld_data_raw_w),
        .ram_ready_o   (ram_rdy_w),
        .HADDR_o       (HADDR_dm_o),
        .HTRANS_o      (HTRANS_dm_o),
        .HWRITE_o      (HWRITE_dm_o),
        .HSIZE_o       (HSIZE_dm_o),
        .HWDATA_o      (HWDATA_dm_o),
        .HRDATA_i      (HRDATA_dm_i),
        .HREADY_i      (HREADY_dm_i)
    );

    // CSR read path tied off for now; load value meets WB mux off this register’s clock edge.
    mem_wb_reg u_mw (
        .clk_i             (clk_i),
        .rst_n_i           (rst_n_i),
        .flush_i           (1'b0),
        .gate_i            (~stall_freeze_ex_w),
        .alu_res_m_in      (alu_res_m_w),
        .rd_adr_m_in       (rd_adr_m_w),
        .pc_plus4_m_in     (pc_plus4_m_w),
        .opc7_m_in         (opc7_m_w),
        .wb_from_ld_m_in   (wb_ld_m_w),
        .rf_we_m_in        (rf_we_m_w),
        .csr_rdata_m_in    (32'b0),
        .csr_to_rf_m_in    (1'b0),
        .alu_res_w_out     (alu_res_w_w),
        .rd_adr_w_out      (rd_adr_w_w),
        .pc_plus4_w_out    (pc_plus4_w_w),
        .opc7_w_out        (opc7_w_w),
        .wb_from_ld_w_out  (wb_ld_w_w),
        .rf_we_w_out       (rf_we_w_w),
        .csr_rdata_w_out   (csr_rdata_w_w),
        .csr_to_rf_w_out   (csr_to_rf_w_w)
    );

    wb_stage u_wb ( // rd <= ALU/logical result or sign-extended load
        .alu_res_w_i    (alu_res_w_w),
        .ld_data_w_i    (ld_data_raw_w),
        .wb_from_ld_w_i (wb_ld_w_w),
        .rf_wdata_w_o   (rf_wdata_w_w)
    );

    assign pc_dbg_o      = pc_fetch_w;
    assign HBUSREQ_dm_o  = mem_rd_m_w | mem_we_m_w;
endmodule