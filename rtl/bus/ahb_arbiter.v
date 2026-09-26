// AHB arbiter (Phase 9): AMBA 2-style HBUSREQ/HGRANT arbitration in front
// of AHB-Lite slaves (AHB-Lite itself is single-master).
// Two masters: [0] CPU data port, [1] DMAC. Ownership only changes on a rising
// edge with HREADY = 1:
//   CPU requesting -> CPU; else DMAC requesting -> DMAC; else CPU (parked, so
//   CPU accesses start with zero arbitration latency).
// No HLOCK: the DMAC keeps its captured read data if it loses the bus between
// its read and its write, so no transfer needs to be atomic.
module ahb_arbiter (
    input        HCLK,
    input        HRESETn,
    input  [1:0] HBUSREQ,        // [0] CPU, [1] DMAC
    input        HREADY,
    output reg   HMASTER,        // address-phase owner: 0 CPU, 1 DMAC
    output reg   HMASTER_DATA,   // data-phase owner: HMASTER delayed when HREADY = 1
    output [1:0] HGRANT          // one-hot decode of HMASTER
);

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HMASTER      <= 1'b0;
            HMASTER_DATA <= 1'b0;
        end else if (HREADY) begin
            HMASTER_DATA <= HMASTER;
            if (HBUSREQ[0])
                HMASTER <= 1'b0;
            else if (HBUSREQ[1])
                HMASTER <= 1'b1;
            else
                HMASTER <= 1'b0;
        end
    end

    assign HGRANT = {HMASTER, ~HMASTER};

endmodule
