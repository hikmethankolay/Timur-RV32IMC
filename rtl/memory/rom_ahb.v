module rom_ahb (
    input         HCLK,
    input         HRESETn,
    input         HSEL,
    input  [31:0] HADDR,
    input  [1:0]  HTRANS,
    input         HWRITE,
    input  [2:0]  HSIZE,
    input  [31:0] HWDATA,
    output [31:0] HRDATA,
    output        HREADY,
    output        HRESP
);

    // M10K inference with MIF initialization
    (* romstyle = "block", ram_init_file = "rom.mif" *) reg [31:0] mem [0:16383];

    initial begin
        $readmemh("test_rom.hex", mem);
    end

    wire active = HSEL & HTRANS[1];

    // Synchronous Read Pipeline
    reg [31:0] read_data;
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            read_data <= 32'b0;
        // Read during Address Phase -> Available during Data Phase
        else if (active && !HWRITE)
            read_data <= mem[HADDR[15:2]];
    end

    assign HRDATA = read_data;
    assign HREADY = 1'b1;
    assign HRESP  = 1'b0;

endmodule