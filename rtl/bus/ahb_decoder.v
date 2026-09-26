// AHB address decoder (Phase 9).
//   HSEL_ROM : HADDR[31:16] = 0x0000   ROM AHB port
//   HSEL_RAM : HADDR[31:16] = 0x2000   RAM
//   HSEL_APB : HADDR[31:16] = 0x4000   AHB-to-APB bridge
//   none     : default slave (HREADY = 1, HRDATA = 0; writes ignored)
// A data-phase select register copies the HSEL vector at every rising edge
// where HREADY = 1; HRDATA and HREADY are multiplexed with it, because with
// pipelined AHB the data phase always belongs to the previous address phase.
// The muxed HREADY drives every slave's HREADY input and both masters.
module ahb_decoder (
    input         HCLK,
    input         HRESETn,
    input  [31:0] HADDR,

    output        HSEL_ROM,
    output        HSEL_RAM,
    output        HSEL_APB,

    input  [31:0] HRDATA_ROM,
    input  [31:0] HRDATA_RAM,
    input  [31:0] HRDATA_APB,
    input         HREADYOUT_ROM,
    input         HREADYOUT_RAM,
    input         HREADYOUT_APB,

    output [31:0] HRDATA,
    output        HREADY
);

    assign HSEL_ROM = (HADDR[31:16] == 16'h0000);
    assign HSEL_RAM = (HADDR[31:16] == 16'h2000);
    assign HSEL_APB = (HADDR[31:16] == 16'h4000);

    reg sel_rom_d;
    reg sel_ram_d;
    reg sel_apb_d;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            sel_rom_d <= 1'b0;
            sel_ram_d <= 1'b0;
            sel_apb_d <= 1'b0;
        end else if (HREADY) begin
            sel_rom_d <= HSEL_ROM;
            sel_ram_d <= HSEL_RAM;
            sel_apb_d <= HSEL_APB;
        end
    end

    assign HRDATA = sel_rom_d ? HRDATA_ROM :
                    sel_ram_d ? HRDATA_RAM :
                    sel_apb_d ? HRDATA_APB :
                                32'h00000000;

    assign HREADY = sel_rom_d ? HREADYOUT_ROM :
                    sel_ram_d ? HREADYOUT_RAM :
                    sel_apb_d ? HREADYOUT_APB :
                                1'b1;

endmodule
