// CPU data master (Phase 9): AHB master 0, loads and stores from MEM/WB.
// Instruction fetch has its own ROM port, so this master only carries data.
//   Address phase : driven while EX/MEM holds a valid load or store (MEM stage)
//   Accepted      : HGRANT AND HREADY at the rising edge -> data phase pending,
//                   HWDATA register loaded (held through wait states)
//   Data phase    : completes on a rising edge with HREADY = 1 (WB stage)
//   bus_wait      : freezes the whole pipeline while either phase waits
module cpu_ahb_master (
    input             HCLK,
    input             HRESETn,

    // from EX/MEM
    input      [31:0] addr,         // EX/MEM result
    input      [31:0] store_data,   // EX/MEM store data after store_aligner
    input      [2:0]  funct3,       // access size
    input             mem_read,
    input             mem_write,
    input             mem_valid,

    // bus
    input             HGRANT,       // arbiter: CPU owns the address phase
    input             HREADY,
    input      [31:0] HRDATA,
    output     [31:0] HADDR,
    output     [1:0]  HTRANS,
    output            HWRITE,
    output     [2:0]  HSIZE,
    output     [2:0]  HBURST,       // SINGLE
    output     [3:0]  HPROT,        // 0011: data access, privileged
    output            HMASTLOCK,    // 0; no Timur slave uses these three
    output reg [31:0] HWDATA,
    output            HBUSREQ,

    // to WB and the hazard unit
    output     [31:0] load_data,    // HRDATA passed to the WB load formatter
    output            bus_wait
);

    localparam [1:0] HTRANS_IDLE   = 2'b00,
                     HTRANS_NONSEQ = 2'b10;

    wire access   = mem_valid && (mem_read || mem_write);
    wire accepted = access && HGRANT && HREADY;

    reg data_pending;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            data_pending <= 1'b0;
        else if (accepted)
            data_pending <= 1'b1;          // stays set if a data phase ends on the same edge
        else if (data_pending && HREADY)
            data_pending <= 1'b0;
    end

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            HWDATA <= 32'b0;
        else if (accepted)
            HWDATA <= store_data;
    end

    assign HBUSREQ   = access;
    assign HTRANS    = access ? HTRANS_NONSEQ : HTRANS_IDLE;
    assign HADDR     = addr;
    assign HWRITE    = mem_write;
    assign HSIZE     = {1'b0, funct3[1:0]};
    assign HBURST    = 3'b000;
    assign HPROT     = 4'b0011;
    assign HMASTLOCK = 1'b0;

    assign load_data = HRDATA;
    assign bus_wait  = (access && !(HGRANT && HREADY)) || (data_pending && !HREADY);

endmodule
