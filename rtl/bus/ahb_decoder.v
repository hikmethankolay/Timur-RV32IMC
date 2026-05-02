module ahb_decoder (
    input         HCLK,
    input         HRESETn,

    // Current bus address from active master
    input  [31:0] HADDR,

    // Slave read-data and ready inputs
    input  [31:0] HRDATA_rom,
    input         HREADY_rom,
    input  [31:0] HRDATA_ram,
    input         HREADY_ram,
    input  [31:0] HRDATA_apb,
    input         HREADY_apb,

    // Slave select outputs
    output        HSEL_rom,
    output        HSEL_ram,
    output        HSEL_apb,

    // Muxed outputs back to active master
    output [31:0] HRDATA,    // From selected slave
    output        HREADY     // From selected slave (1 if no slave selected)
);

    // Address decode: upper 16 bits select region
    wire HSEL_rom_a = (HADDR[31:16] == 16'h0000);
    wire HSEL_ram_a = (HADDR[31:16] == 16'h2000);
    wire HSEL_apb_a = (HADDR[31:16] == 16'h4000);

    reg HSEL_rom_d;
    reg HSEL_ram_d;
    reg HSEL_apb_d;

    assign HSEL_rom = HSEL_rom_a;
    assign HSEL_ram = HSEL_ram_a;
    assign HSEL_apb = HSEL_apb_a;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HSEL_rom_d <= 1'b0;
            HSEL_ram_d <= 1'b0;
            HSEL_apb_d <= 1'b0;
        end else begin
            HSEL_rom_d <= HSEL_rom_a;
            HSEL_ram_d <= HSEL_ram_a;
            HSEL_apb_d <= HSEL_apb_a;
        end
    end

    // HRDATA mux — use the previous cycle's select so data phase follows address phase
    assign HRDATA = HSEL_rom_d ? HRDATA_rom :
                   HSEL_ram_d ? HRDATA_ram :
                   HSEL_apb_d ? HRDATA_apb :
                              32'h0000_0000;

    // HREADY mux — default 1 so the bus doesn't stall when idle
    assign HREADY = HSEL_rom_d ? HREADY_rom :
                   HSEL_ram_d ? HREADY_ram :
                   HSEL_apb_d ? HREADY_apb :
                              1'b1;

endmodule
