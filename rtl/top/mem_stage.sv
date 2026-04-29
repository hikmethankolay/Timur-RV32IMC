// Data memory stage: AHB RAM @ 0x2000_…. Store data registered for AHB data phase; loads formatted for WB.
module mem_stage (
    input         clk_i,
    input         rst_n_i,
    input  [31:0] addr_m_i,      // Byte address from EX ALU
    input  [31:0] rs2_store_m_i, // Store value (byte lane handling in RAM)
    input         mem_rd_m_i,
    input         mem_we_m_i,
    input  [2:0]  funct3_m_i,   // Encodes LB/LW/... and AHB HSIZE
    output [31:0] ld_data_wb_o, // Sign/zero-extended load for register write
    output        ram_ready_o
);
    // HWDATA valid in data phase — one cycle after address phase seen by ram_ahb.
    reg [31:0] hwdata_q;
    always @(posedge clk_i) hwdata_q <= rs2_store_m_i;

    wire [1:0]  htrans_w;
    wire        hresp_w;
    wire        sel_ram_w = (addr_m_i[31:16] == 16'h2000);
    wire [31:0] rd_word_w;

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

    ram_ahb u_dmem (
        .HCLK    (clk_i),
        .HRESETn (rst_n_i),
        .HSEL    (sel_ram_w),
        .HADDR   (addr_m_i),
        .HTRANS  (htrans_w),
        .HWRITE  (mem_we_m_i),
        .HSIZE   (funct3_m_i),
        .HWDATA  (hwdata_q),
        .HRDATA  (rd_word_w),
        .HREADY  (ram_ready_o),
        .HRESP   (hresp_w)
    );

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
