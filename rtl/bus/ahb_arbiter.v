module ahb_arbiter (
    input         HCLK,
    input         HRESETn,

    // Master request / lock inputs
    input  [1:0]  HBUSREQ,    // [0]=CPU, [1]=DMAC
    input  [1:0]  HLOCK,      // [0]=unused, [1]=DMAC burst hold

    // Active slave's ready — must be 1 to switch masters
    input         HREADY,

    // Grants
    output [1:0]  HGRANT,     // [0]=CPU granted, [1]=DMAC granted
    output        HMASTER,    // 0=CPU drives bus, 1=DMAC drives bus
    output        HMASTLOCK   // 1 when current master is in a locked sequence
);

    localparam GRANT_CPU  = 1'b0;
    localparam GRANT_DMAC = 1'b1;

    reg state;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn)
            state <= GRANT_CPU;
        else case (state)
            GRANT_CPU:
                // CPU has the bus. Switch to DMAC only if CPU is not requesting,
                // DMAC is requesting, and we are at a transfer boundary.
                // (Ties go to CPU because both bits asserted leaves !HBUSREQ[0]=0.)
                if (!HBUSREQ[0] && HBUSREQ[1] && HREADY)
                    state <= GRANT_DMAC;

            GRANT_DMAC:
                // DMAC has the bus. Reclaim for CPU at the next boundary if
                // CPU requests OR DMAC has stopped requesting, but never while
                // DMAC is holding its lock (atomic burst in progress).
                if ((HBUSREQ[0] || !HBUSREQ[1]) && HREADY && !HLOCK[1])
                    state <= GRANT_CPU;
        endcase
    end

    assign HGRANT[0]  = (state == GRANT_CPU);
    assign HGRANT[1]  = (state == GRANT_DMAC);
    assign HMASTER    = state;
    assign HMASTLOCK  = (state == GRANT_CPU) ? HLOCK[0] : HLOCK[1];

endmodule
