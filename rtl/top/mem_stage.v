module mem_stage(
    input         clk,
    input         rst_n,
    input  [31:0] alu_result,
    input  [31:0] rs2_data,
    input         MemRead,
    input         MemWrite,
    input  [2:0]  funct3,
    output [31:0] mem_read_data
);
    // AHB data-phase register: holds rs2_data so HWDATA is valid one cycle
    // after the address phase (as required by AHB-Lite for write transfers).
    reg  [31:0] hwdata_d;
    wire [31:0] HWDATA;
    wire [1:0]  htrans_ram;
    wire        HREADY_RAM, HRESP;
    wire        HSEL_RAM = (alu_result[31:16] == 16'h2000);

    always @(posedge clk) hwdata_d <= rs2_data;
    assign HWDATA = hwdata_d;

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
        .HRDATA  (mem_read_data),
        .HREADY  (HREADY_RAM),
        .HRESP   (HRESP)
    );
endmodule
