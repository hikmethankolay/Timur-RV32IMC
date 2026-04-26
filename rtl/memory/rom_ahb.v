module rom_ahb (
    input         HCLK,      // AHB clock
    input         HRESETn,   // Active-low async reset
    input         HSEL,      // Slave select from address decoder
    input  [31:0] HADDR,     // AHB address bus
    input  [1:0]  HTRANS,    // Transfer type — active when HTRANS[1]=1
    input         HWRITE,    // Ignored — ROM is read-only
    input  [2:0]  HSIZE,     // Ignored — ROM always returns full word
    input  [31:0] HWDATA,    // Ignored — ROM is read-only
    output [31:0] HRDATA,    // Read data (instruction word)
    output        HREADY,    // Always 1 — single-cycle slave
    output        HRESP      // Always 0 — OKAY
);

    (* ram_init_file = "rom.mif" *) reg [31:0] mem [0:16383];

    initial begin
        $readmemh("test_rom.hex", mem);
    end

    wire active = HSEL && HTRANS[1];

    reg [31:0] addr_reg;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            addr_reg <= 32'b0;
        end else if (active) begin
            addr_reg <= HADDR;
        end
    end

    assign HRDATA = mem[addr_reg[15:2]];
    assign HREADY = 1'b1;
    assign HRESP  = 1'b0;

endmodule
