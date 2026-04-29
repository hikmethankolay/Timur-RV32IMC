// MEM/WB register: WB controls + ALU result; load data path comes from mem_stage flops in parallel.
module mem_wb_reg (
    input         clk_i,
    input         rst_n_i,
    input         flush_i, // Unused tied 0 in current datapath
    input         gate_i,  // Freeze with backend stall
    input  [31:0] alu_res_m_in,    // ALU result for non-load WB
    input  [4:0]  rd_adr_m_in,
    input  [31:0] pc_plus4_m_in,   // Saved for JAL-style WB metadata if extended
    input  [6:0]  opc7_m_in,
    input         wb_from_ld_m_in,
    input         rf_we_m_in,
    input  [31:0] csr_rdata_m_in, // CSR read path (stubbed in datapath today)
    input         csr_to_rf_m_in,
    // Values valid during WB stage
    output reg [31:0] alu_res_w_out,
    output reg [4:0]  rd_adr_w_out,
    output reg [31:0] pc_plus4_w_out,
    output reg [6:0]  opc7_w_out,
    output reg        wb_from_ld_w_out,
    output reg        rf_we_w_out,
    output reg [31:0] csr_rdata_w_out,
    output reg        csr_to_rf_w_out
);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            alu_res_w_out    <= 32'b0;
            rd_adr_w_out     <= 5'b0;
            pc_plus4_w_out   <= 32'b0;
            opc7_w_out       <= 7'b0;
            wb_from_ld_w_out <= 1'b0;
            rf_we_w_out      <= 1'b0;
            csr_rdata_w_out  <= 32'b0;
            csr_to_rf_w_out  <= 1'b0;
        end else if (flush_i) begin
            alu_res_w_out    <= 32'b0;
            rd_adr_w_out     <= 5'b0;
            pc_plus4_w_out   <= 32'b0;
            opc7_w_out       <= 7'b0;
            wb_from_ld_w_out <= 1'b0;
            rf_we_w_out      <= 1'b0;
            csr_rdata_w_out  <= 32'b0;
            csr_to_rf_w_out  <= 1'b0;
        end else if (gate_i) begin
            alu_res_w_out    <= alu_res_m_in;
            rd_adr_w_out     <= rd_adr_m_in;
            pc_plus4_w_out   <= pc_plus4_m_in;
            opc7_w_out       <= opc7_m_in;
            wb_from_ld_w_out <= wb_from_ld_m_in;
            rf_we_w_out      <= rf_we_m_in;
            csr_rdata_w_out  <= csr_rdata_m_in;
            csr_to_rf_w_out  <= csr_to_rf_m_in;
        end
    end
endmodule
