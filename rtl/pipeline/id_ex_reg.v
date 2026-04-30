// ID/EX pipeline register: gate freezes latch during DIV backend stall; flush on branch or ID bubble.
module id_ex_reg (
    input         clk_i,
    input         rst_n_i,
    input         gate_i,   // 0 = hold EX operands (freeze with multicycle op)
    input         flush_i,  // 1 = inject bubble into EX (NOP control)
    // Operand + PC bundle from decode / ID adders
    input  [31:0] pc_d_in,
    input  [31:0] pc_plus4_d_in,
    input  [31:0] btarget_pc_d_in,
    input  [31:0] rs1_val_d_in,
    input  [31:0] rs2_val_d_in,
    input  [31:0] imm32_d_in,
    input  [4:0]  rs1_adr_d_in,
    input  [4:0]  rs2_adr_d_in,
    input  [4:0]  rd_adr_d_in,
    input  [6:0]  opc7_d_in,
    input  [4:0]  alu_ctl_d_in,
    input         alu_a_use_id_d_in,
    input  [31:0] alu_a_id_d_in,
    input         alu_imm_b_d_in,
    input         br_jmp_d_in,
    input         mem_rd_d_in,
    input         mem_we_d_in,
    input         wb_from_ld_d_in,
    input         rf_we_d_in,
    input  [2:0]  funct3_d_in,
    input         csr_we_d_in,
    input  [1:0]  csr_op_d_in,
    input  [11:0] csr_adr_d_in,
    input         trap_ecall_d_in,
    input         trap_ebreak_d_in,
    input         trap_mret_d_in,
    // Latched EX-stage view (suffix _x = enters execute this cycle when gate=1)
    output reg [31:0] pc_x_out,
    output reg [31:0] pc_plus4_x_out,
    output reg [31:0] btarget_pc_x_out,
    output reg [31:0] rs1_val_x_out,
    output reg [31:0] rs2_val_x_out,
    output reg [31:0] imm32_x_out,
    output reg [4:0]  rs1_adr_x_out,
    output reg [4:0]  rs2_adr_x_out,
    output reg [4:0]  rd_adr_x_out,
    output reg [6:0]  opc7_x_out,
    output reg [4:0]  alu_ctl_x_out,
    output reg        alu_a_use_id_x_out,
    output reg [31:0] alu_a_id_x_out,
    output reg        alu_imm_b_x_out,
    output reg        br_jmp_x_out,
    output reg        mem_rd_x_out,
    output reg        mem_we_x_out,
    output reg        wb_from_ld_x_out,
    output reg        rf_we_x_out,
    output reg [2:0]  funct3_x_out,
    output reg        csr_we_x_out,
    output reg [1:0]  csr_op_x_out,
    output reg [11:0] csr_adr_x_out,
    output reg        trap_ecall_x_out,
    output reg        trap_ebreak_x_out,
    output reg        trap_mret_x_out
);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pc_x_out           <= 32'b0;
            pc_plus4_x_out      <= 32'b0;
            btarget_pc_x_out    <= 32'b0;
            rs1_val_x_out       <= 32'b0;
            rs2_val_x_out       <= 32'b0;
            imm32_x_out         <= 32'b0;
            rs1_adr_x_out       <= 5'b0;
            rs2_adr_x_out       <= 5'b0;
            rd_adr_x_out        <= 5'b0;
            opc7_x_out          <= 7'b0;
            alu_ctl_x_out       <= 5'b0;
            alu_a_use_id_x_out  <= 1'b0;
            alu_a_id_x_out      <= 32'b0;
            alu_imm_b_x_out     <= 1'b0;
            br_jmp_x_out        <= 1'b0;
            mem_rd_x_out        <= 1'b0;
            mem_we_x_out        <= 1'b0;
            wb_from_ld_x_out    <= 1'b0;
            rf_we_x_out         <= 1'b0;
            funct3_x_out        <= 3'b0;
            csr_we_x_out        <= 1'b0;
            csr_op_x_out        <= 2'b0;
            csr_adr_x_out       <= 12'b0;
            trap_ecall_x_out    <= 1'b0;
            trap_ebreak_x_out   <= 1'b0;
            trap_mret_x_out     <= 1'b0;
        end else if (flush_i) begin
            pc_x_out           <= 32'b0;
            pc_plus4_x_out      <= 32'b0;
            btarget_pc_x_out    <= 32'b0;
            rs1_val_x_out       <= 32'b0;
            rs2_val_x_out       <= 32'b0;
            imm32_x_out         <= 32'b0;
            rs1_adr_x_out       <= 5'b0;
            rs2_adr_x_out       <= 5'b0;
            rd_adr_x_out        <= 5'b0;
            opc7_x_out          <= 7'b0;
            alu_ctl_x_out       <= 5'b0;
            alu_a_use_id_x_out  <= 1'b0;
            alu_a_id_x_out      <= 32'b0;
            alu_imm_b_x_out     <= 1'b0;
            br_jmp_x_out        <= 1'b0;
            mem_rd_x_out        <= 1'b0;
            mem_we_x_out        <= 1'b0;
            wb_from_ld_x_out    <= 1'b0;
            rf_we_x_out         <= 1'b0;
            funct3_x_out        <= 3'b0;
            csr_we_x_out        <= 1'b0;
            csr_op_x_out        <= 2'b0;
            csr_adr_x_out       <= 12'b0;
            trap_ecall_x_out    <= 1'b0;
            trap_ebreak_x_out   <= 1'b0;
            trap_mret_x_out     <= 1'b0;
        end else if (gate_i) begin
            pc_x_out           <= pc_d_in;
            pc_plus4_x_out      <= pc_plus4_d_in;
            btarget_pc_x_out    <= btarget_pc_d_in;
            rs1_val_x_out       <= rs1_val_d_in;
            rs2_val_x_out       <= rs2_val_d_in;
            imm32_x_out         <= imm32_d_in;
            rs1_adr_x_out       <= rs1_adr_d_in;
            rs2_adr_x_out       <= rs2_adr_d_in;
            rd_adr_x_out        <= rd_adr_d_in;
            opc7_x_out          <= opc7_d_in;
            alu_ctl_x_out       <= alu_ctl_d_in;
            alu_a_use_id_x_out  <= alu_a_use_id_d_in;
            alu_a_id_x_out      <= alu_a_id_d_in;
            alu_imm_b_x_out     <= alu_imm_b_d_in;
            br_jmp_x_out        <= br_jmp_d_in;
            mem_rd_x_out        <= mem_rd_d_in;
            mem_we_x_out        <= mem_we_d_in;
            wb_from_ld_x_out    <= wb_from_ld_d_in;
            rf_we_x_out         <= rf_we_d_in;
            funct3_x_out        <= funct3_d_in;
            csr_we_x_out        <= csr_we_d_in;
            csr_op_x_out        <= csr_op_d_in;
            csr_adr_x_out       <= csr_adr_d_in;
            trap_ecall_x_out    <= trap_ecall_d_in;
            trap_ebreak_x_out   <= trap_ebreak_d_in;
            trap_mret_x_out     <= trap_mret_d_in;
        end
    end
endmodule
