// Data memory stage: AHB data bus @ 0x2000_.... Store data registered for AHB data phase; loads formatted for WB.
module mem_stage (
    input         clk_i,
    input         rst_n_i,
    input  [31:0] addr_m_i,      // Byte address from EX ALU
    input  [31:0] rs2_store_m_i, // Store value (byte lane handling in RAM)
    input         mem_rd_m_i,
    input         mem_we_m_i,
    input  [2:0]  funct3_m_i,   // Encodes LB/LW/... and AHB HSIZE
    output [31:0] ld_data_wb_o, // Sign/zero-extended load for register write
    output        ram_ready_o,
    // AHB D-access master (→ shared data bus at SoC level)
    output [31:0] HADDR_o,
    output [1:0]  HTRANS_o,
    output        HWRITE_o,
    output [2:0]  HSIZE_o,
    output [31:0] HWDATA_o,
    input  [31:0] HRDATA_i,
    input         HREADY_i
);
    // HWDATA valid in data phase — one cycle after address phase seen by slave.
    reg [31:0] hwdata_q;
    always @(posedge clk_i) hwdata_q <= rs2_store_m_i;

    wire [1:0] htrans_w;

    // Remember decode for load when read data returns next edge.
    reg [1:0] ld_addr_lsb_q;
    reg [2:0] ld_funct3_q;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ld_addr_lsb_q <= 2'b00;
            ld_funct3_q   <= 3'b010;
        end else if (mem_rd_m_i) begin
            ld_addr_lsb_q <= addr_m_i[1:0];
            ld_funct3_q   <= funct3_m_i;
        end
    end

    mux2 #(.WIDTH(2)) u_htrans (
        .in0(2'b00),
        .in1(2'b10),
        .sel(mem_rd_m_i | mem_we_m_i),
        .out(htrans_w)
    );

    assign HADDR_o     = addr_m_i;
    assign HTRANS_o    = htrans_w;
    assign HWRITE_o    = mem_we_m_i;
    assign HSIZE_o     = funct3_m_i;
    assign HWDATA_o    = hwdata_q;
    assign ram_ready_o = HREADY_i;

    wire [31:0] rd_word_w = HRDATA_i;

    reg [7:0]  byte_w;
    reg [15:0] half_w;
    reg [31:0] ld_fmt_w;
    always @(*) begin
        case (ld_addr_lsb_q)
            2'b00: byte_w = rd_word_w[7:0];
            2'b01: byte_w = rd_word_w[15:8];
            2'b10: byte_w = rd_word_w[23:16];
            default: byte_w = rd_word_w[31:24];
        endcase
        if (ld_addr_lsb_q[1] == 1'b0) half_w = rd_word_w[15:0];
        else half_w = rd_word_w[31:16];
        case (ld_funct3_q)
            3'b000: ld_fmt_w = {{24{byte_w[7]}}, byte_w};
            3'b100: ld_fmt_w = {24'b0, byte_w};
            3'b001: ld_fmt_w = {{16{half_w[15]}}, half_w};
            3'b101: ld_fmt_w = {16'b0, half_w};
            default: ld_fmt_w = rd_word_w;
        endcase
    end

    assign ld_data_wb_o = ld_fmt_w;
endmodule
