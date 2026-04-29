// EX/MEM pipeline register: flush clears in-flight branch shadow; gate tied to same freeze as ID/EX.
module ex_mem_reg (
    input         clk_i,
    input         rst_n_i,
    input         flush_i, // Taken branch: kill speculated op entering MEM
    input         gate_i,  // 0 = hold MEM inputs (DIV busy)
    // EX result this cycle: address for LSU; rd/jump/branch info
    input  [31:0] alu_res_x_in,
    input  [31:0] rs2_store_x_in,
    input  [4:0]  rd_adr_x_in,
    input  [31:0] pc_plus4_x_in,
    input  [6:0]  opc7_x_in,
    input  [31:0] jmp_pc_x_in,
    input         br_taken_x_in,
    input         mem_rd_x_in,
    input         mem_we_x_in,
    input         wb_from_ld_x_in,
    input         rf_we_x_in,
    input  [2:0]  funct3_x_in,
    input         br_jmp_x_in,
    input  [31:0] csr_wdata_x_in,
    input  [11:0] csr_adr_x_in,
    input         csr_we_x_in,
    input  [1:0]  csr_op_x_in,
    input         trap_ecall_x_in,
    input         trap_ebreak_x_in,
    input         trap_mret_x_in,
    // MEM-stage view (what memory and branch resolution see)
    output reg [31:0] alu_res_m_out,
    output reg [31:0] rs2_store_m_out,
    output reg [4:0]  rd_adr_m_out,
    output reg [31:0] pc_plus4_m_out,
    output reg [6:0]  opc7_m_out,
    output reg [31:0] jmp_pc_m_out,
    output reg        br_taken_m_out,
    output reg        mem_rd_m_out,
    output reg        mem_we_m_out,
    output reg        wb_from_ld_m_out,
    output reg        rf_we_m_out,
    output reg [2:0]  funct3_m_out,
    output reg        br_jmp_m_out,
    output reg [31:0] csr_wdata_m_out,
    output reg [11:0] csr_adr_m_out,
    output reg        csr_we_m_out,
    output reg [1:0]  csr_op_m_out,
    output reg        trap_ecall_m_out,
    output reg        trap_ebreak_m_out,
    output reg        trap_mret_m_out
);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            alu_res_m_out     <= 32'b0;
            rs2_store_m_out   <= 32'b0;
            rd_adr_m_out      <= 5'b0;
            pc_plus4_m_out    <= 32'b0;
            opc7_m_out        <= 7'b0;
            jmp_pc_m_out      <= 32'b0;
            br_taken_m_out    <= 1'b0;
            mem_rd_m_out      <= 1'b0;
            mem_we_m_out      <= 1'b0;
            wb_from_ld_m_out  <= 1'b0;
            rf_we_m_out       <= 1'b0;
            funct3_m_out      <= 3'b0;
            br_jmp_m_out      <= 1'b0;
            csr_wdata_m_out   <= 32'b0;
            csr_adr_m_out     <= 12'b0;
            csr_we_m_out      <= 1'b0;
            csr_op_m_out      <= 2'b0;
            trap_ecall_m_out  <= 1'b0;
            trap_ebreak_m_out <= 1'b0;
            trap_mret_m_out   <= 1'b0;
        end else if (flush_i) begin
            alu_res_m_out     <= 32'b0;
            rs2_store_m_out   <= 32'b0;
            rd_adr_m_out      <= 5'b0;
            pc_plus4_m_out    <= 32'b0;
            opc7_m_out        <= 7'b0;
            jmp_pc_m_out      <= 32'b0;
            br_taken_m_out    <= 1'b0;
            mem_rd_m_out      <= 1'b0;
            mem_we_m_out      <= 1'b0;
            wb_from_ld_m_out  <= 1'b0;
            rf_we_m_out       <= 1'b0;
            funct3_m_out      <= 3'b0;
            br_jmp_m_out      <= 1'b0;
            csr_wdata_m_out   <= 32'b0;
            csr_adr_m_out     <= 12'b0;
            csr_we_m_out      <= 1'b0;
            csr_op_m_out      <= 2'b0;
            trap_ecall_m_out  <= 1'b0;
            trap_ebreak_m_out <= 1'b0;
            trap_mret_m_out   <= 1'b0;
        end else if (gate_i) begin
            alu_res_m_out     <= alu_res_x_in;
            rs2_store_m_out   <= rs2_store_x_in;
            rd_adr_m_out      <= rd_adr_x_in;
            pc_plus4_m_out    <= pc_plus4_x_in;
            opc7_m_out        <= opc7_x_in;
            jmp_pc_m_out      <= jmp_pc_x_in;
            br_taken_m_out    <= br_taken_x_in;
            mem_rd_m_out      <= mem_rd_x_in;
            mem_we_m_out      <= mem_we_x_in;
            wb_from_ld_m_out  <= wb_from_ld_x_in;
            rf_we_m_out       <= rf_we_x_in;
            funct3_m_out      <= funct3_x_in;
            br_jmp_m_out      <= br_jmp_x_in;
            csr_wdata_m_out   <= csr_wdata_x_in;
            csr_adr_m_out     <= csr_adr_x_in;
            csr_we_m_out      <= csr_we_x_in;
            csr_op_m_out      <= csr_op_x_in;
            trap_ecall_m_out  <= trap_ecall_x_in;
            trap_ebreak_m_out <= trap_ebreak_x_in;
            trap_mret_m_out   <= trap_mret_x_in;
        end
    end
endmodule
