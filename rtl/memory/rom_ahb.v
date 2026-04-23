module rom_ahb (
    input         HCLK,      // AHB clock — used: clocks address register
    input         HRESETn,   // Active-low async reset — used: resets address register
    input         HSEL,      // Slave select — used: gates address registration
    input  [31:0] HADDR,     // AHB address bus — used: registered and used to index ROM
    input  [1:0]  HTRANS,    // Transfer type — used: HTRANS[1] detects active transfer
    input         HWRITE,    // Write/read select — NOT USED: ROM ignores all writes
    input  [2:0]  HSIZE,     // Transfer size — NOT USED: ROM always returns full word
    input  [31:0] HWDATA,    // Write data — NOT USED: ROM is read-only
    output [31:0] HRDATA,    // Read data — used: instruction word sent to CPU
    output        HREADY,    // Transfer complete — used: hardwired 1, ROM is single-cycle
    output        HRESP      // Response status — used: hardwired 0 (OKAY)
);

    (* ram_init_file = "rom.mif" *) reg [31:0] mem [0:16383];

    integer i;
    initial begin
        for (i = 0; i < 16384; i = i + 1)
            mem[i] = 32'h00000013;
    end

    reg [31:0] addr_reg;
    wire active = HSEL && HTRANS[1];
    
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