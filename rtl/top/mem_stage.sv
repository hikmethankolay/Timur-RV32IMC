module mem_stage(
    input         clk,
    input         rst_n,
    input  [31:0] alu_result,
    input  [31:0] rs2_data,
    input         MemRead,
    input         MemWrite,
    input  [2:0]  funct3,
    output [31:0] mem_read_data,
    output HREADY_RAM
);
    // AHB data-phase register: holds rs2_data so HWDATA is valid one cycle
    // after the address phase (as required by AHB-Lite for write transfers).
    reg  [31:0] hwdata_d;
    wire [31:0] HWDATA;
    wire [1:0]  htrans_ram;
    wire        HRESP;
    wire        HSEL_RAM = (alu_result[31:16] == 16'h2000);
    wire [31:0] mem_read_word;

    reg [1:0] load_addr_lsb_d;
    reg [2:0] load_funct3_d;

    reg [7:0]  load_byte;
    reg [15:0] load_half;
    reg [31:0] load_data_fmt;

    always @(posedge clk) hwdata_d <= rs2_data;
    assign HWDATA = hwdata_d;

    // Capture load decode and byte-lane info in address phase so it aligns
    // with HRDATA returned in the following data phase.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_addr_lsb_d <= 2'b00;
            load_funct3_d   <= 3'b010;
        end else if (MemRead) begin
            load_addr_lsb_d <= alu_result[1:0];
            load_funct3_d   <= funct3;
        end
    end

    mux2 #(.WIDTH(2)) htrans_mux(
        .in0(2'b00),
        .in1(2'b10),
        .sel(MemRead | MemWrite),
        .out(htrans_ram)
    );

    ram_ahb data_memory(
        .HCLK    (clk),
        .HRESETn (rst_n),
        .HSEL    (HSEL_RAM),
        .HADDR   (alu_result),
        .HTRANS  (htrans_ram),
        .HWRITE  (MemWrite),
        .HSIZE   (funct3),
        .HWDATA  (HWDATA),
        .HRDATA  (mem_read_word),
        .HREADY  (HREADY_RAM),
        .HRESP   (HRESP)
    );

    // LSU read-side formatting now lives in the CPU:
    // memory returns aligned 32-bit words, then funct3/addr[1:0] select the
    // correct byte/halfword and perform sign/zero extension for register writeback.
    always @(*) begin
        case (load_addr_lsb_d)
            2'b00: load_byte = mem_read_word[7:0];
            2'b01: load_byte = mem_read_word[15:8];
            2'b10: load_byte = mem_read_word[23:16];
            default: load_byte = mem_read_word[31:24];
        endcase

        if (load_addr_lsb_d[1] == 1'b0)
            load_half = mem_read_word[15:0];
        else
            load_half = mem_read_word[31:16];

        case (load_funct3_d)
            3'b000:  load_data_fmt = {{24{load_byte[7]}}, load_byte}; // LB
            3'b100:  load_data_fmt = {24'b0, load_byte};              // LBU
            3'b001:  load_data_fmt = {{16{load_half[15]}}, load_half}; // LH
            3'b101:  load_data_fmt = {16'b0, load_half};               // LHU
            default: load_data_fmt = mem_read_word;                    // LW/other
        endcase
    end

    assign mem_read_data = load_data_fmt;
endmodule
