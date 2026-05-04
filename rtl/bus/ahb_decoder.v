module ahb_decoder (
    input         HCLK,
    input         HRESETn,

    // Current bus address and transfer type from active master
    input  [31:0] HADDR,
    input  [1:0]  HTRANS,   // [1]=1 for NONSEQ/SEQ (active transfer)

    // Slave read-data and ready inputs
    input  [31:0] HRDATA_rom,
    input         HREADY_rom,
    input  [31:0] HRDATA_ram,
    input         HREADY_ram,
    input  [31:0] HRDATA_apb,
    input         HREADY_apb,

    // Slave select outputs (combinatorial — address phase)
    output        HSEL_rom,
    output        HSEL_ram,
    output        HSEL_apb,

    // Muxed outputs back to active master (data phase — registered select)
    output [31:0] HRDATA,
    output        HREADY
);

    // Address decode: upper 16 bits select region (combinatorial, address phase)
    wire hsel_rom_a = (HADDR[31:16] == 16'h0000);
    wire hsel_ram_a = (HADDR[31:16] == 16'h2000);
    wire hsel_apb_a = (HADDR[31:16] == 16'h4000);

    assign HSEL_rom = hsel_rom_a;
    assign HSEL_ram = hsel_ram_a;
    assign HSEL_apb = hsel_apb_a;

    reg hsel_rom_d, hsel_ram_d, hsel_apb_d;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            { hsel_rom_d, hsel_ram_d, hsel_apb_d } <= 3'b0;
        else if (HTRANS[1])
            { hsel_rom_d, hsel_ram_d, hsel_apb_d } <= { hsel_rom_a, hsel_ram_a, hsel_apb_a };
    end

    // HRDATA mux: data from slave accessed in the previous active clock cycle
    assign HRDATA = hsel_rom_d ? HRDATA_rom :
                   hsel_ram_d ? HRDATA_ram :
                   hsel_apb_d ? HRDATA_apb :
                               32'h0000_0000;

    // HREADY mux: ready from the slave currently completing its data phase
    assign HREADY = hsel_rom_d ? HREADY_rom :
                   hsel_ram_d ? HREADY_ram :
                   hsel_apb_d ? HREADY_apb :
                               1'b1;

endmodule
