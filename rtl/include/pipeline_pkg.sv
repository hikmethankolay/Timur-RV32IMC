// pipeline_pkg: shared packed struct produced by ID and consumed by ID/EX wiring in datapath.
package pipeline_pkg;

    typedef struct packed {
        // Instruction fields from parser
        logic [6:0]  opc7;
        logic [4:0]  rd_idx;
        logic [2:0]  funct3;
        logic [4:0]  rs1_idx;
        logic [4:0]  rs2_idx;
        logic [6:0]  funct7;
        logic [31:0] imm32;
        logic [31:0] rs1_rdata;
        logic [31:0] rs2_rdata;
        // EX datapath control
        logic [4:0]  alu_ctrl5;     // ALU op select
        logic        alu_a_use_id;  // 1: ALU A from alu_a_id (LUI/AUIPC); 0: forwarded rs1 in EX
        logic [31:0] alu_a_id;      // LUI→0, AUIPC→PC @ ID (latches with same instr as pc_d)
        logic        alu_use_imm;   // 1: ALU port B from imm, 0: from rs2
        logic        ctl_br_jmp;   // Branch/jal/jalr (uses MEM redirect path)
        logic        ctl_mem_rd;   // Load
        logic        ctl_mem_we;   // Store
        logic        ctl_wb_from_ld; // WB mux selects load data vs ALU
        logic        ctl_rf_we;      // Register file write at WB
        // CSR / traps (reserved for privileged flow)
        logic [11:0] csr_adr12;
        logic        csr_we;
        logic [1:0]  csr_op2;
        logic        trap_ecall;
        logic        trap_ebreak;
        logic        trap_mret;
    } dec_bus_t;

endpackage
